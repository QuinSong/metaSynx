import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../utils/formatters.dart';

class HistoryScreen extends StatefulWidget {
  final Map<String, String> accountNames;
  final Stream<Map<String, dynamic>> historyDataStream;
  final void Function(String period, int? terminalIndex) onRequestHistory;
  final bool includeCommissionSwap;

  const HistoryScreen({
    super.key,
    required this.accountNames,
    required this.historyDataStream,
    required this.onRequestHistory,
    required this.includeCommissionSwap,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<Map<String, dynamic>>? _historySubscription;
  
  List<Map<String, dynamic>> _todayHistory = [];
  List<Map<String, dynamic>> _weekHistory = [];
  List<Map<String, dynamic>> _monthHistory = [];
  
  bool _loadingToday = false;
  bool _loadingWeek = false;
  bool _loadingMonth = false;
  
  bool _loadedToday = false;
  bool _loadedWeek = false;
  bool _loadedMonth = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    
    // Listen to history data
    _historySubscription = widget.historyDataStream.listen(_onHistoryReceived);
    
    // Load today's history initially
    _loadHistory('today');
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _historySubscription?.cancel();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      switch (_tabController.index) {
        case 0:
          if (!_loadedToday) _loadHistory('today');
          break;
        case 1:
          if (!_loadedWeek) _loadHistory('week');
          break;
        case 2:
          if (!_loadedMonth) _loadHistory('month');
          break;
      }
    }
  }

  void _loadHistory(String period) {
    setState(() {
      switch (period) {
        case 'today':
          _loadingToday = true;
          break;
        case 'week':
          _loadingWeek = true;
          break;
        case 'month':
          _loadingMonth = true;
          break;
      }
    });
    
    widget.onRequestHistory(period, null);
  }

  void _onHistoryReceived(Map<String, dynamic> data) {
    if (data['action'] != 'history_data') return;
    
    final period = data['period'] as String? ?? 'today';
    final history = (data['history'] as List<dynamic>?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ?? [];
    
    setState(() {
      switch (period) {
        case 'today':
          _todayHistory = history;
          _loadingToday = false;
          _loadedToday = true;
          break;
        case 'week':
          _weekHistory = history;
          _loadingWeek = false;
          _loadedWeek = true;
          break;
        case 'month':
          _monthHistory = history;
          _loadingMonth = false;
          _loadedMonth = true;
          break;
      }
    });
  }

  double _calculateTotalProfit(List<Map<String, dynamic>> history) {
    double total = 0;
    for (final trade in history) {
      final profit = (trade['profit'] as num?)?.toDouble() ?? 0;
      if (widget.includeCommissionSwap) {
        final swap = (trade['swap'] as num?)?.toDouble() ?? 0;
        final commission = (trade['commission'] as num?)?.toDouble() ?? 0;
        total += profit + swap + commission;
      } else {
        total += profit;
      }
    }
    return total;
  }

  String _getAccountName(Map<String, dynamic> trade) {
    final account = trade['account']?.toString() ?? '';
    return widget.accountNames[account] ?? account;
  }

  String _formatDateTime(int? timestamp) {
    if (timestamp == null || timestamp == 0) return '--';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Trade History', style: TextStyle(color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Week'),
            Tab(text: 'Month'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistoryList(_todayHistory, _loadingToday, 'today'),
          _buildHistoryList(_weekHistory, _loadingWeek, 'week'),
          _buildHistoryList(_monthHistory, _loadingMonth, 'month'),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<Map<String, dynamic>> history, bool loading, String period) {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No closed trades',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _loadHistory(period),
              child: const Text('Refresh', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
      );
    }

    final totalProfit = _calculateTotalProfit(history);

    return Column(
      children: [
        // Summary header
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${history.length} trades',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.includeCommissionSwap ? 'Net Total P/L' : 'Total P/L',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.formatCurrencyWithSign(totalProfit),
                    style: TextStyle(
                      color: totalProfit >= 0 ? AppColors.primary : AppColors.error,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Trade list
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _loadHistory(period),
            color: AppColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: history.length,
              itemBuilder: (context, index) => _buildTradeItem(history[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTradeItem(Map<String, dynamic> trade) {
    final symbol = trade['symbol']?.toString() ?? '';
    final type = (trade['type']?.toString() ?? '').toUpperCase();
    final lots = (trade['lots'] as num?)?.toDouble() ?? 0;
    final openPrice = (trade['openPrice'] as num?)?.toDouble() ?? 0;
    final closePrice = (trade['closePrice'] as num?)?.toDouble() ?? 0;
    final profit = (trade['profit'] as num?)?.toDouble() ?? 0;
    final swap = (trade['swap'] as num?)?.toDouble() ?? 0;
    final commission = (trade['commission'] as num?)?.toDouble() ?? 0;
    final closeTime = trade['closeTime'] as int?;
    final accountName = _getAccountName(trade);
    
    final displayProfit = widget.includeCommissionSwap 
        ? profit + swap + commission 
        : profit;
    
    final isBuy = type == 'BUY';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Top row: Symbol, Type, Lots, Profit
          Row(
            children: [
              // Symbol
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      symbol,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      accountName,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Type & Lots
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isBuy 
                      ? AppColors.primary.withOpacity(0.15)
                      : AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$type ${lots.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isBuy ? AppColors.primary : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Profit
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    Formatters.formatCurrencyWithSign(displayProfit),
                    style: TextStyle(
                      color: displayProfit >= 0 ? AppColors.primary : AppColors.error,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _formatDateTime(closeTime),
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // Bottom row: Prices
          Row(
            children: [
              Text(
                'Open: ${_formatPrice(openPrice, symbol)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Text(
                'Close: ${_formatPrice(closePrice, symbol)}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              if (widget.includeCommissionSwap && (swap != 0 || commission != 0)) ...[
                const Spacer(),
                Text(
                  'S: ${swap.toStringAsFixed(2)} C: ${commission.toStringAsFixed(2)}',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price, String symbol) {
    // Determine decimal places based on price level
    int decimals = 5;
    if (price > 1000) decimals = 2;
    else if (price > 10) decimals = 3;
    return price.toStringAsFixed(decimals);
  }
}