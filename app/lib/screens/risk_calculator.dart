import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:intl/intl.dart';
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
    required String orderType,
    required String lots,
    String? sl,
    String? tp,
  }) onOpenNewOrder;
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
    required this.onOpenNewOrder,
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
  final _currencyFormat = NumberFormat('#,##0.00', 'en_US');
  
  double _lotSize = 0;
  double _potentialLoss = 0;
  double _potentialProfit = 0;
  double _riskRewardRatio = 0;
  double _pipValue = 0;
  double _slPips = 0;
  double _tpPips = 0;
  
  String _riskMode = 'percent';
  String _orderType = 'buy';
  int? _selectedAccountIndex;
  double _accountBalance = 0;
  String _accountCurrency = 'USD';
  bool _applySuffix = false; // Will be set based on whether suffix exists
  
  StreamSubscription<Map<String, dynamic>>? _symbolInfoSubscription;
  Map<String, Map<String, dynamic>> _cachedSymbolInfo = {};
  bool _isLoadingSymbolInfo = false;
  String? _currentSymbolInfoRequest;
  int _symbolDigits = 5;
  double _minLot = 0.01;
  double _maxLot = 100.0;
  double _lotStep = 0.01;
  double _brokerPipValue = 0;
  double _pipSize = 0.0001;
  
  bool _hasSearched = false;
  bool _symbolNotFound = false;
  String? _symbolError;
  double _currentBid = 0;
  double _currentAsk = 0;
  double _suggestedSL = 0;
  double _suggestedTP = 0;
  
  static const double _defaultSLPips = 50;
  static const double _defaultTPPips = 100;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _symbolInfoSubscription = widget.symbolInfoStream?.listen(_handleSymbolInfo);
    
    if (widget.accounts.isNotEmpty) {
      if (widget.mainAccountNum != null) {
        final mainIdx = widget.accounts.indexWhere((a) => a['account'] == widget.mainAccountNum);
        if (mainIdx >= 0) _selectedAccountIndex = mainIdx;
      }
      _selectedAccountIndex ??= 0;
      _updateAccountInfo();
      _updateSuffixState(); // Set initial suffix state
    }
    
    _entryController.addListener(_calculate);
    _slController.addListener(_calculate);
    _tpController.addListener(_calculate);
    _riskPercentController.addListener(_calculate);
    _riskAmountController.addListener(_calculate);
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

  String _getCurrentSuffix() {
    if (_selectedAccountIndex == null) return '';
    final account = widget.accounts[_selectedAccountIndex!];
    final accountNum = account['account']?.toString() ?? '';
    return widget.symbolSuffixes[accountNum] ?? '';
  }

  void _updateSuffixState() {
    final suffix = _getCurrentSuffix();
    // Only enable suffix toggle if a suffix is configured for this account
    setState(() {
      _applySuffix = suffix.isNotEmpty;
    });
  }

  String _getSymbolWithSuffix(String symbol) {
    if (!_applySuffix) return symbol;
    final suffix = _getCurrentSuffix();
    if (suffix.isNotEmpty && !symbol.endsWith(suffix)) return symbol + suffix;
    return symbol;
  }

  void _onSearch() {
    final symbol = _symbolController.text.toUpperCase().trim();
    if (symbol.isEmpty) return;
    
    final symbolWithSuffix = _getSymbolWithSuffix(symbol);
    
    if (_cachedSymbolInfo.containsKey(symbolWithSuffix)) {
      _applySymbolInfo(_cachedSymbolInfo[symbolWithSuffix]!);
      setState(() => _hasSearched = true);
      return;
    }
    
    if (widget.onRequestSymbolInfo != null && _selectedAccountIndex != null) {
      final terminalIndex = widget.accounts[_selectedAccountIndex!]['index'] as int? ?? 0;
      setState(() {
        _isLoadingSymbolInfo = true;
        _currentSymbolInfoRequest = symbolWithSuffix;
      });
      widget.onRequestSymbolInfo!(symbolWithSuffix, terminalIndex);
    }
  }

  void _handleSymbolInfo(Map<String, dynamic> info) {
    final symbol = info['symbol'] as String?;
    if (symbol == null) return;
    
    // Check if symbol is valid
    final isValid = info['valid'] as bool? ?? true;
    final error = info['error'] as String?;
    
    if (!isValid || error != null) {
      setState(() {
        _isLoadingSymbolInfo = false;
        _symbolNotFound = true;
        _symbolError = error ?? 'Symbol not found';
        _hasSearched = false;
      });
      return;
    }
    
    // Cache the info
    _cachedSymbolInfo[symbol] = info;
    
    // Apply if it's for the current symbol
    if (symbol == _currentSymbolInfoRequest) {
      _applySymbolInfo(info);
      setState(() {
        _hasSearched = true;
        _symbolNotFound = false;
        _symbolError = null;
      });
    }
  }

  void _applySymbolInfo(Map<String, dynamic> info) {
    final bid = (info['bid'] as num?)?.toDouble() ?? 0;
    final ask = (info['ask'] as num?)?.toDouble() ?? 0;
    final digits = (info['digits'] as num?)?.toInt() ?? 5;
    final pipSize = (info['pipSize'] as num?)?.toDouble() ?? 0.0001;
    final pipValue = (info['pipValue'] as num?)?.toDouble() ?? 0;
    
    setState(() {
      _isLoadingSymbolInfo = false;
      _brokerPipValue = pipValue;
      _pipValue = pipValue > 0 ? pipValue : 10.0; // Update pip value immediately
      _pipSize = pipSize > 0 ? pipSize : 0.0001;
      _symbolDigits = digits;
      _minLot = (info['minLot'] as num?)?.toDouble() ?? 0.01;
      _maxLot = (info['maxLot'] as num?)?.toDouble() ?? 100.0;
      _lotStep = (info['lotStep'] as num?)?.toDouble() ?? 0.01;
      _currentBid = bid;
      _currentAsk = ask;
      
      if (_orderType == 'buy' && ask > 0) {
        _entryController.text = ask.toStringAsFixed(digits);
      } else if (_orderType == 'sell' && bid > 0) {
        _entryController.text = bid.toStringAsFixed(digits);
      }
      
      final entryPrice = _orderType == 'buy' ? ask : bid;
      if (entryPrice > 0) {
        if (_orderType == 'buy') {
          _suggestedSL = entryPrice - (_defaultSLPips * _pipSize);
          _suggestedTP = entryPrice + (_defaultTPPips * _pipSize);
        } else {
          _suggestedSL = entryPrice + (_defaultSLPips * _pipSize);
          _suggestedTP = entryPrice - (_defaultTPPips * _pipSize);
        }
      }
    });
    _calculate();
  }

  void _onReset() {
    setState(() {
      _hasSearched = false;
      _isLoadingSymbolInfo = false;
      _symbolNotFound = false;
      _symbolError = null;
      _entryController.clear();
      _slController.clear();
      _tpController.clear();
      _lotSize = 0;
      _potentialLoss = 0;
      _potentialProfit = 0;
      _riskRewardRatio = 0;
      _slPips = 0;
      _tpPips = 0;
      _currentBid = 0;
      _currentAsk = 0;
      _suggestedSL = 0;
      _suggestedTP = 0;
      _brokerPipValue = 0;
      _pipValue = 0;
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSymbol = prefs.getString('calc_symbol');
    final savedRiskPercent = prefs.getString('calc_risk_percent');
    if (savedSymbol != null) _symbolController.text = savedSymbol;
    if (savedRiskPercent != null) _riskPercentController.text = savedRiskPercent;
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('calc_symbol', _symbolController.text);
    await prefs.setString('calc_risk_percent', _riskPercentController.text);
  }

  void _updateAccountInfo() {
    if (_selectedAccountIndex != null && _selectedAccountIndex! < widget.accounts.length) {
      final account = widget.accounts[_selectedAccountIndex!];
      setState(() {
        _accountBalance = (account['balance'] as num?)?.toDouble() ?? 0;
        _accountCurrency = account['currency'] as String? ?? 'USD';
      });
    }
  }

  void _calculate() {
    final entry = double.tryParse(_entryController.text) ?? 0;
    final sl = double.tryParse(_slController.text) ?? 0;
    final tp = double.tryParse(_tpController.text) ?? 0;
    
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
    
    double pipSize = _pipSize > 0 ? _pipSize : 0.0001;
    
    double slDistance = _orderType == 'buy' ? (entry - sl) / pipSize : (sl - entry) / pipSize;
    double tpDistance = 0;
    if (tp > 0) {
      tpDistance = _orderType == 'buy' ? (tp - entry) / pipSize : (entry - tp) / pipSize;
    }
    
    double pipValuePerLot = _brokerPipValue > 0 ? _brokerPipValue : 10.0;
    
    double riskAmount = _riskMode == 'percent'
        ? _accountBalance * ((double.tryParse(_riskPercentController.text) ?? 0) / 100)
        : double.tryParse(_riskAmountController.text) ?? 0;
    
    double lotSize = 0;
    if (slDistance > 0 && pipValuePerLot > 0) {
      lotSize = riskAmount / (slDistance * pipValuePerLot);
      if (_lotStep > 0) {
        lotSize = (lotSize / _lotStep).floor() * _lotStep;
      } else {
        lotSize = (lotSize * 100).floor() / 100;
      }
      if (lotSize < _minLot) lotSize = _minLot;
      if (lotSize > _maxLot) lotSize = _maxLot;
    }
    
    final potentialLoss = slDistance * pipValuePerLot * lotSize;
    final potentialProfit = tp > 0 ? tpDistance * pipValuePerLot * lotSize : 0.0;
    double rrRatio = (slDistance > 0 && tpDistance > 0) ? tpDistance / slDistance : 0;
    
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

  void _openNewOrderScreen() {
    if (_lotSize <= 0) return;
    
    final sl = _slController.text.trim();
    final tp = _tpController.text.trim();
    final symbol = _symbolController.text.toUpperCase();
    
    _savePreferences();
    
    // Pop calculator screen first, then open new order
    Navigator.pop(context);
    
    widget.onOpenNewOrder(
      symbol: symbol,
      orderType: _orderType,
      lots: _lotSize.toStringAsFixed(2),
      sl: sl.isNotEmpty ? sl : null,
      tp: tp.isNotEmpty ? tp : null,
    );
  }

  String _getAccountDisplayName(int index) {
    if (index >= widget.accounts.length) return 'Account';
    final account = widget.accounts[index];
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  String _formatRR(double ratio) {
    if (ratio <= 0) return '—';
    // Remove unnecessary trailing zeros
    String formatted = ratio.toStringAsFixed(2);
    if (formatted.endsWith('0')) formatted = formatted.substring(0, formatted.length - 1);
    if (formatted.endsWith('0')) formatted = formatted.substring(0, formatted.length - 1);
    if (formatted.endsWith('.')) formatted = formatted.substring(0, formatted.length - 1);
    return '1:$formatted';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        toolbarHeight: 50,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Risk Calculator', style: TextStyle(color: Colors.white, fontSize: 18)),
        actions: [
          if (_hasSearched)
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
              onPressed: _onReset,
              tooltip: 'Reset',
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSearchSection(),
              if (_hasSearched) ...[
                const SizedBox(height: 16),
                _buildResultsCard(),
                const SizedBox(height: 16),
                _buildSectionTitle('ORDER TYPE'),
                const SizedBox(height: 8),
                _buildOrderTypeToggle(),
                const SizedBox(height: 16),
                _buildSectionTitle('PRICE LEVELS'),
                const SizedBox(height: 8),
                _buildPriceField('Entry Price', _entryController, null),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildPriceField(
                      'Stop Loss', 
                      _slController, 
                      _suggestedSL > 0 ? _suggestedSL.toStringAsFixed(_symbolDigits) : null,
                      borderColor: AppColors.error.withOpacity(0.5),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _buildPriceField(
                      'Take Profit', 
                      _tpController, 
                      _suggestedTP > 0 ? _suggestedTP.toStringAsFixed(_symbolDigits) : null,
                      borderColor: AppColors.primary.withOpacity(0.5),
                    )),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSectionTitle('RISK SETTINGS'),
                const SizedBox(height: 8),
                _buildRiskModeSelector(),
                const SizedBox(height: 12),
                if (_riskMode == 'percent') ...[
                  _buildRiskField(),
                  const SizedBox(height: 8),
                  _buildQuickRiskButtons(),
                ] else
                  _buildAmountField(),
                const SizedBox(height: 20),
                _buildPlaceOrderButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    final suffix = _getCurrentSuffix();
    
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.all(_hasSearched ? 12 : 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hasSearched ? AppColors.border : AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_hasSearched) ...[
            _buildSectionTitle('ACCOUNT'),
            const SizedBox(height: 8),
            _buildAccountSelector(),
            const SizedBox(height: 16),
            _buildSectionTitle('SYMBOL'),
            const SizedBox(height: 8),
            _buildSymbolInput(suffix),
            if (_symbolNotFound) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _symbolError ?? 'Symbol not found',
                        style: const TextStyle(color: AppColors.error, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildSearchButton(),
          ] else
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getAccountDisplayName(_selectedAccountIndex ?? 0),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_currencyFormat.format(_accountBalance)} $_accountCurrency',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      _symbolController.text.toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    if (_applySuffix && suffix.isNotEmpty)
                      Text(suffix, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildAccountSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedAccountIndex,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
          items: List.generate(widget.accounts.length, (index) {
            final account = widget.accounts[index];
            final balance = (account['balance'] as num?)?.toDouble() ?? 0;
            final currency = account['currency'] as String? ?? 'USD';
            return DropdownMenuItem<int>(
              value: index,
              child: Row(
                children: [
                  Expanded(child: Text(_getAccountDisplayName(index), style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis)),
                  Text('${_currencyFormat.format(balance)} $currency', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            );
          }),
          onChanged: (value) {
            setState(() => _selectedAccountIndex = value);
            _updateAccountInfo();
            _updateSuffixState();
          },
        ),
      ),
    );
  }

  Widget _buildSymbolInput(String suffix) {
    final hasSuffix = suffix.isNotEmpty;
    
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _symbolController,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            onChanged: (_) {
              // Clear error when user types
              if (_symbolNotFound) {
                setState(() {
                  _symbolNotFound = false;
                  _symbolError = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: 'e.g. EURUSD',
              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        if (hasSuffix) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '+',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.w300,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _applySuffix = !_applySuffix;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _applySuffix ? AppColors.primary : AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _applySuffix ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_link,
                    color: _applySuffix ? Colors.white : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    suffix,
                    style: TextStyle(
                      color: _applySuffix ? Colors.white : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoadingSymbolInfo ? null : _onSearch,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _isLoadingSymbolInfo
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, color: Colors.black),
                  SizedBox(width: 8),
                  Text('SEARCH', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1));
  }

  Widget _buildOrderTypeToggle() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Expanded(child: _buildOrderTypeButton('buy', 'BUY', AppColors.primary, Colors.black)),
          Expanded(child: _buildOrderTypeButton('sell', 'SELL', AppColors.error, Colors.white)),
        ],
      ),
    );
  }

  Widget _buildOrderTypeButton(String type, String label, Color activeColor, Color textColor) {
    final isSelected = _orderType == type;
    return GestureDetector(
      onTap: () {
        if (_orderType == type) return; // No change needed
        
        setState(() {
          _orderType = type;
          // Clear SL and TP when switching order type
          _slController.clear();
          _tpController.clear();
          
          if (type == 'buy' && _currentAsk > 0) {
            _entryController.text = _currentAsk.toStringAsFixed(_symbolDigits);
            _suggestedSL = _currentAsk - (_defaultSLPips * _pipSize);
            _suggestedTP = _currentAsk + (_defaultTPPips * _pipSize);
          } else if (type == 'sell' && _currentBid > 0) {
            _entryController.text = _currentBid.toStringAsFixed(_symbolDigits);
            _suggestedSL = _currentBid + (_defaultSLPips * _pipSize);
            _suggestedTP = _currentBid - (_defaultTPPips * _pipSize);
          }
        });
        _calculate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: type == 'buy' ? const Radius.circular(9) : Radius.zero,
            right: type == 'sell' ? const Radius.circular(9) : Radius.zero,
          ),
        ),
        child: Center(child: Text(label, style: TextStyle(color: isSelected ? textColor : AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 14))),
      ),
    );
  }

  Widget _buildPriceField(String label, TextEditingController controller, String? hint, {Color? borderColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          onTap: () {
            if (hint != null && controller.text.isEmpty) {
              controller.text = hint;
            }
          },
          decoration: InputDecoration(
            hintText: hint ?? '0.00000',
            hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor ?? AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor ?? AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor ?? AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildRiskModeSelector() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Expanded(child: _buildRiskModeButton('percent', 'RISK %')),
          Expanded(child: _buildRiskModeButton('amount', 'FIXED \$')),
        ],
      ),
    );
  }

  Widget _buildRiskModeButton(String mode, String label) {
    final isSelected = _riskMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _riskMode = mode);
        _calculate();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: mode == 'percent' ? const Radius.circular(9) : Radius.zero,
            right: mode == 'amount' ? const Radius.circular(9) : Radius.zero,
          ),
        ),
        child: Center(child: Text(label, style: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12))),
      ),
    );
  }

  Widget _buildRiskField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Risk %', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _riskPercentController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: '1.0',
            suffixText: '%',
            suffixStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Risk Amount', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _riskAmountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: '100',
            suffixText: _accountCurrency,
            suffixStyle: const TextStyle(color: AppColors.textSecondary),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickRiskButtons() {
    return Row(
      children: [0.5, 1.0, 2.0, 3.0, 5.0].map((p) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(left: p == 0.5 ? 0 : 4, right: p == 5.0 ? 0 : 4),
          child: _buildQuickRiskButton(p),
        ),
      )).toList(),
    );
  }

  Widget _buildQuickRiskButton(double percent) {
    final isSelected = _riskPercentController.text == percent.toString();
    return GestureDetector(
      onTap: () => _setQuickRisk(percent),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withOpacity(0.2) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
        ),
        child: Center(child: Text('${percent.toString().replaceAll('.0', '')}%', style: TextStyle(color: isSelected ? AppColors.primary : AppColors.textSecondary, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))),
      ),
    );
  }

  Widget _buildResultsCard() {
    final riskAmount = _riskMode == 'percent'
        ? _accountBalance * ((double.tryParse(_riskPercentController.text) ?? 0) / 100)
        : double.tryParse(_riskAmountController.text) ?? 0;
    final hasBrokerData = _brokerPipValue > 0;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primaryWithOpacity(0.15), AppColors.primaryWithOpacity(0.05)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(hasBrokerData ? Icons.verified : Icons.info_outline, size: 12, color: hasBrokerData ? AppColors.primary : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(
                hasBrokerData ? 'Pip value: \$${_pipValue.toStringAsFixed(2)}/lot (broker)' : 'Pip value: \$${_pipValue.toStringAsFixed(2)}/lot (est.)',
                style: TextStyle(color: hasBrokerData ? AppColors.primary : AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('POSITION SIZE', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(_lotSize > 0 ? _lotSize.toStringAsFixed(2) : '—', style: const TextStyle(color: AppColors.primary, fontSize: 48, fontWeight: FontWeight.bold)),
          const Text('LOTS', style: TextStyle(color: AppColors.primary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: _buildStatItem('Risk', riskAmount > 0 ? '${_currencyFormat.format(riskAmount)} $_accountCurrency' : '—', AppColors.textSecondary)),
              Expanded(child: _buildStatItem('Loss', _potentialLoss > 0 ? '-${_currencyFormat.format(_potentialLoss)}' : '—', AppColors.error)),
              Expanded(child: _buildStatItem('Profit', _potentialProfit > 0 ? '+${_currencyFormat.format(_potentialProfit)}' : '—', AppColors.primary)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildStatItem('SL', _slPips > 0 ? '${_slPips.toStringAsFixed(1)} pips' : '—', AppColors.textSecondary)),
              Expanded(child: _buildStatItem('TP', _tpPips > 0 ? '${_tpPips.toStringAsFixed(1)} pips' : '—', AppColors.textSecondary)),
              Expanded(child: _buildStatItem('R:R', _formatRR(_riskRewardRatio), _riskRewardRatio >= 2 ? AppColors.primary : (_riskRewardRatio >= 1 ? Colors.orange : AppColors.error))),
            ],
          ),
          if (_riskRewardRatio > 0) ...[
            const SizedBox(height: 16),
            _buildRiskRewardBar(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRiskRewardBar() {
    final total = 1 + _riskRewardRatio;
    return Column(
      children: [
        SizedBox(
          height: 8,
          child: Row(
            children: [
              Flexible(flex: (100 / total).round(), child: Container(decoration: const BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.horizontal(left: Radius.circular(4))))),
              Flexible(flex: (100 * _riskRewardRatio / total).round(), child: Container(decoration: const BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.horizontal(right: Radius.circular(4))))),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Risk', style: TextStyle(color: AppColors.error, fontSize: 10)),
            Text('Reward', style: TextStyle(color: AppColors.primary, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceOrderButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _lotSize > 0 ? _openNewOrderScreen : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: _orderType == 'buy' ? AppColors.primary : AppColors.error,
          disabledBackgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _lotSize > 0 
                  ? '${_orderType.toUpperCase()} ${_lotSize.toStringAsFixed(2)} LOTS'
                  : 'ENTER SL TO CALCULATE',
              style: TextStyle(
                color: _lotSize > 0 ? Colors.white : AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_lotSize > 0) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward,
                color: Colors.white,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    );
  }
}