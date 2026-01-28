import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart' as relay;
import '../components/connection_card.dart';
import '../components/scan_button.dart';
import '../utils/formatters.dart';
import 'qr_scanner.dart';
import 'new_order.dart';
import 'account.dart';
import 'settings/settings.dart';
import 'chart.dart';
import 'history.dart';
import 'risk_calculator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final relay.RelayConnection _connection = relay.RelayConnection();
  relay.ConnectionState _connectionState = relay.ConnectionState.disconnected;
  bool _bridgeConnected = false;
  String? _roomId;
  final ValueNotifier<List<Map<String, dynamic>>> _accountsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final ValueNotifier<List<Map<String, dynamic>>> _positionsNotifier =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  final StreamController<Map<String, dynamic>> _chartDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _historyDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _symbolInfoController =
      StreamController<Map<String, dynamic>>.broadcast();
  Map<String, String> _accountNames = {};
  String? _mainAccountNum;
  Map<String, double> _lotRatios = {};
  Map<String, String> _symbolSuffixes = {};
  Set<String> _preferredPairs = {};
  bool _includeCommissionSwap = false;
  bool _showPLPercent = false;
  bool _confirmBeforeClose = true;
  Timer? _refreshTimer;
  bool _isAppInForeground = true;
  int _selectedNavIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _setupConnection();
    _tryAutoConnect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - resume immediately
        _isAppInForeground = true;
        // Force immediate reconnect if we have a saved connection
        _connection.reconnectNow();
        if (_bridgeConnected) {
          _startRefreshTimer();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // App went to background - stop polling
        _isAppInForeground = false;
        _stopRefreshTimer();
        break;
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    // Load account names
    final namesJson = prefs.getString('account_names');
    if (namesJson != null) {
      _accountNames = Map<String, String>.from(jsonDecode(namesJson));
    }

    // Load main account
    final mainAccount = prefs.getString('main_account');
    if (mainAccount != null && mainAccount.isNotEmpty) {
      _mainAccountNum = mainAccount;
    }

    // Load lot ratios
    final ratiosJson = prefs.getString('lot_ratios');
    if (ratiosJson != null) {
      final decoded = jsonDecode(ratiosJson) as Map<String, dynamic>;
      _lotRatios = decoded.map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    // Load symbol suffixes
    final suffixesJson = prefs.getString('symbol_suffixes');
    if (suffixesJson != null) {
      _symbolSuffixes = Map<String, String>.from(jsonDecode(suffixesJson));
    }

    // Load preferred pairs
    final pairsJson = prefs.getString('preferred_pairs');
    if (pairsJson != null) {
      final List<dynamic> decoded = jsonDecode(pairsJson);
      _preferredPairs = decoded.map((e) => e.toString()).toSet();
    }

    // Load include commission/swap setting
    _includeCommissionSwap = prefs.getBool('include_commission_swap') ?? false;

    // Load show P/L % setting
    _showPLPercent = prefs.getBool('show_pl_percent') ?? false;

    // Load confirm before close setting (default true)
    _confirmBeforeClose = prefs.getBool('confirm_before_close') ?? true;

    setState(() {});
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_names', jsonEncode(_accountNames));
    await prefs.setString('main_account', _mainAccountNum ?? '');
    await prefs.setString('lot_ratios', jsonEncode(_lotRatios));
    await prefs.setString('symbol_suffixes', jsonEncode(_symbolSuffixes));
    await prefs.setString(
      'preferred_pairs',
      jsonEncode(_preferredPairs.toList()),
    );
    await prefs.setBool('include_commission_swap', _includeCommissionSwap);
    await prefs.setBool('show_pl_percent', _showPLPercent);
    await prefs.setBool('confirm_before_close', _confirmBeforeClose);
  }

  Future<void> _updateConfirmBeforeClose(bool value) async {
    setState(() => _confirmBeforeClose = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('confirm_before_close', value);
  }

  String getAccountDisplayName(Map<String, dynamic> account) {
    final accountNum = account['account'] as String? ?? '';
    final customName = _accountNames[accountNum];
    if (customName != null && customName.isNotEmpty) {
      return customName;
    }
    return accountNum;
  }

  double _getLotRatio(String accountNum) {
    if (_mainAccountNum == null) return 1.0;
    if (accountNum == _mainAccountNum) return 1.0;
    return _lotRatios[accountNum] ?? 1.0;
  }

  String _getSymbolWithSuffix(String symbol, String accountNum) {
    final suffix = _symbolSuffixes[accountNum] ?? '';
    return '$symbol$suffix';
  }

  void _setupConnection() {
    _connection.onStateChanged = (state) {
      setState(() => _connectionState = state);
      if (state == relay.ConnectionState.connected) {
        _startAccountsRefresh();
      } else {
        _stopAccountsRefresh();
        // Check if connection config was cleared (room expired)
        if (_connection.connectionConfig == null && _roomId != null) {
          _handleRoomExpired();
        }
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

  Future<void> _handleRoomExpired() async {
    // Clear saved connection
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_connection');
    setState(() {
      _roomId = null;
      _accountsNotifier.value = [];
      _positionsNotifier.value = [];
    });
    _showError('Connection expired. Please scan QR code again.');
  }

  void _startAccountsRefresh() {
    // Don't start if app is in background
    if (!_isAppInForeground) return;

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_bridgeConnected && _isAppInForeground) {
        _requestAccounts();
        _requestAllPositions();
      }
    });
  }

  void _startRefreshTimer() {
    _startAccountsRefresh();
  }

  void _stopAccountsRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _stopRefreshTimer() {
    _stopAccountsRefresh();
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
        await _connection.restoreConnection(config);
      } catch (e) {
        debugPrint('Auto-connect failed: $e');
        // Don't clear config - let it keep trying
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
            final currentPositions = List<Map<String, dynamic>>.from(
              _positionsNotifier.value,
            );
            currentPositions.removeWhere(
              (p) => p['terminalIndex'] == targetIndex,
            );
            currentPositions.addAll(List<Map<String, dynamic>>.from(positions));
            _positionsNotifier.value = currentPositions;
          } else {
            // Full replacement when getting all positions
            _positionsNotifier.value = List<Map<String, dynamic>>.from(
              positions,
            );
          }
        }
        break;

      case 'order_result':
        _handleOrderResult(message);
        break;

      case 'chart_data':
        // Forward chart data via stream
        _chartDataController.add(message);
        break;

      case 'symbol_info':
        // Forward symbol info via stream
        _symbolInfoController.add(message);
        break;

      case 'history_data':
        // Forward history data via stream
        _historyDataController.add(message);
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

  void _requestAllPositions() {
    _connection.send({'action': 'get_positions'});
  }

  void _closePosition(int ticket, int terminalIndex, [double? lots]) {
    final data = <String, dynamic>{
      'action': 'close_position',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
    };
    if (lots != null) {
      data['lots'] = lots;
    }
    _connection.send(data);
  }

  void _modifyPosition(int ticket, int terminalIndex, double? sl, double? tp) {
    // -1 = keep existing, 0 = remove, >0 = set new value
    _connection.send({
      'action': 'modify_position',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
      'sl': sl ?? -1,
      'tp': tp ?? -1,
    });
  }

  void _cancelOrder(int ticket, int terminalIndex) {
    _connection.send({
      'action': 'cancel_order',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
    });
  }

  void _modifyPendingOrder(int ticket, int terminalIndex, double price) {
    _connection.send({
      'action': 'modify_pending',
      'ticket': ticket,
      'terminalIndex': terminalIndex,
      'price': price,
    });
  }

  void _requestChartData(String symbol, String timeframe, int terminalIndex) {
    _connection.send({
      'action': 'get_chart_data',
      'symbol': symbol,
      'timeframe': timeframe,
      'terminalIndex': terminalIndex,
    });
  }

  void _requestHistory(String period, int? terminalIndex) {
    _connection.send({
      'action': 'get_history',
      'period': period,
      'terminalIndex': terminalIndex,
    });
  }

  void _requestSymbolInfo(String symbol, int terminalIndex) {
    _connection.send({
      'action': 'get_symbol_info',
      'symbol': symbol,
      'terminalIndex': terminalIndex,
    });
  }

  void _openAccountDetail(Map<String, dynamic> account) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountDetailScreen(
          initialAccount: account,
          accountsNotifier: _accountsNotifier,
          positionsNotifier: _positionsNotifier,
          onClosePosition: _closePosition,
          onModifyPosition: _modifyPosition,
          onCancelOrder: _cancelOrder,
          onModifyPendingOrder: _modifyPendingOrder,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          includeCommissionSwap: _includeCommissionSwap,
          showPLPercent: _showPLPercent,
          confirmBeforeClose: _confirmBeforeClose,
          onConfirmBeforeCloseChanged: _updateConfirmBeforeClose,
          symbolSuffixes: _symbolSuffixes,
          lotRatios: _lotRatios,
          preferredPairs: _preferredPairs,
          onPlaceOrder: _placeOrder,
          chartDataStream: _chartDataController.stream,
          onRequestChartData: _requestChartData,
          bottomNavBar: _buildExternalNavBar(1), // Chart highlighted
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
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          lotRatios: _lotRatios,
          preferredPairs: _preferredPairs,
          symbolSuffixes: _symbolSuffixes,
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
    required double? price,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) {
    // Generate unique magic number for this order batch
    // Using timestamp to ensure uniqueness across orders
    final magic = DateTime.now().millisecondsSinceEpoch % 2147483647;

    for (final index in accountIndices) {
      double adjustedLots = lots;

      if (useRatios) {
        // Find account number for this index to get lot ratio
        final account = _accountsNotifier.value.firstWhere(
          (a) => a['index'] == index,
          orElse: () => <String, dynamic>{},
        );
        final accountNum = account['account'] as String? ?? '';
        final ratio = _getLotRatio(accountNum);
        adjustedLots = double.parse((lots * ratio).toStringAsFixed(2));
      }

      // Get account for symbol suffix (only if applySuffix is true)
      String finalSymbol = symbol;
      if (applySuffix) {
        final account = _accountsNotifier.value.firstWhere(
          (a) => a['index'] == index,
          orElse: () => <String, dynamic>{},
        );
        final accountNum = account['account'] as String? ?? '';
        finalSymbol = _getSymbolWithSuffix(symbol, accountNum);
      }

      _connection.send({
        'action': 'place_order',
        'symbol': finalSymbol,
        'type': type,
        'lots': adjustedLots,
        'tp': tp ?? 0,
        'sl': sl ?? 0,
        'price': price ?? 0,
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
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.primary),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connection.disconnect();
    _stopAccountsRefresh();
    _accountsNotifier.dispose();
    _positionsNotifier.dispose();
    _chartDataController.close();
    _historyDataController.close();
    _symbolInfoController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFullyConnected =
        _connectionState == relay.ConnectionState.connected &&
        _bridgeConnected &&
        _accountsNotifier.value.isNotEmpty;

    // Show accounts view if connected OR if we have cached accounts (reconnecting)
    final showAccountsView =
        isFullyConnected || _accountsNotifier.value.isNotEmpty;

    return Scaffold(
      body: showAccountsView
          ? SafeArea(child: _buildCurrentScreen())
          : _buildDisconnectedContent(), // Handle SafeArea internally
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_selectedNavIndex) {
      case 0:
        return _buildHomeContent();
      case 1:
        return ChartScreen(
          positions: _positionsNotifier.value,
          positionsNotifier: _positionsNotifier,
          accounts: _accountsNotifier.value,
          onClosePosition: _closePosition,
          onModifyPosition: _modifyPosition,
          onCancelOrder: _cancelOrder,
          onModifyPendingOrder: _modifyPendingOrder,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          includeCommissionSwap: _includeCommissionSwap,
          showPLPercent: _showPLPercent,
          confirmBeforeClose: _confirmBeforeClose,
          onConfirmBeforeCloseChanged: _updateConfirmBeforeClose,
          chartDataStream: _chartDataController.stream,
          onRequestChartData: _requestChartData,
          symbolSuffixes: _symbolSuffixes,
          lotRatios: _lotRatios,
          preferredPairs: _preferredPairs,
          onPlaceOrder: _placeOrder,
        );
      case 2:
        return HistoryScreen(
          accountNames: _accountNames,
          historyDataStream: _historyDataController.stream,
          onRequestHistory: _requestHistory,
          includeCommissionSwap: _includeCommissionSwap,
        );
      case 3:
        return SettingsScreen(
          accounts: _accountsNotifier.value,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          lotRatios: _lotRatios,
          symbolSuffixes: _symbolSuffixes,
          preferredPairs: _preferredPairs,
          includeCommissionSwap: _includeCommissionSwap,
          showPLPercent: _showPLPercent,
          confirmBeforeClose: _confirmBeforeClose,
          onNamesUpdated: (names) {
            setState(() {
              _accountNames = names;
            });
            _saveSettings();
          },
          onMainAccountUpdated: (accountNum) {
            setState(() {
              _mainAccountNum = accountNum;
            });
            _saveSettings();
          },
          onLotRatiosUpdated: (ratios) {
            setState(() {
              _lotRatios = ratios;
            });
            _saveSettings();
          },
          onSymbolSuffixesUpdated: (suffixes) {
            setState(() {
              _symbolSuffixes = suffixes;
            });
            _saveSettings();
          },
          onPreferredPairsUpdated: (pairs) {
            setState(() {
              _preferredPairs = pairs;
            });
          },
          onIncludeCommissionSwapUpdated: (value) {
            setState(() {
              _includeCommissionSwap = value;
            });
          },
          onShowPLPercentUpdated: (value) {
            setState(() {
              _showPLPercent = value;
            });
          },
          onConfirmBeforeCloseUpdated: (value) {
            setState(() {
              _confirmBeforeClose = value;
            });
          },
        );
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    final isFullyConnected =
        _connectionState == relay.ConnectionState.connected && _bridgeConnected;
    final isReconnecting =
        _accountsNotifier.value.isNotEmpty && !isFullyConnected;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          ConnectionCard(
            connectionState: _connectionState,
            bridgeConnected: _bridgeConnected,
            roomId: _roomId,
            onDisconnect: _disconnect,
            isReconnecting: isReconnecting,
          ),
          const SizedBox(height: 24),
          Text(
            'ACCOUNTS (${_accountsNotifier.value.length})',
            style: AppTextStyles.label,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: _accountsNotifier,
              builder: (context, accounts, _) {
                return ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: _positionsNotifier,
                  builder: (context, positions, _) {
                    // Sort accounts with main account first
                    final sortedAccounts = List<Map<String, dynamic>>.from(
                      accounts,
                    );
                    sortedAccounts.sort((a, b) {
                      final aIsMain = a['account'] == _mainAccountNum;
                      final bIsMain = b['account'] == _mainAccountNum;
                      if (aIsMain && !bIsMain) return -1;
                      if (!aIsMain && bIsMain) return 1;
                      return (a['index'] as int? ?? 0).compareTo(
                        b['index'] as int? ?? 0,
                      );
                    });
                    return ListView(
                      children: [
                        // Show totals section if more than 1 account
                        if (sortedAccounts.length > 1)
                          _buildTotalsSection(sortedAccounts, positions),
                        // Account cards
                        ...sortedAccounts.map(
                          (account) => _buildAccountCard(account),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedContent() {
    // When not connected and no cached accounts
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return SafeArea(
      bottom: false, // We'll handle bottom separately for the button
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildHeader(),
                const SizedBox(height: 10),
                ConnectionCard(
                  connectionState: _connectionState,
                  bridgeConnected: _bridgeConnected,
                  roomId: _roomId,
                  onDisconnect: _disconnect,
                ),
                // Show loading accounts if connected to bridge but no accounts yet
                if (_connectionState == relay.ConnectionState.connected &&
                    _bridgeConnected &&
                    _accountsNotifier.value.isEmpty) ...[
                  const SizedBox(height: 24),
                  _buildLoadingAccounts(),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (_connectionState == relay.ConnectionState.disconnected)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding),
              child: ScanButton(onPressed: _openScanner),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    // Show nav bar if connected OR if we have cached accounts (reconnecting)
    final showNavBar =
        (_connectionState == relay.ConnectionState.connected &&
            _bridgeConnected &&
            _accountsNotifier.value.isNotEmpty) ||
        _accountsNotifier.value.isNotEmpty;

    if (!showNavBar) return const SizedBox.shrink();

    return _buildNavBarContent(_selectedNavIndex, (index) {
      setState(() {
        _selectedNavIndex = index;
      });
    });
  }

  // Build nav bar for pushed screens (account detail -> position -> chart)
  Widget _buildExternalNavBar(int selectedIndex) {
    return _buildNavBarContent(selectedIndex, (index) {
      // Pop all routes back to home and set the selected tab
      Navigator.of(context).popUntil((route) => route.isFirst);
      setState(() {
        _selectedNavIndex = index;
      });
    });
  }

  Widget _buildNavBarContent(int selectedIndex, void Function(int) onTap) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItemWithCallback(
                Icons.home,
                'Home',
                0,
                selectedIndex,
                onTap,
              ),
              _buildNavItemWithCallback(
                Icons.candlestick_chart,
                'Chart',
                1,
                selectedIndex,
                onTap,
              ),
              _buildNavItemWithCallback(
                Icons.history,
                'History',
                2,
                selectedIndex,
                onTap,
              ),
              _buildNavItemWithCallback(
                Icons.settings,
                'Settings',
                3,
                selectedIndex,
                onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItemWithCallback(
    IconData icon,
    String label,
    int index,
    int selectedIndex,
    void Function(int) onTap,
  ) {
    final isSelected = selectedIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    // Show buttons if connected OR if we have cached accounts (reconnecting)
    final showButtons =
        (_connectionState == relay.ConnectionState.connected &&
            _bridgeConnected &&
            _accountsNotifier.value.isNotEmpty) ||
        _accountsNotifier.value.isNotEmpty;

    return Row(
      children: [
        const Text('METASYNX', style: AppTextStyles.heading),
        const Spacer(),
        if (showButtons) ...[
          IconButton(
            icon: const Icon(
              Icons.calculate_outlined,
              color: AppColors.primary,
              size: 26,
            ),
            onPressed: _openRiskCalculator,
            tooltip: 'Risk Calculator',
          ),
          IconButton(
            icon: const FaIcon(
              FontAwesomeIcons.squarePlus,
              color: AppColors.primary,
              size: 24,
            ),
            onPressed: _openNewOrder,
            tooltip: 'New Order',
          ),
        ],
      ],
    );
  }

  void _openRiskCalculator() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RiskCalculatorScreen(
          accounts: _accountsNotifier.value,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          lotRatios: _lotRatios,
          symbolSuffixes: _symbolSuffixes,
          preferredPairs: _preferredPairs,
          onOpenNewOrder: _openNewOrderWithValues,
          onRequestSymbolInfo: _requestSymbolInfo,
          symbolInfoStream: _symbolInfoController.stream,
        ),
      ),
    );
  }

  void _openNewOrderWithValues({
    required String symbol,
    required String orderType,
    required String lots,
    String? sl,
    String? tp,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewOrderScreen(
          accounts: _accountsNotifier.value,
          accountNames: _accountNames,
          mainAccountNum: _mainAccountNum,
          lotRatios: _lotRatios,
          preferredPairs: _preferredPairs,
          symbolSuffixes: _symbolSuffixes,
          initialSymbol: symbol,
          initialOrderType: orderType,
          initialLots: lots,
          initialSL: sl,
          initialTP: tp,
          onPlaceOrder: _placeOrder,
        ),
      ),
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

  Widget _buildTotalsSection(
    List<Map<String, dynamic>> accounts,
    List<Map<String, dynamic>> positions,
  ) {
    double totalBalance = 0;
    double totalEquity = 0;
    double totalProfit = 0;

    for (final account in accounts) {
      totalBalance += (account['balance'] as num?)?.toDouble() ?? 0;
      totalEquity += (account['equity'] as num?)?.toDouble() ?? 0;

      final accountIndex = account['index'] as int? ?? -1;
      final accountPositions = positions.where(
        (p) => p['terminalIndex'] == accountIndex,
      );

      for (final pos in accountPositions) {
        final rawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
        if (_includeCommissionSwap) {
          final swap = (pos['swap'] as num?)?.toDouble() ?? 0;
          final commission = (pos['commission'] as num?)?.toDouble() ?? 0;
          totalProfit += rawProfit + swap + commission;
        } else {
          totalProfit += rawProfit;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          const Text(
            'TOTAL',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Balance',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrency(totalBalance),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrency(totalEquity),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
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
                          _includeCommissionSwap ? 'Net P/L' : 'P/L',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                        if (_showPLPercent && totalBalance > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '${((totalProfit / totalBalance) * 100).toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: totalProfit == 0
                                  ? Colors.white
                                  : (totalProfit > 0
                                        ? AppColors.primary
                                        : AppColors.error),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      Formatters.formatCurrencyWithSign(totalProfit),
                      style: TextStyle(
                        color: totalProfit >= 0
                            ? AppColors.primary
                            : AppColors.error,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final equity = (account['equity'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final accountIndex = account['index'] as int? ?? -1;
    final currency = account['currency'] as String? ?? 'USD';
    final displayName = getAccountDisplayName(account);
    final hasCustomName = _accountNames[accountNum]?.isNotEmpty == true;
    final isMainAccount = _mainAccountNum == accountNum;

    // Calculate P/L from positions based on setting
    final accountPositions = _positionsNotifier.value
        .where((p) => p['terminalIndex'] == accountIndex)
        .toList();

    double profit = 0;
    for (final pos in accountPositions) {
      final rawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
      if (_includeCommissionSwap) {
        final swap = (pos['swap'] as num?)?.toDouble() ?? 0;
        final commission = (pos['commission'] as num?)?.toDouble() ?? 0;
        profit += rawProfit + swap + commission;
      } else {
        profit += rawProfit;
      }
    }

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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMainAccount) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'MAIN',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (hasCustomName)
                        Text(
                          accountNum,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
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
                Expanded(child: _buildStatColumn('Balance', balance, currency)),
                Expanded(child: _buildStatColumn('Equity', equity, currency)),
                Expanded(
                  child: _buildPLColumn(
                    profit,
                    balance,
                    currency,
                    _includeCommissionSwap,
                  ),
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
        Text(
          label,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          Formatters.formatCurrency(value),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildPLColumn(
    double profit,
    double balance,
    String currency,
    bool isNetPL,
  ) {
    final isPositive = profit >= 0;
    final plPercent = balance > 0 ? (profit / balance) * 100 : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              isNetPL ? 'Net P/L' : 'P/L',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            if (_showPLPercent && balance > 0) ...[
              const SizedBox(width: 8),
              Text(
                '${plPercent.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: profit == 0
                      ? Colors.white
                      : (profit > 0 ? AppColors.primary : AppColors.error),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          Formatters.formatCurrencyWithSign(profit),
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
