import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart' as relay;
import '../components/connection_indicator.dart';
import '../components/connection_card.dart';
import '../components/scan_button.dart';
import 'qr_scanner_screen.dart';
import 'new_order_screen.dart';
import 'account_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final relay.RelayConnection _connection = relay.RelayConnection();
  relay.ConnectionState _connectionState = relay.ConnectionState.disconnected;
  bool _bridgeConnected = false;
  String? _roomId;
  final ValueNotifier<List<Map<String, dynamic>>> _accountsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _positionsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _setupConnection();
    _tryAutoConnect();
  }

  void _setupConnection() {
    _connection.onStateChanged = (state) {
      setState(() => _connectionState = state);
      if (state == relay.ConnectionState.connected) {
        _startAccountsRefresh();
      } else {
        _stopAccountsRefresh();
      }
    };
    _connection.onPairingStatusChanged = (bridgeConnected) {
      setState(() => _bridgeConnected = bridgeConnected);
      if (bridgeConnected) {
        _requestAccounts();
      }
    };
    _connection.onMessage = _handleMessage;
  }

  void _startAccountsRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_bridgeConnected) {
        _requestAccounts();
      }
    });
  }

  void _stopAccountsRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  Future<void> _tryAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final lastConnection = prefs.getString('last_connection');
    if (lastConnection != null) {
      try {
        final config = jsonDecode(lastConnection) as Map<String, dynamic>;
        setState(() {
          _roomId = config['room'];
        });
        await _connection.connect(config);
      } catch (e) {
        debugPrint('Auto-connect failed: $e');
      }
    }
  }

  void _openScanner() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerScreen()),
    );

    if (result != null) {
      setState(() {
        _connectionState = relay.ConnectionState.connecting;
        _roomId = result['room'];
      });

      try {
        await _connection.connect(result);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_connection', jsonEncode(result));
      } catch (e) {
        _showError('Connection failed: $e');
        setState(() => _connectionState = relay.ConnectionState.disconnected);
      }
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final action = message['action'] as String?;

    switch (action) {
      case 'accounts_list':
        final accounts = message['accounts'] as List?;
        if (accounts != null) {
          _accountsNotifier.value = List<Map<String, dynamic>>.from(accounts);
          // Trigger setState to update account count in UI
          setState(() {});
        }
        break;

      case 'positions_list':
        final positions = message['positions'] as List?;
        final targetIndex = message['targetIndex'] as int?;
        if (positions != null) {
          if (targetIndex != null) {
            // Merge: replace positions for this terminal only, keep others
            final currentPositions = List<Map<String, dynamic>>.from(_positionsNotifier.value);
            currentPositions.removeWhere((p) => p['terminalIndex'] == targetIndex);
            currentPositions.addAll(List<Map<String, dynamic>>.from(positions));
            _positionsNotifier.value = currentPositions;
          } else {
            // Full replacement when getting all positions
            _positionsNotifier.value = List<Map<String, dynamic>>.from(positions);
          }
        }
        break;

      case 'order_result':
        _handleOrderResult(message);
        break;

      case 'pong':
        break;
    }
  }

  void _handleOrderResult(Map<String, dynamic> message) {
    final success = message['success'] as bool? ?? false;
    final accountNum = message['account'] as String? ?? '';
    final errorMsg = message['error'] as String?;

    if (success) {
      _showSuccess('Order placed on $accountNum');
    } else {
      _showError('Order failed on $accountNum: ${errorMsg ?? "Unknown error"}');
    }
  }

  void _requestAccounts() {
    _connection.send({'action': 'get_accounts'});
  }

  void _requestPositions(int targetIndex) {
    _connection.send({
      'action': 'get_positions',
      'targetIndex': targetIndex,
    });
  }

  void _requestAllPositions() {
    _connection.send({
      'action': 'get_positions',
    });
  }

  void _closePosition(int ticket, int terminalIndex) {
    _connection.send({
      'action': 'close_position',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
    });
  }

  void _modifyPosition(int ticket, int terminalIndex, double? sl, double? tp) {
    _connection.send({
      'action': 'modify_position',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
      'sl': sl ?? 0,
      'tp': tp ?? 0,
    });
  }

  void _openAccountDetail(Map<String, dynamic> account) {
    final accountIndex = account['index'] as int;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountDetailScreen(
          initialAccount: account,
          accountsNotifier: _accountsNotifier,
          positionsNotifier: _positionsNotifier,
          onRefreshPositions: () => _requestPositions(accountIndex),
          onRefreshAllPositions: _requestAllPositions,
          onClosePosition: _closePosition,
          onModifyPosition: _modifyPosition,
        ),
      ),
    );
  }

  void _openNewOrder() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewOrderScreen(
          accounts: _accountsNotifier.value,
          onPlaceOrder: _placeOrder,
        ),
      ),
    );
  }

  void _placeOrder({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required List<int> accountIndices,
  }) {
    // Generate unique magic number for this order batch
    // Using timestamp to ensure uniqueness across orders
    final magic = DateTime.now().millisecondsSinceEpoch % 2147483647;
    
    for (final index in accountIndices) {
      _connection.send({
        'action': 'place_order',
        'symbol': symbol,
        'type': type,
        'lots': lots,
        'tp': tp ?? 0,
        'sl': sl ?? 0,
        'targetIndex': index,
        'magic': magic,
      });
    }
  }

  void _disconnect() async {
    _connection.disconnect();
    _stopAccountsRefresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_connection');
    setState(() {
      _connectionState = relay.ConnectionState.disconnected;
      _bridgeConnected = false;
      _roomId = null;
      _accountsNotifier.value = [];
      _positionsNotifier.value = [];
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  void dispose() {
    _connection.disconnect();
    _stopAccountsRefresh();
    _accountsNotifier.dispose();
    _positionsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showFab = _connectionState == relay.ConnectionState.connected &&
        _bridgeConnected &&
        _accountsNotifier.value.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              ConnectionCard(
                connectionState: _connectionState,
                bridgeConnected: _bridgeConnected,
                roomId: _roomId,
                onDisconnect: _disconnect,
              ),
              const SizedBox(height: 24),
              if (_connectionState == relay.ConnectionState.connected &&
                  _bridgeConnected) ...[
                Text(
                  'ACCOUNTS (${_accountsNotifier.value.length})',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _accountsNotifier.value.isEmpty
                      ? _buildLoadingAccounts()
                      : ValueListenableBuilder<List<Map<String, dynamic>>>(
                          valueListenable: _accountsNotifier,
                          builder: (context, accounts, _) {
                            return ListView.builder(
                              itemCount: accounts.length,
                              itemBuilder: (context, index) =>
                                  _buildAccountCard(accounts[index]),
                            );
                          },
                        ),
                ),
              ] else
                const Spacer(),
              if (_connectionState == relay.ConnectionState.disconnected)
                ScanButton(onPressed: _openScanner),
            ],
          ),
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton.extended(
              onPressed: _openNewOrder,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text(
                'New Order',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text('METASYNX', style: AppTextStyles.heading),
        const Spacer(),
        ConnectionIndicator(
          connectionState: _connectionState,
          bridgeConnected: _bridgeConnected,
        ),
      ],
    );
  }

  Widget _buildLoadingAccounts() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 16),
          Text('Loading accounts...', style: AppTextStyles.body),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final equity = (account['equity'] as num?)?.toDouble() ?? 0;
    final profit = (account['profit'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final name = account['name'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'USD';

    return GestureDetector(
      onTap: () => _openAccountDetail(account),
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
            // Account number & name
            Row(
              children: [
                Text(
                  accountNum,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (name.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      name,
                      style: AppTextStyles.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Balance, Equity, P/L row
            Row(
              children: [
                Expanded(
                  child: _buildStatColumn('Balance', balance, currency),
                ),
                Expanded(
                  child: _buildStatColumn('Equity', equity, currency),
                ),
                Expanded(
                  child: _buildPLColumn(profit, currency),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, double value, String currency) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          '${value.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildPLColumn(double profit, String currency) {
    final isPositive = profit >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('P/L', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(
          '${isPositive ? '+' : ''}${profit.toStringAsFixed(2)}',
          style: TextStyle(
            color: isPositive ? AppColors.primary : AppColors.error,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}