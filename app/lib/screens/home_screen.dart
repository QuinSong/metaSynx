import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../services/relay_connection.dart' as relay;
import '../components/connection_indicator.dart';
import '../components/connection_card.dart';
import '../components/quick_actions.dart';
import '../components/scan_button.dart';
import 'qr_scanner_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _setupConnection();
    _tryAutoConnect();
  }

  void _setupConnection() {
    _connection.onStateChanged = (state) {
      setState(() => _connectionState = state);
    };
    _connection.onPairingStatusChanged = (bridgeConnected) {
      setState(() => _bridgeConnected = bridgeConnected);
    };
    _connection.onMessage = _handleMessage;
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

        // Save for auto-reconnect
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
        debugPrint('Received ${accounts?.length ?? 0} accounts');
        // TODO: Navigate to accounts screen or show data
        break;

      case 'positions_list':
        // TODO: Handle positions data
        break;

      case 'pong':
        // Ping response - connection is healthy
        break;
    }
  }

  void _disconnect() async {
    _connection.disconnect();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_connection');
    setState(() {
      _connectionState = relay.ConnectionState.disconnected;
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
              _buildHeader(),

              const SizedBox(height: 48),

              // Connection Card
              ConnectionCard(
                connectionState: _connectionState,
                bridgeConnected: _bridgeConnected,
                roomId: _roomId,
                onDisconnect: _disconnect,
              ),

              const SizedBox(height: 24),

              // Quick Actions (only when fully paired)
              if (_connectionState == relay.ConnectionState.connected &&
                  _bridgeConnected) ...[
                const Text(
                  'QUICK ACTIONS',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 16),
                QuickActions(
                  onAccountsTap: () {
                    _connection.send({'action': 'get_accounts'});
                  },
                  onPositionsTap: () {
                    _connection.send({'action': 'get_positions'});
                  },
                  onNewOrderTap: () {
                    // TODO: Navigate to new order screen
                  },
                  onHistoryTap: () {
                    // TODO: Navigate to history screen
                  },
                ),
              ],

              const Spacer(),

              // Scan Button (when disconnected)
              if (_connectionState == relay.ConnectionState.disconnected)
                ScanButton(onPressed: _openScanner),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'METASYNX',
          style: AppTextStyles.heading,
        ),
        const Spacer(),
        ConnectionIndicator(
          connectionState: _connectionState,
          bridgeConnected: _bridgeConnected,
        ),
      ],
    );
  }
}