import 'package:flutter/material.dart';
import '../core/theme.dart';

class NewOrderScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final void Function({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required List<int> accountIndices,
  }) onPlaceOrder;

  const NewOrderScreen({
    super.key,
    required this.accounts,
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

  String _orderType = 'buy';
  late Set<int> _selectedAccountIndices;
  bool _isPlacing = false;

  final List<String> _commonPairs = [
    'EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'AUDUSD',
    'USDCAD', 'NZDUSD', 'XAUUSD', 'XAGUSD', 'BTCUSD',
  ];

  @override
  void initState() {
    super.initState();
    // Select all accounts by default
    _selectedAccountIndices = widget.accounts
        .map((a) => a['index'] as int)
        .toSet();
  }

  @override
  void dispose() {
    _symbolController.dispose();
    _lotsController.dispose();
    _tpController.dispose();
    _slController.dispose();
    super.dispose();
  }

  void _placeOrder() {
    final symbol = _symbolController.text.trim().toUpperCase();
    final lotsText = _lotsController.text.trim();
    final tpText = _tpController.text.trim();
    final slText = _slController.text.trim();

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

    final tp = tpText.isNotEmpty ? double.tryParse(tpText) : null;
    final sl = slText.isNotEmpty ? double.tryParse(slText) : null;

    setState(() => _isPlacing = true);

    widget.onPlaceOrder(
      symbol: symbol,
      type: _orderType,
      lots: lots,
      tp: tp,
      sl: sl,
      accountIndices: _selectedAccountIndices.toList(),
    );

    // Show confirmation and go back
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Placing ${_orderType.toUpperCase()} $lots $symbol on ${_selectedAccountIndices.length} account(s)',
        ),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('New Order', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
                        _orderType == 'buy' ? 'PLACE BUY ORDER' : 'PLACE SELL ORDER',
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
    );
  }

  Widget _buildSymbolField() {
    return TextField(
      controller: _symbolController,
      style: const TextStyle(color: Colors.white, fontSize: 18),
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        hintText: 'e.g. EURUSD',
        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildQuickPairs() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _commonPairs.map((pair) {
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
              borderRadius: BorderRadius.circular(16),
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
                  color: _orderType == 'buy' ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'BUY',
                    style: TextStyle(
                      color: _orderType == 'buy' ? Colors.black : AppColors.textSecondary,
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
                  color: _orderType == 'sell' ? AppColors.error : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'SELL',
                    style: TextStyle(
                      color: _orderType == 'sell' ? Colors.white : AppColors.textSecondary,
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

  Widget _buildAccountsSelection() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.accounts.map((account) {
        final index = account['index'] as int;
        final accountNum = account['account'] as String? ?? 'Unknown';
        final name = account['name'] as String? ?? '';
        final isSelected = _selectedAccountIndices.contains(index);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedAccountIndices.remove(index);
              } else {
                _selectedAccountIndices.add(index);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryWithOpacity(0.2) : AppColors.surface,
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
                  color: isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountNum,
                      style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (name.isNotEmpty)
                      Text(
                        name,
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
    );
  }

  Widget _buildLotsField() {
    return Row(
      children: [
        IconButton(
          onPressed: () {
            final current = double.tryParse(_lotsController.text) ?? 0.01;
            if (current > 0.01) {
              _lotsController.text = (current - 0.01).toStringAsFixed(2);
            }
          },
          icon: const Icon(Icons.remove_circle_outline, color: AppColors.primary),
        ),
        Expanded(
          child: TextField(
            controller: _lotsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        IconButton(
          onPressed: () {
            final current = double.tryParse(_lotsController.text) ?? 0.01;
            _lotsController.text = (current + 0.01).toStringAsFixed(2);
          },
          icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
        ),
      ],
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}