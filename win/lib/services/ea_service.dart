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

  /// Read file with retry on access error (file might be locked by EA)
  Future<String?> _readFileSafe(File file) async {
    for (int i = 0; i < 3; i++) {
      try {
        return await file.readAsString();
      } catch (e) {
        if (i < 2) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
      }
    }
    return null;
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
          final content = await _readFileSafe(entity);
          if (content == null) continue;
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

  /// Get positions for a specific terminal
  Future<List<Map<String, dynamic>>> getPositions(int terminalIndex) async {
    if (_commonDataPath == null) return [];

    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\positions_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) return [];

    try {
      final content = await _readFileSafe(file);
      if (content == null) return [];
      final data = jsonDecode(content) as Map<String, dynamic>;
      final positions = List<Map<String, dynamic>>.from(data['positions'] ?? []);
      return positions;
    } catch (e) {
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
      command['timestamp'] = DateTime.now().millisecondsSinceEpoch;
      command['cmdId'] = '${DateTime.now().millisecondsSinceEpoch}_$terminalIndex';
      
      final json = jsonEncode(command);
      await file.writeAsString(json);
      onLog?.call('Command sent: ${command['action']}');
      
      // Wait for command file to be deleted (EA processed it)
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (!await file.exists()) {
          return true;
        }
      }
      
      return true;
    } catch (e) {
      onLog?.call('Error sending command: $e');
      return false;
    }
  }

  /// Place an order
  Future<void> placeOrder({
    required String symbol,
    required String type,
    required double lots,
    double? sl,
    double? tp,
    double? price,
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
      'price': price ?? 0,
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

  /// Close a position
  Future<bool> closePosition(int ticket, int terminalIndex) async {
    onLog?.call('Closing position: ticket=$ticket');
    return await sendCommandToTerminal(terminalIndex, {
      'action': 'close_position',
      'ticket': ticket,
    });
  }

  /// Modify a position
  Future<bool> modifyPosition(int ticket, int terminalIndex, {double? sl, double? tp}) async {
    onLog?.call('Modifying position: ticket=$ticket');
    return await sendCommandToTerminal(terminalIndex, {
      'action': 'modify_position',
      'ticket': ticket,
      'sl': sl ?? -1,
      'tp': tp ?? -1,
    });
  }

  /// Get chart data - sends command to EA and reads response
  /// This is fire-and-forget to avoid blocking other commands
  Future<Map<String, dynamic>?> getChartData(String symbol, String timeframe, int terminalIndex) async {
    if (_commonDataPath == null) return null;
    
    // Send get_chart_data command to EA - fire and forget, don't wait
    _sendChartCommandAsync(terminalIndex, symbol, timeframe);
    
    // Read the existing chart file (may be from previous request)
    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\chart_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) return null;
    
    try {
      final content = await _readFileSafe(file);
      if (content == null || content.isEmpty) return null;
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
  
  /// Send chart command without waiting - fire and forget
  void _sendChartCommandAsync(int terminalIndex, String symbol, String timeframe) async {
    if (_commonDataPath == null) return;
    
    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\command_$terminalIndex.json';
    final file = File(filePath);
    
    // Only write if no command is pending (file doesn't exist)
    // This prevents chart requests from overwriting trading commands
    if (await file.exists()) return;
    
    try {
      final command = {
        'action': 'get_chart_data',
        'symbol': symbol,
        'timeframe': timeframe,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'cmdId': '${DateTime.now().millisecondsSinceEpoch}_$terminalIndex',
      };
      await file.writeAsString(jsonEncode(command));
    } catch (e) {
      // Ignore errors - chart data is not critical
    }
  }

  /// Get closed positions history
  Future<List<Map<String, dynamic>>> getHistory(String period, int terminalIndex) async {
    if (_commonDataPath == null) return [];
    
    // Send get_history command to EA
    await sendCommandToTerminal(terminalIndex, {
      'action': 'get_history',
      'period': period,
    });
    
    // Wait a moment for EA to write the file
    await Future.delayed(const Duration(milliseconds: 300));
    
    // Read the history file
    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\history_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) return [];
    
    try {
      final content = await _readFileSafe(file);
      if (content == null || content.isEmpty) return [];
      
      final data = jsonDecode(content) as Map<String, dynamic>;
      final history = data['history'] as List<dynamic>? ?? [];
      
      return history.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        map['terminalIndex'] = terminalIndex;
        map['account'] = data['account'];
        return map;
      }).toList();
    } catch (e) {
      onLog?.call('Error reading history: $e');
      return [];
    }
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