import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const MT4ControlApp());
}

class MT4ControlApp extends StatelessWidget {
  const MT4ControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MT4 Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00D4AA),
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        fontFamily: 'SF Pro Display',
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E14),
          elevation: 0,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ============================================
// HOME PAGE
// ============================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final RelayConnection _connection = RelayConnection();
  ConnectionState _connectionState = ConnectionState.disconnected;
  bool _bridgeConnected = false;
  String? _roomId;

  @override
  void initState() {
    super.initState();
    _connection.onStateChanged = (state) {
      setState(() => _connectionState = state);
    };
    _connection.onPairingStatusChanged = (bridgeConnected) {
      setState(() => _bridgeConnected = bridgeConnected);
    };
    _connection.onMessage = _handleMessage;
    _tryAutoConnect();
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
        // Auto-connect failed, user will need to scan again
        debugPrint('Auto-connect failed: $e');
      }
    }
  }

  void _openScanner() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (result != null) {
      setState(() {
        _connectionState = ConnectionState.connecting;
        _roomId = result['room'];
      });

      try {
        await _connection.connect(result);

        // Save for auto-reconnect
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('last_connection', jsonEncode(result));
      } catch (e) {
        _showError('Connection failed: $e');
        setState(() => _connectionState = ConnectionState.disconnected);
      }
    }
  }

  void _handleMessage(Map<String, dynamic> message) {
    final action = message['action'] as String?;
    
    switch (action) {
      case 'accounts_list':
        final accounts = message['accounts'] as List?;
        debugPrint('Received ${accounts?.length ?? 0} accounts');
        // TODO: Update UI with accounts
        break;
      
      case 'positions_list':
        // TODO: Update UI with positions
        break;
      
      case 'pong':
        // Ping response
        break;
    }
  }

  void _disconnect() async {
    _connection.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_connection');
    setState(() {
      _connectionState = ConnectionState.disconnected;
      _bridgeConnected = false;
      _roomId = null;
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

  @override
  void dispose() {
    _connection.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Text(
                    'MT4 CONTROL',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  _buildConnectionIndicator(),
                ],
              ),

              const SizedBox(height: 48),

              // Connection Card
              _buildConnectionCard(),

              const SizedBox(height: 24),

              // Quick Actions (only when fully paired)
              if (_connectionState == ConnectionState.connected && _bridgeConnected) ...[
                const Text(
                  'QUICK ACTIONS',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 2,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 16),
                _buildQuickActions(),
              ],

              const Spacer(),

              // Scan Button (when disconnected)
              if (_connectionState == ConnectionState.disconnected)
                _buildScanButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    Color color;
    String text;

    if (_connectionState == ConnectionState.connected && _bridgeConnected) {
      color = const Color(0xFF00D4AA);
      text = 'Paired';
    } else if (_connectionState == ConnectionState.connected) {
      color = Colors.orange;
      text = 'Waiting for Bridge';
    } else if (_connectionState == ConnectionState.connecting) {
      color = Colors.orange;
      text = 'Connecting...';
    } else {
      color = const Color(0xFF6B7280);
      text = 'Disconnected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard() {
    if (_connectionState == ConnectionState.connected && _bridgeConnected) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF00D4AA).withOpacity(0.15),
              const Color(0xFF00D4AA).withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF00D4AA).withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D4AA).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.link,
                    color: Color(0xFF00D4AA),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'MT4 Bridge Connected',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Room: $_roomId',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _disconnect,
                  icon: const Icon(
                    Icons.link_off,
                    color: Color(0xFF6B7280),
                  ),
                  tooltip: 'Disconnect',
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_connectionState == ConnectionState.connected) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.orange.withOpacity(0.3),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Colors.orange,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Waiting for Bridge',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Room: $_roomId',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Make sure the Windows Bridge is running',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _disconnect,
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      );
    }

    if (_connectionState == ConnectionState.connecting) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF30363D),
          ),
        ),
        child: const Column(
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Color(0xFF00D4AA),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Connecting...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF30363D),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.qr_code_scanner,
            size: 48,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 16),
          const Text(
            'No Bridge Connected',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Scan the QR code on your VPS to connect',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildActionCard(
          icon: Icons.account_balance_wallet,
          label: 'Accounts',
          onTap: () {
            _connection.send({'action': 'get_accounts'});
          },
        ),
        _buildActionCard(
          icon: Icons.candlestick_chart,
          label: 'Positions',
          onTap: () {
            _connection.send({'action': 'get_positions'});
          },
        ),
        _buildActionCard(
          icon: Icons.add_circle_outline,
          label: 'New Order',
          onTap: () {
            // TODO: Navigate to new order page
          },
        ),
        _buildActionCard(
          icon: Icons.history,
          label: 'History',
          onTap: () {
            // TODO: Navigate to history page
          },
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF30363D),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: const Color(0xFF00D4AA),
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _openScanner,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00D4AA),
          foregroundColor: const Color(0xFF0A0E14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_scanner, size: 24),
            SizedBox(width: 12),
            Text(
              'Scan QR Code',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// QR SCANNER PAGE
// ============================================

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _processQRCode(barcode.rawValue!);
        break;
      }
    }
  }

  void _processQRCode(String rawValue) {
    setState(() => _isProcessing = true);

    try {
      final data = jsonDecode(rawValue) as Map<String, dynamic>;

      // Validate QR data (must have server, room, and secret)
      if (!data.containsKey('server') || 
          !data.containsKey('room') || 
          !data.containsKey('secret')) {
        _showError('Invalid QR code format');
        setState(() => _isProcessing = false);
        return;
      }

      // Check version compatibility
      final version = data['v'] as int? ?? 1;
      if (version < 2) {
        _showError('QR code version not supported. Please regenerate.');
        setState(() => _isProcessing = false);
        return;
      }

      HapticFeedback.mediumImpact();
      Navigator.pop(context, data);
    } catch (e) {
      _showError('Could not parse QR code');
      setState(() => _isProcessing = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          Container(
            decoration: ShapeDecoration(
              shape: QRScannerOverlayShape(
                borderColor: const Color(0xFF00D4AA),
                borderRadius: 16,
                borderLength: 40,
                borderWidth: 4,
                cutOutSize: 280,
                overlayColor: Colors.black.withOpacity(0.7),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Scan Bridge QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _controller.toggleTorch(),
                    icon: const Icon(
                      Icons.flash_on,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 100,
            left: 24,
            right: 24,
            child: Column(
              children: [
                if (_isProcessing)
                  const CircularProgressIndicator(
                    color: Color(0xFF00D4AA),
                  )
                else
                  const Text(
                    'Point your camera at the QR code\non your MT4 Bridge',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// QR SCANNER OVERLAY
// ============================================

class QRScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final Color overlayColor;
  final double borderRadius;
  final double borderLength;
  final double cutOutSize;

  const QRScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 3.0,
    this.overlayColor = Colors.black54,
    this.borderRadius = 0,
    this.borderLength = 40,
    this.cutOutSize = 250,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addRect(rect)
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: rect.center,
            width: cutOutSize,
            height: cutOutSize,
          ),
          Radius.circular(borderRadius),
        ),
      )
      ..fillType = PathFillType.evenOdd;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;

    final cutOut = Rect.fromCenter(
      center: rect.center,
      width: cutOutSize,
      height: cutOutSize,
    );

    canvas.drawPath(getOuterPath(rect), paint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth
      ..strokeCap = StrokeCap.round;

    // Top left
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.left, cutOut.top + borderLength)
        ..lineTo(cutOut.left, cutOut.top + borderRadius)
        ..quadraticBezierTo(cutOut.left, cutOut.top, cutOut.left + borderRadius, cutOut.top)
        ..lineTo(cutOut.left + borderLength, cutOut.top),
      borderPaint,
    );

    // Top right
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.right - borderLength, cutOut.top)
        ..lineTo(cutOut.right - borderRadius, cutOut.top)
        ..quadraticBezierTo(cutOut.right, cutOut.top, cutOut.right, cutOut.top + borderRadius)
        ..lineTo(cutOut.right, cutOut.top + borderLength),
      borderPaint,
    );

    // Bottom right
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.right, cutOut.bottom - borderLength)
        ..lineTo(cutOut.right, cutOut.bottom - borderRadius)
        ..quadraticBezierTo(cutOut.right, cutOut.bottom, cutOut.right - borderRadius, cutOut.bottom)
        ..lineTo(cutOut.right - borderLength, cutOut.bottom),
      borderPaint,
    );

    // Bottom left
    canvas.drawPath(
      Path()
        ..moveTo(cutOut.left + borderLength, cutOut.bottom)
        ..lineTo(cutOut.left + borderRadius, cutOut.bottom)
        ..quadraticBezierTo(cutOut.left, cutOut.bottom, cutOut.left, cutOut.bottom - borderRadius)
        ..lineTo(cutOut.left, cutOut.bottom - borderLength),
      borderPaint,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return QRScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth * t,
      overlayColor: overlayColor,
      borderRadius: borderRadius * t,
      borderLength: borderLength * t,
      cutOutSize: cutOutSize * t,
    );
  }
}

