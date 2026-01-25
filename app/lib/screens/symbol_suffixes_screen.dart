import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';

class SymbolSuffixesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final Map<String, String> symbolSuffixes;
  final Function(Map<String, String>) onSymbolSuffixesUpdated;

  const SymbolSuffixesScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    required this.symbolSuffixes,
    required this.onSymbolSuffixesUpdated,
  });

  @override
  State<SymbolSuffixesScreen> createState() => _SymbolSuffixesScreenState();
}

class _SymbolSuffixesScreenState extends State<SymbolSuffixesScreen> {
  late Map<String, String> _suffixes;
  late Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _suffixes = Map.from(widget.symbolSuffixes);
    _controllers = {};
    
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final suffix = _suffixes[accountNum] ?? '';
      _controllers[accountNum] = TextEditingController(text: suffix);
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
    // Update suffixes from controllers
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final suffix = _controllers[accountNum]?.text.trim() ?? '';
      _suffixes[accountNum] = suffix;
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('symbol_suffixes', jsonEncode(_suffixes));

    // Notify parent
    widget.onSymbolSuffixesUpdated(_suffixes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Symbol suffixes saved'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }

  Widget _buildExampleCard() {
    final examples = <String>[];
    
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final suffix = _controllers[accountNum]?.text ?? '';
      final name = _getAccountDisplayName(accountNum);
      if (suffix.isNotEmpty) {
        examples.add('$name: XAUUSD → XAUUSD$suffix');
      } else {
        examples.add('$name: XAUUSD → XAUUSD (no suffix)');
      }
    }
    
    if (examples.isEmpty) return const SizedBox.shrink();
    
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
              Icon(Icons.swap_horiz, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Text(
                'Example: Placing order on XAUUSD',
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
        title: const Text('Symbol Suffixes', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
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
      body: widget.accounts.isEmpty
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
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, 
                          color: AppColors.textSecondary.withOpacity(0.7), 
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Set symbol suffixes for each account. For example, if your broker uses '
                            '"XAUUSD-VIP" or "EURUSD.std", enter the suffix here. '
                            'When placing orders, the suffix will be automatically appended.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Example
                  _buildExampleCard(),
                  
                  const SizedBox(height: 24),
                  
                  // Suffix inputs
                  const Text(
                    'ACCOUNT SUFFIXES',
                    style: AppTextStyles.label,
                  ),
                  const SizedBox(height: 12),
                  
                  ...widget.accounts.map((account) {
                    final accountNum = account['account'] as String? ?? '';
                    final broker = account['broker'] as String? ?? '';
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryWithOpacity(0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.account_balance,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getAccountDisplayName(accountNum),
                                      style: const TextStyle(
                                        color: Colors.white,
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
                                    if (broker.isNotEmpty)
                                      Text(
                                        broker,
                                        style: const TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _controllers[accountNum],
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Symbol Suffix',
                              labelStyle: TextStyle(
                                color: AppColors.textMuted.withOpacity(0.7),
                                fontSize: 12,
                              ),
                              hintText: 'e.g. -VIP, .std, _micro',
                              hintStyle: TextStyle(
                                color: AppColors.textMuted.withOpacity(0.5),
                                fontSize: 13,
                              ),
                              filled: true,
                              fillColor: AppColors.background,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(color: AppColors.primary),
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}