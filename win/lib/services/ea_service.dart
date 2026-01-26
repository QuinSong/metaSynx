import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Service for communicating with MT4 Expert Advisors via file system
class EAService {
  static const String _bridgeFolder = 'MetaSynx';
  static String? _commonDataPath;
  
  Timer? _pollTimer;
  final Map<int, Timer> _chartStreamTimers = {};
  final Map<int, DateTime> _lastChartFileModified = {};
  
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
  Future<Map<String, dynamic>?> getChartData(String symbol, String timeframe, int terminalIndex) async {
    if (_commonDataPath == null) return null;
    
    // Send get_chart_data command to EA
    await sendCommandToTerminal(terminalIndex, {
      'action': 'get_chart_data',
      'symbol': symbol,
      'timeframe': timeframe,
    });
    
    // Read the chart file
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

  /// Subscribe to chart updates - tells EA to start streaming data
  Future<void> subscribeChart(String symbol, String timeframe, int terminalIndex) async {
    await sendCommandToTerminal(terminalIndex, {
      'action': 'subscribe_chart',
      'symbol': symbol,
      'timeframe': timeframe,
    });
  }

  /// Unsubscribe from chart updates - tells EA to stop streaming
  Future<void> unsubscribeChart(int terminalIndex) async {
    await sendCommandToTerminal(terminalIndex, {
      'action': 'unsubscribe_chart',
    });
  }

  /// Start streaming chart data to callback (polls chart file for changes)
  void startChartStream(int terminalIndex, void Function(Map<String, dynamic>) onData) {
    stopChartStream(terminalIndex);
    
    _chartStreamTimers[terminalIndex] = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _checkChartUpdate(terminalIndex, onData),
    );
  }

  /// Stop streaming chart data
  void stopChartStream(int terminalIndex) {
    _chartStreamTimers[terminalIndex]?.cancel();
    _chartStreamTimers.remove(terminalIndex);
    _lastChartFileModified.remove(terminalIndex);
  }

  /// Check for chart file updates and send to callback
  Future<void> _checkChartUpdate(int terminalIndex, void Function(Map<String, dynamic>) onData) async {
    if (_commonDataPath == null) return;
    
    final filePath = '$_commonDataPath\\Files\\$_bridgeFolder\\chart_$terminalIndex.json';
    final file = File(filePath);
    
    if (!await file.exists()) return;
    
    try {
      final modified = await file.lastModified();
      final lastModified = _lastChartFileModified[terminalIndex];
      
      // Only read if file was modified since last check
      if (lastModified == null || modified.isAfter(lastModified)) {
        _lastChartFileModified[terminalIndex] = modified;
        
        final content = await _readFileSafe(file);
        if (content != null && content.isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          onData(data);
        }
      }
    } catch (e) {
      // Ignore errors - file might be locked
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
    // Stop all chart streams
    for (final timer in _chartStreamTimers.values) {
      timer.cancel();
    }
    _chartStreamTimers.clear();
    _lastChartFileModified.clear();
  }
}