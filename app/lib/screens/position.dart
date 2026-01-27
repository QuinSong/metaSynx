import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../utils/formatters.dart';
import 'chart.dart';

class PositionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> position;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final List<Map<String, dynamic>> accounts;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;
  // For ChartScreen
  final Map<String, String> symbolSuffixes;
  final Map<String, double> lotRatios;
  final Set<String> preferredPairs;
  final void Function({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) onPlaceOrder;
  // Chart data (optional - may not be available from position screen)
  final Stream<Map<String, dynamic>>? chartDataStream;
  final void Function(String symbol, String timeframe, int terminalIndex)? onRequestChartData;

  const PositionDetailScreen({
    super.key,
    required this.position,
    required this.positionsNotifier,
    required this.accounts,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.accountNames,
    this.mainAccountNum,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onConfirmBeforeCloseChanged,
    required this.symbolSuffixes,
    required this.lotRatios,
    required this.preferredPairs,
    required this.onPlaceOrder,
    this.chartDataStream,
    this.onRequestChartData,
  });

  @override
  State<PositionDetailScreen> createState() => _PositionDetailScreenState();
}

class _PositionDetailScreenState extends State<PositionDetailScreen> {
  Set<int> _selectedTerminalIndices = {};
  Set<int> _knownTerminalIndices = {};
  bool _initialized = false;
  
  final _slController = TextEditingController();
  final _tpController = TextEditingController();
  bool _isProcessing = false;
  int _digits = 5; // Default to 5 decimal places
  
  // Track original SL/TP to detect modifications
  String _originalSL = '';
  String _originalTP = '';
  bool _hasModifications = false;

  @override
  void initState() {
    super.initState();
    
    // Detect digits from open price
    _digits = _detectDigits(widget.position['openPrice']);
    
    // Pre-fill SL/TP from current position using detected digits
    final sl = (widget.position['sl'] as num?)?.toDouble() ?? 0;
    final tp = (widget.position['tp'] as num?)?.toDouble() ?? 0;
    if (sl > 0) {
      _slController.text = sl.toStringAsFixed(_digits);
      _originalSL = _slController.text;
    }
    if (tp > 0) {
      _tpController.text = tp.toStringAsFixed(_digits);
      _originalTP = _tpController.text;
    }
    
    // Listen to SL/TP changes to detect modifications
    _slController.addListener(_checkForModifications);
    _tpController.addListener(_checkForModifications);
    
    // Initialize with the original position's terminal
    final originalTerminal = widget.position['terminalIndex'] as int;
    _selectedTerminalIndices.add(originalTerminal);
    _knownTerminalIndices.add(originalTerminal);
    
    // Listen to position updates (data comes from home screen)
    widget.positionsNotifier.addListener(_onPositionsUpdated);
    
    // Initialize with current data
    _onPositionsUpdated();
  }
  
  void _checkForModifications() {
    final slChanged = _slController.text != _originalSL;
    final tpChanged = _tpController.text != _originalTP;
    final hasModifications = slChanged || tpChanged;
    
    if (hasModifications != _hasModifications) {
      setState(() {
        _hasModifications = hasModifications;
      });
    }
  }

  /// Detect number of decimal places from a price value
  int _detectDigits(dynamic price) {
    if (price == null) return 5;
    
    final priceStr = price.toString();
    final dotIndex = priceStr.indexOf('.');
    if (dotIndex < 0) return 0;
    
    // Count digits after decimal, ignoring trailing zeros
    final decimals = priceStr.substring(dotIndex + 1);
    
    // For forex pairs, typically 5 or 3 digits
    // For metals/indices, typically 2-3 digits
    // For crypto, can vary widely
    
    // Use the actual decimal places from the price
    int digits = decimals.length;
    
    // Common patterns:
    // EURUSD: 1.12345 = 5 digits
    // USDJPY: 150.123 = 3 digits  
    // XAUUSD: 2650.12 = 2 digits
    // BTCUSD: 45000.00 = 2 digits
    
    // Cap at reasonable max
    return digits.clamp(0, 8);
  }

