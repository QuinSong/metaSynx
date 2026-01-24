import 'package:flutter/material.dart';
import 'dart:async';
import '../core/theme.dart';

class PositionDetailScreen extends StatefulWidget {
  final Map<String, dynamic> position;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final List<Map<String, dynamic>> accounts;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final VoidCallback onRefreshAllPositions;

  const PositionDetailScreen({
    super.key,
    required this.position,
    required this.positionsNotifier,
    required this.accounts,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.onRefreshAllPositions,
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
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    
    // Pre-fill SL/TP from current position
    final sl = (widget.position['sl'] as num?)?.toDouble() ?? 0;
    final tp = (widget.position['tp'] as num?)?.toDouble() ?? 0;
    if (sl > 0) _slController.text = sl.toStringAsFixed(5);
    if (tp > 0) _tpController.text = tp.toStringAsFixed(5);
    
    // Initialize with the original position's terminal
    final originalTerminal = widget.position['terminalIndex'] as int;
    _selectedTerminalIndices.add(originalTerminal);
    _knownTerminalIndices.add(originalTerminal);
    
    // Listen to position updates
    widget.positionsNotifier.addListener(_onPositionsUpdated);
    
    // Start refresh timer
    widget.onRefreshAllPositions();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      widget.onRefreshAllPositions();
    });
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
  void dispose() {
    _refreshTimer?.cancel();
    widget.positionsNotifier.removeListener(_onPositionsUpdated);
    _slController.dispose();
    _tpController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _findMatchingPositions() {
    final symbol = widget.position['symbol'] as String;
    final type = widget.position['type'] as String;
    final magic = widget.position['magic'] as int?;
    final lots = widget.position['lots'];
    final openTime = widget.position['openTime'] as String?;

    // Find positions with same symbol and type across ALL terminals
    return widget.positionsNotifier.value.where((p) {
      if (p['symbol'] != symbol) return false;
      if (p['type'] != type) return false;
      
      // If magic numbers match and are non-zero, it's definitely the same order batch
      final posMagic = p['magic'] as int?;
      if (magic != null && magic != 0 && posMagic == magic) return true;
      
      // Match by lots and approximate open time
      if (p['lots'] == lots) {
        // If open times are close (within a few seconds), consider it a match
        final posOpenTime = p['openTime'] as String?;
        if (openTime != null && posOpenTime != null && openTime.length >= 16 && posOpenTime.length >= 16) {
          // Simple string comparison - orders placed together will have very similar times
          if (openTime.substring(0, 16) == posOpenTime.substring(0, 16)) return true;
        }
        return true; // Same symbol, type, lots - likely same batch
      }
      
      return false;
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
      return account['account'] as String? ?? 'Account $terminalIndex';
    } catch (e) {
      return 'Account $terminalIndex';
    }
  }

  void _closePositions() {
    if (_selectedTerminalIndices.isEmpty) {
      _showError('Please select at least one account');
      return;
    }

    setState(() => _isProcessing = true);

    final matching = _findMatchingPositions();
    int closedCount = 0;
    
    for (final terminalIndex in _selectedTerminalIndices) {
      final pos = matching.where((p) => p['terminalIndex'] == terminalIndex).firstOrNull;
      if (pos != null) {
        final ticket = pos['ticket'] as int;
        widget.onClosePosition(ticket, terminalIndex);
        closedCount++;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Closing $closedCount position(s)'),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context);
  }

  void _modifyPositions() {
    if (_selectedTerminalIndices.isEmpty) {
      _showError('Please select at least one account');
      return;
    }

    final slText = _slController.text.trim();
    final tpText = _tpController.text.trim();
    final sl = slText.isNotEmpty ? double.tryParse(slText) : null;
    final tp = tpText.isNotEmpty ? double.tryParse(tpText) : null;

    if (sl == null && tp == null) {
      _showError('Please enter SL or TP value');
      return;
    }

    setState(() => _isProcessing = true);

    final matching = _findMatchingPositions();
    int modifiedCount = 0;

    for (final terminalIndex in _selectedTerminalIndices) {
      final pos = matching.where((p) => p['terminalIndex'] == terminalIndex).firstOrNull;
      if (pos != null) {
        final ticket = pos['ticket'] as int;
        widget.onModifyPosition(ticket, terminalIndex, sl, tp);
        modifiedCount++;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Modifying $modifiedCount position(s)'),
        backgroundColor: AppColors.primary,
      ),
    );

    Navigator.pop(context);
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          widget.position['symbol'] as String? ?? '',
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ValueListenableBuilder<List<Map<String, dynamic>>>(
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
          final profit = (currentPos['profit'] as num?)?.toDouble() ?? 0;
          final isBuy = type.toLowerCase() == 'buy';

          // Calculate total P/L across all matching positions
          double totalProfit = 0;
          for (final pos in matchingPositions) {
            totalProfit += (pos['profit'] as num?)?.toDouble() ?? 0;
          }

          // Use known terminals for display to avoid flickering
          final displayTerminals = _knownTerminalIndices.isNotEmpty 
              ? _knownTerminalIndices 
              : matchingPositions.map((p) => p['terminalIndex'] as int).toSet();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Position summary card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
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
                                  openPrice.toStringAsFixed(5),
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
                                  currentPrice.toStringAsFixed(5),
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
                                const Text('P/L', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                Text(
                                  '${profit >= 0 ? '+' : ''}${profit.toStringAsFixed(2)}',
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
                                'Total P/L (${displayTerminals.length} positions)',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                              ),
                              Text(
                                '${totalProfit >= 0 ? '+' : ''}${totalProfit.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: totalProfit >= 0 ? AppColors.primary : AppColors.error,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
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
                                    '${posProfit >= 0 ? '+' : ''}${posProfit.toStringAsFixed(2)}',
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
                              hintText: '0.00000',
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
                              hintText: '0.00000',
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
                      'MODIFY ${_selectedTerminalIndices.length} POSITION(S)',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Close button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _closePositions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'CLOSE ${_selectedTerminalIndices.length} POSITION(S)',
                            style: const TextStyle(
                              color: Colors.white,
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
    );
  }
}