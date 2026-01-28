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
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 60; // Max 60 seconds between attempts
  static const int _baseReconnectDelay = 2; // Start with 2 seconds

  ConnectionState _state = ConnectionState.disconnected;
  Function(ConnectionState)? onStateChanged;
  Function(bool)? onPairingStatusChanged;
  Function(Map<String, dynamic>)? onMessage;

  ConnectionState get state => _state;
  bool get isConnected => _state == ConnectionState.connected;
  Map<String, dynamic>? get connectionConfig => _connectionConfig;

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

    _deviceName ??= await _getDeviceName();

    try {
      final wsUrl = 'wss://$server/ws/relay/$roomId';
      debugPrint('Connecting to $wsUrl (attempt ${_reconnectAttempts + 1})');

      _socket = await WebSocket.connect(wsUrl)
          .timeout(const Duration(seconds: 15));

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
      debugPrint('Connection failed: $e');
      _setState(ConnectionState.disconnected);
      _scheduleReconnect();
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
          _reconnectAttempts = 0; // Reset on successful connection
          _startPingTimer();
          break;

        case 'pairing_status':
          final bridgeConnected = message['bridge_connected'] as bool? ?? false;
          onPairingStatusChanged?.call(bridgeConnected);
          break;

        case 'error':
          debugPrint('Server error: ${message['message']}');
          final errorMsg = message['message'] as String?;
          
          // Only clear config on permanent errors
          if (errorMsg == 'Invalid room secret') {
            debugPrint('Invalid secret - clearing config');
            _connectionConfig = null;
            _setState(ConnectionState.disconnected);
          } else if (errorMsg == 'Room not found or expired') {
            // Room expired - keep config but stop reconnecting
            // User will need to re-scan QR code
            debugPrint('Room expired - clearing config');
            _connectionConfig = null;
            _setState(ConnectionState.disconnected);
          } else {
            // Temporary error - try reconnecting
            _setState(ConnectionState.disconnected);
            _scheduleReconnect();
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

    final wasConnected = _state == ConnectionState.connected;
    _setState(ConnectionState.disconnected);
    
    if (wasConnected) {
      onPairingStatusChanged?.call(false);
    }
    
    // Always try to reconnect if we have config
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_connectionConfig == null) {
      debugPrint('No connection config - not reconnecting');
      return;
    }

    _reconnectTimer?.cancel();
    
    // Exponential backoff: 2, 4, 8, 16, 32, 60, 60, 60...
    final delay = (_baseReconnectDelay * (1 << _reconnectAttempts.clamp(0, 5)))
        .clamp(0, _maxReconnectDelay);
    _reconnectAttempts++;
    
    debugPrint('Scheduling reconnect in $delay seconds (attempt $_reconnectAttempts)');
    
    _reconnectTimer = Timer(Duration(seconds: delay), () async {
      if (_state == ConnectionState.disconnected && _connectionConfig != null) {
        await connect(_connectionConfig!);
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_socket != null) {
        send({'action': 'ping'});
      }
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

  /// Force immediate reconnection (call when app comes to foreground)
  Future<void> reconnectNow() async {
    if (_connectionConfig == null) return;
    
    // Cancel any scheduled reconnect
    _reconnectTimer?.cancel();
    
    // If already connected, just return
    if (_state == ConnectionState.connected && _socket != null) {
      debugPrint('Already connected');
      return;
    }
    
    // Reset attempts for immediate connection
    _reconnectAttempts = 0;
    
    debugPrint('Forcing immediate reconnect');
    await connect(_connectionConfig!);
  }

  /// Restore connection from saved config (call on app startup)
  Future<void> restoreConnection(Map<String, dynamic> config) async {
    _connectionConfig = config;
    _reconnectAttempts = 0;
    await connect(config);
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _stopPingTimer();
    _socket?.close();
    _socket = null;
    _connectionConfig = null;
    _reconnectAttempts = 0;
    _setState(ConnectionState.disconnected);
    onPairingStatusChanged?.call(false);
  }
}