  String _formatPrice(double? price) {
    if (price == null) return '-';
    return price.toStringAsFixed(_digits);
  }

  void _onPositionsUpdated() {
    final matching = _findMatchingPositions();
    final currentTerminals = matching.map((p) => p['terminalIndex'] as int).toSet();
    
    if (!_initialized && matching.isNotEmpty) {
      // First time we get matching positions - select all
      setState(() {
        _selectedTerminalIndices = Set.from(currentTerminals);
        _knownTerminalIndices = Set.from(currentTerminals);
        _initialized = true;
      });
    } else if (_initialized) {
      // Add any new terminals that appear (but don't remove deselected ones)
      final newTerminals = currentTerminals.difference(_knownTerminalIndices);
      if (newTerminals.isNotEmpty) {
        setState(() {
          _selectedTerminalIndices.addAll(newTerminals);
          _knownTerminalIndices.addAll(newTerminals);
        });
      }
    }
  }

  @override
  @override
  void dispose() {
    widget.positionsNotifier.removeListener(_onPositionsUpdated);
    _slController.removeListener(_checkForModifications);
    _tpController.removeListener(_checkForModifications);
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _findMatchingPositions() {
    final symbol = widget.position['symbol'] as String;
    final type = widget.position['type'] as String;
    final magic = widget.position['magic'] as int?;

    // Only match positions with the same non-zero magic number
    // This ensures only positions opened together from the app are linked
    if (magic == null || magic == 0) {
      // No magic number - this position stands alone
      return widget.positionsNotifier.value.where((p) {
        return p['terminalIndex'] == widget.position['terminalIndex'] &&
               p['ticket'] == widget.position['ticket'];
      }).toList();
    }

    // Find positions with same magic number across ALL terminals
    return widget.positionsNotifier.value.where((p) {
      if (p['symbol'] != symbol) return false;
      if (p['type'] != type) return false;
      
      final posMagic = p['magic'] as int?;
      return posMagic == magic;
    }).toList();
  }

  Map<String, dynamic>? _getCurrentPosition() {
    // Get updated position data for the original position
    final terminalIndex = widget.position['terminalIndex'] as int;
    final ticket = widget.position['ticket'] as int;
    
    try {
      return widget.positionsNotifier.value.firstWhere(
        (p) => p['terminalIndex'] == terminalIndex && p['ticket'] == ticket,
      );
    } catch (e) {
      return widget.position; // Fallback to original
    }
  }

  String _getAccountDisplay(int terminalIndex) {
    try {
      final account = widget.accounts.firstWhere(
        (a) => a['index'] == terminalIndex,
      );
      final accountNum = account['account'] as String? ?? '';
      final customName = widget.accountNames[accountNum];
      if (customName != null && customName.isNotEmpty) {
        return customName;
      }
      return accountNum.isNotEmpty ? accountNum : 'Account $terminalIndex';
    } catch (e) {
      return 'Account $terminalIndex';
    }
  }

  void _closePositions() async {
    if (_selectedTerminalIndices.isEmpty) {
      _showError('Please select at least one account');
      return;
    }

    // Show confirmation dialog if enabled
    if (widget.confirmBeforeClose) {
      final confirmed = await _showCloseConfirmationDialog();
      if (!confirmed) return;
    }

    setState(() => _isProcessing = true);

    // Get all positions to close
    final positionsToClose = <Map<String, int>>[];
    
    // First, try to find matching positions
    final matching = _findMatchingPositions();
    for (final terminalIndex in _selectedTerminalIndices) {
      final pos = matching.where((p) => p['terminalIndex'] == terminalIndex).firstOrNull;
      if (pos != null) {
        positionsToClose.add({
          'ticket': pos['ticket'] as int,
          'terminalIndex': terminalIndex,
        });
      }
    }
    
    // If no matches found, use the original position
    if (positionsToClose.isEmpty) {
      final origTerminal = widget.position['terminalIndex'] as int;
      if (_selectedTerminalIndices.contains(origTerminal)) {
        positionsToClose.add({
          'ticket': widget.position['ticket'] as int,
          'terminalIndex': origTerminal,
        });
      }
    }

    if (positionsToClose.isEmpty) {
      _showError('No positions to close');
      setState(() => _isProcessing = false);
      return;
    }

    // Send all close commands
    for (final item in positionsToClose) {
      widget.onClosePosition(item['ticket']!, item['terminalIndex']!);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Closing ${positionsToClose.length} position(s)'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<bool> _showCloseConfirmationDialog() async {
    bool dontShowAgain = false;
    final type = (widget.position['type']?.toString() ?? '').toUpperCase();
    final symbol = widget.position['symbol'] as String? ?? '';
    final count = _selectedTerminalIndices.length;
    final positionLabel = count == 1 ? 'position' : 'positions';
    
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.primary.withOpacity(0.3)),
          ),
          title: const Text(
            'Confirm Close',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are about to close $count $type $positionLabel on $symbol. This action cannot be undone.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  setDialogState(() {
                    dontShowAgain = !dontShowAgain;
                  });
                },
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: dontShowAgain,
                        onChanged: (value) {
                          setDialogState(() {
                            dontShowAgain = value ?? false;
                          });
                        },
                        activeColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Don't ask me again",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (dontShowAgain) {
                  widget.onConfirmBeforeCloseChanged(false);
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Close Position',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    
    return result ?? false;
  }