// ============================================
// RELAY CONNECTION
// ============================================

enum ConnectionState {
  disconnected,
  connecting,
  connected,
}

class RelayConnection {
  WebSocket? _socket;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Map<String, dynamic>? _connectionConfig;
  String? _deviceName;

  ConnectionState _state = ConnectionState.disconnected;
  Function(ConnectionState)? onStateChanged;
  Function(bool)? onPairingStatusChanged;
  Function(Map<String, dynamic>)? onMessage;

  ConnectionState get state => _state;
  bool get isConnected => _state == ConnectionState.connected;

  void _setState(ConnectionState newState) {
    _state = newState;
    onStateChanged?.call(newState);
  }

  Future<void> connect(Map<String, dynamic> config) async {
    _connectionConfig = config;
    _setState(ConnectionState.connecting);

    final server = config['server'] as String;
    final roomId = config['room'] as String;
    final secret = config['secret'] as String;

    _deviceName = await _getDeviceName();

    try {
      final wsUrl = 'wss://$server/ws/relay/$roomId';
      debugPrint('Connecting to $wsUrl');

      _socket = await WebSocket.connect(wsUrl)
          .timeout(const Duration(seconds: 10));

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _onDisconnected();
        },
      );

      // Send join message with secret
      _socket!.add(jsonEncode({
        'type': 'join',
        'role': 'mobile',
        'secret': secret,
        'device_name': _deviceName,
      }));
    } catch (e) {
      _setState(ConnectionState.disconnected);
      rethrow;
    }
  }

  Future<String> _getDeviceName() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.name;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.model;
      }
    } catch (e) {
      debugPrint('Error getting device name: $e');
    }
    return 'Mobile Device';
  }

  void _onData(dynamic data) {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      switch (type) {
        case 'joined':
          debugPrint('Joined room: ${message['room_id']}');
          _setState(ConnectionState.connected);
          _startPingTimer();
          break;

        case 'pairing_status':
          final bridgeConnected = message['bridge_connected'] as bool? ?? false;
          onPairingStatusChanged?.call(bridgeConnected);
          break;

        case 'error':
          debugPrint('Server error: ${message['message']}');
          if (_state == ConnectionState.connecting) {
            _setState(ConnectionState.disconnected);
          }
          // Don't auto-reconnect on auth errors
          if (message['message'] == 'Invalid room secret') {
            _connectionConfig = null;
          }
          break;

        default:
          onMessage?.call(message);
      }
    } catch (e) {
      debugPrint('Error parsing message: $e');
    }
  }

  void _onDisconnected() {
    _stopPingTimer();
    _socket = null;

    if (_state == ConnectionState.connected) {
      _setState(ConnectionState.disconnected);
      onPairingStatusChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_connectionConfig == null) return;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_state == ConnectionState.disconnected && _connectionConfig != null) {
        try {
          await connect(_connectionConfig!);
        } catch (e) {
          _scheduleReconnect();
        }
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      send({'action': 'ping'});
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void send(Map<String, dynamic> message) {
    if (_socket != null) {
      _socket!.add(jsonEncode(message));
    }
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _socket?.close();
    _socket = null;
    _connectionConfig = null;
    _setState(ConnectionState.disconnected);
    onPairingStatusChanged?.call(false);
  }
}