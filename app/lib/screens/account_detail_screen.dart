import 'package:flutter/material.dart';
import 'dart:async';
import '../core/theme.dart';
import 'position_detail_screen.dart';

class AccountDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initialAccount;
  final ValueNotifier<List<Map<String, dynamic>>> accountsNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final VoidCallback onRefreshPositions;
  final VoidCallback onRefreshAllPositions;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final Map<String, String> accountNames;

  const AccountDetailScreen({
    super.key,
    required this.initialAccount,
    required this.accountsNotifier,
    required this.positionsNotifier,
    required this.onRefreshPositions,
    required this.onRefreshAllPositions,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.accountNames,
  });

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Timer? _refreshTimer;
  late int _accountIndex;
  bool _positionsLoaded = false;
  Set<String> _selectedPairs = {};
  Set<String> _allKnownPairs = {};
  bool _filtersInitialized = false;

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
    
    // Listen for positions updates
    widget.positionsNotifier.addListener(_onPositionsUpdated);
    
    // Request positions immediately
    widget.onRefreshPositions();
    
    // Start periodic refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.onRefreshPositions();
    });
  }

  void _onPositionsUpdated() {
    final positions = _getAllPositionsForAccount();
    final currentPairs = positions.map((p) => p['symbol'] as String? ?? '').toSet();
    
    // Initialize filters with all pairs selected on first load
    if (!_filtersInitialized && positions.isNotEmpty) {
      setState(() {
        _selectedPairs = Set.from(currentPairs);
        _allKnownPairs = Set.from(currentPairs);
        _filtersInitialized = true;
        _positionsLoaded = true;
      });
    } else if (_filtersInitialized) {
      // Auto-select any new pairs that appear
      final newPairs = currentPairs.difference(_allKnownPairs);
      if (newPairs.isNotEmpty) {
        setState(() {
          _selectedPairs.addAll(newPairs);
          _allKnownPairs.addAll(newPairs);
        });
      }
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
    _refreshTimer?.cancel();
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
            return Text(
              account?['account'] as String? ?? 'Account',
              style: const TextStyle(color: Colors.white),
            );
          },
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
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
                padding: const EdgeInsets.all(16),
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
    );
  }

  Widget _buildAccountInfoCard(Map<String, dynamic> account) {
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final equity = (account['equity'] as num?)?.toDouble() ?? 0;
    final freeMargin = (account['freeMargin'] as num?)?.toDouble() ?? 0;
    final margin = (account['margin'] as num?)?.toDouble() ?? 0;
    final profit = (account['profit'] as num?)?.toDouble() ?? 0;
    final marginLevel = (account['marginLevel'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final broker = account['broker'] as String? ?? '';
    final server = account['server'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'USD';
    final leverage = account['leverage'] as int? ?? 0;
    final connected = account['connected'] as bool? ?? false;
    final tradeAllowed = account['tradeAllowed'] as bool? ?? false;
    final openPositions = account['openPositions'] as int? ?? 0;
    final displayName = _getAccountDisplayName(accountNum);
    final hasCustomName = widget.accountNames[accountNum]?.isNotEmpty == true;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: connected
              ? AppColors.primaryWithOpacity(0.3)
              : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (hasCustomName)
                      Text(accountNum, style: AppTextStyles.body),
                  ],
                ),
              ),
              _buildStatusChip(connected, tradeAllowed),
            ],
          ),

          const SizedBox(height: 8),
          Text(broker, style: AppTextStyles.body),
          Text(
            'Server: $server',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),

          const SizedBox(height: 20),
          const Divider(color: AppColors.border),
          const SizedBox(height: 16),

          // Balance & Equity
          Row(
            children: [
              Expanded(child: _buildMainStat('Balance', balance, currency)),
              Expanded(child: _buildMainStat('Equity', equity, currency)),
            ],
          ),

          const SizedBox(height: 20),

          // Profit/Loss
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: profit >= 0
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Floating P/L', style: AppTextStyles.body),
                Text(
                  '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)} $currency',
                  style: TextStyle(
                    color: profit >= 0 ? AppColors.primary : AppColors.error,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Details grid
          Row(
            children: [
              Expanded(child: _buildDetailItem('Free Margin', '${freeMargin.toStringAsFixed(2)} $currency')),
              Expanded(child: _buildDetailItem('Used Margin', '${margin.toStringAsFixed(2)} $currency')),
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
                    } else {
                      _selectedPairs.add(pair);
                    }
                  });
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
    final totalProfit = profit + swap + commission;
    final digits = _detectDigits(openPrice);

    return GestureDetector(
      onTap: () => _openPositionDetail(position),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Symbol + Type + Lots
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
              const Spacer(),
              Text(
                '${lots.toStringAsFixed(2)} lots',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Prices row
          Row(
            children: [
              Expanded(
                child: _buildPriceItem('Open', openPrice.toStringAsFixed(digits)),
              ),
              Expanded(
                child: _buildPriceItem('Current', currentPrice.toStringAsFixed(digits)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('P/L', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                    Text(
                      '${totalProfit >= 0 ? '+' : ''}${totalProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: totalProfit >= 0 ? AppColors.primary : AppColors.error,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),

          // SL/TP row
          Row(
            children: [
              Expanded(
                child: _buildPriceItem('SL', sl > 0 ? sl.toStringAsFixed(digits) : '-'),
              ),
              Expanded(
                child: _buildPriceItem('TP', tp > 0 ? tp.toStringAsFixed(digits) : '-'),
              ),
              Expanded(
                child: _buildPriceItem('Swap', swap.toStringAsFixed(2)),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Ticket & Time
          Row(
            children: [
              Text(
                '#$ticket',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18),
              const SizedBox(width: 4),
              Text(
                openTime,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
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
          onRefreshAllPositions: widget.onRefreshAllPositions,
          accountNames: widget.accountNames,
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

  Widget _buildStatusChip(bool connected, bool tradeAllowed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: connected
            ? (tradeAllowed ? AppColors.primary : AppColors.warning)
            : AppColors.error,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? (tradeAllowed ? 'Active' : 'Read Only') : 'Offline',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStat(String label, double value, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body),
        const SizedBox(height: 4),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(currency, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
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