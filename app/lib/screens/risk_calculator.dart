import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../core/theme.dart';

class RiskCalculatorScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final Map<String, double> lotRatios;
  final Map<String, String> symbolSuffixes;
  final Set<String> preferredPairs;
  final void Function({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required double? price,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  })
  onPlaceOrder;
  final void Function(String symbol, int terminalIndex)? onRequestSymbolInfo;
  final Stream<Map<String, dynamic>>? symbolInfoStream;

  const RiskCalculatorScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    this.mainAccountNum,
    required this.lotRatios,
    required this.symbolSuffixes,
    required this.preferredPairs,
    required this.onPlaceOrder,
    this.onRequestSymbolInfo,
    this.symbolInfoStream,
  });

  @override
  State<RiskCalculatorScreen> createState() => _RiskCalculatorScreenState();
}

class _RiskCalculatorScreenState extends State<RiskCalculatorScreen> {
  final _symbolController = TextEditingController(text: 'EURUSD');
  final _entryController = TextEditingController();
  final _slController = TextEditingController();
  final _tpController = TextEditingController();
  final _riskPercentController = TextEditingController(text: '1.0');
  final _riskAmountController = TextEditingController();

  // Calculation results
  double _lotSize = 0;
  double _potentialLoss = 0;
  double _potentialProfit = 0;
  double _riskRewardRatio = 0;
  double _pipValue = 0;
  double _slPips = 0;
  double _tpPips = 0;

  // Settings
  String _riskMode = 'percent'; // 'percent' or 'amount'
  String _orderType = 'buy';
  int? _selectedAccountIndex;
  double _accountBalance = 0;
  String _accountCurrency = 'USD';

  // Symbol info from broker
  StreamSubscription<Map<String, dynamic>>? _symbolInfoSubscription;
  Map<String, Map<String, dynamic>> _cachedSymbolInfo = {};
  bool _isLoadingSymbolInfo = false;
  String? _currentSymbolInfoRequest;
  int _symbolDigits = 5;
  double _minLot = 0.01;
  double _maxLot = 100.0;
  double _lotStep = 0.01;
  double _brokerPipValue = 0; // Pip value from broker
  double _pipSize = 0.0001;

  // Fallback pip values (used when broker info not available)
  final Map<String, double> _fallbackPipValues = {
    'EURUSD': 10.0,
    'GBPUSD': 10.0,
    'USDJPY': 9.1,
    'USDCHF': 10.8,
    'AUDUSD': 10.0,
    'USDCAD': 7.5,
    'NZDUSD': 10.0,
    'EURGBP': 12.7,
    'EURJPY': 9.1,
    'GBPJPY': 9.1,
    'XAUUSD': 1.0,
    'XAGUSD': 5.0,
    'BTCUSD': 1.0,
    'ETHUSD': 1.0,
  };

  @override
  void initState() {
    super.initState();
    _loadPreferences();

    // Subscribe to symbol info stream
    _symbolInfoSubscription = widget.symbolInfoStream?.listen(
      _handleSymbolInfo,
    );

    // Set default account
    if (widget.accounts.isNotEmpty) {
      // Try to find main account first
      if (widget.mainAccountNum != null) {
        final mainIdx = widget.accounts.indexWhere(
          (a) => a['account'] == widget.mainAccountNum,
        );
        if (mainIdx >= 0) {
          _selectedAccountIndex = mainIdx;
        }
      }
      _selectedAccountIndex ??= 0;
      _updateAccountInfo();
    }

    // Add listeners
    _entryController.addListener(_calculate);
    _slController.addListener(_calculate);
    _tpController.addListener(_calculate);
    _riskPercentController.addListener(_calculate);
    _riskAmountController.addListener(_calculate);
    _symbolController.addListener(_onSymbolChanged);

    // Request initial symbol info
    _requestSymbolInfo();
  }

  @override
  void dispose() {
    _symbolInfoSubscription?.cancel();
    _symbolController.dispose();
    _entryController.dispose();
    _slController.dispose();
    _tpController.dispose();
    _riskPercentController.dispose();
    _riskAmountController.dispose();
    super.dispose();
  }

