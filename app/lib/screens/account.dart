import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../utils/formatters.dart';
import 'position.dart';

class AccountDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initialAccount;
  final ValueNotifier<List<Map<String, dynamic>>> accountsNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;
  // For PositionDetailScreen -> ChartScreen
  final Map<String, String> symbolSuffixes;
  final Map<String, double> lotRatios;
  final Set<String> preferredPairs;
  final void Function({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) onPlaceOrder;
  // Chart streaming
  final Stream<Map<String, dynamic>>? chartDataStream;
  final void Function(String symbol, String timeframe, int terminalIndex)? onRequestChartData;
  final void Function(String symbol, String timeframe, int terminalIndex)? onSubscribeChart;
  final void Function(int terminalIndex)? onUnsubscribeChart;

  const AccountDetailScreen({
    super.key,
    required this.initialAccount,
    required this.accountsNotifier,
    required this.positionsNotifier,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.accountNames,
    this.mainAccountNum,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onConfirmBeforeCloseChanged,
    required this.symbolSuffixes,
    required this.lotRatios,
    required this.preferredPairs,
    required this.onPlaceOrder,
    this.chartDataStream,
    this.onRequestChartData,
    this.onSubscribeChart,
    this.onUnsubscribeChart,
  });

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  late int _accountIndex;
  bool _positionsLoaded = false;
  Set<String> _selectedPairs = {};
  Set<String> _allKnownPairs = {};
  Set<String> _deselectedPairs = {}; // Track explicitly deselected pairs
  bool _filtersInitialized = false;
  bool _accountDetailsExpanded = false;
  bool _prefsLoaded = false;
  Set<int> _expandedPositions = {}; // Track expanded position tickets

  String _getAccountDisplayName(String accountNum) {
    final customName = widget.accountNames[accountNum];
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    return accountNum;
  }

  int _detectDigits(double price) {
    final priceStr = price.toString();
    final dotIndex = priceStr.indexOf('.');
    if (dotIndex < 0) return 0;
    return priceStr.substring(dotIndex + 1).length.clamp(0, 8);
  }

  @override
  void initState() {
    super.initState();
    _accountIndex = widget.initialAccount['index'] as int;
    
    // Load saved filter preferences
    _loadFilterPrefs();
    
    // Listen for positions updates (data comes from home screen)
    widget.positionsNotifier.addListener(_onPositionsUpdated);
    
    // Initialize with current data
    _onPositionsUpdated();
  }

  Future<void> _loadFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'deselected_pairs_$_accountIndex';
    final deselectedJson = prefs.getString(key);
    if (deselectedJson != null) {
      final List<dynamic> decoded = jsonDecode(deselectedJson);
      _deselectedPairs = decoded.map((e) => e.toString()).toSet();
    }
    _prefsLoaded = true;
    // Re-apply filters if positions already loaded
    if (_filtersInitialized) {
      setState(() {
        _selectedPairs = _allKnownPairs.difference(_deselectedPairs);
      });
    }
  }

  Future<void> _saveFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'deselected_pairs_$_accountIndex';
    // Save deselected pairs (inverse of selected)
    final deselected = _allKnownPairs.difference(_selectedPairs);
    await prefs.setString(key, jsonEncode(deselected.toList()));
  }

  void _onPositionsUpdated() {
    final positions = _getAllPositionsForAccount();
    final currentPairs = positions.map((p) => p['symbol'] as String? ?? '').toSet();
    
    // Initialize filters with all pairs selected on first load (minus previously deselected)
    if (!_filtersInitialized && positions.isNotEmpty) {
      setState(() {
        _allKnownPairs = Set.from(currentPairs);
        // Select all pairs except those previously deselected
        _selectedPairs = _prefsLoaded 
            ? currentPairs.difference(_deselectedPairs)
            : Set.from(currentPairs);
        _filtersInitialized = true;
        _positionsLoaded = true;
      });
    } else if (_filtersInitialized) {
      // Auto-select any new pairs that appear (only if not previously deselected)
      final newPairs = currentPairs.difference(_allKnownPairs);
      if (newPairs.isNotEmpty) {
        setState(() {
          // Only auto-select new pairs that weren't previously deselected
          final pairsToAdd = newPairs.difference(_deselectedPairs);
          _selectedPairs.addAll(pairsToAdd);
          _allKnownPairs.addAll(newPairs);
        });
      }
      
      // Check if selected pairs have any positions left
      final selectedPairsWithPositions = _selectedPairs.intersection(currentPairs);
      if (selectedPairsWithPositions.isEmpty && currentPairs.isNotEmpty) {
        // No positions left on selected pairs - select all remaining pairs
        setState(() {
          _selectedPairs = Set.from(currentPairs);
          // Clear deselected pairs since we're resetting
          _deselectedPairs.clear();
        });
        _saveFilterPrefs();
      }
      
      // Remove pairs from allKnownPairs that no longer have positions
      _allKnownPairs = _allKnownPairs.intersection(currentPairs);
      // Also clean up deselectedPairs
      _deselectedPairs = _deselectedPairs.intersection(currentPairs);
    } else if (!_positionsLoaded) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && !_positionsLoaded) {
          setState(() => _positionsLoaded = true);
        }
      });
    }
  }

  @override
  void dispose() {
    widget.positionsNotifier.removeListener(_onPositionsUpdated);
    super.dispose();
  }

  Map<String, dynamic>? _getCurrentAccount() {
    try {
      return widget.accountsNotifier.value.firstWhere(
        (a) => a['index'] == _accountIndex,
      );
    } catch (e) {
      return null;
    }
  }

  List<Map<String, dynamic>> _getAllPositionsForAccount() {
    return widget.positionsNotifier.value
        .where((p) => p['terminalIndex'] == _accountIndex)
        .toList();
  }

  List<Map<String, dynamic>> _getFilteredPositions() {
    final positions = _getAllPositionsForAccount()
        .where((p) => _selectedPairs.contains(p['symbol'] as String? ?? ''))
        .toList();
    
    // Sort by symbol first, then by open time (most recent first)
    positions.sort((a, b) {
      final symbolA = a['symbol'] as String? ?? '';
      final symbolB = b['symbol'] as String? ?? '';
      final symbolCompare = symbolA.compareTo(symbolB);
      
      if (symbolCompare != 0) return symbolCompare;
      
      // Same symbol - sort by open time descending (most recent first)
      final timeA = a['openTime'] as String? ?? '';
      final timeB = b['openTime'] as String? ?? '';
      return timeB.compareTo(timeA);
    });
    
    return positions;
  }

  Map<String, int> _getPairCounts() {
    final positions = _getAllPositionsForAccount();
    final counts = <String, int>{};
    for (final pos in positions) {
      final symbol = pos['symbol'] as String? ?? '';
      counts[symbol] = (counts[symbol] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: widget.accountsNotifier,
          builder: (context, _, __) {
            final account = _getCurrentAccount();
            final accountNum = account?['account'] as String? ?? 'Account';
            final displayName = _getAccountDisplayName(accountNum);
            return Text(
              displayName,
              style: const TextStyle(color: Colors.white),
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: widget.accountsNotifier,
          builder: (context, accounts, _) {
            final account = _getCurrentAccount();
            if (account == null) {
              return const Center(
                child: Text('Account not found', style: AppTextStyles.body),
              );
            }

            return ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: widget.positionsNotifier,
              builder: (context, _, __) {
                final allPositions = _getAllPositionsForAccount();
                final filteredPositions = _getFilteredPositions();
                final pairCounts = _getPairCounts();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccountInfoCard(account),
                      const SizedBox(height: 24),
                      _buildPositionsSection(allPositions, filteredPositions, pairCounts),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildAccountInfoCard(Map<String, dynamic> account) {
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final equity = (account['equity'] as num?)?.toDouble() ?? 0;
    final freeMargin = (account['freeMargin'] as num?)?.toDouble() ?? 0;
    final margin = (account['margin'] as num?)?.toDouble() ?? 0;
    final marginLevel = (account['marginLevel'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final broker = account['broker'] as String? ?? '';
    final brokerName = account['name'] as String? ?? accountNum;
    final server = account['server'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'USD';
    final leverage = account['leverage'] as int? ?? 0;
    final openPositions = account['openPositions'] as int? ?? 0;

    // Calculate P/L from positions based on setting
    final accountPositions = widget.positionsNotifier.value.where(
      (p) => p['terminalIndex'] == _accountIndex
    ).toList();
    
    double profit = 0;
    for (final pos in accountPositions) {
      final rawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
      if (widget.includeCommissionSwap) {
        final swap = (pos['swap'] as num?)?.toDouble() ?? 0;
        final commission = (pos['commission'] as num?)?.toDouble() ?? 0;
        profit += rawProfit + swap + commission;
      } else {
        profit += rawProfit;
      }
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          _accountDetailsExpanded = !_accountDetailsExpanded;
        });
      },
      child: Container(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance & Equity row with chevron
            Row(
              children: [
                Expanded(child: _buildMainStat('Balance', balance, currency)),
                Expanded(child: _buildMainStat('Equity', equity, currency)),
                Icon(
                  _accountDetailsExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.textSecondary,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Profit/Loss
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: profit >= 0
                    ? AppColors.primary.withOpacity(0.1)
                    : AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.includeCommissionSwap ? 'Net Floating P/L' : 'Floating P/L',
                    style: AppTextStyles.body,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${Formatters.formatCurrencyWithSign(profit)} $currency',
                        style: TextStyle(
                          color: profit >= 0 ? AppColors.primary : AppColors.error,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (widget.showPLPercent && balance > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${((profit / balance) * 100).toStringAsFixed(2)}%',
                          style: TextStyle(
                            color: profit == 0 
                                ? Colors.white 
                                : (profit > 0 ? AppColors.primary : AppColors.error),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Expanded details
            if (_accountDetailsExpanded) ...[
              const SizedBox(height: 20),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),

              // Account number and name
              Row(
                children: [
                  Expanded(child: _buildDetailItem('Account Number', accountNum)),
                  Expanded(child: _buildDetailItem('Account Name', brokerName)),
                ],
              ),
              const SizedBox(height: 12),
              _buildDetailItem('Broker', broker),
              const SizedBox(height: 12),
              _buildDetailItem('Server', server),

              const SizedBox(height: 16),
              const Divider(color: AppColors.border),
              const SizedBox(height: 16),

              // Details grid
              Row(
                children: [
                  Expanded(child: _buildDetailItem('Free Margin', '${Formatters.formatCurrency(freeMargin)} $currency')),
                  Expanded(child: _buildDetailItem('Used Margin', '${Formatters.formatCurrency(margin)} $currency')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildDetailItem('Margin Level', marginLevel > 0 ? '${marginLevel.toStringAsFixed(1)}%' : '-')),
                  Expanded(child: _buildDetailItem('Leverage', '1:$leverage')),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildDetailItem('Open Positions', '$openPositions')),
                  Expanded(child: _buildDetailItem('Currency', currency)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPositionsSection(
    List<Map<String, dynamic>> allPositions,
    List<Map<String, dynamic>> filteredPositions,
    Map<String, int> pairCounts,
  ) {
    final sortedPairs = pairCounts.keys.toList()..sort();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row with title and pair chips
        Row(
          children: [
            Text(
              'POSITIONS${_positionsLoaded ? ' (${allPositions.length})' : ''}',
              style: AppTextStyles.label,
            ),
          ],
        ),
        
        // Pair filter chips
        if (_positionsLoaded && pairCounts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: sortedPairs.map((pair) {
              final count = pairCounts[pair] ?? 0;
              final isSelected = _selectedPairs.contains(pair);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedPairs.remove(pair);
                      _deselectedPairs.add(pair);
                    } else {
                      _selectedPairs.add(pair);
                      _deselectedPairs.remove(pair);
                    }
                  });
                  _saveFilterPrefs();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? AppColors.primaryWithOpacity(0.2) 
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        pair,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? AppColors.primary 
                              : AppColors.textSecondary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            color: isSelected ? Colors.black : AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
        
        const SizedBox(height: 16),
        
        if (!_positionsLoaded)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text('Loading positions...', style: AppTextStyles.body),
                ],
              ),
            ),
          )
        else if (allPositions.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No open positions', style: AppTextStyles.body),
                ],
              ),
            ),
          )
        else if (filteredPositions.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.filter_list_off, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text('No positions match filter', style: AppTextStyles.body),
                ],
              ),
            ),
          )
        else
          ...filteredPositions.map((pos) => _buildPositionCard(pos)),
      ],
    );
  }

  Widget _buildPositionCard(Map<String, dynamic> position) {
    final symbol = position['symbol'] as String? ?? '';
    final type = position['type'] as String? ?? '';
    final lots = (position['lots'] as num?)?.toDouble() ?? 0;
    final openPrice = (position['openPrice'] as num?)?.toDouble() ?? 0;
    final currentPrice = (position['currentPrice'] as num?)?.toDouble() ?? 0;
    final sl = (position['sl'] as num?)?.toDouble() ?? 0;
    final tp = (position['tp'] as num?)?.toDouble() ?? 0;
    final profit = (position['profit'] as num?)?.toDouble() ?? 0;
    final swap = (position['swap'] as num?)?.toDouble() ?? 0;
    final commission = (position['commission'] as num?)?.toDouble() ?? 0;
    final ticket = position['ticket'] as int? ?? 0;
    final openTime = position['openTime'] as String? ?? '';

    final isBuy = type.toLowerCase() == 'buy';
    final displayProfit = widget.includeCommissionSwap 
        ? profit + swap + commission 
        : profit;
    final digits = _detectDigits(openPrice);
    
    // Get account balance for P/L %
    final account = _getCurrentAccount();
    final balance = (account?['balance'] as num?)?.toDouble() ?? 0;
    final plPercent = balance > 0 ? (displayProfit / balance) * 100 : 0.0;
    
    final isExpanded = _expandedPositions.contains(ticket);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left side - tap to expand/collapse (covers full height)
            Expanded(
              flex: 3,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedPositions.remove(ticket);
                    } else {
                      _expandedPositions.add(ticket);
                    }
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, top: 16, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header left: Symbol + Type
                      Row(
                        children: [
                          Text(
                            symbol,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isBuy ? AppColors.primary : AppColors.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              type.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Prices left: Open + Current
                      Row(
                        children: [
                          Expanded(
                            child: _buildPriceItem('Open', openPrice.toStringAsFixed(digits)),
                          ),
                          Expanded(
                            child: _buildPriceItem('Current', currentPrice.toStringAsFixed(digits)),
                          ),
                        ],
                      ),
                      // Expanded content
                      if (isExpanded) ...[
                        const SizedBox(height: 12),
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPriceItem('SL', sl > 0 ? sl.toStringAsFixed(digits) : '-'),
                            ),
                            Expanded(
                              child: _buildPriceItem('TP', tp > 0 ? tp.toStringAsFixed(digits) : '-'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            // Right side - tap to go to detail (covers full height)
            Expanded(
              flex: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openPositionDetail(position),
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 16, bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Header right: Lots + Chevron
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${lots.toStringAsFixed(2)} lots',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 22),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // P/L section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            widget.includeCommissionSwap ? 'Net P/L' : 'P/L',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                          if (widget.showPLPercent && balance > 0) ...[
                            const SizedBox(width: 8),
                            Text(
                              '${plPercent.toStringAsFixed(2)}%',
                              style: TextStyle(
                                color: displayProfit == 0 
                                    ? Colors.white 
                                    : (displayProfit > 0 ? AppColors.primary : AppColors.error),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        Formatters.formatCurrencyWithSign(displayProfit),
                        style: TextStyle(
                          color: displayProfit >= 0 ? AppColors.primary : AppColors.error,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // Expanded content right side
                      if (isExpanded) ...[
                        const SizedBox(height: 12),
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 12),
                        Text(
                          openTime,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                        Text(
                          '#$ticket',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openPositionDetail(Map<String, dynamic> position) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PositionDetailScreen(
          position: position,
          positionsNotifier: widget.positionsNotifier,
          accounts: widget.accountsNotifier.value,
          onClosePosition: widget.onClosePosition,
          onModifyPosition: widget.onModifyPosition,
          accountNames: widget.accountNames,
          mainAccountNum: widget.mainAccountNum,
          includeCommissionSwap: widget.includeCommissionSwap,
          showPLPercent: widget.showPLPercent,
          confirmBeforeClose: widget.confirmBeforeClose,
          onConfirmBeforeCloseChanged: widget.onConfirmBeforeCloseChanged,
          symbolSuffixes: widget.symbolSuffixes,
          lotRatios: widget.lotRatios,
          preferredPairs: widget.preferredPairs,
          onPlaceOrder: widget.onPlaceOrder,
          chartDataStream: widget.chartDataStream,
          onRequestChartData: widget.onRequestChartData,
          onSubscribeChart: widget.onSubscribeChart,
          onUnsubscribeChart: widget.onUnsubscribeChart,
        ),
      ),
    );
  }

  Widget _buildPriceItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildMainStat(String label, double value, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body),
        const SizedBox(height: 4),
        Text(
          Formatters.formatCurrency(value),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(currency, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}