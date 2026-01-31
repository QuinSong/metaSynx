import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart';
import '../services/room_service.dart';
import '../services/ea_service.dart';
import '../services/user_service.dart';
import '../components/components.dart';

class HomeScreen extends StatefulWidget {
  final String relayServer;
  final String userEmail;
  final VoidCallback onSignOut;

  const HomeScreen({
    super.key,
    required this.relayServer,
    required this.userEmail,
    required this.onSignOut,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RelayConnection? _connection;
  final EAService _eaService = EAService();
  final UserService _userService = UserService();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _roomId;
  String? _roomSecret;
  String? _qrData;
  bool _mobileHasConnected = false;  // true once mobile connects (hides QR until New Room)
  String? _mobileDeviceName;
  List<String> _logs = [];
  List<Map<String, dynamic>> _accounts = [];
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  @override
  void dispose() {
    _disposed = true;
    // Decrement activeRooms if mobile was connected
    if (_mobileHasConnected) {
      _userService.decrementActiveRooms(widget.relayServer);
    }
    _connection?.disconnect();
    _eaService.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    if (_disposed) return;
    
    // Initialize EA Service (silent)
    _eaService.onLog = (msg) {
      if (!_disposed) _addLog(msg);
    };
    _eaService.onAccountsUpdated = (accounts) {
      if (!_disposed && mounted) {
        setState(() => _accounts = accounts);
      }
    };
    await _eaService.initialize();
    
    if (_disposed) return;
    _eaService.startPolling();

    if (_disposed) return;
    
    // Initialize Relay Connection
    _connection = RelayConnection(
      server: widget.relayServer,
      onStatusChanged: (status) {
        if (!_disposed && mounted) {
          setState(() => _status = status);
        }
      },
      onPairingStatusChanged: (mobileConnected, deviceName) {
        if (_disposed || !mounted) return;
        setState(() {
          // Only update device name if provided
          if (deviceName != null && deviceName.isNotEmpty) {
            _mobileDeviceName = deviceName;
          }
          
          // Once mobile connects for the first time, set flag to hide QR code
          if (mobileConnected && !_mobileHasConnected) {
            _mobileHasConnected = true;
            // Only log on first connect
            _addLog('📱 Mobile connected: $deviceName');
            // Increment activeRooms when mobile connects
            _userService.incrementActiveRooms(widget.relayServer);
          }
        });
        
        // Don't log disconnects here - relay sends disconnect when app is backgrounded
        // We only want to log when user manually disconnects or creates new room
      },
      onMessageReceived: (msg) {
        if (!_disposed) _handleMessage(msg);
      },
      onLog: (msg) {
        if (!_disposed) _addLog(msg);
      },
    );

    if (_disposed) return;
    await _createRoomAndConnect();
  }

  Future<void> _createRoomAndConnect() async {
    if (_disposed || !mounted) return;
    setState(() => _status = ConnectionStatus.connecting);

    try {
      // Try to restore saved room first
      final prefs = await SharedPreferences.getInstance();
      final savedRoomId = prefs.getString('room_id');
      final savedRoomSecret = prefs.getString('room_secret');
      final savedServer = prefs.getString('room_server');
      
      if (savedRoomId != null && savedRoomSecret != null && savedServer == widget.relayServer) {
        // Try to rejoin saved room
        _roomId = savedRoomId;
        _roomSecret = savedRoomSecret;
        _qrData = RoomService.generateQrPayload(widget.relayServer, _roomId!, _roomSecret!);
        _mobileHasConnected = true;  // Assume mobile was connected before
        setState(() {});
        
        _addLog('🔄 Restoring previous session...');
        await _connection!.connect(_roomId!, _roomSecret!);
        return;
      }
      
      // No saved room or different server - create new room
      final credentials = await RoomService.createRoom(widget.relayServer);
      _roomId = credentials.roomId;
      _roomSecret = credentials.roomSecret;

      // Save room credentials
      await prefs.setString('room_id', _roomId!);
      await prefs.setString('room_secret', _roomSecret!);
      await prefs.setString('room_server', widget.relayServer);

      _qrData = RoomService.generateQrPayload(widget.relayServer, _roomId!, _roomSecret!);
      setState(() {});

      await _connection!.connect(_roomId!, _roomSecret!);
    } catch (e) {
      _addLog('Error: $e');
      setState(() => _status = ConnectionStatus.error);
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final action = message['action'] as String?;

    switch (action) {
      case 'ping':
        _connection?.send({'action': 'pong'});
        break;

      case 'manual_disconnect':
        // User manually disconnected from the app - show QR code again
        _addLog('📱 Mobile disconnected');
        // Decrement activeRooms since mobile disconnected
        if (_mobileHasConnected) {
          _userService.decrementActiveRooms(widget.relayServer);
        }
        // Clear saved room so user needs to scan QR again
        _clearSavedRoom();
        setState(() {
          _mobileHasConnected = false;  // Reset so QR shows
          _mobileDeviceName = null;
        });
        break;

      case 'get_accounts':
        // Send real account data from EA
        _connection?.send({
          'action': 'accounts_list',
          'accounts': _accounts,
        });
        break;

      case 'get_positions':
        _handleGetPositions(message);
        break;

      case 'place_order':
        _handlePlaceOrder(message);
        break;

      case 'close_position':
        _handleClosePosition(message);
        break;

      case 'modify_position':
        _handleModifyPosition(message);
        break;

      case 'cancel_order':
        _handleCancelOrder(message);
        break;

      case 'modify_pending':
        _handleModifyPending(message);
        break;

      case 'get_chart_data':
        _handleGetChartData(message);
        break;

      case 'get_history':
        _handleGetHistory(message);
        break;

      case 'get_symbol_info':
        _handleGetSymbolInfo(message);
        break;
    }
  }

  String _getAccountName(int terminalIndex) {
    if (terminalIndex < _accounts.length) {
      final account = _accounts[terminalIndex];
      return account['account'] as String? ?? 'Account $terminalIndex';
    }
    return 'Account $terminalIndex';
  }

  Future<void> _handleGetSymbolInfo(Map<String, dynamic> message) async {
    final symbol = message['symbol'] as String?;
    final terminalIndex = message['terminalIndex'] as int? ?? 0;
    
    if (symbol == null || symbol.isEmpty) return;
    
    final info = await _eaService.getSymbolInfo(symbol, terminalIndex);
    
    if (info != null) {
      _connection?.send({
        'action': 'symbol_info',
        'symbol': symbol,
        ...info,
      });
    }
  }

  Future<void> _handleGetPositions(Map<String, dynamic> message) async {
    final targetIndex = message['targetIndex'] as int?;
    
    if (targetIndex != null) {
      // Get positions for specific terminal - read directly from file
      final positions = await _eaService.getPositions(targetIndex);
      for (final pos in positions) {
        pos['terminalIndex'] = targetIndex;
      }
      _connection?.send({
        'action': 'positions_list',
        'targetIndex': targetIndex,
        'positions': positions,
      });
    } else {
      // Get positions for all terminals
      final allPositions = await _eaService.getAllPositions();
      _connection?.send({
        'action': 'positions_list',
        'positions': allPositions,
      });
    }
  }

  Future<void> _handlePlaceOrder(Map<String, dynamic> message) async {
    final symbol = message['symbol'] as String;
    final type = message['type'] as String;
    final lots = (message['lots'] as num).toDouble();
    final sl = (message['sl'] as num?)?.toDouble();
    final tp = (message['tp'] as num?)?.toDouble();
    final price = (message['price'] as num?)?.toDouble();
    final targetIndex = message['targetIndex'] as int?;
    final targetAll = message['targetAll'] as bool? ?? false;
    final magic = message['magic'] as int?;

    // Format order type nicely
    final typeDisplay = type.replaceAll('_', ' ').toUpperCase();
    final priceStr = price != null && price > 0 ? ' @ $price' : '';
    
    if (targetAll) {
      _addLog('📈 $typeDisplay $symbol ${lots}L$priceStr → All accounts');
    } else if (targetIndex != null) {
      final accountName = _getAccountName(targetIndex);
      _addLog('📈 $typeDisplay $symbol ${lots}L$priceStr → $accountName');
    }

    await _eaService.placeOrder(
      symbol: symbol,
      type: type,
      lots: lots,
      sl: sl,
      tp: tp,
      price: price,
      targetIndex: targetIndex,
      targetAll: targetAll,
      magic: magic,
    );
  }

  Future<void> _handleClosePosition(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    final lots = (message['lots'] as num?)?.toDouble();
    
    if (ticket == null || terminalIndex == null) return;
    
    final accountName = _getAccountName(terminalIndex);
    if (lots != null) {
      _addLog('📉 Partial close #$ticket (${lots}L) → $accountName');
    } else {
      _addLog('📉 Close #$ticket → $accountName');
    }
    await _eaService.closePosition(ticket, terminalIndex, lots: lots);
  }

  Future<void> _handleModifyPosition(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    final sl = (message['sl'] as num?)?.toDouble();
    final tp = (message['tp'] as num?)?.toDouble();
    
    if (ticket == null || terminalIndex == null) return;
    
    final accountName = _getAccountName(terminalIndex);
    _addLog('✏️ Modify #$ticket → $accountName');
    await _eaService.modifyPosition(ticket, terminalIndex, sl: sl, tp: tp);
  }

  Future<void> _handleCancelOrder(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    
    if (ticket == null || terminalIndex == null) return;
    
    final accountName = _getAccountName(terminalIndex);
    _addLog('❌ Cancel #$ticket → $accountName');
    await _eaService.cancelOrder(ticket, terminalIndex);
  }

  Future<void> _handleModifyPending(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    final price = (message['price'] as num?)?.toDouble();
    final sl = (message['sl'] as num?)?.toDouble();
    final tp = (message['tp'] as num?)?.toDouble();
    
    if (ticket == null || terminalIndex == null || price == null) return;
    
    final accountName = _getAccountName(terminalIndex);
    _addLog('✏️ Modify pending #$ticket @ $price → $accountName');
    await _eaService.modifyPendingOrder(ticket, terminalIndex, price, sl: sl, tp: tp);
  }

  void _handleGetChartData(Map<String, dynamic> message) {
    final symbol = message['symbol'] as String?;
    final timeframe = message['timeframe'] as String?;
    final terminalIndex = message['terminalIndex'] as int? ?? 0;
    
    if (symbol == null || timeframe == null) return;
    
    // Fire and forget - don't block message processing
    _fetchAndSendChartData(symbol, timeframe, terminalIndex);
  }
  
  Future<void> _fetchAndSendChartData(String symbol, String timeframe, int terminalIndex) async {
    final data = await _eaService.getChartData(symbol, timeframe, terminalIndex);
    if (data != null) {
      _connection?.send({
        'action': 'chart_data',
        ...data,
      });
    }
  }

  void _handleGetHistory(Map<String, dynamic> message) {
    final period = message['period'] as String? ?? 'today';
    final terminalIndex = message['terminalIndex'] as int?;
    
    // Fire and forget
    _fetchAndSendHistory(period, terminalIndex);
  }
  
  Future<void> _fetchAndSendHistory(String period, int? terminalIndex) async {
    final allHistory = <Map<String, dynamic>>[];
    
    if (terminalIndex != null) {
      // Get history for specific terminal
      final history = await _eaService.getHistory(period, terminalIndex);
      allHistory.addAll(history);
    } else {
      // Get history for all terminals - get indices from accounts
      final accounts = await _eaService.getAccounts();
      for (final account in accounts) {
        final idx = account['index'] as int?;
        if (idx != null) {
          final history = await _eaService.getHistory(period, idx);
          allHistory.addAll(history);
        }
      }
    }
    
    // Sort by close time descending
    allHistory.sort((a, b) {
      final aTime = a['closeTime'] as int? ?? 0;
      final bTime = b['closeTime'] as int? ?? 0;
      return bTime.compareTo(aTime);
    });
    
    _connection?.send({
      'action': 'history_data',
      'period': period,
      'history': allHistory,
    });
  }

  void _regenerateRoom() async {
    // Log disconnect and decrement activeRooms if mobile was connected
    if (_mobileHasConnected) {
      _addLog('📱 Mobile disconnected');
      _userService.decrementActiveRooms(widget.relayServer);
    }
    
    // Clear saved room so a new one is created
    await _clearSavedRoom();
    
    _connection?.disconnect();
    setState(() {
      _roomId = null;
      _roomSecret = null;
      _qrData = null;
      _mobileHasConnected = false;  // Reset so QR shows again
      _mobileDeviceName = null;
    });
    await _createRoomAndConnect();
  }

  Future<void> _clearSavedRoom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('room_id');
    await prefs.remove('room_secret');
    await prefs.remove('room_server');
  }

  void _addLog(String message) {
    final now = DateTime.now();
    final timestamp = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.insert(0, '$timestamp  $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _buildLeftPanel(),
          _buildRightPanel(),
        ],
      ),
    );
  }

