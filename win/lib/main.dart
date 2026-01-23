import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const MT4BridgeApp());
}

// ============================================
// CONFIGURATION - UPDATE THESE
// ============================================

const String RELAY_SERVER = 'vps2.bk.harmonicmarkets.com:8443';
const String API_KEY = 'YOUR_API_KEY_HERE'; // Your existing API key

// ============================================
// APP
// ============================================

class MT4BridgeApp extends StatelessWidget {
  const MT4BridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MT4 Bridge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00D4AA),
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        fontFamily: 'Segoe UI',
      ),
      home: const BridgeHomePage(),
    );
  }
}

class BridgeHomePage extends StatefulWidget {
  const BridgeHomePage({super.key});

  @override
  State<BridgeHomePage> createState() => _BridgeHomePageState();
}

class _BridgeHomePageState extends State<BridgeHomePage> {
  // Connection state
  RelayConnection? _connection;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  String? _roomId;
  String? _roomSecret;
  String? _qrData;
  bool _mobileConnected = false;
  String? _mobileDeviceName;
  List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _initializeConnection();
  }

  Future<void> _initializeConnection() async {
    _addLog('Initializing MT4 Bridge...');

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
      // Create room via REST API
      final response = await http.post(
        Uri.parse('https://$RELAY_SERVER/ws/relay/create-room'),
        headers: {
          'x-api-key': API_KEY,
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to create room: ${response.body}');
      }

      final data = jsonDecode(response.body);
      _roomId = data['room_id'];
      _roomSecret = data['room_secret'];
      _addLog('Room created: $_roomId');

      // Generate QR data with secret
      _generateQrData();

      // Connect to WebSocket
      await _connection!.connect(_roomId!, _roomSecret!);
    } catch (e) {
      _addLog('Error: $e');
      setState(() => _status = ConnectionStatus.error);
    }
  }

  void _generateQrData() {
    // QR code contains server, room, and secret
    final qrPayload = {
      'server': RELAY_SERVER,
      'room': _roomId,
      'secret': _roomSecret,
      'v': 2, // Version for compatibility checking
    };

    setState(() {
      _qrData = jsonEncode(qrPayload);
    });

    _addLog('QR code generated');
  }

  void _handleMessage(Map<String, dynamic> message) {
    final action = message['action'] as String?;
    _addLog('Received: $action');

    switch (action) {
      case 'ping':
        _connection?.send({'action': 'pong'});
        break;

      case 'get_accounts':
        // TODO: Get from EA and respond
        _connection?.send({
          'action': 'accounts_list',
          'accounts': _getMockAccounts(), // Replace with real EA data
        });
        break;

      case 'get_positions':
        // TODO: Get from EA and respond
        _connection?.send({
          'action': 'positions_list',
          'positions': [],
        });
        break;

      case 'place_order':
        _addLog('Order: ${message['symbol']} ${message['type']} ${message['lots']} lots');
        // TODO: Forward to EA
        break;

      default:
        _addLog('Unknown action: $action');
    }
  }

  List<Map<String, dynamic>> _getMockAccounts() {
    // Replace this with actual EA data
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
          // Left panel - QR Code and status
          Container(
            width: 400,
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              border: Border(
                right: BorderSide(
                  color: const Color(0xFF00D4AA).withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Header with status
                Container(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      _buildStatusIndicator(),
                      const SizedBox(width: 12),
                      const Text(
                        'MT4 BRIDGE',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
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
                          _mobileConnected ? 'MOBILE PAIRED' : 'SCAN TO CONNECT',
                          style: TextStyle(
                            fontSize: 14,
                            letterSpacing: 3,
                            color: _mobileConnected
                                ? const Color(0xFF00D4AA)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // QR Code or paired status
                        if (_mobileConnected)
                          _buildPairedStatus()
                        else
                          _buildQrCode(),

                        const SizedBox(height: 24),

                        // Room ID display
                        if (_roomId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Room: ',
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  _roomId!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontFamily: 'Consolas',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 2,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _roomId!));
                                    _addLog('Room ID copied to clipboard');
                                  },
                                  icon: const Icon(
                                    Icons.copy,
                                    size: 18,
                                    color: Color(0xFF6B7280),
                                  ),
                                  tooltip: 'Copy Room ID',
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 16),

                        // Regenerate button
                        TextButton.icon(
                          onPressed: _regenerateRoom,
                          icon: const Icon(
                            Icons.refresh,
                            size: 18,
                            color: Color(0xFF00D4AA),
                          ),
                          label: const Text(
                            'New Room',
                            style: TextStyle(
                              color: Color(0xFF00D4AA),
                            ),
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
                      _buildInfoRow('Server', RELAY_SERVER),
                      const SizedBox(height: 4),
                      _buildInfoRow('Status', _status.name.toUpperCase()),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right panel - Logs
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Mobile device card (if connected)
                if (_mobileConnected)
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF00D4AA).withOpacity(0.15),
                          const Color(0xFF00D4AA).withOpacity(0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00D4AA).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4AA).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.phone_android,
                            color: Color(0xFF00D4AA),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mobileDeviceName ?? 'Mobile Device',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const Text(
                                'Connected and ready',
                                style: TextStyle(
                                  color: Color(0xFF00D4AA),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4AA),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00D4AA).withOpacity(0.5),
                                blurRadius: 6,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Logs section
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      const Text(
                        'ACTIVITY LOG',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 2,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() => _logs.clear()),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _logs[index],
                          style: const TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 13,
                            color: Color(0xFF8B949E),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color color;
    switch (_status) {
      case ConnectionStatus.connected:
        color = const Color(0xFF00D4AA);
        break;
      case ConnectionStatus.connecting:
        color = Colors.orange;
        break;
      case ConnectionStatus.error:
        color = Colors.red;
        break;
      default:
        color = const Color(0xFF6B7280);
    }

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildQrCode() {
    if (_qrData == null || _status != ConnectionStatus.connected) {
      return Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: _status == ConnectionStatus.error
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'Connection Error',
                      style: TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _createRoomAndConnect,
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(
                  color: Color(0xFF00D4AA),
                ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00D4AA).withOpacity(0.15),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: QrImageView(
        data: _qrData!,
        version: QrVersions.auto,
        size: 220,
        backgroundColor: Colors.white,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0A0E14),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0A0E14),
        ),
      ),
    );
  }

  Widget _buildPairedStatus() {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00D4AA).withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4AA).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: Color(0xFF00D4AA),
              size: 64,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Successfully Paired',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _mobileDeviceName ?? 'Mobile Device',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF8B949E),
            fontFamily: 'Consolas',
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ============================================
// RELAY CONNECTION
// ============================================

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class RelayConnection {
  final Function(ConnectionStatus) onStatusChanged;
  final Function(bool, String?) onPairingStatusChanged;
  final Function(Map<String, dynamic>) onMessageReceived;
  final Function(String) onLog;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  String? _currentRoomId;
  String? _currentRoomSecret;
  bool _intentionalDisconnect = false;

  RelayConnection({
    required this.onStatusChanged,
    required this.onPairingStatusChanged,
    required this.onMessageReceived,
    required this.onLog,
  });

  Future<void> connect(String roomId, String roomSecret) async {
    _currentRoomId = roomId;
    _currentRoomSecret = roomSecret;
    _intentionalDisconnect = false;
    onStatusChanged(ConnectionStatus.connecting);

    try {
      final wsUrl = 'wss://$RELAY_SERVER/ws/relay/$roomId';
      onLog('Connecting to $wsUrl');

      _socket = await WebSocket.connect(wsUrl);
      onLog('WebSocket connected');

      // Send join message with secret
      _socket!.add(jsonEncode({
        'type': 'join',
        'role': 'bridge',
        'secret': roomSecret,
        'device_name': 'MT4 Bridge',
      }));

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (error) {
          onLog('WebSocket error: $error');
          _onDisconnected();
        },
      );
    } catch (e) {
      onLog('Connection failed: $e');
      onStatusChanged(ConnectionStatus.error);
      _scheduleReconnect();
    }
  }

  void _onData(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'joined':
          onLog('Joined room: ${message['room_id']}');
          onStatusChanged(ConnectionStatus.connected);
          break;

        case 'pairing_status':
          final mobileConnected = message['mobile_connected'] as bool? ?? false;
          final deviceName = message['mobile_device'] as String?;
          onPairingStatusChanged(mobileConnected, deviceName);
          break;

        case 'error':
          onLog('Server error: ${message['message']}');
          if (message['message'] == 'Invalid room secret') {
            onStatusChanged(ConnectionStatus.error);
          }
          break;

        default:
          // Forward other messages (from mobile) to handler
          onMessageReceived(message);
      }
    } catch (e) {
      onLog('Error parsing message: $e');
    }
  }

  void _onDisconnected() {
    _socket = null;

    if (!_intentionalDisconnect) {
      onStatusChanged(ConnectionStatus.disconnected);
      onPairingStatusChanged(false, null);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_intentionalDisconnect || _currentRoomId == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (_currentRoomId != null && 
          _currentRoomSecret != null && 
          !_intentionalDisconnect) {
        onLog('Attempting reconnect...');
        connect(_currentRoomId!, _currentRoomSecret!);
      }
    });
  }

  void send(Map<String, dynamic> message) {
    if (_socket != null) {
      _socket!.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _socket?.close();
    _socket = null;
    _currentRoomId = null;
    _currentRoomSecret = null;
    onStatusChanged(ConnectionStatus.disconnected);
  }
}