  void _modifyPositions() async {
    if (_selectedTerminalIndices.isEmpty) {
      _showError('Please select at least one account');
      return;
    }

    final slText = _slController.text.trim();
    final tpText = _tpController.text.trim();
    
    // Debug: print exactly what was entered
    debugPrint('SL text entered: "$slText"');
    debugPrint('TP text entered: "$tpText"');
    
    final sl = slText.isNotEmpty ? double.tryParse(slText) : null;
    final tp = tpText.isNotEmpty ? double.tryParse(tpText) : null;
    
    // Debug: print parsed values
    debugPrint('SL parsed: $sl');
    debugPrint('TP parsed: $tp');

    if (sl == null && tp == null) {
      _showError('Please enter SL or TP value');
      return;
    }

    // Get current price from live position data (not the static widget.position)
    final ticket = widget.position['ticket'] as int?;
    final terminalIndex = widget.position['terminalIndex'] as int?;
    final livePosition = widget.positionsNotifier.value.firstWhere(
      (p) => p['ticket'] == ticket && p['terminalIndex'] == terminalIndex,
      orElse: () => widget.position,
    );
    
    final currentPrice = (livePosition['currentPrice'] as num?)?.toDouble() ?? 0;
    final type = (livePosition['type'] as String? ?? '').toLowerCase();
    final isBuy = type == 'buy';

    // Validate SL/TP based on position type and current price
    if (currentPrice > 0) {
      if (isBuy) {
        // BUY: SL must be below current price, TP must be above current price
        if (sl != null && sl > 0 && sl >= currentPrice) {
          _showError('Stop Loss must be below current price for BUY positions');
          return;
        }
        if (tp != null && tp > 0 && tp <= currentPrice) {
          _showError('Take Profit must be above current price for BUY positions');
          return;
        }
      } else {
        // SELL: SL must be above current price, TP must be below current price
        if (sl != null && sl > 0 && sl <= currentPrice) {
          _showError('Stop Loss must be above current price for SELL positions');
          return;
        }
        if (tp != null && tp > 0 && tp >= currentPrice) {
          _showError('Take Profit must be below current price for SELL positions');
          return;
        }
      }
    }

    setState(() => _isProcessing = true);

    // Get all positions to modify
    final positionsToModify = <Map<String, int>>[];
    
    // First, try to find matching positions
    final matching = _findMatchingPositions();
    for (final terminalIndex in _selectedTerminalIndices) {
      final pos = matching.where((p) => p['terminalIndex'] == terminalIndex).firstOrNull;
      if (pos != null) {
        positionsToModify.add({
          'ticket': pos['ticket'] as int,
          'terminalIndex': terminalIndex,
        });
      }
    }
    
    // If no matches found, use the original position
    if (positionsToModify.isEmpty) {
      final origTerminal = widget.position['terminalIndex'] as int;
      if (_selectedTerminalIndices.contains(origTerminal)) {
        positionsToModify.add({
          'ticket': widget.position['ticket'] as int,
          'terminalIndex': origTerminal,
        });
      }
    }

    if (positionsToModify.isEmpty) {
      _showError('No positions to modify');
      setState(() => _isProcessing = false);
      return;
    }

    // Send all modify commands
    for (final item in positionsToModify) {
      widget.onModifyPosition(item['ticket']!, item['terminalIndex']!, sl, tp);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Modifying ${positionsToModify.length} position(s)'),
          backgroundColor: AppColors.primary,
        ),
      );
      Navigator.pop(context);
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

