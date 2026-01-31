import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme.dart';
import 'account_names.dart';
import 'lot_sizing.dart';
import 'symbol_suffixes.dart';
import 'preferred_symbols.dart';

class SettingsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Map<String, String> accountNames;
  final Set<String> hiddenAccounts;
  final String? mainAccountNum;
  final Map<String, double> lotRatios;
  final Map<String, String> symbolSuffixes;
  final Set<String> preferredPairs;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final Function(Map<String, String>) onNamesUpdated;
  final Function(Set<String>) onHiddenAccountsUpdated;
  final Function(String?) onMainAccountUpdated;
  final Function(Map<String, double>) onLotRatiosUpdated;
  final Function(Map<String, String>) onSymbolSuffixesUpdated;
  final Function(Set<String>) onPreferredPairsUpdated;
  final Function(bool) onIncludeCommissionSwapUpdated;
  final Function(bool) onShowPLPercentUpdated;
  final Function(bool) onConfirmBeforeCloseUpdated;

  const SettingsScreen({
    super.key,
    required this.accounts,
    required this.accountNames,
    required this.hiddenAccounts,
    required this.mainAccountNum,
    required this.lotRatios,
    required this.symbolSuffixes,
    required this.preferredPairs,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onNamesUpdated,
    required this.onHiddenAccountsUpdated,
    required this.onMainAccountUpdated,
    required this.onLotRatiosUpdated,
    required this.onSymbolSuffixesUpdated,
    required this.onPreferredPairsUpdated,
    required this.onIncludeCommissionSwapUpdated,
    required this.onShowPLPercentUpdated,
    required this.onConfirmBeforeCloseUpdated,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, String> _accountNames;
  late Set<String> _hiddenAccounts;
  late String? _mainAccountNum;
  late Map<String, double> _lotRatios;
  late Map<String, String> _symbolSuffixes;
  late Set<String> _preferredPairs;
  late bool _includeCommissionSwap;
  late bool _showPLPercent;
  late bool _confirmBeforeClose;

  @override
  void initState() {
    super.initState();
    _accountNames = Map.from(widget.accountNames);
    _hiddenAccounts = Set.from(widget.hiddenAccounts);
    _mainAccountNum = widget.mainAccountNum;
    _lotRatios = Map.from(widget.lotRatios);
    _symbolSuffixes = Map.from(widget.symbolSuffixes);
    _preferredPairs = Set.from(widget.preferredPairs);
    _includeCommissionSwap = widget.includeCommissionSwap;
    _showPLPercent = widget.showPLPercent;
    _confirmBeforeClose = widget.confirmBeforeClose;
  }

  Future<void> _toggleCommissionSwap(bool value) async {
    setState(() {
      _includeCommissionSwap = value;
    });

    // Save to prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('include_commission_swap', value);

    // Notify parent
    widget.onIncludeCommissionSwapUpdated(value);
  }

  Future<void> _toggleConfirmBeforeClose(bool value) async {
    setState(() {
      _confirmBeforeClose = value;
    });

    // Save to prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirm_before_close', value);

    // Notify parent
    widget.onConfirmBeforeCloseUpdated(value);
  }

  Future<void> _toggleShowPLPercent(bool value) async {
    setState(() {
      _showPLPercent = value;
    });

    // Save to prefs
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_pl_percent', value);

    // Notify parent
    widget.onShowPLPercentUpdated(value);
  }

  void _openAccountNames() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountNamesScreen(
          accounts: widget.accounts,
          accountNames: _accountNames,
          hiddenAccounts: _hiddenAccounts,
          onNamesUpdated: (names) {
            setState(() {
              _accountNames = names;
            });
            widget.onNamesUpdated(names);
          },
          onHiddenAccountsUpdated: (hidden) {
            setState(() {
              _hiddenAccounts = hidden;
            });
            widget.onHiddenAccountsUpdated(hidden);
          },
        ),
      ),
    );
  }

  void _openLotSizing() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LotSizingScreen(
          accounts: widget.accounts,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          lotRatios: _lotRatios,
          onMainAccountUpdated: (mainAccount) {
            setState(() {
              _mainAccountNum = mainAccount;
            });
            widget.onMainAccountUpdated(mainAccount);
          },
          onLotRatiosUpdated: (ratios) {
            setState(() {
              _lotRatios = ratios;
            });
            widget.onLotRatiosUpdated(ratios);
          },
        ),
      ),
    );
  }

  void _openSymbolSuffixes() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SymbolSuffixesScreen(
          accounts: widget.accounts,
          accountNames: _accountNames,
          symbolSuffixes: _symbolSuffixes,
          onSymbolSuffixesUpdated: (suffixes) {
            setState(() {
              _symbolSuffixes = suffixes;
            });
            widget.onSymbolSuffixesUpdated(suffixes);
          },
        ),
      ),
    );
  }

  void _openPreferredPairs() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PreferredSymbolsScreen(
          selectedPairs: _preferredPairs,
          onPairsUpdated: (pairs) {
            setState(() {
              _preferredPairs = pairs;
            });
            widget.onPreferredPairsUpdated(pairs);
          },
        ),
      ),
    );
  }

  String _getMainAccountDisplay() {
    if (_mainAccountNum == null) return 'Not set';
    final customName = _accountNames[_mainAccountNum];
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    return _mainAccountNum!;
  }

  int _getNamedAccountsCount() {
    return _accountNames.values.where((name) => name.isNotEmpty).length;
  }

  int _getSuffixesCount() {
    return _symbolSuffixes.values.where((suffix) => suffix.isNotEmpty).length;
  }

  int _getPreferredPairsCount() {
    return _preferredPairs.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Account Names Card
            _buildNavigationCard(
              icon: Icons.badge_outlined,
              title: 'Account Names',
              subtitle:
                  '${_getNamedAccountsCount()} of ${widget.accounts.length} accounts named',
              onTap: _openAccountNames,
            ),

            const SizedBox(height: 12),

            // Lot Sizing Card
            _buildNavigationCard(
              icon: Icons.scale_outlined,
              title: 'Lot Sizing',
              subtitle: _mainAccountNum != null
                  ? 'Main account: ${_getMainAccountDisplay()}'
                  : 'Configure proportional lot sizes',
              onTap: _openLotSizing,
            ),

            const SizedBox(height: 12),

            // Preferred Symbols Card
            _buildNavigationCard(
              icon: Icons.currency_exchange_outlined,
              title: 'Preferred Symbols',
              subtitle: _getPreferredPairsCount() > 0
                  ? '${_getPreferredPairsCount()} symbol${_getPreferredPairsCount() == 1 ? '' : 's'} selected'
                  : 'Choose symbols for new orders',
              onTap: _openPreferredPairs,
            ),

            const SizedBox(height: 12),

            // Symbol Suffixes Card
            _buildNavigationCard(
              icon: Icons.text_fields_outlined,
              title: 'Symbol Suffixes',
              subtitle: _getSuffixesCount() > 0
                  ? '${_getSuffixesCount()} suffix${_getSuffixesCount() == 1 ? '' : 'es'} configured'
                  : 'Add broker symbol suffixes',
              onTap: _openSymbolSuffixes,
            ),

            const SizedBox(height: 12),

            // Confirm Before Close Checkbox
            GestureDetector(
              onTap: () => _toggleConfirmBeforeClose(!_confirmBeforeClose),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryWithOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Confirm Before Closing',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _confirmBeforeClose
                                ? 'Show confirmation dialog before closing positions'
                                : 'Close positions without confirmation',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _confirmBeforeClose
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _confirmBeforeClose
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                      child: _confirmBeforeClose
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.black,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Include Commission & Swap Checkbox
            GestureDetector(
              onTap: () => _toggleCommissionSwap(!_includeCommissionSwap),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryWithOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calculate_outlined,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Include Commission & Swap',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _includeCommissionSwap
                                ? 'P/L includes commission and swap fees'
                                : 'P/L shows raw profit only',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _includeCommissionSwap
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _includeCommissionSwap
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                      child: _includeCommissionSwap
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.black,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Show P/L % Checkbox
            GestureDetector(
              onTap: () => _toggleShowPLPercent(!_showPLPercent),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryWithOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.percent,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Show P/L %',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _showPLPercent
                                ? 'Display P/L as percentage of balance'
                                : 'P/L percentage hidden',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _showPLPercent
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: _showPLPercent
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                      child: _showPLPercent
                          ? const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.black,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primaryWithOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.textSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
