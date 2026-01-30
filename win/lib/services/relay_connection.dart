import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class RelayConnection {
  final String server;
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
    required this.server,
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
      final wsUrl = 'wss://$server/ws/relay/$roomId';

      _socket = await WebSocket.connect(wsUrl);

      // Send join message with secret
      _socket!.add(jsonEncode({
        'type': 'join',
        'role': 'bridge',
        'secret': roomSecret,
        'device_name': 'MetaSynx Bridge',
      }));

      _socket!.listen(
        _onData,
        onDone: _onDisconnected,
        onError: (error) {
          onLog('Connection error: $error');
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