  String _stripSuffix(String symbol) {
    // Common base symbols - if symbol starts with one of these, strip anything after
    final baseSymbols = [
      'XAUUSD', 'XAGUSD', 'EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'USDCAD',
      'AUDUSD', 'NZDUSD', 'EURGBP', 'EURJPY', 'GBPJPY', 'BTCUSD', 'ETHUSD',
      'US30', 'US500', 'NAS100', 'UK100', 'GER40', 'FRA40', 'JPN225',
    ];
    
    for (final base in baseSymbols) {
      if (symbol.toUpperCase().startsWith(base)) {
        return base;
      }
    }
    
    // If no known base found, try to strip common suffixes
    final suffixPatterns = ['.', '-', '_', '#'];
    for (final pattern in suffixPatterns) {
      final index = symbol.indexOf(pattern);
      if (index > 0) {
        return symbol.substring(0, index);
      }
    }
    
    return symbol;
  }

  void _openChart() {
    final symbol = widget.position['symbol'] as String? ?? '';
    final cleanSymbol = _stripSuffix(symbol);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChartScreen(
          positions: widget.positionsNotifier.value,
          positionsNotifier: widget.positionsNotifier,
          accounts: widget.accounts,
          initialSymbol: cleanSymbol,
          onClosePosition: widget.onClosePosition,
          onModifyPosition: widget.onModifyPosition,
          accountNames: widget.accountNames,
          mainAccountNum: widget.mainAccountNum,
          includeCommissionSwap: widget.includeCommissionSwap,
          showPLPercent: widget.showPLPercent,
          confirmBeforeClose: widget.confirmBeforeClose,
          onConfirmBeforeCloseChanged: widget.onConfirmBeforeCloseChanged,
          chartDataStream: widget.chartDataStream,
          onRequestChartData: widget.onRequestChartData,
          symbolSuffixes: widget.symbolSuffixes,
          lotRatios: widget.lotRatios,
          preferredPairs: widget.preferredPairs,
          onPlaceOrder: widget.onPlaceOrder,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Get account display name for appbar
    final terminalIndex = widget.position['terminalIndex'] as int? ?? -1;
    final accountDisplayName = _getAccountDisplay(terminalIndex);
    
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          accountDisplayName,
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              icon: const Icon(Icons.candlestick_chart, color: AppColors.primary),
              onPressed: () => _openChart(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false, // AppBar handles top
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: widget.positionsNotifier,
          builder: (context, allPositions, _) {
            final currentPos = _getCurrentPosition();
            final matchingPositions = _findMatchingPositions();
            
            if (currentPos == null) {
              return const Center(
                child: Text('Position closed', style: AppTextStyles.body),
              );
            }

            final symbol = currentPos['symbol'] as String? ?? '';
            final type = currentPos['type'] as String? ?? '';
            final lots = (currentPos['lots'] as num?)?.toDouble() ?? 0;
            final openPrice = (currentPos['openPrice'] as num?)?.toDouble() ?? 0;
            final currentPrice = (currentPos['currentPrice'] as num?)?.toDouble() ?? 0;
            final rawProfit = (currentPos['profit'] as num?)?.toDouble() ?? 0;
            final swap = (currentPos['swap'] as num?)?.toDouble() ?? 0;
            final commission = (currentPos['commission'] as num?)?.toDouble() ?? 0;
            final profit = widget.includeCommissionSwap 
                ? rawProfit + swap + commission 
                : rawProfit;
            final isBuy = type.toLowerCase() == 'buy';
            
            // Get account balance for P/L %
            final posTerminalIndex = currentPos['terminalIndex'] as int? ?? -1;
            final account = widget.accounts.firstWhere(
              (a) => a['index'] == posTerminalIndex,
              orElse: () => <String, dynamic>{},
            );
            final balance = (account['balance'] as num?)?.toDouble() ?? 0;
          final plPercent = balance > 0 ? (profit / balance) * 100 : 0.0;

          // Calculate total P/L across all matching positions
          double totalProfit = 0;
          double totalBalance = 0;
          final seenTerminals = <int>{};
          
          for (final pos in matchingPositions) {
            final posRawProfit = (pos['profit'] as num?)?.toDouble() ?? 0;
            final posSwap = (pos['swap'] as num?)?.toDouble() ?? 0;
            final posCommission = (pos['commission'] as num?)?.toDouble() ?? 0;
            if (widget.includeCommissionSwap) {
              totalProfit += posRawProfit + posSwap + posCommission;
            } else {
              totalProfit += posRawProfit;
            }
            
            // Sum up balances (only once per terminal)
            final posTerminal = pos['terminalIndex'] as int? ?? -1;
            if (!seenTerminals.contains(posTerminal)) {
              seenTerminals.add(posTerminal);
              final posAccount = widget.accounts.firstWhere(
                (a) => a['index'] == posTerminal,
                orElse: () => <String, dynamic>{},
              );
              totalBalance += (posAccount['balance'] as num?)?.toDouble() ?? 0;
            }
          }
          
          final totalPlPercent = totalBalance > 0 ? (totalProfit / totalBalance) * 100 : 0.0;

          // Use known terminals for display to avoid flickering, sorted with main account first
          final displayTerminalsSet = _knownTerminalIndices.isNotEmpty 
              ? _knownTerminalIndices 
              : matchingPositions.map((p) => p['terminalIndex'] as int).toSet();
          final displayTerminals = displayTerminalsSet.toList();
          // Sort with main account first
          displayTerminals.sort((a, b) {
            final aAccount = widget.accounts.firstWhere(
              (acc) => acc['index'] == a,
              orElse: () => <String, dynamic>{},
            );
            final bAccount = widget.accounts.firstWhere(
              (acc) => acc['index'] == b,
              orElse: () => <String, dynamic>{},
            );
            final aIsMain = aAccount['account'] == widget.mainAccountNum;
            final bIsMain = bAccount['account'] == widget.mainAccountNum;
            if (aIsMain && !bIsMain) return -1;
            if (!aIsMain && bIsMain) return 1;
            return a.compareTo(b);
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Position summary card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primaryWithOpacity(0.15),
                        AppColors.primaryWithOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isBuy 
                          ? AppColors.primary.withOpacity(0.3) 
                          : AppColors.error.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            symbol,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isBuy ? AppColors.primary : AppColors.error,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              type.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${lots.toStringAsFixed(2)} lots',
                            style: AppTextStyles.body,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Open Price', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  _formatPrice(openPrice),
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text('Current Price', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  _formatPrice(currentPrice),
                                  style: TextStyle(
                                    color: isBuy 
                                        ? (currentPrice >= openPrice ? AppColors.primary : AppColors.error)
                                        : (currentPrice <= openPrice ? AppColors.primary : AppColors.error),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      widget.includeCommissionSwap ? 'Net P/L' : 'P/L',
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                    ),
                                    if (widget.showPLPercent && balance > 0) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '${plPercent.toStringAsFixed(2)}%',
                                        style: TextStyle(
                                          color: profit == 0 
                                              ? Colors.white 
                                              : (profit > 0 ? AppColors.primary : AppColors.error),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  Formatters.formatCurrencyWithSign(profit),
                                  style: TextStyle(
                                    color: profit >= 0 ? AppColors.primary : AppColors.error,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      // Always show commission/swap details
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (widget.includeCommissionSwap)
                            Column(
                              children: [
                                const Text('Raw P/L', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                Text(
                                  Formatters.formatCurrencyWithSign(rawProfit),
                                  style: TextStyle(
                                    color: rawProfit == 0 ? Colors.white : (rawProfit > 0 ? AppColors.primary : AppColors.error),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          Column(
                            children: [
                              const Text('Swap', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              Text(
                                Formatters.formatCurrency(swap),
                                style: TextStyle(
                                  color: swap == 0 ? Colors.white : (swap > 0 ? AppColors.primary : AppColors.error),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Commission', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              Text(
                                Formatters.formatCurrency(commission),
                                style: TextStyle(
                                  color: commission == 0 ? Colors.white : (commission > 0 ? AppColors.primary : AppColors.error),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      // Total P/L if multiple positions
                      if (displayTerminals.length > 1) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          decoration: BoxDecoration(
                            color: totalProfit >= 0
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                widget.includeCommissionSwap 
                                    ? 'Total Net P/L (${displayTerminals.length} positions)'
                                    : 'Total P/L (${displayTerminals.length} positions)',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    Formatters.formatCurrencyWithSign(totalProfit),
                                    style: TextStyle(
                                      color: totalProfit >= 0 ? AppColors.primary : AppColors.error,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (widget.showPLPercent) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${totalPlPercent >= 0 ? '+' : ''}${totalPlPercent.toStringAsFixed(2)}%',
                                      style: TextStyle(
                                        color: totalProfit >= 0 ? AppColors.primary : AppColors.error,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Accounts selection
                Text(
                  'ACCOUNTS (${_selectedTerminalIndices.length}/${displayTerminals.length})',
                  style: AppTextStyles.label,
                ),
                const SizedBox(height: 12),
                
                if (displayTerminals.length <= 1)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Position only exists on ${_getAccountDisplay(widget.position['terminalIndex'] as int)}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: displayTerminals.map((terminalIndex) {
                      final accountNum = _getAccountDisplay(terminalIndex);
                      final pos = matchingPositions.where((p) => p['terminalIndex'] == terminalIndex).firstOrNull;
                      final posProfit = (pos?['profit'] as num?)?.toDouble() ?? 0;
                      final isSelected = _selectedTerminalIndices.contains(terminalIndex);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedTerminalIndices.remove(terminalIndex);
                            } else {
                              _selectedTerminalIndices.add(terminalIndex);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? AppColors.primaryWithOpacity(0.2) 
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    accountNum,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : AppColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    Formatters.formatCurrencyWithSign(posProfit),
                                    style: TextStyle(
                                      color: posProfit >= 0 ? AppColors.primary : AppColors.error,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                const SizedBox(height: 32),

                // Modify section
                const Text('MODIFY POSITION', style: AppTextStyles.label),
                const SizedBox(height: 12),
                
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Stop Loss', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _slController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _formatPrice(0),
                              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Take Profit', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _tpController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _formatPrice(0),
                              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: _isProcessing ? null : _modifyPositions,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'MODIFY ${_selectedTerminalIndices.length} ${_getPositionTypeLabel()}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Close button - disabled if SL/TP has been modified
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_isProcessing || _hasModifications) ? null : _closePositions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasModifications ? AppColors.error.withOpacity(0.3) : AppColors.error,
                      disabledBackgroundColor: AppColors.error.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'CLOSE ${_selectedTerminalIndices.length} ${_getPositionTypeLabel()}',
                            style: TextStyle(
                              color: _hasModifications ? Colors.white.withOpacity(0.5) : Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  String _getPositionTypeLabel() {
    final type = (widget.position['type']?.toString() ?? '').toLowerCase();
    final count = _selectedTerminalIndices.length;
    if (type == 'buy') {
      return count == 1 ? 'BUY' : 'BUYS';
    } else {
      return count == 1 ? 'SELL' : 'SELLS';
    }
  }
}