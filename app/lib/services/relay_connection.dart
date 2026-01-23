import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';

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