  void _onSymbolChanged() {
    _requestSymbolInfo();
    _calculate();
  }

  void _requestSymbolInfo() {
    final symbol = _symbolController.text.toUpperCase().trim();
    if (symbol.isEmpty) return;

    // Check cache first
    if (_cachedSymbolInfo.containsKey(symbol)) {
      _applySymbolInfo(_cachedSymbolInfo[symbol]!);
      return;
    }

    // Request from broker
    if (widget.onRequestSymbolInfo != null && _selectedAccountIndex != null) {
      final terminalIndex =
          widget.accounts[_selectedAccountIndex!]['index'] as int? ?? 0;
      setState(() {
        _isLoadingSymbolInfo = true;
        _currentSymbolInfoRequest = symbol;
      });
      widget.onRequestSymbolInfo!(symbol, terminalIndex);
    }
  }

  void _handleSymbolInfo(Map<String, dynamic> info) {
    final symbol = info['symbol'] as String?;
    if (symbol == null) return;

    // Cache the info
    _cachedSymbolInfo[symbol] = info;

    // Apply if it's for the current symbol
    if (symbol == _currentSymbolInfoRequest) {
      _applySymbolInfo(info);
    }
  }

  void _applySymbolInfo(Map<String, dynamic> info) {
    setState(() {
      _isLoadingSymbolInfo = false;
      _brokerPipValue = (info['pipValue'] as num?)?.toDouble() ?? 0;
      _pipSize = (info['pipSize'] as num?)?.toDouble() ?? 0.0001;
      _symbolDigits = (info['digits'] as num?)?.toInt() ?? 5;
      _minLot = (info['minLot'] as num?)?.toDouble() ?? 0.01;
      _maxLot = (info['maxLot'] as num?)?.toDouble() ?? 100.0;
      _lotStep = (info['lotStep'] as num?)?.toDouble() ?? 0.01;

      // Auto-fill entry price with current bid/ask if empty
      if (_entryController.text.isEmpty) {
        final bid = (info['bid'] as num?)?.toDouble();
        final ask = (info['ask'] as num?)?.toDouble();
        if (_orderType == 'buy' && ask != null && ask > 0) {
          _entryController.text = ask.toStringAsFixed(_symbolDigits);
        } else if (_orderType == 'sell' && bid != null && bid > 0) {
          _entryController.text = bid.toStringAsFixed(_symbolDigits);
        }
      }
    });
    _calculate();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSymbol = prefs.getString('calc_symbol');
    final savedRiskPercent = prefs.getString('calc_risk_percent');

    if (savedSymbol != null) {
      _symbolController.text = savedSymbol;
    }
    if (savedRiskPercent != null) {
      _riskPercentController.text = savedRiskPercent;
    }
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calc_symbol', _symbolController.text);
    await prefs.setString('calc_risk_percent', _riskPercentController.text);
  }

  void _updateAccountInfo() {
    if (_selectedAccountIndex != null &&
        _selectedAccountIndex! < widget.accounts.length) {
      final account = widget.accounts[_selectedAccountIndex!];
      setState(() {
        _accountBalance = (account['balance'] as num?)?.toDouble() ?? 0;
        _accountCurrency = account['currency'] as String? ?? 'USD';
      });
      _requestSymbolInfo(); // Re-request symbol info for new account
      _calculate();
    }
  }

