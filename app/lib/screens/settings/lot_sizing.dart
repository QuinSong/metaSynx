import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class LotSizingScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final Map<String, double> lotRatios;
  final Function(String?) onMainAccountUpdated;
  final Function(Map<String, double>) onLotRatiosUpdated;

  const LotSizingScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    required this.mainAccountNum,
    required this.lotRatios,
    required this.onMainAccountUpdated,
    required this.onLotRatiosUpdated,
  });

  @override
  State<LotSizingScreen> createState() => _LotSizingScreenState();
}

class _LotSizingScreenState extends State<LotSizingScreen> {
  late String? _mainAccountNum;
  late Map<String, double> _lotRatios;
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _mainAccountNum = widget.mainAccountNum;
    _lotRatios = Map.from(widget.lotRatios);
    _controllers = {};
    
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final ratio = _lotRatios[accountNum] ?? 1.0;
      _controllers[accountNum] = TextEditingController(text: ratio.toString());
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getAccountDisplayName(String accountNum) {
    final customName = widget.accountNames[accountNum];
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    return accountNum;
  }

  Future<void> _saveSettings() async {
    // Update ratios from controllers
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final text = _controllers[accountNum]?.text.trim() ?? '1.0';
      final ratio = double.tryParse(text) ?? 1.0;
      _lotRatios[accountNum] = ratio;
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('main_account', _mainAccountNum ?? '');
    await prefs.setString('lot_ratios', jsonEncode(_lotRatios));

    // Notify parent
    widget.onMainAccountUpdated(_mainAccountNum);
    widget.onLotRatiosUpdated(_lotRatios);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lot sizing saved'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _buildExampleCalculation() {
    // Calculate example with 0.10 lots
    const baseLots = 0.10;
    final examples = <String>[];
    
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final text = _controllers[accountNum]?.text ?? '1.0';
      final ratio = double.tryParse(text) ?? 1.0;
      final calculatedLots = (baseLots * ratio).toStringAsFixed(2);
      final name = _getAccountDisplayName(accountNum);
      examples.add('$name: $calculatedLots lots');
    }
    
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryWithOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.calculate, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Example: Opening 0.10 lots',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...examples.map((ex) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '• $ex',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Lot Sizing', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveSettings,
            child: const Text(
              'SAVE',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: widget.accounts.isEmpty
            ? const Center(
                child: Text(
                  'No accounts connected',
                  style: AppTextStyles.body,
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, 
                            color: Colors.orange, 
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Set up proportional lot sizing across accounts. '
                              'Select a main account with base lot size (1.0), then set ratios for other accounts. '
                              'Example: If main account has ratio 1.0 and another has 1.5, '
                              'opening 0.1 lots will place 0.1 on main and 0.15 on the other.',
                              style: TextStyle(
                                color: Colors.orange.shade200,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Main Account Selection
                  const Text(
                    'MAIN ACCOUNT',
                    style: AppTextStyles.label,
                  ),
                  const SizedBox(height: 12),
                  
                  ...widget.accounts.map((account) {
                    final accountNum = account['account'] as String? ?? '';
                    final isMain = _mainAccountNum == accountNum;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _mainAccountNum = accountNum;
                          _controllers[accountNum]?.text = '1.0';
                          _lotRatios[accountNum] = 1.0;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isMain ? AppColors.primaryWithOpacity(0.15) : AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isMain ? AppColors.primary : AppColors.border,
                            width: isMain ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isMain ? Icons.check_circle : Icons.circle_outlined,
                              color: isMain ? AppColors.primary : AppColors.textSecondary,
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getAccountDisplayName(accountNum),
                                    style: TextStyle(
                                      color: isMain ? Colors.white : AppColors.textSecondary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (widget.accountNames[accountNum]?.isNotEmpty == true)
                                    Text(
                                      accountNum,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (isMain)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'MAIN',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
                  
                  const SizedBox(height: 24),
                  
                  // Example calculation
                  if (_mainAccountNum != null) ...[
                    _buildExampleCalculation(),
                    const SizedBox(height: 24),
                  ],
                  
                  // Lot Ratios
                  const Text(
                    'LOT RATIOS',
                    style: AppTextStyles.label,
                  ),
                  const SizedBox(height: 12),
                  
                  if (_mainAccountNum == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade300, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Please select a main account above to configure lot ratios.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...widget.accounts.map((account) {
                      final accountNum = account['account'] as String? ?? '';
                      final isMain = _mainAccountNum == accountNum;
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _getAccountDisplayName(accountNum),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (widget.accountNames[accountNum]?.isNotEmpty == true)
                                    Text(
                                      accountNum,
                                      style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (isMain)
                              Container(
                                width: 80,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryWithOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '1.0',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              SizedBox(
                                width: 80,
                                child: TextField(
                                  controller: _controllers[accountNum],
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white, fontSize: 14),
                                  onChanged: (_) => setState(() {}),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: AppColors.background,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.border),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.border),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(color: AppColors.primary),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            const Text(
                              'x',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
              ],
            ),
          ),
      ),
    );
  }
}