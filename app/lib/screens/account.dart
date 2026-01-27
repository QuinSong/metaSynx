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
  final void Function(int ticket, int terminalIndex) onCancelOrder;
  final void Function(int ticket, int terminalIndex, double price) onModifyPendingOrder;
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
    required double? price,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) onPlaceOrder;
  // Chart data
  final Stream<Map<String, dynamic>>? chartDataStream;
  final void Function(String symbol, String timeframe, int terminalIndex)? onRequestChartData;
  // Bottom nav bar
  final Widget? bottomNavBar;

  const AccountDetailScreen({
    super.key,
    required this.initialAccount,
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
    this.bottomNavBar,
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

  List<Map<String, dynamic>> _getPendingOrders() {
    return _getAllPositionsForAccount()
        .where((p) => p['isPending'] == true)
        .toList();
  }

  List<Map<String, dynamic>> _getMarketPositions() {
    return _getAllPositionsForAccount()
        .where((p) => p['isPending'] != true)
        .toList();
  }

  List<Map<String, dynamic>> _getFilteredPositions() {
    final positions = _getMarketPositions()
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

  String _formatOrderType(String type) {
    // Convert buy_limit to BUY LIMIT, sell_stop to SELL STOP, etc.
    return type.toUpperCase().replaceAll('_', ' ');
  }

  Map<String, int> _getPairCounts() {
    final positions = _getMarketPositions();
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
                final allPositions = _getMarketPositions();
                final filteredPositions = _getFilteredPositions();
                final pairCounts = _getPairCounts();
                final pendingOrders = _getPendingOrders();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAccountInfoCard(account),
                      if (pendingOrders.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        _buildPendingOrdersSection(pendingOrders),
                      ],
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

  Widget _buildPendingOrdersSection(List<Map<String, dynamic>> pendingOrders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ORDERS (${pendingOrders.length})',
          style: AppTextStyles.label,
        ),
        const SizedBox(height: 12),
        ...pendingOrders.map((order) => _buildPendingOrderCard(order)),
      ],
    );
  }

  Widget _buildPendingOrderCard(Map<String, dynamic> order) {
    final symbol = order['symbol'] as String? ?? '';
    final type = order['type'] as String? ?? '';
    final lots = (order['lots'] as num?)?.toDouble() ?? 0;
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    final currentPrice = (order['currentPrice'] as num?)?.toDouble() ?? 0;
    final ticket = order['ticket'] as int? ?? 0;
    final terminalIndex = order['terminalIndex'] as int? ?? 0;
    
    final formattedType = _formatOrderType(type);
    final isBuy = type.toLowerCase().contains('buy');
    final digits = _detectDigits(openPrice);
    // Buy limit/stop uses ask, sell limit/stop uses bid
    final priceLabel = isBuy ? 'Current (Ask)' : 'Current (Bid)';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Top row: Symbol + Type badge, Lots
          Row(
            children: [
              // Symbol
              Text(
                symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              // Order type badge
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
              const Spacer(),
              // Lots
              Text(
                '${lots.toStringAsFixed(2)} lots',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 10),
          
          // Middle row: Price info
          Row(
            children: [
              // Order price
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Price',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    openPrice.toStringAsFixed(digits),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              // Current price
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    priceLabel,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    currentPrice.toStringAsFixed(digits),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Edit button
              GestureDetector(
                onTap: () => _showEditPendingOrderDialog(order),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.edit,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Cancel button
              GestureDetector(
                onTap: () => _showCancelOrderConfirmation(ticket, terminalIndex, symbol, formattedType),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: AppColors.error,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Find similar pending orders across ALL accounts (same symbol, type, price)
  List<Map<String, dynamic>> _findSimilarPendingOrders(Map<String, dynamic> order) {
    final symbol = order['symbol']?.toString() ?? '';
    final type = order['type']?.toString() ?? '';
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    
    return widget.positionsNotifier.value.where((p) {
      if (p['isPending'] != true) return false;
      if (p['symbol']?.toString() != symbol) return false;
      if (p['type']?.toString() != type) return false;
      // Match orders with same price (within small tolerance)
      final pPrice = (p['openPrice'] as num?)?.toDouble() ?? 0;
      return (pPrice - openPrice).abs() < 0.00001;
    }).toList();
  }

  String _getAccountNameForIndex(int terminalIndex) {
    final account = widget.accountsNotifier.value.firstWhere(
      (a) => a['index'] == terminalIndex,
      orElse: () => <String, dynamic>{},
    );
    final accountNum = account['account']?.toString() ?? '';
    return _getAccountDisplayName(accountNum);
  }

  void _showCancelOrderConfirmation(int ticket, int terminalIndex, String symbol, String type) {
    // Find the order
    final order = widget.positionsNotifier.value.firstWhere(
      (p) => p['ticket'] == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (order.isEmpty) return;
    
    // Find similar orders across all accounts
    final similarOrders = _findSimilarPendingOrders(order);
    final selectedOrders = <int>{ticket};  // Pre-select current order
    
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
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    similarOrders.length > 1 ? 'Accounts' : 'Account',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...similarOrders.map((o) {
                    final oTicket = o['ticket'] as int? ?? 0;
                    final oTerminalIndex = o['terminalIndex'] as int? ?? 0;
                    final accountName = _getAccountNameForIndex(oTerminalIndex);
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
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'Cancel ${_formatOrderType(type)} order on $symbol?',
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
                
                // Cancel all selected orders
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
                  color: selectedOrders.isEmpty ? AppColors.textMuted : AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPendingOrderDialog(Map<String, dynamic> order) {
    final ticket = order['ticket'] as int? ?? 0;
    final symbol = order['symbol'] as String? ?? '';
    final openPrice = (order['openPrice'] as num?)?.toDouble() ?? 0;
    final digits = _detectDigits(openPrice);
    
    // Find similar orders across all accounts
    final similarOrders = _findSimilarPendingOrders(order);
    final selectedOrders = <int>{ticket};  // Pre-select current order
    
    final priceController = TextEditingController(text: openPrice.toStringAsFixed(digits));
    
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
                  // Account selection
                  Text(
                    similarOrders.length > 1 ? 'Accounts' : 'Account',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  ...similarOrders.map((o) {
                    final oTicket = o['ticket'] as int? ?? 0;
                    final oTerminalIndex = o['terminalIndex'] as int? ?? 0;
                    final accountName = _getAccountNameForIndex(oTerminalIndex);
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
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Text('New Price', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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
                Navigator.pop(context);
                
                // Modify all selected orders
                for (final o in similarOrders) {
                  final oTicket = o['ticket'] as int? ?? 0;
                  if (selectedOrders.contains(oTicket)) {
                    final oTerminalIndex = o['terminalIndex'] as int? ?? 0;
                    widget.onModifyPendingOrder(oTicket, oTerminalIndex, newPrice);
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
                  color: selectedOrders.isEmpty ? AppColors.textMuted : AppColors.primary,
                ),
              ),
            ),
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

    final isBuy = type.toLowerCase().contains('buy');
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
                              _formatOrderType(type),
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
          bottomNavBar: widget.bottomNavBar,
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