  void _calculate() {
    final entry = double.tryParse(_entryController.text) ?? 0;
    final sl = double.tryParse(_slController.text) ?? 0;
    final tp = double.tryParse(_tpController.text) ?? 0;
    final symbol = _symbolController.text.toUpperCase();

    if (entry <= 0 || sl <= 0) {
      setState(() {
        _lotSize = 0;
        _potentialLoss = 0;
        _potentialProfit = 0;
        _riskRewardRatio = 0;
        _slPips = 0;
        _tpPips = 0;
      });
      return;
    }

    // Use broker pip size if available, otherwise determine from symbol
    double pipSize = _pipSize;
    if (pipSize <= 0) {
      pipSize = 0.0001; // Default for most pairs
      if (symbol.contains('JPY')) {
        pipSize = 0.01;
      } else if (symbol.startsWith('XAU')) {
        pipSize = 0.1;
      } else if (symbol.startsWith('XAG')) {
        pipSize = 0.01;
      } else if (symbol.startsWith('BTC') || symbol.startsWith('ETH')) {
        pipSize = 1.0;
      }
    }

    // Calculate SL distance in pips
    double slDistance;
    if (_orderType == 'buy') {
      slDistance = (entry - sl) / pipSize;
    } else {
      slDistance = (sl - entry) / pipSize;
    }

    // Calculate TP distance in pips
    double tpDistance = 0;
    if (tp > 0) {
      if (_orderType == 'buy') {
        tpDistance = (tp - entry) / pipSize;
      } else {
        tpDistance = (entry - tp) / pipSize;
      }
    }

    // Get pip value - prefer broker value, fallback to estimates
    double pipValuePerLot;
    if (_brokerPipValue > 0) {
      pipValuePerLot = _brokerPipValue;
    } else {
      pipValuePerLot = _fallbackPipValues[symbol] ?? 10.0;

      // Handle non-USD accounts (simplified conversion)
      if (_accountCurrency != 'USD') {
        if (_accountCurrency == 'EUR') {
          pipValuePerLot *= 1.08;
        } else if (_accountCurrency == 'GBP') {
          pipValuePerLot *= 1.27;
        }
      }
    }

    // Calculate risk amount
    double riskAmount;
    if (_riskMode == 'percent') {
      final riskPercent = double.tryParse(_riskPercentController.text) ?? 0;
      riskAmount = _accountBalance * (riskPercent / 100);
    } else {
      riskAmount = double.tryParse(_riskAmountController.text) ?? 0;
    }

    // Calculate lot size
    double lotSize = 0;
    if (slDistance > 0 && pipValuePerLot > 0) {
      lotSize = riskAmount / (slDistance * pipValuePerLot);

      // Round to lot step
      if (_lotStep > 0) {
        lotSize = (lotSize / _lotStep).floor() * _lotStep;
      } else {
        lotSize = (lotSize * 100).floor() / 100;
      }

      // Apply min/max limits
      if (lotSize < _minLot) lotSize = _minLot;
      if (lotSize > _maxLot) lotSize = _maxLot;
    }

    // Calculate potential loss and profit
    final potentialLoss = slDistance * pipValuePerLot * lotSize;
    final potentialProfit = tp > 0
        ? tpDistance * pipValuePerLot * lotSize
        : 0.0;

    // Calculate risk/reward ratio
    double rrRatio = 0;
    if (slDistance > 0 && tpDistance > 0) {
      rrRatio = tpDistance / slDistance;
    }

    setState(() {
      _lotSize = lotSize;
      _potentialLoss = potentialLoss;
      _potentialProfit = potentialProfit;
      _riskRewardRatio = rrRatio;
      _pipValue = pipValuePerLot;
      _slPips = slDistance.abs();
      _tpPips = tpDistance.abs();
    });
  }

  void _setQuickRisk(double percent) {
    setState(() {
      _riskMode = 'percent';
      _riskPercentController.text = percent.toString();
    });
    _calculate();
  }

