import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../utils/formatters.dart';
import 'position.dart';

class TotalOverviewScreen extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> accountsNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final void Function(int ticket, int terminalIndex, [double? lots]) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final void Function(int ticket, int terminalIndex) onCancelOrder;
  final void Function(int ticket, int terminalIndex, double price, {double? sl, double? tp}) onModifyPendingOrder;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;
  final Map<String, String> symbolSuffixes;
  final Map<String, double> lotRatios;
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
  }) onPlaceOrder;
  final Stream<Map<String, dynamic>>? chartDataStream;
  final void Function(String symbol, String timeframe, int terminalIndex)? onRequestChartData;

  const TotalOverviewScreen({
    super.key,
    required this.accountsNotifier,
    required this.positionsNotifier,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.onCancelOrder,
    required this.onModifyPendingOrder,
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
  });

  @override
  State<TotalOverviewScreen> createState() => _TotalOverviewScreenState();
}

class _TotalOverviewScreenState extends State<TotalOverviewScreen> {
  Set<int> _expandedPositions = {};
  Set<String> _selectedPairs = {};
  Set<String> _allKnownPairs = {};
  Set<String> _deselectedPairs = {};
  bool _filtersInitialized = false;
  bool _prefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFilterPrefs();
    widget.positionsNotifier.addListener(_onPositionsUpdated);
    _onPositionsUpdated();
  }

  @override
  void dispose() {
    widget.positionsNotifier.removeListener(_onPositionsUpdated);
    super.dispose();
  }

  Future<void> _loadFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final deselectedJson = prefs.getString('deselected_pairs_overview');
    if (deselectedJson != null) {
      final List<dynamic> decoded = jsonDecode(deselectedJson);
      _deselectedPairs = decoded.map((e) => e.toString()).toSet();
    }
    _prefsLoaded = true;
    if (_filtersInitialized) {
      setState(() {
        _selectedPairs = _allKnownPairs.difference(_deselectedPairs);
      });
    }
  }

  Future<void> _saveFilterPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final deselected = _allKnownPairs.difference(_selectedPairs);
    await prefs.setString('deselected_pairs_overview', jsonEncode(deselected.toList()));
  }

  void _onPositionsUpdated() {
    final positions = widget.positionsNotifier.value;
    final currentPairs = positions.map((p) => p['symbol'] as String? ?? '').toSet();

    if (!_filtersInitialized && positions.isNotEmpty) {
      setState(() {
        _allKnownPairs = Set.from(currentPairs);
        _selectedPairs = _prefsLoaded
            ? currentPairs.difference(_deselectedPairs)
            : Set.from(currentPairs);
        _filtersInitialized = true;
      });
    } else if (_filtersInitialized) {
      final newPairs = currentPairs.difference(_allKnownPairs);
      if (newPairs.isNotEmpty) {
        setState(() {
          final pairsToAdd = newPairs.difference(_deselectedPairs);
          _selectedPairs.addAll(pairsToAdd);
          _allKnownPairs.addAll(newPairs);
        });
      }

      final selectedPairsWithPositions = _selectedPairs.intersection(currentPairs);
      if (selectedPairsWithPositions.isEmpty && currentPairs.isNotEmpty) {
        setState(() {
          _selectedPairs = Set.from(currentPairs);
          _deselectedPairs.clear();
        });
        _saveFilterPrefs();
      }

      _allKnownPairs = _allKnownPairs.intersection(currentPairs);
      _deselectedPairs = _deselectedPairs.intersection(currentPairs);
    }
  }

  int _detectDigits(double price) {
    final priceStr = price.toString();
    final dotIndex = priceStr.indexOf('.');
    if (dotIndex < 0) return 0;
    return priceStr.substring(dotIndex + 1).length.clamp(0, 8);
  }

  /// Check if a position is hedged and should show the hedge indicator
  bool _isHedgedPosition(Map<String, dynamic> position, List<Map<String, dynamic>> allPositions) {
    final symbol = position['symbol'] as String? ?? '';
    final ticket = position['ticket'] as int? ?? 0;
    
    // Get all positions for this symbol (excluding pending orders)
    final symbolPositions = allPositions.where((p) {
      final pType = (p['type'] as String?)?.toLowerCase() ?? '';
      return p['symbol'] == symbol && (pType == 'buy' || pType == 'sell');
    }).toList();
    
    // Count buy and sell lots
    final buyPositions = <Map<String, dynamic>>[];
    final sellPositions = <Map<String, dynamic>>[];
    
    for (final p in symbolPositions) {
      final pType = (p['type'] as String?)?.toLowerCase() ?? '';
      
      if (pType == 'buy') {
        buyPositions.add(p);
      } else if (pType == 'sell') {
        sellPositions.add(p);
      }
    }
    
    // No hedge if only one direction
    if (buyPositions.isEmpty || sellPositions.isEmpty) return false;
    
    // Sort both lists by lots descending to match largest first
    buyPositions.sort((a, b) => ((b['lots'] as num?)?.toDouble() ?? 0)
        .compareTo((a['lots'] as num?)?.toDouble() ?? 0));
    sellPositions.sort((a, b) => ((b['lots'] as num?)?.toDouble() ?? 0)
        .compareTo((a['lots'] as num?)?.toDouble() ?? 0));
    
    // Track which positions are hedged
    final hedgedTickets = <int>{};
    final usedBuyIndices = <int>{};
    final usedSellIndices = <int>{};
    
    // Match positions with same lot size
    for (int i = 0; i < buyPositions.length; i++) {
      if (usedBuyIndices.contains(i)) continue;
      final buyLot = (buyPositions[i]['lots'] as num?)?.toDouble() ?? 0;
      
      for (int j = 0; j < sellPositions.length; j++) {
        if (usedSellIndices.contains(j)) continue;
        final sellLot = (sellPositions[j]['lots'] as num?)?.toDouble() ?? 0;
        
        if ((buyLot - sellLot).abs() < 0.0001) {
          // Found a hedge pair
          hedgedTickets.add(buyPositions[i]['ticket'] as int? ?? 0);
          hedgedTickets.add(sellPositions[j]['ticket'] as int? ?? 0);
          usedBuyIndices.add(i);
          usedSellIndices.add(j);
          break;
        }
      }
    }
    
    return hedgedTickets.contains(ticket);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Total Overview',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: widget.accountsNotifier,
          builder: (context, accounts, _) {
            return ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: widget.positionsNotifier,
              builder: (context, positions, _) {
                return _buildContent(accounts, positions);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> positions,
  ) {
    // Calculate totals
    double totalBalance = 0;
    double totalEquity = 0;
    double totalProfit = 0;
    double totalRawProfit = 0;
    double totalSwap = 0;
    double totalCommission = 0;

    for (final account in accounts) {
      totalBalance += (account['balance'] as num?)?.toDouble() ?? 0;
      totalEquity += (account['equity'] as num?)?.toDouble() ?? 0;
    }

    // Separate positions and pending orders
    final openPositions = <Map<String, dynamic>>[];
    final pendingOrders = <Map<String, dynamic>>[];

    for (final pos in positions) {
      final type = (pos['type'] as String?)?.toLowerCase() ?? '';
      final rawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
      final swap = (pos['swap'] as num?)?.toDouble() ?? 0;
      final commission = (pos['commission'] as num?)?.toDouble() ?? 0;

      totalRawProfit += rawProfit;
      totalSwap += swap;
      totalCommission += commission;

      if (widget.includeCommissionSwap) {
        totalProfit += rawProfit + swap + commission;
      } else {
        totalProfit += rawProfit;
      }

      if (type == 'buy' || type == 'sell') {
        openPositions.add(pos);
      } else {
        pendingOrders.add(pos);
      }
    }

    // Filter positions by selected pairs
    final filteredPositions = openPositions
        .where((p) => _selectedPairs.contains(p['symbol'] as String? ?? ''))
        .toList();

    // Count positions per pair
    final pairCounts = <String, int>{};
    for (final pos in openPositions) {
      final symbol = pos['symbol'] as String? ?? '';
      pairCounts[symbol] = (pairCounts[symbol] ?? 0) + 1;
    }

    // Group filtered positions by symbol
    final positionsBySymbol = <String, List<Map<String, dynamic>>>{};
    for (final pos in filteredPositions) {
      final symbol = pos['symbol'] as String? ?? 'Unknown';
      positionsBySymbol.putIfAbsent(symbol, () => []).add(pos);
    }

    // Group pending orders by symbol
    final ordersBySymbol = <String, List<Map<String, dynamic>>>{};
    for (final order in pendingOrders) {
      final symbol = order['symbol'] as String? ?? 'Unknown';
      ordersBySymbol.putIfAbsent(symbol, () => []).add(order);
    }

    // Sort symbols alphabetically
    final sortedPositionSymbols = positionsBySymbol.keys.toList()..sort();
    final sortedOrderSymbols = ordersBySymbol.keys.toList()..sort();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total summary card
          _buildSummaryCard(
            totalBalance: totalBalance,
            totalEquity: totalEquity,
            totalProfit: totalProfit,
            totalRawProfit: totalRawProfit,
            totalSwap: totalSwap,
            totalCommission: totalCommission,
            positionCount: openPositions.length,
            orderCount: pendingOrders.length,
          ),

          const SizedBox(height: 24),

          // Pending Orders section (shown first, only if there are orders)
          if (pendingOrders.isNotEmpty) ...[
            Text(
              'PENDING ORDERS (${pendingOrders.length})',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            ...sortedOrderSymbols.map((symbol) {
              return _buildSymbolGroup(symbol, ordersBySymbol[symbol]!, accounts, true, openPositions);
            }),
            const SizedBox(height: 24),
          ],

          // Open Positions section
          Text(
            'POSITIONS (${openPositions.length})',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),

          // Pair filter chips
          if (pairCounts.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildPairFilters(pairCounts),
          ],

          const SizedBox(height: 16),

          if (openPositions.isEmpty)
            _buildEmptyState('No open positions', Icons.inbox_outlined)
          else if (filteredPositions.isEmpty)
            _buildEmptyState('No positions match filter', Icons.filter_list_off)
          else
            ...sortedPositionSymbols.map((symbol) {
              return _buildSymbolGroup(symbol, positionsBySymbol[symbol]!, accounts, false, openPositions);
            }),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPairFilters(Map<String, int> pairCounts) {
    final sortedPairs = pairCounts.keys.toList()..sort();

    return Wrap(
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
              borderRadius: BorderRadius.circular(8),
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
    );
  }

  Widget _buildSummaryCard({
    required double totalBalance,
    required double totalEquity,
    required double totalProfit,
    required double totalRawProfit,
    required double totalSwap,
    required double totalCommission,
    required int positionCount,
    required int orderCount,
  }) {
    final plPercent = totalBalance > 0 ? (totalProfit / totalBalance) * 100 : 0.0;
    final plColor = totalProfit == 0
        ? Colors.white
        : (totalProfit > 0 ? AppColors.primary : AppColors.error);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryWithOpacity(0.15),
            AppColors.primaryWithOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TOTAL SUMMARY',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              Text(
                '$positionCount positions • $orderCount orders',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Balance / Equity / P/L row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Balance',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrency(totalBalance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Equity',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrency(totalEquity),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.includeCommissionSwap ? 'Net P/L' : 'P/L',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        if (widget.showPLPercent && totalBalance > 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${plPercent.toStringAsFixed(2)}%',
                            style: TextStyle(color: plColor, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrencyWithSign(totalProfit),
                      style: TextStyle(
                        color: plColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Commission/Swap details if enabled
          if (widget.includeCommissionSwap) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(
                  children: [
                    const Text(
                      'Raw P/L',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Text(
                      Formatters.formatCurrencyWithSign(totalRawProfit),
                      style: TextStyle(
                        color: totalRawProfit == 0
                            ? Colors.white
                            : (totalRawProfit > 0 ? AppColors.primary : AppColors.error),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text(
                      'Swap',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Text(
                      Formatters.formatCurrencyWithSign(totalSwap),
                      style: TextStyle(
                        color: totalSwap == 0
                            ? Colors.white
                            : (totalSwap > 0 ? AppColors.primary : AppColors.error),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text(
                      'Commission',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                    Text(
                      Formatters.formatCurrencyWithSign(totalCommission),
                      style: TextStyle(
                        color: totalCommission == 0
                            ? Colors.white
                            : (totalCommission > 0 ? AppColors.primary : AppColors.error),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSymbolGroup(
    String symbol,
    List<Map<String, dynamic>> positions,
    List<Map<String, dynamic>> accounts,
    bool isPendingOrders,
    List<Map<String, dynamic>> allOpenPositions,
  ) {
    // Calculate total P/L for this symbol group
    double symbolProfit = 0;
    double totalLots = 0;

    for (final pos in positions) {
      final rawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
      final lots = (pos['lots'] as num?)?.toDouble() ?? 0;
      totalLots += lots;

      if (widget.includeCommissionSwap) {
        final swap = (pos['swap'] as num?)?.toDouble() ?? 0;
        final commission = (pos['commission'] as num?)?.toDouble() ?? 0;
        symbolProfit += rawProfit + swap + commission;
      } else {
        symbolProfit += rawProfit;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Symbol header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${positions.length} ${isPendingOrders ? 'orders' : 'positions'}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (!isPendingOrders) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${totalLots.toStringAsFixed(2)} lots',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                const Spacer(),
                if (!isPendingOrders)
                  Text(
                    Formatters.formatCurrencyWithSign(symbolProfit),
                    style: TextStyle(
                      color: symbolProfit == 0
                          ? Colors.white
                          : (symbolProfit > 0 ? AppColors.primary : AppColors.error),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),

          // Position/Order items
          ...positions.map((pos) => _buildPositionItem(pos, accounts, isPendingOrders, allOpenPositions)),
        ],
      ),
    );
  }

  Widget _buildPositionItem(
    Map<String, dynamic> position,
    List<Map<String, dynamic>> accounts,
    bool isPendingOrder,
    List<Map<String, dynamic>> allOpenPositions,
  ) {
    final ticket = position['ticket'] as int? ?? 0;
    final rawType = (position['type'] as String?)?.toUpperCase() ?? '';
    final type = rawType.replaceAll('_', ' '); // Remove underscore
    final lots = (position['lots'] as num?)?.toDouble() ?? 0;
    final openPrice = (position['openPrice'] as num?)?.toDouble() ?? 0;
    final currentPrice = (position['currentPrice'] as num?)?.toDouble() ?? 0;
    final rawProfit = (position['profit'] as num?)?.toDouble() ?? 0;
    final swap = (position['swap'] as num?)?.toDouble() ?? 0;
    final commission = (position['commission'] as num?)?.toDouble() ?? 0;
    final terminalIndex = position['terminalIndex'] as int? ?? 0;
    final sl = (position['sl'] as num?)?.toDouble();
    final tp = (position['tp'] as num?)?.toDouble();

    final profit = widget.includeCommissionSwap
        ? rawProfit + swap + commission
        : rawProfit;

    // Detect digits from current price
    final digits = _detectDigits(currentPrice);

    // Get account name
    final account = accounts.firstWhere(
      (a) => a['index'] == terminalIndex,
      orElse: () => {'account': 'Account $terminalIndex'},
    );
    final accountName = widget.accountNames[account['account'] as String?] ??
        account['account'] as String? ??
        'Account $terminalIndex';

    final isExpanded = _expandedPositions.contains(ticket);
    final isBuy = type.contains('BUY');
    
    // Check if hedged (only for positions, not pending orders)
    final isHedged = !isPendingOrder && _isHedgedPosition(position, allOpenPositions);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Tappable area for expand (type, lots, account)
              GestureDetector(
                onTap: isPendingOrder
                    ? () => _showPendingOrderPopup(position)
                    : () {
                        setState(() {
                          if (isExpanded) {
                            _expandedPositions.remove(ticket);
                          } else {
                            _expandedPositions.add(ticket);
                          }
                        });
                      },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isBuy
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.error.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          color: isBuy ? AppColors.primary : AppColors.error,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    // Hedge indicator
                    if (isHedged) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Lots
                    Text(
                      lots.toStringAsFixed(2),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Account name
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        accountName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Tappable area for navigation (rest of the card)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: isPendingOrder
                      ? () => _showPendingOrderPopup(position)
                      : () => _openPositionDetail(position),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // P/L or Price for pending
                      if (!isPendingOrder)
                        Text(
                          Formatters.formatCurrencyWithSign(profit),
                          style: TextStyle(
                            color: profit == 0
                                ? Colors.white
                                : (profit > 0 ? AppColors.primary : AppColors.error),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      else
                        Text(
                          '@ ${openPrice.toStringAsFixed(digits)}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Expanded details
          if (isExpanded) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem('Open', openPrice.toStringAsFixed(digits)),
                if (!isPendingOrder)
                  _buildDetailItem('Current', currentPrice.toStringAsFixed(digits)),
                _buildDetailItem('SL', sl != null && sl != 0 ? sl.toStringAsFixed(digits) : '-'),
                _buildDetailItem('TP', tp != null && tp != 0 ? tp.toStringAsFixed(digits) : '-'),
              ],
            ),
          ],
        ],
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
          onCancelOrder: widget.onCancelOrder,
          onModifyPendingOrder: widget.onModifyPendingOrder,
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
        ),
      ),
    );
  }

  // Pending order popup methods
  void _showPendingOrderPopup(Map<String, dynamic> order) {
    final ticket = order['ticket'] as int? ?? 0;
    final terminalIndex = order['terminalIndex'] as int? ?? 0;
    final symbol = order['symbol']?.toString() ?? '';
    final type = order['type']?.toString() ?? '';
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    final lots = (order['lots'] as num?)?.toDouble() ?? 0;
    
    final formattedType = type.toUpperCase().replaceAll('_', ' ');
    final isBuy = type.toLowerCase().contains('buy');
    final digits = _detectDigits(openPrice);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Symbol + Type
            Row(
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBuy 
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    formattedType,
                    style: TextStyle(
                      color: isBuy ? AppColors.primary : AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Price and Lots info
            Row(
              children: [
                Text(
                  '${lots.toStringAsFixed(2)} lots @ ${openPrice.toStringAsFixed(digits)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showEditPendingOrderDialog(order);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, color: AppColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showCancelOrderConfirmation(ticket, terminalIndex, symbol, formattedType);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, color: AppColors.error, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _findSimilarPendingOrders(Map<String, dynamic> order) {
    final symbol = order['symbol']?.toString() ?? '';
    final type = order['type']?.toString() ?? '';
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    
    return widget.positionsNotifier.value.where((p) {
      final pType = (p['type'] as String?)?.toLowerCase() ?? '';
      if (pType == 'buy' || pType == 'sell') return false; // Not pending
      if (p['symbol']?.toString() != symbol) return false;
      if (p['type']?.toString() != type) return false;
      final pPrice = (p['openPrice'] as num?)?.toDouble() ?? 0;
      return (pPrice - openPrice).abs() < 0.00001;
    }).toList();
  }

  String _getAccountName(int terminalIndex) {
    final account = widget.accountsNotifier.value.firstWhere(
      (a) => a['index'] == terminalIndex,
      orElse: () => <String, dynamic>{},
    );
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  void _showEditPendingOrderDialog(Map<String, dynamic> order) {
    final symbol = order['symbol']?.toString() ?? '';
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    final currentSl = (order['sl'] as num?)?.toDouble() ?? 0;
    final currentTp = (order['tp'] as num?)?.toDouble() ?? 0;
    final digits = _detectDigits(openPrice);
    
    final similarOrders = _findSimilarPendingOrders(order);
    final selectedOrders = <int>{};
    
    selectedOrders.add(order['ticket'] as int? ?? 0);
    
    final priceController = TextEditingController(text: openPrice.toStringAsFixed(digits));
    final slController = TextEditingController(text: currentSl > 0 ? currentSl.toStringAsFixed(digits) : '');
    final tpController = TextEditingController(text: currentTp > 0 ? currentTp.toStringAsFixed(digits) : '');
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.primary, width: 1),
          ),
          title: Text('Edit Order - $symbol', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (similarOrders.length > 1) ...[
                    const Text('Accounts', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    ...similarOrders.map((o) {
                      final ticket = o['ticket'] as int? ?? 0;
                      final terminalIndex = o['terminalIndex'] as int? ?? 0;
                      final accountName = _getAccountName(terminalIndex);
                      final lots = (o['lots'] as num?)?.toDouble() ?? 0;
                      final isSelected = selectedOrders.contains(ticket);
                      
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            if (isSelected) {
                              selectedOrders.remove(ticket);
                            } else {
                              selectedOrders.add(ticket);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.15) : AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  accountName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                '${lots.toStringAsFixed(2)} lots',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                  const Text('Price', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    autofocus: similarOrders.length == 1,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('SL', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: slController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Optional',
                                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TP', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: tpController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Optional',
                                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                                filled: true,
                                fillColor: AppColors.background,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: selectedOrders.isEmpty ? null : () {
                final newPrice = double.tryParse(priceController.text);
                if (newPrice == null || newPrice <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid price'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                final newSl = slController.text.isEmpty ? null : double.tryParse(slController.text);
                final newTp = tpController.text.isEmpty ? null : double.tryParse(tpController.text);
                
                Navigator.pop(context);
                
                for (final o in similarOrders) {
                  final ticket = o['ticket'] as int? ?? 0;
                  if (selectedOrders.contains(ticket)) {
                    final terminalIndex = o['terminalIndex'] as int? ?? 0;
                    widget.onModifyPendingOrder(ticket, terminalIndex, newPrice, sl: newSl, tp: newTp);
                  }
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Modifying ${selectedOrders.length} order(s)...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              child: Text(
                'Update${selectedOrders.length > 1 ? ' (${selectedOrders.length})' : ''}',
                style: TextStyle(
                  color: selectedOrders.isEmpty ? AppColors.textSecondary : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCancelOrderConfirmation(int ticket, int terminalIndex, String symbol, String type) {
    final order = widget.positionsNotifier.value.firstWhere(
      (p) => (p['ticket'] as int? ?? 0) == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (order.isEmpty) {
      _showSingleCancelDialog(ticket, terminalIndex, symbol, type);
      return;
    }
    
    final similarOrders = _findSimilarPendingOrders(order);
    
    if (similarOrders.length <= 1) {
      _showSingleCancelDialog(ticket, terminalIndex, symbol, type);
      return;
    }
    
    final selectedOrders = <int>{ticket};
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.primary, width: 1),
          ),
          title: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Accounts', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  ...similarOrders.map((o) {
                    final oTicket = o['ticket'] as int? ?? 0;
                    final oTerminalIndex = o['terminalIndex'] as int? ?? 0;
                    final accountName = _getAccountName(oTerminalIndex);
                    final lots = (o['lots'] as num?)?.toDouble() ?? 0;
                    final isSelected = selectedOrders.contains(oTicket);
                    
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          if (isSelected) {
                            selectedOrders.remove(oTicket);
                          } else {
                            selectedOrders.add(oTicket);
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.error.withOpacity(0.15) : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.error : AppColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                              color: isSelected ? AppColors.error : AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                accountName,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${lots.toStringAsFixed(2)} lots',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'Cancel $type order on $symbol?',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: selectedOrders.isEmpty ? null : () {
                Navigator.pop(context);
                
                for (final o in similarOrders) {
                  final oTicket = o['ticket'] as int? ?? 0;
                  if (selectedOrders.contains(oTicket)) {
                    final oTerminalIndex = o['terminalIndex'] as int? ?? 0;
                    widget.onCancelOrder(oTicket, oTerminalIndex);
                  }
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cancelling ${selectedOrders.length} order(s)...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              child: Text(
                'Yes, Cancel${selectedOrders.length > 1 ? ' (${selectedOrders.length})' : ''}',
                style: TextStyle(
                  color: selectedOrders.isEmpty ? AppColors.textSecondary : AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSingleCancelDialog(int ticket, int terminalIndex, String symbol, String type) {
    final accountName = _getAccountName(terminalIndex);
    
    final order = widget.positionsNotifier.value.firstWhere(
      (p) => (p['ticket'] as int? ?? 0) == ticket,
      orElse: () => <String, dynamic>{},
    );
    final lots = (order['lots'] as num?)?.toDouble() ?? 0;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.primary, width: 1),
        ),
        title: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_box, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          accountName,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${lots.toStringAsFixed(2)} lots',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cancel $type order on $symbol?',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onCancelOrder(ticket, terminalIndex);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cancelling order...'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}