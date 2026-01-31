import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';

class NewOrderScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final Map<String, double> lotRatios;
  final Set<String> preferredPairs;
  final Map<String, String> symbolSuffixes;
  final String? initialSymbol;
  final String? initialOrderType;
  final String? initialLots;
  final String? initialSL;
  final String? initialTP;
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

  const NewOrderScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    required this.mainAccountNum,
    required this.lotRatios,
    required this.preferredPairs,
    required this.symbolSuffixes,
    this.initialSymbol,
    this.initialOrderType,
    this.initialLots,
    this.initialSL,
    this.initialTP,
    required this.onPlaceOrder,
  });

  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final _symbolController = TextEditingController();
  final _lotsController = TextEditingController(text: '0.01');
  final _tpController = TextEditingController();
  final _slController = TextEditingController();
  final _priceController = TextEditingController();

  String _orderType = 'buy';
  String _executionMode = 'market'; // market, limit, stop
  late Set<int> _selectedAccountIndices;
  bool _isPlacing = false;
  bool _applySuffix = true; // Whether to apply broker suffix to symbol

  // Default pairs if none selected in settings
  static const List<String> _defaultPairs = [
    'EURUSD',
    'GBPUSD',
    'USDJPY',
    'USDCHF',
    'AUDUSD',
    'USDCAD',
    'NZDUSD',
    'XAUUSD',
    'XAGUSD',
    'BTCUSD',
  ];

  List<String> get _displayPairs {
    if (widget.preferredPairs.isNotEmpty) {
      return widget.preferredPairs.toList()..sort();
    }
    return _defaultPairs;
  }

  List<Map<String, dynamic>> _getSortedAccounts() {
    final sorted = List<Map<String, dynamic>>.from(widget.accounts);
    sorted.sort((a, b) {
      final aIsMain = a['account'] == widget.mainAccountNum;
      final bIsMain = b['account'] == widget.mainAccountNum;
      if (aIsMain && !bIsMain) return -1;
      if (!aIsMain && bIsMain) return 1;
      return (a['index'] as int? ?? 0).compareTo(b['index'] as int? ?? 0);
    });
    return sorted;
  }

  @override
  void initState() {
    super.initState();
    // Select all accounts by default
    _selectedAccountIndices = widget.accounts
        .map((a) => a['index'] as int)
        .toSet();

    // Set initial order type if provided
    if (widget.initialOrderType != null) {
      _orderType = widget.initialOrderType!;
    }

    // Set initial lots if provided, otherwise load from preferences
    if (widget.initialLots != null && widget.initialLots!.isNotEmpty) {
      _lotsController.text = widget.initialLots!;
    } else {
      _loadSavedLots();
    }

    // Load saved suffix preference
    _loadSavedSuffixPref();

    // Set initial symbol if provided, detecting and stripping suffix
    if (widget.initialSymbol != null && widget.initialSymbol!.isNotEmpty) {
      _setSymbolWithSuffixDetection(widget.initialSymbol!);
    }

    // Set initial SL if provided
    if (widget.initialSL != null && widget.initialSL!.isNotEmpty) {
      _slController.text = widget.initialSL!;
    }

    // Set initial TP if provided
    if (widget.initialTP != null && widget.initialTP!.isNotEmpty) {
      _tpController.text = widget.initialTP!;
    }
  }

  Future<void> _loadSavedLots() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLots = prefs.getString('last_lots');
    if (savedLots != null && savedLots.isNotEmpty) {
      _lotsController.text = savedLots;
    }
  }

  Future<void> _saveLots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_lots', _lotsController.text);
  }

  Future<void> _loadSavedSuffixPref() async {
    final prefs = await SharedPreferences.getInstance();
    final savedSuffix = prefs.getBool('apply_suffix');
    if (savedSuffix != null) {
      setState(() {
        _applySuffix = savedSuffix;
      });
    }
  }

  Future<void> _saveSuffixPref() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('apply_suffix', _applySuffix);
  }

  void _setSymbolWithSuffixDetection(String symbol) {
    // Check if symbol ends with any configured suffix
    String? detectedSuffix;
    for (final suffix in widget.symbolSuffixes.values) {
      if (suffix.isNotEmpty &&
          symbol.toUpperCase().endsWith(suffix.toUpperCase())) {
        detectedSuffix = suffix;
        break;
      }
    }

    if (detectedSuffix != null) {
      // Strip suffix and enable suffix toggle
      final baseSymbol = symbol.substring(
        0,
        symbol.length - detectedSuffix.length,
      );
      _symbolController.text = baseSymbol;
      _applySuffix = true;
    } else {
      _symbolController.text = symbol;
      _applySuffix = false;
    }
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _lotsController.dispose();
    _tpController.dispose();
    _slController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  bool get _isMainAccountSelected {
    if (widget.mainAccountNum == null) return false;
    return _selectedAccountIndices.any((index) {
      final account = widget.accounts.firstWhere(
        (a) => a['index'] == index,
        orElse: () => <String, dynamic>{},
      );
      return account['account'] == widget.mainAccountNum;
    });
  }

  bool get _useRatios {
    // Use ratios only if main account is selected
    return _isMainAccountSelected;
  }

  void _toggleAccountSelection(int index) {
    final account = widget.accounts.firstWhere(
      (a) => a['index'] == index,
      orElse: () => <String, dynamic>{},
    );
    final accountNum = account['account'] as String? ?? '';
    final isMainAccount = accountNum == widget.mainAccountNum;
    final isSelected = _selectedAccountIndices.contains(index);

    setState(() {
      if (isSelected) {
        // Deselecting
        _selectedAccountIndices.remove(index);
      } else {
        // Selecting
        if (_isMainAccountSelected || isMainAccount) {
          // Main account is selected or we're selecting main - allow multiple
          _selectedAccountIndices.add(index);
        } else {
          // Main account not selected and we're not selecting main - only allow one
          _selectedAccountIndices.clear();
          _selectedAccountIndices.add(index);
        }
      }
    });
  }

  void _placeOrder() {
    final symbol = _symbolController.text.trim().toUpperCase();
    final lotsText = _lotsController.text.trim();
    final tpText = _tpController.text.trim();
    final slText = _slController.text.trim();
    final priceText = _priceController.text.trim();

    if (symbol.isEmpty) {
      _showError('Please enter a symbol');
      return;
    }

    final lots = double.tryParse(lotsText);
    if (lots == null || lots <= 0) {
      _showError('Please enter valid lot size');
      return;
    }

    if (_selectedAccountIndices.isEmpty) {
      _showError('Please select at least one account');
      return;
    }

    // For limit/stop orders, price is required
    double? price;
    if (_executionMode != 'market') {
      price = double.tryParse(priceText);
      if (price == null || price <= 0) {
        _showError('Please enter a valid price for ${_executionMode} order');
        return;
      }
    }

    final tp = tpText.isNotEmpty ? double.tryParse(tpText) : null;
    final sl = slText.isNotEmpty ? double.tryParse(slText) : null;

    setState(() => _isPlacing = true);

    // Save the lots for next time
    _saveLots();

    // Determine order type string based on execution mode
    // market: buy, sell
    // limit: buy_limit, sell_limit
    // stop: buy_stop, sell_stop
    String orderType = _orderType;
    if (_executionMode != 'market') {
      orderType = '${_orderType}_${_executionMode}';
    }

    widget.onPlaceOrder(
      symbol: symbol,
      type: orderType,
      lots: lots,
      tp: tp,
      sl: sl,
      price: price,
      accountIndices: _selectedAccountIndices.toList(),
      useRatios: _useRatios,
      applySuffix: _applySuffix,
    );

    // Show confirmation and go back
    final ratioMsg = _useRatios ? ' (with lot ratios)' : '';
    final modeMsg = _executionMode != 'market'
        ? ' ${_executionMode.toUpperCase()}'
        : '';
    final priceMsg = price != null ? ' @ $price' : '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Placing ${_orderType.toUpperCase()}$modeMsg $lots $symbol$priceMsg on ${_selectedAccountIndices.length} account(s)$ratioMsg',
        ),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'New Order',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Symbol
              const Text('SYMBOL', style: AppTextStyles.label),
              const SizedBox(height: 8),
              _buildSymbolField(),
              const SizedBox(height: 8),
              _buildQuickPairs(),

              const SizedBox(height: 24),

              // Buy/Sell toggle
              const Text('ORDER TYPE', style: AppTextStyles.label),
              const SizedBox(height: 8),
              _buildOrderTypeToggle(),

              const SizedBox(height: 24),

              // Execution mode (Market/Limit/Stop)
              const Text('EXECUTION', style: AppTextStyles.label),
              const SizedBox(height: 8),
              _buildExecutionModeToggle(),

              // Price field (only for limit/stop orders)
              if (_executionMode != 'market') ...[
                const SizedBox(height: 16),
                const Text('PRICE', style: AppTextStyles.label),
                const SizedBox(height: 8),
                _buildPendingPriceField(),
              ],

              const SizedBox(height: 24),

              // Accounts selection
              Text(
                'ACCOUNTS (${_selectedAccountIndices.length}/${widget.accounts.length})',
                style: AppTextStyles.label,
              ),
              const SizedBox(height: 8),
              _buildAccountsSelection(),

              const SizedBox(height: 24),

              // Lots
              const Text('LOT SIZE', style: AppTextStyles.label),
              const SizedBox(height: 8),
              _buildLotsField(),

              const SizedBox(height: 24),

              // TP/SL row
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TAKE PROFIT', style: AppTextStyles.label),
                        const SizedBox(height: 8),
                        _buildPriceField(_tpController, 'Optional'),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('STOP LOSS', style: AppTextStyles.label),
                        const SizedBox(height: 8),
                        _buildPriceField(_slController, 'Optional'),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Place Order button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isPlacing ? null : _placeOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _orderType == 'buy'
                        ? AppColors.primary
                        : AppColors.error,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isPlacing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _orderType == 'buy'
                              ? 'PLACE BUY ORDER'
                              : 'PLACE SELL ORDER',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSymbolField() {
    // Check if any suffix is configured
    final hasSuffixes = widget.symbolSuffixes.values.any((s) => s.isNotEmpty);

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _symbolController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: 'e.g. EURUSD',
              hintStyle: TextStyle(
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
          ),
        ),
        if (hasSuffixes) ...[
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
              _saveSuffixPref();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: _applySuffix ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _applySuffix ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                'Suffix',
                style: TextStyle(
                  color: _applySuffix ? Colors.white : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuickPairs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _displayPairs.map((pair) {
        final isSelected = _symbolController.text.toUpperCase() == pair;
        return GestureDetector(
          onTap: () {
            setState(() {
              _symbolController.text = pair;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Text(
              pair,
              style: TextStyle(
                color: isSelected ? Colors.black : AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildOrderTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _orderType = 'buy'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _orderType == 'buy'
                      ? AppColors.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'BUY',
                    style: TextStyle(
                      color: _orderType == 'buy'
                          ? Colors.black
                          : AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _orderType = 'sell'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: _orderType == 'sell'
                      ? AppColors.error
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'SELL',
                    style: TextStyle(
                      color: _orderType == 'sell'
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
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

  Widget _buildExecutionModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildExecutionModeButton('market', 'MARKET'),
          _buildExecutionModeButton('limit', 'LIMIT'),
          _buildExecutionModeButton('stop', 'STOP'),
        ],
      ),
    );
  }

  Widget _buildExecutionModeButton(String mode, String label) {
    final isSelected = _executionMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _executionMode = mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withOpacity(0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isSelected
                ? Border.all(color: AppColors.primary, width: 1)
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingPriceField() {
    return TextField(
      controller: _priceController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: 'Enter price',
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildAccountsSelection() {
    final hasMainAccount = widget.mainAccountNum != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Explanation text
        if (hasMainAccount)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _useRatios
                  ? AppColors.primaryWithOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _useRatios
                    ? AppColors.primaryWithOpacity(0.3)
                    : Colors.orange.withOpacity(0.3),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _useRatios ? Icons.auto_awesome : Icons.info_outline,
                  color: _useRatios ? AppColors.primary : Colors.orange,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _useRatios
                        ? 'Lot ratios enabled. Lots will be adjusted per account based on your settings.'
                        : 'Select main account to use lot ratios, or select one account to use exact lot size.',
                    style: TextStyle(
                      color: _useRatios
                          ? AppColors.textSecondary
                          : Colors.orange.shade200,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: AppColors.textSecondary,
                  size: 16,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No main account set. Go to Settings to configure lot ratios for multi-account trading.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Account buttons - sort with main account first
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _getSortedAccounts().map((account) {
            final index = account['index'] as int;
            final accountNum = account['account'] as String? ?? 'Unknown';
            final customName = widget.accountNames[accountNum];
            final displayName = (customName != null && customName.isNotEmpty)
                ? customName
                : accountNum;
            final hasCustomName = customName != null && customName.isNotEmpty;
            final isSelected = _selectedAccountIndices.contains(index);
            final isMainAccount = accountNum == widget.mainAccountNum;

            return GestureDetector(
              onTap: () => _toggleAccountSelection(index),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryWithOpacity(0.2)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.circle_outlined,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (isMainAccount) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'MAIN',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.black
                                        : AppColors.surface,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (hasCustomName)
                          Text(
                            accountNum,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.textSecondary
                                  : AppColors.textMuted,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildLotsField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // -0.1 button
          GestureDetector(
            onTap: () {
              final current = double.tryParse(_lotsController.text) ?? 0.01;
              if (current > 0.1) {
                _lotsController.text = (current - 0.1).toStringAsFixed(2);
              } else if (current > 0.01) {
                _lotsController.text = '0.01';
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '-0.1',
                style: TextStyle(
                  color: AppColors.error.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // -0.01 button
          GestureDetector(
            onTap: () {
              final current = double.tryParse(_lotsController.text) ?? 0.01;
              if (current > 0.01) {
                _lotsController.text = (current - 0.01).toStringAsFixed(2);
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '-0.01',
                style: TextStyle(
                  color: AppColors.error.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Lots input
          Expanded(
            child: TextField(
              controller: _lotsController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          // +0.01 button
          GestureDetector(
            onTap: () {
              final current = double.tryParse(_lotsController.text) ?? 0.01;
              _lotsController.text = (current + 0.01).toStringAsFixed(2);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '+0.01',
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // +0.1 button
          GestureDetector(
            onTap: () {
              final current = double.tryParse(_lotsController.text) ?? 0.01;
              _lotsController.text = (current + 0.1).toStringAsFixed(2);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                '+0.1',
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceField(TextEditingController controller, String hint) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
