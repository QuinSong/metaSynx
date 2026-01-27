import 'package:flutter/material.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart';
import '../services/room_service.dart';
import '../services/ea_service.dart';
import '../components/components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RelayConnection? _connection;
  final EAService _eaService = EAService();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _roomId;
  String? _roomSecret;
  String? _qrData;
  bool _mobileConnected = false;
  String? _mobileDeviceName;
  List<String> _logs = [];
  List<Map<String, dynamic>> _accounts = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    _addLog('Initializing MetaSynx Bridge...');

    // Initialize EA Service
    _eaService.onLog = _addLog;
    _eaService.onAccountsUpdated = (accounts) {
      setState(() => _accounts = accounts);
    };
    await _eaService.initialize();
    _eaService.startPolling();

    // Initialize Relay Connection
    _connection = RelayConnection(
      onStatusChanged: (status) {
        setState(() => _status = status);
        _addLog('Connection status: ${status.name}');
      },
      onPairingStatusChanged: (mobileConnected, deviceName) {
        setState(() {
          _mobileConnected = mobileConnected;
          _mobileDeviceName = deviceName;
        });
        if (mobileConnected) {
          _addLog('Mobile paired: $deviceName');
        } else {
          _addLog('Mobile disconnected');
        }
      },
      onMessageReceived: _handleMessage,
      onLog: _addLog,
    );

    await _createRoomAndConnect();
  }

  Future<void> _createRoomAndConnect() async {
    setState(() => _status = ConnectionStatus.connecting);
    _addLog('Creating relay room...');

    try {
      final credentials = await RoomService.createRoom();
      _roomId = credentials.roomId;
      _roomSecret = credentials.roomSecret;
      _addLog('Room created: $_roomId');

      _qrData = RoomService.generateQrPayload(_roomId!, _roomSecret!);
      setState(() {});
      _addLog('QR code generated');

      await _connection!.connect(_roomId!, _roomSecret!);
    } catch (e) {
      _addLog('Error: $e');
      setState(() => _status = ConnectionStatus.error);
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final action = message['action'] as String?;
    
    // Only log non-polling actions
    if (action != 'get_accounts' && action != 'get_positions' && action != 'ping' && action != 'get_chart_data') {
      _addLog('Received: $action');
    }

    switch (action) {
      case 'ping':
        _connection?.send({'action': 'pong'});
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

      case 'get_chart_data':
        _handleGetChartData(message);
        break;

      default:
        _addLog('Unknown action: $action');
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
    final targetIndex = message['targetIndex'] as int?;
    final targetAll = message['targetAll'] as bool? ?? false;
    final magic = message['magic'] as int?;

    _addLog('Order: $symbol $type $lots lots (magic: $magic)');

    await _eaService.placeOrder(
      symbol: symbol,
      type: type,
      lots: lots,
      sl: sl,
      tp: tp,
      targetIndex: targetIndex,
      targetAll: targetAll,
      magic: magic,
    );
  }

  Future<void> _handleClosePosition(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    
    if (ticket == null || terminalIndex == null) {
      _addLog('Close position: missing ticket or terminalIndex');
      return;
    }
    
    _addLog('Closing position: ticket=$ticket on terminal $terminalIndex');
    await _eaService.closePosition(ticket, terminalIndex);
    _addLog('Close command sent for ticket=$ticket');
  }

  Future<void> _handleModifyPosition(Map<String, dynamic> message) async {
    final ticket = message['ticket'] as int?;
    final terminalIndex = message['terminalIndex'] as int?;
    final sl = (message['sl'] as num?)?.toDouble();
    final tp = (message['tp'] as num?)?.toDouble();
    
    if (ticket == null || terminalIndex == null) {
      _addLog('Modify position: missing ticket or terminalIndex');
      return;
    }
    
    _addLog('Modifying position: ticket=$ticket on terminal $terminalIndex, SL=$sl, TP=$tp');
    await _eaService.modifyPosition(ticket, terminalIndex, sl: sl, tp: tp);
    _addLog('Modify command sent for ticket=$ticket');
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

  void _regenerateRoom() async {
    _addLog('Regenerating room...');
    _connection?.disconnect();
    setState(() {
      _roomId = null;
      _roomSecret = null;
      _qrData = null;
      _mobileConnected = false;
      _mobileDeviceName = null;
    });
    await _createRoomAndConnect();
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    setState(() {
      _logs.insert(0, '[$timestamp] $message');
      if (_logs.length > 100) _logs.removeLast();
    });
  }

  @override
  void dispose() {
    _connection?.disconnect();
    _eaService.dispose();
    super.dispose();
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
                StatusIndicator(status: _status),
                const SizedBox(width: 12),
                const Text('METASYNX BRIDGE', style: AppTextStyles.heading),
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
                    _mobileConnected ? 'MOBILE PAIRED' : 'SCAN TO CONNECT',
                    style: TextStyle(
                      fontSize: 14,
                      letterSpacing: 3,
                      color: _mobileConnected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_mobileConnected)
                    PairedStatus(deviceName: _mobileDeviceName)
                  else
                    QrCodeDisplay(
                      qrData: _qrData,
                      status: _status,
                      onRetry: _createRoomAndConnect,
                    ),

                  const SizedBox(height: 24),

                  if (_roomId != null)
                    RoomIdDisplay(
                      roomId: _roomId!,
                      onCopied: () => _addLog('Room ID copied to clipboard'),
                    ),

                  const SizedBox(height: 16),

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
                InfoRow(label: 'Server', value: relayServer),
                const SizedBox(height: 4),
                InfoRow(label: 'Status', value: _status.name.toUpperCase()),
                const SizedBox(height: 4),
                InfoRow(label: 'MT4 Terminals', value: '${_accounts.length} connected'),
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
          if (_mobileConnected) MobileDeviceCard(deviceName: _mobileDeviceName),
          
          // Account cards
          if (_accounts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'MT4 TERMINALS (${_accounts.length})',
                style: AppTextStyles.label,
              ),
            ),
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
            ),
          ],
          
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
    final freeMargin = (account['freeMargin'] as num?)?.toDouble() ?? 0;
    final accountNum = account['account'] as String? ?? 'Unknown';
    final broker = account['broker'] as String? ?? '';
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
          const SizedBox(height: 4),
          Text(
            broker,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          _buildAccountRow('Balance', balance, currency),
          _buildAccountRow('Equity', equity, currency),
          _buildAccountRow('Free', freeMargin, currency),
        ],
      ),
    );
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
          '${value.toStringAsFixed(2)} $currency',
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