  Widget _buildLeftPanel() {
    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(
          right: BorderSide(
            color: AppColors.primaryWithOpacity(0.2),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Image.asset(
                  'assets/logo.png',
                  height: 50,
                ),
              ],
            ),
          ),

          // QR Code section
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _mobileHasConnected ? 'MOBILE PAIRED' : 'SCAN TO CONNECT',
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 3,
                      color: _mobileHasConnected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Show PairedStatus (always green) if mobile has connected, otherwise show QR
                  if (_mobileHasConnected)
                    PairedStatus(deviceName: _mobileDeviceName)
                  else
                    QrCodeDisplay(
                      qrData: _qrData,
                      status: _status,
                      onRetry: _createRoomAndConnect,
                    ),

                  const SizedBox(height: 24),

                  TextButton.icon(
                    onPressed: _regenerateRoom,
                    icon: const Icon(
                      Icons.refresh,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'New Room',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Connection info
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                InfoRow(label: 'User', value: widget.userEmail),
                const SizedBox(height: 4),
                InfoRow(label: 'Server', value: widget.relayServer),
                const SizedBox(height: 4),
                InfoRow(label: 'Status', value: _status.name.toUpperCase()),
                const SizedBox(height: 4),
                InfoRow(label: 'MT4 Terminals', value: '${_accounts.length} connected'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout, size: 18),
                    label: const Text('Sign Out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightPanel() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_mobileHasConnected) MobileDeviceCard(
            deviceName: _mobileDeviceName,
          ),
          
          // MT4 Terminals section - always show
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'MT4 TERMINALS${_accounts.isNotEmpty ? ' (${_accounts.length})' : ''}',
              style: AppTextStyles.label,
            ),
          ),
          if (_accounts.isNotEmpty)
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _accounts.length,
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  return _buildAccountCard(account);
                },
              ),
            )
          else
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.textSecondary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Attach MetaSynx EA to an MT4 chart to connect',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(
            child: ActivityLog(
              logs: _logs,
              onClear: () => setState(() => _logs.clear()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final balance = (account['balance'] as num?)?.toDouble() ?? 0;
    final equity = (account['equity'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final broker = account['broker'] as String? ?? '';
    final accountName = account['name'] as String? ?? '';
    final currency = account['currency'] as String? ?? 'USD';
    final connected = account['connected'] as bool? ?? false;

    return Container(
      width: 200,
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connected 
              ? AppColors.primaryWithOpacity(0.3) 
              : AppColors.error.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: connected ? AppColors.primary : AppColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  accountNum,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            broker,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          if (accountName.isNotEmpty) ...[
            Text(
              accountName,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          _buildAccountRow('Balance', balance, currency),
          _buildAccountRow('Equity', equity, currency),
        ],
      ),
    );
  }

  String _formatNumber(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    
    // Add thousand separators
    final buffer = StringBuffer();
    final digits = intPart.replaceAll('-', '');
    final isNegative = intPart.startsWith('-');
    
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(digits[i]);
    }
    
    return '${isNegative ? '-' : ''}${buffer.toString()}.$decPart';
  }

  Widget _buildAccountRow(String label, double value, String currency) {
    final isProfit = value >= 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 10,
          ),
        ),
        Text(
          '${_formatNumber(value)} $currency',
          style: TextStyle(
            color: label == 'Balance' 
                ? AppColors.textPrimary 
                : (isProfit ? AppColors.primary : AppColors.error),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}