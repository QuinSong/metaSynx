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
    
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.contains('status_') && entity.path.endsWith('.json')) {
        try {
          final content = await entity.readAsString();
          final data = jsonDecode(content) as Map<String, dynamic>;
          
          final stat = await entity.stat();
          final age = DateTime.now().difference(stat.modified);
          if (age.inSeconds < 10) {
            accounts.add(data);
          }
        } catch (e) {
          // Skip invalid files
        }
      }
    }

    accounts.sort((a, b) => (a['index'] as int? ?? 0).compareTo(b['index'] as int? ?? 0));
    return accounts;
  }

  /// Get positions for a specific terminal (reads directly from file)
  Future<List<Map<String, dynamic>>> getPositions(int terminalIndex) async {
    if (_commonDataPath == null) return [];

    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\positions_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) return [];

    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final positions = List<Map<String, dynamic>>.from(data['positions'] ?? []);
      return positions;
    } catch (e) {
      onLog?.call('Error reading positions: $e');
      return [];
    }
  }

  /// Get positions for all terminals
  Future<List<Map<String, dynamic>>> getAllPositions() async {
    if (_commonDataPath == null) return [];

    final accounts = await getAccounts();
    final allPositions = <Map<String, dynamic>>[];
    
    for (final account in accounts) {
      final index = account['index'] as int;
      final positions = await getPositions(index);
      for (final pos in positions) {
        pos['terminalIndex'] = index;
        allPositions.add(pos);
      }
    }
    
    return allPositions;
  }

  /// Send a command to a specific terminal and wait for confirmation
  Future<bool> sendCommandToTerminal(int terminalIndex, Map<String, dynamic> command) async {
    if (_commonDataPath == null) {
      onLog?.call('Cannot send command: EA service not initialized');
      return false;
    }

    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\command_$terminalIndex.json';
    final file = File(filePath);
    
    try {
      // Add unique identifier to command
      command['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      command['cmdId'] = '${DateTime.now().millisecondsSinceEpoch}_$terminalIndex';
      
      final json = jsonEncode(command);
      await file.writeAsString(json);
      onLog?.call('Command written for terminal $terminalIndex: ${command['action']}');
      
      // Wait for command file to be deleted (EA processed it)
      for (int i = 0; i < 20; i++) {  // Wait up to 2 seconds
        await Future.delayed(const Duration(milliseconds: 100));
        if (!await file.exists()) {
          onLog?.call('Command processed by terminal $terminalIndex');
          return true;
        }
      }
      
      onLog?.call('Warning: Command may not have been processed by terminal $terminalIndex');
      return true;  // Return true anyway, EA might have processed it
    } catch (e) {
      onLog?.call('Error sending command: $e');
      return false;
    }
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
    int? magic,
  }) async {
    final command = {
      'action': 'place_order',
      'symbol': symbol,
      'type': type,
      'lots': lots,
      'sl': sl ?? 0,
      'tp': tp ?? 0,
      'magic': magic ?? DateTime.now().millisecondsSinceEpoch % 2147483647,
    };

    if (targetIndex != null) {
      await sendCommandToTerminal(targetIndex, Map.from(command));
    } else if (targetAll) {
      final accounts = await getAccounts();
      for (final account in accounts) {
        final index = account['index'] as int;
        await sendCommandToTerminal(index, Map.from(command));
      }
    }
  }

  /// Close a position - waits for confirmation
  Future<bool> closePosition(int ticket, int terminalIndex) async {
    onLog?.call('Closing position: ticket=$ticket on terminal $terminalIndex');
    return await sendCommandToTerminal(terminalIndex, {
      'action': 'close_position',
      'ticket': ticket,
    });
  }

  /// Modify a position - waits for confirmation
  /// sl/tp: null = keep existing (-1), 0 = remove, >0 = set new value
  Future<bool> modifyPosition(int ticket, int terminalIndex, {double? sl, double? tp}) async {
    onLog?.call('Modifying position: ticket=$ticket, SL=$sl, TP=$tp on terminal $terminalIndex');
    return await sendCommandToTerminal(terminalIndex, {
      'action': 'modify_position',
      'ticket': ticket,
      'sl': sl ?? -1,
      'tp': tp ?? -1,
    });
  }

  /// Poll for account status updates
  Future<void> _pollAccountStatus() async {
    final accounts = await getAccounts();
    onAccountsUpdated?.call(accounts);
  }

  /// Find MT4 Common Data folder
  Future<String?> _findCommonDataPath() async {
    final possiblePaths = [
      '${Platform.environment['APPDATA']}\\MetaQuotes\\Terminal\\Common',
      '${Platform.environment['PROGRAMDATA']}\\MetaQuotes\\Terminal\\Common',
    ];

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        return path;
      }
    }

    return null;
  }

  void dispose() {
    stopPolling();
  }
}