  void _placeOrderWithCalculatedLots() {
    if (_lotSize <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please calculate lot size first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final entry = double.tryParse(_entryController.text);
    final sl = double.tryParse(_slController.text);
    final tp = double.tryParse(_tpController.text);
    final symbol = _symbolController.text.toUpperCase();

    // Determine if it's a market or pending order
    // For simplicity, we'll assume market order
    final accountIndices = _selectedAccountIndex != null
        ? [widget.accounts[_selectedAccountIndex!]['index'] as int]
        : <int>[];

    widget.onPlaceOrder(
      symbol: symbol,
      type: _orderType,
      lots: _lotSize,
      tp: tp,
      sl: sl,
      price: entry,
      accountIndices: accountIndices,
      useRatios: false,
      applySuffix: true,
    );

    _savePreferences();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Placing ${_orderType.toUpperCase()} ${_lotSize.toStringAsFixed(2)} lots $symbol',
        ),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context);
  }

  String _getAccountDisplayName(int index) {
    if (index >= widget.accounts.length) return 'Account';
    final account = widget.accounts[index];
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Risk Calculator',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Account selector
              _buildSectionTitle('ACCOUNT'),
              const SizedBox(height: 8),
              _buildAccountSelector(),

              const SizedBox(height: 20),

              // Symbol & Order Type
              _buildSectionTitle('INSTRUMENT'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _symbolController,
                      label: 'Symbol',
                      hint: 'EURUSD',
                      textCapitalization: TextCapitalization.characters,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildOrderTypeToggle()),
                ],
              ),

              const SizedBox(height: 20),

              // Price inputs
              _buildSectionTitle('PRICE LEVELS'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _entryController,
                label: 'Entry Price',
                hint: '1.08500',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _slController,
                      label: 'Stop Loss',
                      hint: '1.08000',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      borderColor: AppColors.error.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _tpController,
                      label: 'Take Profit',
                      hint: '1.09500',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      borderColor: AppColors.primary.withOpacity(0.5),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Risk settings
              _buildSectionTitle('RISK SETTINGS'),
              const SizedBox(height: 8),
              _buildRiskModeSelector(),
              const SizedBox(height: 12),
              if (_riskMode == 'percent') ...[
                _buildTextField(
                  controller: _riskPercentController,
                  label: 'Risk %',
                  hint: '1.0',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  suffix: '%',
                ),
                const SizedBox(height: 8),
                _buildQuickRiskButtons(),
              ] else
                _buildTextField(
                  controller: _riskAmountController,
                  label: 'Risk Amount',
                  hint: '100',
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  suffix: _accountCurrency,
                ),

              const SizedBox(height: 24),

              // Results
              _buildResultsCard(),

              const SizedBox(height: 24),

              // Place order button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _lotSize > 0
                      ? _placeOrderWithCalculatedLots
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orderType == 'buy'
                        ? AppColors.primary
                        : AppColors.error,
                    disabledBackgroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _lotSize > 0
                        ? '${_orderType.toUpperCase()} ${_lotSize.toStringAsFixed(2)} LOTS'
                        : 'CALCULATE FIRST',
                    style: TextStyle(
                      color: _lotSize > 0
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildAccountSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedAccountIndex,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.textSecondary,
          ),
          items: List.generate(widget.accounts.length, (index) {
            final account = widget.accounts[index];
            final balance = (account['balance'] as num?)?.toDouble() ?? 0;
            final currency = account['currency'] as String? ?? 'USD';
            return DropdownMenuItem<int>(
              value: index,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _getAccountDisplayName(index),
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${balance.toStringAsFixed(2)} $currency',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          }),
          onChanged: (value) {
            setState(() {
              _selectedAccountIndex = value;
            });
            _updateAccountInfo();
          },
        ),
      ),
    );
  }

  Widget _buildOrderTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _orderType = 'buy');
                _calculate();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _orderType == 'buy'
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(9),
                  ),
                ),
                child: Center(
                  child: Text(
                    'BUY',
                    style: TextStyle(
                      color: _orderType == 'buy'
                          ? Colors.black
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _orderType = 'sell');
                _calculate();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _orderType == 'sell'
                      ? AppColors.error
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(9),
                  ),
                ),
                child: Center(
                  child: Text(
                    'SELL',
                    style: TextStyle(
                      color: _orderType == 'sell'
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? suffix,
    Color? borderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor ?? AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor ?? AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor ?? AppColors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            suffixText: suffix,
            suffixStyle: const TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildRiskModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _riskMode = 'percent');
                _calculate();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _riskMode == 'percent'
                      ? AppColors.primary.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(9),
                  ),
                ),
                child: Center(
                  child: Text(
                    'RISK %',
                    style: TextStyle(
                      color: _riskMode == 'percent'
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _riskMode = 'amount');
                _calculate();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _riskMode == 'amount'
                      ? AppColors.primary.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(9),
                  ),
                ),
                child: Center(
                  child: Text(
                    'FIXED \$',
                    style: TextStyle(
                      color: _riskMode == 'amount'
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickRiskButtons() {
    return Row(
      children: [
        _buildQuickRiskButton(0.5),
        const SizedBox(width: 8),
        _buildQuickRiskButton(1.0),
        const SizedBox(width: 8),
        _buildQuickRiskButton(2.0),
        const SizedBox(width: 8),
        _buildQuickRiskButton(3.0),
        const SizedBox(width: 8),
        _buildQuickRiskButton(5.0),
      ],
    );
  }

  Widget _buildQuickRiskButton(double percent) {
    final isSelected = _riskPercentController.text == percent.toString();
    return Expanded(
      child: GestureDetector(
        onTap: () => _setQuickRisk(percent),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.2)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Center(
            child: Text(
              '${percent.toString().replaceAll('.0', '')}%',
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCard() {
    final riskAmount = _riskMode == 'percent'
        ? _accountBalance *
              ((double.tryParse(_riskPercentController.text) ?? 0) / 100)
        : double.tryParse(_riskAmountController.text) ?? 0;

    final hasBrokerData = _brokerPipValue > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryWithOpacity(0.15),
            AppColors.primaryWithOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Pip value source indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_isLoadingSymbolInfo)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              else
                Icon(
                  hasBrokerData ? Icons.verified : Icons.info_outline,
                  size: 12,
                  color: hasBrokerData
                      ? AppColors.primary
                      : AppColors.textSecondary,
                ),
              const SizedBox(width: 6),
              Text(
                hasBrokerData
                    ? 'Pip value: \$${_pipValue.toStringAsFixed(2)}/lot (from broker)'
                    : _isLoadingSymbolInfo
                    ? 'Loading symbol info...'
                    : 'Pip value: \$${_pipValue.toStringAsFixed(2)}/lot (estimated)',
                style: TextStyle(
                  color: hasBrokerData
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Lot size - main result
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'POSITION SIZE',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _lotSize > 0 ? _lotSize.toStringAsFixed(2) : '—',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'LOTS',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 24),

          // Stats grid
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Risk',
                  riskAmount > 0
                      ? '${riskAmount.toStringAsFixed(2)} $_accountCurrency'
                      : '—',
                  AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Potential Loss',
                  _potentialLoss > 0
                      ? '-${_potentialLoss.toStringAsFixed(2)}'
                      : '—',
                  AppColors.error,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Potential Profit',
                  _potentialProfit > 0
                      ? '+${_potentialProfit.toStringAsFixed(2)}'
                      : '—',
                  AppColors.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'SL Distance',
                  _slPips > 0 ? '${_slPips.toStringAsFixed(1)} pips' : '—',
                  AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'TP Distance',
                  _tpPips > 0 ? '${_tpPips.toStringAsFixed(1)} pips' : '—',
                  AppColors.textSecondary,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  'Risk:Reward',
                  _riskRewardRatio > 0
                      ? '1:${_riskRewardRatio.toStringAsFixed(2)}'
                      : '—',
                  _riskRewardRatio >= 2
                      ? AppColors.primary
                      : (_riskRewardRatio >= 1
                            ? Colors.orange
                            : AppColors.error),
                ),
              ),
            ],
          ),

          // R:R visual indicator
          if (_riskRewardRatio > 0) ...[
            const SizedBox(height: 16),
            _buildRiskRewardBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildRiskRewardBar() {
    final totalParts = 1 + _riskRewardRatio;
    final riskWidth = 1 / totalParts;
    final rewardWidth = _riskRewardRatio / totalParts;

    return Column(
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4)),
          child: Row(
            children: [
              Flexible(
                flex: (riskWidth * 100).round(),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(4),
                    ),
                  ),
                ),
              ),
              Flexible(
                flex: (rewardWidth * 100).round(),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Risk',
              style: TextStyle(color: AppColors.error, fontSize: 10),
            ),
            Text(
              'Reward',
              style: TextStyle(color: AppColors.primary, fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
