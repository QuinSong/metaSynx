import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Service for communicating with MT4 Expert Advisors via file system
class EAService {
  static const String _bridgeFolder = 'MetaSynx';
  static String? _commonDataPath;
  
  Timer? _pollTimer;
  Function(List<Map<String, dynamic>>)? onAccountsUpdated;
  Function(String)? onLog;

  /// Initialize the EA service
  Future<void> initialize() async {
    _commonDataPath = await _findCommonDataPath();
    if (_commonDataPath == null) {
      onLog?.call('Warning: Could not find MT4 Common Data folder');
      return;
    }
    
    final bridgePath = '$_commonDataPath\\Files\\$_bridgeFolder';
    final dir = Directory(bridgePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    onLog?.call('EA Service initialized: $bridgePath');
  }

  /// Start polling for account status updates
  void startPolling({Duration interval = const Duration(seconds: 1)}) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(interval, (_) => _pollAccountStatus());
  }

  /// Stop polling
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Get all connected accounts from EA status files
  Future<List<Map<String, dynamic>>> getAccounts() async {
    if (_commonDataPath == null) return [];

    final bridgePath = '$_commonDataPath\\Files\\$_bridgeFolder';
    final dir = Directory(bridgePath);
    
    if (!await dir.exists()) return [];

    final accounts = <Map<String, dynamic>>[];
    
    // Look for status_*.json files
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.contains('status_') && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          
          // Check if status is recent (within last 5 seconds)
          final lastUpdate = data['lastUpdate'] as String?;
          if (lastUpdate != null) {
            // Add file modification time check as backup
            final stat = await entity.stat();
            final age = DateTime.now().difference(stat.modified);
            if (age.inSeconds < 10) {
              accounts.add(data);
            }
          }
        } catch (e) {
          onLog?.call('Error reading status file: $e');
        }
      }
    }

    // Sort by index
    accounts.sort((a, b) => (a['index'] as int? ?? 0).compareTo(b['index'] as int? ?? 0));
    
    return accounts;
  }

  /// Get positions for a specific terminal
  Future<List<Map<String, dynamic>>> getPositions(int terminalIndex) async {
    if (_commonDataPath == null) {
      onLog?.call('Cannot get positions: EA service not initialized');
      return [];
    }

    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\positions_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) {
      onLog?.call('Positions file not found: positions_$terminalIndex.json');
      return [];
    }

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final positions = List<Map<String, dynamic>>.from(data['positions'] ?? []);
      onLog?.call('Read ${positions.length} positions from terminal $terminalIndex');
      return positions;
    } catch (e) {
      onLog?.call('Error reading positions: $e');
      return [];
    }
  }

  /// Send a command to a specific terminal
  Future<void> sendCommandToTerminal(int terminalIndex, Map<String, dynamic> command) async {
    if (_commonDataPath == null) {
      onLog?.call('Cannot send command: EA service not initialized');
      return;
    }

    // Use per-terminal command file
    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\command_$terminalIndex.json';
    final file = File(filePath);
    
    try {
      command['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      final json = jsonEncode(command);
      await file.writeAsString(json);
      onLog?.call('Command sent to terminal $terminalIndex: ${command['action']}');
    } catch (e) {
      onLog?.call('Error sending command: $e');
    }
  }

  /// Request positions from a terminal
  Future<void> requestPositions(int terminalIndex) async {
    await sendCommandToTerminal(terminalIndex, {
      'action': 'get_positions',
    });
  }

  /// Place an order on specific terminal
  Future<void> placeOrder({
    required String symbol,
    required String type,
    required double lots,
    double? sl,
    double? tp,
    int? targetIndex,
    bool targetAll = false,
  }) async {
    final command = {
      'action': 'place_order',
      'symbol': symbol,
      'type': type,
      'lots': lots,
      'sl': sl ?? 0,
      'tp': tp ?? 0,
    };

    if (targetIndex != null) {
      await sendCommandToTerminal(targetIndex, command);
    } else if (targetAll) {
      // Send to all connected terminals
      final accounts = await getAccounts();
      for (final account in accounts) {
        final index = account['index'] as int;
        await sendCommandToTerminal(index, command);
        // Small delay between commands
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  /// Close a position
  Future<void> closePosition(int ticket, int terminalIndex) async {
    await sendCommandToTerminal(terminalIndex, {
      'action': 'close_position',
      'ticket': ticket,
    });
  }

  /// Modify a position
  Future<void> modifyPosition(int ticket, int terminalIndex, {double? sl, double? tp}) async {
    await sendCommandToTerminal(terminalIndex, {
      'action': 'modify_position',
      'ticket': ticket,
      'sl': sl ?? 0,
      'tp': tp ?? 0,
    });
  }

  /// Poll for account status updates
  Future<void> _pollAccountStatus() async {
    final accounts = await getAccounts();
    onAccountsUpdated?.call(accounts);
  }

  /// Find MT4 Common Data folder
  Future<String?> _findCommonDataPath() async {
    // Common locations for MT4 common data
    final possiblePaths = [
      '${Platform.environment['APPDATA']}\\MetaQuotes\\Terminal\\Common',
      '${Platform.environment['PROGRAMDATA']}\\MetaQuotes\\Terminal\\Common',
      'C:\\Users\\${Platform.environment['USERNAME']}\\AppData\\Roaming\\MetaQuotes\\Terminal\\Common',
    ];

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        return path;
      }
    }

    // Fallback: search for it
    try {
      final appDataPath = Platform.environment['APPDATA'];
      if (appDataPath != null) {
        final metaQuotesPath = '$appDataPath\\MetaQuotes\\Terminal\\Common';
        final dir = Directory(metaQuotesPath);
        if (await dir.exists()) {
          return metaQuotesPath;
        }
      }
    } catch (e) {
      // Ignore
    }

    return null;
  }

  void dispose() {
    stopPolling();
  }
}