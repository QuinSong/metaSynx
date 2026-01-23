import 'package:flutter/material.dart';
import '../core/config.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart';
import '../services/room_service.dart';
import '../components/components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RelayConnection? _connection;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _roomId;
  String? _roomSecret;
  String? _qrData;
  bool _mobileConnected = false;
  String? _mobileDeviceName;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    _addLog('Initializing MetaSynx Bridge...');

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
    _addLog('Received: $action');

    switch (action) {
      case 'ping':
        _connection?.send({'action': 'pong'});
        break;

      case 'get_accounts':
        _connection?.send({
          'action': 'accounts_list',
          'accounts': _getMockAccounts(),
        });
        break;

      case 'get_positions':
        _connection?.send({
          'action': 'positions_list',
          'positions': [],
        });
        break;

      case 'place_order':
        _addLog('Order: ${message['symbol']} ${message['type']} ${message['lots']} lots');
        break;

      default:
        _addLog('Unknown action: $action');
    }
  }

  List<Map<String, dynamic>> _getMockAccounts() {
    return [
      {'index': 0, 'account': '12345678', 'balance': 10000.00, 'equity': 10250.50, 'broker': 'Demo Broker'},
      {'index': 1, 'account': '87654321', 'balance': 5000.00, 'equity': 5120.75, 'broker': 'Demo Broker'},
    ];
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
}
