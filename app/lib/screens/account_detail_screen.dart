import 'package:flutter/material.dart';
import 'dart:async';
import '../core/theme.dart';

class AccountDetailScreen extends StatefulWidget {
  final Map<String, dynamic> initialAccount;
  final ValueNotifier<List<Map<String, dynamic>>> accountsNotifier;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final VoidCallback onRefreshPositions;

  const AccountDetailScreen({
    super.key,
    required this.initialAccount,
    required this.accountsNotifier,
    required this.positionsNotifier,
    required this.onRefreshPositions,
  });

  @override
  State<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends State<AccountDetailScreen> {
  Timer? _refreshTimer;
  late int _accountIndex;

  @override
  void initState() {
    super.initState();
    _accountIndex = widget.initialAccount['index'] as int;
    
    // Request positions immediately
    widget.onRefreshPositions();
    
    // Start periodic refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.onRefreshPositions();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
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

  List<Map<String, dynamic>> _getPositionsForAccount() {
    return widget.positionsNotifier.value
        .where((p) => p['terminalIndex'] == _accountIndex)
        .toList()
      ..sort((a, b) => (a['symbol'] as String).compareTo(b['symbol'] as String));
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
              final positions = _getPositionsForAccount();
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAccountInfoCard(account),
                    const SizedBox(height: 24),
                    _buildPositionsSection(positions),
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
    final name = account['name'] as String? ?? '';
    final broker = account['broker'] as String? ?? '';
    final server = account['server'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'USD';
    final leverage = account['leverage'] as int? ?? 0;
    final connected = account['connected'] as bool? ?? false;
    final tradeAllowed = account['tradeAllowed'] as bool? ?? false;
    final openPositions = account['openPositions'] as int? ?? 0;

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
                      accountNum,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (name.isNotEmpty)
                      Text(name, style: AppTextStyles.body),
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

  Widget _buildPositionsSection(List<Map<String, dynamic>> positions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'POSITIONS (${positions.length})',
          style: AppTextStyles.label,
        ),
        const SizedBox(height: 12),
        if (positions.isEmpty)
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
        else
          ...positions.map((pos) => _buildPositionCard(pos)),
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

    return Container(
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
                child: _buildPriceItem('Open', openPrice.toStringAsFixed(5)),
              ),
              Expanded(
                child: _buildPriceItem('Current', currentPrice.toStringAsFixed(5)),
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
                child: _buildPriceItem('SL', sl > 0 ? sl.toStringAsFixed(5) : '-'),
              ),
              Expanded(
                child: _buildPriceItem('TP', tp > 0 ? tp.toStringAsFixed(5) : '-'),
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
              Text(
                openTime,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
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