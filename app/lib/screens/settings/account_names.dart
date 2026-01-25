import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';

class AccountNamesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final Function(Map<String, String>) onNamesUpdated;

  const AccountNamesScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    required this.onNamesUpdated,
  });

  @override
  State<AccountNamesScreen> createState() => _AccountNamesScreenState();
}

class _AccountNamesScreenState extends State<AccountNamesScreen> {
  late Map<String, TextEditingController> _controllers;
  late Map<String, String> _names;

  @override
  void initState() {
    super.initState();
    _names = Map.from(widget.accountNames);
    _controllers = {};
    
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final currentName = _names[accountNum] ?? '';
      _controllers[accountNum] = TextEditingController(text: currentName);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _saveNames() async {
    // Update names from controllers
    for (final account in widget.accounts) {
      final accountNum = account['account'] as String? ?? '';
      final newName = _controllers[accountNum]?.text.trim() ?? '';
      if (newName.isNotEmpty) {
        _names[accountNum] = newName;
      } else {
        _names.remove(accountNum);
      }
    }

    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_names', jsonEncode(_names));

    // Notify parent
    widget.onNamesUpdated(_names);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account names saved'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Account Names', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _saveNames,
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
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: widget.accounts.length,
                itemBuilder: (context, index) {
                  final account = widget.accounts[index];
                  final accountNum = account['account'] as String? ?? '';
                  final broker = account['broker'] as String? ?? '';
                  final server = account['server'] as String? ?? '';

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
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  accountNum,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  broker,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Display Name',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _controllers[accountNum],
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter custom name (optional)',
                          hintStyle: TextStyle(
                            color: AppColors.textSecondary.withOpacity(0.5),
                          ),
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
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          suffixIcon: _controllers[accountNum]?.text.isNotEmpty == true
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: AppColors.textSecondary,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _controllers[accountNum]?.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Server: $server',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}