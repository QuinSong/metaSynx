import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/theme.dart';
import 'position.dart';
import 'new_order.dart';

class ChartScreen extends StatefulWidget {
  final List<Map<String, dynamic>> positions;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final List<Map<String, dynamic>> accounts;
  final String? initialSymbol;
  final int? initialAccountIndex;
  final void Function(int ticket, int terminalIndex, [double? lots]) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final void Function(int ticket, int terminalIndex) onCancelOrder;
  final void Function(int ticket, int terminalIndex, double price) onModifyPendingOrder;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;
  // MT4 chart data
  final Stream<Map<String, dynamic>>? chartDataStream;
  final void Function(String symbol, String timeframe, int terminalIndex)? onRequestChartData;
  // New order
  final Map<String, String> symbolSuffixes;
  final Map<String, double> lotRatios;
  final Set<String> preferredPairs;
  final void Function({
    required String symbol,
    required String type,
    required double lots,
    required double? tp,
    required double? sl,
    required double? price,
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) onPlaceOrder;
  // Optional bottom nav bar for when opened from position screen
  final Widget? bottomNavBar;

  const ChartScreen({
    super.key,
    required this.positions,
    required this.positionsNotifier,
    required this.accounts,
    this.initialSymbol,
    this.initialAccountIndex,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.onCancelOrder,
    required this.onModifyPendingOrder,
    required this.accountNames,
    this.mainAccountNum,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onConfirmBeforeCloseChanged,
    this.chartDataStream,
    this.onRequestChartData,
    required this.symbolSuffixes,
    required this.lotRatios,
    required this.preferredPairs,
    required this.onPlaceOrder,
    this.bottomNavBar,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> with WidgetsBindingObserver {
  late WebViewController _controller;
  String _currentSymbol = 'EURUSD';
  String _currentInterval = '15';
  bool _isLoading = true;
  bool _hasReceivedData = false;
  int? _selectedAccountIndex;
  final TextEditingController _symbolController = TextEditingController();
  final FocusNode _symbolFocusNode = FocusNode();
  Timer? _chartPollTimer;
  StreamSubscription<Map<String, dynamic>>? _chartDataSubscription;
  bool _isAppInForeground = true; // Track if app is in foreground
  bool _showBidAskLines = false; // B/A toggle
  double? _currentBid;
  double? _currentAsk;
  bool _chartReady = false;  // True only after _onChartReady fires
  
  // Search overlay
  bool _showSearchOverlay = false;
  List<String> _recentSearches = [];
  
  // Preferred symbols (common forex pairs)
  final List<String> _preferredSymbols = [
    'EURUSD', 'GBPUSD', 'USDJPY', 'USDCHF', 'AUDUSD', 'USDCAD', 'NZDUSD',
    'EURGBP', 'EURJPY', 'GBPJPY', 'XAUUSD', 'XAGUSD', 'BTCUSD', 'ETHUSD',
  ];

  final List<Map<String, String>> _timeframes = [
    {'label': '1m', 'value': '1'},
    {'label': '5m', 'value': '5'},
    {'label': '15m', 'value': '15'},
    {'label': '30m', 'value': '30'},
    {'label': '1H', 'value': '60'},
    {'label': '4H', 'value': '240'},
    {'label': '1D', 'value': 'D'},
    {'label': '1W', 'value': 'W'},
    {'label': '1M', 'value': 'MN'},
  ];

  bool get _useMT4Data => 
      widget.chartDataStream != null && 
      widget.onRequestChartData != null;

  @override
  void initState() {
    super.initState();
    
    // Register for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Listen for position changes to update lines on chart
    widget.positionsNotifier.addListener(_onPositionsChanged);
    
    // Initialize WebView controller first (synchronous)
    _initWebView();
    
    // Then load preferences (async)
    _loadSavedPreferences();
  }
  
  void _onPositionsChanged() {
    // Update position lines on the chart when positions change
    if (_hasReceivedData) {
      final positionsJson = _buildPositionsJson();
      _controller.runJavaScript('updatePositions($positionsJson);');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        // App came back to foreground - resume polling
        _isAppInForeground = true;
        if (_useMT4Data && _selectedAccountIndex != null && _chartPollTimer == null) {
          _startChartPolling();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // App went to background - stop polling
        _isAppInForeground = false;
        _stopChartPolling();
        break;
    }
  }

  Future<void> _loadSavedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load saved account index
    final savedAccountIndex = prefs.getInt('chart_account_index');
    final savedSymbol = prefs.getString('chart_symbol');
    final savedTimeframe = prefs.getString('chart_timeframe');
    final savedShowBidAsk = prefs.getBool('chart_show_bid_ask') ?? false;
    
    // Load recent searches
    _recentSearches = prefs.getStringList('chart_recent_searches') ?? [];
    
    // Load B/A preference
    _showBidAskLines = savedShowBidAsk;
    
    // Validate and set account index - prioritize initialAccountIndex
    if (widget.initialAccountIndex != null) {
      // If opened from a specific account, use that
      _selectedAccountIndex = widget.initialAccountIndex;
    } else if (savedAccountIndex != null && savedAccountIndex < widget.accounts.length) {
      _selectedAccountIndex = savedAccountIndex;
    } else if (widget.accounts.isNotEmpty) {
      _selectedAccountIndex = 0;
    }
    
    // Validate and set symbol
    if (widget.initialSymbol != null && widget.initialSymbol!.isNotEmpty) {
      // If opened with a specific symbol, use that
      _currentSymbol = widget.initialSymbol!;
    } else if (savedSymbol != null && savedSymbol.isNotEmpty) {
      // Check if saved symbol still exists in positions
      final allSymbols = _getAllSymbols();
      if (allSymbols.contains(savedSymbol.toUpperCase())) {
        _currentSymbol = savedSymbol;
      } else if (widget.positions.isNotEmpty) {
        _currentSymbol = widget.positions.first['symbol'] as String? ?? 'EURUSD';
      }
    } else if (widget.positions.isNotEmpty) {
      _currentSymbol = widget.positions.first['symbol'] as String? ?? 'EURUSD';
    }
    
    // Validate and set timeframe
    if (savedTimeframe != null && _timeframes.any((tf) => tf['value'] == savedTimeframe)) {
      _currentInterval = savedTimeframe;
    }
    
    // Detect if current symbol has suffix and update state accordingly
    _symbolController.text = _currentSymbol;
    
    // Listen for chart data updates via stream
    if (_useMT4Data) {
      _chartDataSubscription = widget.chartDataStream!.listen(_onChartDataReceived);
    }
    
    // Add focus listener to show/hide overlay
    _symbolFocusNode.addListener(_onFocusChange);
    
    // Load chart with restored settings
    setState(() {});
    _controller.loadHtmlString(_buildLightweightChartsHtml());
    
    // Save current choices
    _savePreferences();
  }

  Set<String> _getAllSymbols() {
    final symbols = <String>{};
    for (final pos in widget.positions) {
      final symbol = pos['symbol'] as String?;
      if (symbol != null && symbol.isNotEmpty) {
        symbols.add(symbol.toUpperCase());
      }
    }
    return symbols;
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedAccountIndex != null) {
      await prefs.setInt('chart_account_index', _selectedAccountIndex!);
    }
    await prefs.setString('chart_symbol', _currentSymbol);
    await prefs.setString('chart_timeframe', _currentInterval);
    await prefs.setBool('chart_show_bid_ask', _showBidAskLines);
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.background)
      ..addJavaScriptChannel(
        'PositionTap',
        onMessageReceived: (JavaScriptMessage message) {
          _handlePositionTap(message.message);
        },
      )
      ..addJavaScriptChannel(
        'ChartReady',
        onMessageReceived: (JavaScriptMessage message) {
          _onChartReady();
        },
      )
      ..addJavaScriptChannel(
        'TimeframeSelect',
        onMessageReceived: (JavaScriptMessage message) {
          if (mounted) {
            setState(() {
              _currentInterval = message.message;
            });
            _loadChart();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            // Don't hide loading yet - wait for chart data
          },
          onWebResourceError: (error) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_buildLightweightChartsHtml());
  }

  void _onChartReady() {
    // Chart HTML is now loaded and ready to receive data
    _chartReady = true;
    
    // Chart is initialized, now start polling for data from MT4
    if (_useMT4Data && _selectedAccountIndex != null) {
      _hasReceivedData = false;
      
      // Apply saved B/A preference
      if (_showBidAskLines) {
        _controller.runJavaScript('showBidAskLines(null, null);');
      }
      
      // Request initial chart data
      widget.onRequestChartData!(_currentSymbol, _currentInterval, _selectedAccountIndex!);
      
      // Start polling for updates every 500ms
      _startChartPolling();
      
      // Set a timeout - if no data after 5 seconds, show error
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_hasReceivedData && _isLoading) {
          setState(() => _isLoading = false);
          _controller.runJavaScript('''
            document.getElementById('loading').innerHTML = 
              'No data received from MT4.<br>Check that EA is running and symbol exists.';
            document.getElementById('loading').style.display = 'block';
            document.getElementById('loading').style.color = '#FF5252';
          ''');
        }
      });
    } else {
      setState(() => _isLoading = false);
      _controller.runJavaScript('''
        document.getElementById('loading').innerHTML = 'MT4 connection not available';
        document.getElementById('loading').style.color = '#FFA726';
      ''');
    }
  }

  void _startChartPolling() {
    // Don't start polling if app is in background
    if (!_isAppInForeground) return;
    
    _stopChartPolling();
    _chartPollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      // Only poll if app is in foreground, we have a valid account, and MT4 data is enabled
      if (_isAppInForeground && _selectedAccountIndex != null && _useMT4Data && widget.onRequestChartData != null) {
        widget.onRequestChartData!(_currentSymbol, _currentInterval, _selectedAccountIndex!);
      }
    });
  }

  void _stopChartPolling() {
    _chartPollTimer?.cancel();
    _chartPollTimer = null;
  }

  void _onChartDataReceived(Map<String, dynamic> data) {
    // Ignore data if chart is not ready (HTML being rebuilt)
    if (!_chartReady) return;
    
    // Verify data matches current request (ignore stale responses)
    final dataSymbol = data['symbol'] as String?;
    final dataTimeframe = data['timeframe']?.toString();
    
    if (dataSymbol == null) return;
    if (dataSymbol.toUpperCase() != _currentSymbol.toUpperCase()) return;
    if (dataTimeframe != null && dataTimeframe != _currentInterval) return;
    
    // Extract bid/ask
    final bid = data['bid'];
    final ask = data['ask'];
    if (bid != null && ask != null) {
      _currentBid = (bid is num) ? bid.toDouble() : double.tryParse(bid.toString());
      _currentAsk = (ask is num) ? ask.toDouble() : double.tryParse(ask.toString());
      
      if (_currentBid != null && _currentAsk != null) {
        _controller.runJavaScript('updateBidAsk($_currentBid, $_currentAsk);');
      }
    }
    
    final candles = data['candles'] as List?;
    if (candles != null && candles.isNotEmpty) {
      final candlesJson = _candlesToJson(candles);
      
      // Always set full data - simpler and more robust
      _controller.runJavaScript('setFullChartData($candlesJson);');
      
      if (!_hasReceivedData) {
        _hasReceivedData = true;
        setState(() => _isLoading = false);
      }
    }
  }

  String _candlesToJson(List candles) {
    final buffer = StringBuffer('[');
    for (int i = 0; i < candles.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(_candleToJson(candles[i] as Map<String, dynamic>));
    }
    buffer.write(']');
    return buffer.toString();
  }

  String _candleToJson(Map<String, dynamic> candle) {
    final time = candle['time'];
    final open = candle['open'];
    final high = candle['high'];
    final low = candle['low'];
    final close = candle['close'];
    return '{"time":$time,"open":$open,"high":$high,"low":$low,"close":$close}';
  }

  void _handlePositionTap(String ticketStr) {
    final ticket = int.tryParse(ticketStr);
    if (ticket == null) return;
    
    // Use live positions data, not the static widget.positions
    final position = widget.positionsNotifier.value.firstWhere(
      (p) => _parseInt(p['ticket']) == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (position.isEmpty) return;
    
    // Check if it's a pending order
    final isPending = position['isPending'] == true;
    
    if (isPending) {
      // Show popup for pending orders
      _showPendingOrderPopup(position);
    } else {
      // Navigate to position detail for market orders
      _stopChartPolling();
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PositionDetailScreen(
            position: position,
            positionsNotifier: widget.positionsNotifier,
            accounts: widget.accounts,
            onClosePosition: widget.onClosePosition,
            onModifyPosition: widget.onModifyPosition,
            onCancelOrder: widget.onCancelOrder,
            onModifyPendingOrder: widget.onModifyPendingOrder,
            accountNames: widget.accountNames,
            mainAccountNum: widget.mainAccountNum,
            includeCommissionSwap: widget.includeCommissionSwap,
            showPLPercent: widget.showPLPercent,
            confirmBeforeClose: widget.confirmBeforeClose,
            onConfirmBeforeCloseChanged: widget.onConfirmBeforeCloseChanged,
            symbolSuffixes: widget.symbolSuffixes,
            lotRatios: widget.lotRatios,
            preferredPairs: widget.preferredPairs,
            onPlaceOrder: widget.onPlaceOrder,
            bottomNavBar: widget.bottomNavBar,
          ),
        ),
      ).then((_) {
        // Resume polling when returning to chart
        if (mounted && _isAppInForeground) {
          _startChartPolling();
        }
      });
    }
  }

  void _showPendingOrderPopup(Map<String, dynamic> order) {
    final ticket = _parseInt(order['ticket']);
    final terminalIndex = _parseInt(order['terminalIndex']);
    final symbol = order['symbol']?.toString() ?? '';
    final type = order['type']?.toString() ?? '';
    final openPrice = _parseDouble(order['openPrice']);
    final lots = _parseDouble(order['lots']);
    
    final formattedType = type.toUpperCase().replaceAll('_', ' ');
    final isBuy = type.toLowerCase().contains('buy');
    final digits = openPrice > 10 ? 3 : 5;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.primary, width: 1),
        ),
        contentPadding: const EdgeInsets.all(20),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header: Symbol + Type
            Row(
              children: [
                Text(
                  symbol,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBuy 
                        ? AppColors.primary.withOpacity(0.15)
                        : AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    formattedType,
                    style: TextStyle(
                      color: isBuy ? AppColors.primary : AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Price and Lots info
            Row(
              children: [
                Text(
                  '${lots.toStringAsFixed(2)} lots @ ${openPrice.toStringAsFixed(digits)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showEditPendingOrderDialog(order);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit, color: AppColors.primary, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      _showCancelOrderConfirmation(ticket, terminalIndex, symbol, formattedType);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.close, color: AppColors.error, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Cancel',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Find similar pending orders across accounts (same symbol, type, price)
  List<Map<String, dynamic>> _findSimilarPendingOrders(Map<String, dynamic> order) {
    final symbol = order['symbol']?.toString() ?? '';
    final type = order['type']?.toString() ?? '';
    final openPrice = _parseDouble(order['openPrice']);
    
    return widget.positionsNotifier.value.where((p) {
      if (p['isPending'] != true) return false;
      if (p['symbol']?.toString() != symbol) return false;
      if (p['type']?.toString() != type) return false;
      // Match orders with same price (within small tolerance)
      final pPrice = _parseDouble(p['openPrice']);
      return (pPrice - openPrice).abs() < 0.00001;
    }).toList();
  }

  String _getAccountName(int terminalIndex) {
    final account = widget.accounts.firstWhere(
      (a) => a['index'] == terminalIndex,
      orElse: () => <String, dynamic>{},
    );
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  void _showEditPendingOrderDialog(Map<String, dynamic> order) {
    final symbol = order['symbol']?.toString() ?? '';
    final openPrice = _parseDouble(order['openPrice']);
    final digits = openPrice > 10 ? 3 : 5;
    
    // Find all similar orders across accounts
    final similarOrders = _findSimilarPendingOrders(order);
    final selectedOrders = <int>{};  // Set of tickets to modify
    
    // Pre-select the tapped order
    selectedOrders.add(_parseInt(order['ticket']));
    
    final priceController = TextEditingController(text: openPrice.toStringAsFixed(digits));
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.primary, width: 1),
          ),
          title: Text('Edit Order - $symbol', style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Account selection (if multiple accounts have this order)
                  if (similarOrders.length > 1) ...[
                    const Text('Accounts', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    const SizedBox(height: 8),
                    ...similarOrders.map((o) {
                      final ticket = _parseInt(o['ticket']);
                      final terminalIndex = _parseInt(o['terminalIndex']);
                      final accountName = _getAccountName(terminalIndex);
                      final lots = _parseDouble(o['lots']);
                      final isSelected = selectedOrders.contains(ticket);
                      
                      return GestureDetector(
                        onTap: () {
                          setDialogState(() {
                            if (isSelected) {
                              selectedOrders.remove(ticket);
                            } else {
                              selectedOrders.add(ticket);
                            }
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.primary.withOpacity(0.15) : AppColors.background,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? AppColors.primary : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  accountName,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                '${lots.toStringAsFixed(2)} lots',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                  const Text('New Price', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    autofocus: similarOrders.length == 1,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: selectedOrders.isEmpty ? null : () {
                final newPrice = double.tryParse(priceController.text);
                if (newPrice == null || newPrice <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invalid price'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(context);
                
                // Modify all selected orders
                for (final o in similarOrders) {
                  final ticket = _parseInt(o['ticket']);
                  if (selectedOrders.contains(ticket)) {
                    final terminalIndex = _parseInt(o['terminalIndex']);
                    widget.onModifyPendingOrder(ticket, terminalIndex, newPrice);
                  }
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Modifying ${selectedOrders.length} order(s)...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              child: Text(
                'Update${selectedOrders.length > 1 ? ' (${selectedOrders.length})' : ''}',
                style: TextStyle(
                  color: selectedOrders.isEmpty ? AppColors.textMuted : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCancelOrderConfirmation(int ticket, int terminalIndex, String symbol, String type) {
    // Find the original order to get similar orders
    final order = widget.positionsNotifier.value.firstWhere(
      (p) => _parseInt(p['ticket']) == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (order.isEmpty) {
      // Fallback to single order cancel
      _showSingleCancelDialog(ticket, terminalIndex, symbol, type);
      return;
    }
    
    final similarOrders = _findSimilarPendingOrders(order);
    
    if (similarOrders.length <= 1) {
      // Single order, show simple dialog
      _showSingleCancelDialog(ticket, terminalIndex, symbol, type);
      return;
    }
    
    // Multiple accounts have this order
    final selectedOrders = <int>{ticket};  // Pre-select tapped order
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.primary, width: 1),
          ),
          title: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Accounts', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 8),
                  ...similarOrders.map((o) {
                    final oTicket = _parseInt(o['ticket']);
                    final oTerminalIndex = _parseInt(o['terminalIndex']);
                    final accountName = _getAccountName(oTerminalIndex);
                    final lots = _parseDouble(o['lots']);
                    final isSelected = selectedOrders.contains(oTicket);
                    
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          if (isSelected) {
                            selectedOrders.remove(oTicket);
                          } else {
                            selectedOrders.add(oTicket);
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.error.withOpacity(0.15) : AppColors.background,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? AppColors.error : AppColors.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                              color: isSelected ? AppColors.error : AppColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                accountName,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              '${lots.toStringAsFixed(2)} lots',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Text(
                    'Cancel $type order on $symbol?',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('No', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: selectedOrders.isEmpty ? null : () {
                Navigator.pop(context);
                
                // Cancel all selected orders
                for (final o in similarOrders) {
                  final oTicket = _parseInt(o['ticket']);
                  if (selectedOrders.contains(oTicket)) {
                    final oTerminalIndex = _parseInt(o['terminalIndex']);
                    widget.onCancelOrder(oTicket, oTerminalIndex);
                  }
                }
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cancelling ${selectedOrders.length} order(s)...'),
                    backgroundColor: AppColors.primary,
                  ),
                );
              },
              child: Text(
                'Yes, Cancel${selectedOrders.length > 1 ? ' (${selectedOrders.length})' : ''}',
                style: TextStyle(
                  color: selectedOrders.isEmpty ? AppColors.textMuted : AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSingleCancelDialog(int ticket, int terminalIndex, String symbol, String type) {
    final accountName = _getAccountName(terminalIndex);
    
    // Find order to get lots
    final order = widget.positionsNotifier.value.firstWhere(
      (p) => _parseInt(p['ticket']) == ticket,
      orElse: () => <String, dynamic>{},
    );
    final lots = _parseDouble(order['lots']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.primary, width: 1),
        ),
        title: const Text('Cancel Order', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Account', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_box, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          accountName,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                      Text(
                        '${lots.toStringAsFixed(2)} lots',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Cancel $type order on $symbol?',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onCancelOrder(ticket, terminalIndex);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cancelling order...'),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  List<Map<String, dynamic>> _getCurrentPositions() {
    return widget.positionsNotifier.value;
  }

  List<Map<String, dynamic>> _getPositionsForSymbol() {
    return _getCurrentPositions().where((p) {
      final symbolMatch = (p['symbol']?.toString().toUpperCase() ?? '') == _currentSymbol.toUpperCase();
      if (!symbolMatch) return false;
      
      if (_selectedAccountIndex != null) {
        final terminalIndex = _parseInt(p['terminalIndex']);
        return terminalIndex == _selectedAccountIndex;
      }
      
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _getPositionsForAccount() {
    if (_selectedAccountIndex == null) return _getCurrentPositions();
    return _getCurrentPositions().where((p) {
      final terminalIndex = _parseInt(p['terminalIndex']);
      return terminalIndex == _selectedAccountIndex;
    }).toList();
  }

  String _buildPositionLinesJs() {
    final positions = _getPositionsForSymbol();
    if (positions.isEmpty) return '';
    
    final lines = StringBuffer();
    
    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final type = (pos['type']?.toString() ?? '').toLowerCase();
      final openPrice = _parseDouble(pos['openPrice']);
      final sl = _parseDouble(pos['sl']);
      final tp = _parseDouble(pos['tp']);
      final lots = _parseDouble(pos['lots']);
      final ticket = _parseInt(pos['ticket']);
      final isPending = pos['isPending'] == true;
      
      // Determine order direction and type
      final isBuy = type.contains('buy');
      final isLimit = type.contains('limit');
      final isStop = type.contains('stop');
      
      // Color and label based on type
      String entryColor;
      String labelText;
      String labelClass;
      
      if (isPending) {
        // Pending orders use different colors (more muted)
        entryColor = isBuy ? '#00A080' : '#CC4444'; // Slightly muted green/red
        if (isLimit) {
          labelText = '${isBuy ? "BUY" : "SELL"} LMT ${lots.toStringAsFixed(2)}';
        } else if (isStop) {
          labelText = '${isBuy ? "BUY" : "SELL"} STP ${lots.toStringAsFixed(2)}';
        } else {
          labelText = '${isBuy ? "BUY" : "SELL"} ${lots.toStringAsFixed(2)}';
        }
        labelClass = isBuy ? 'entry-buy pending' : 'entry-sell pending';
      } else {
        entryColor = isBuy ? '#00D4AA' : '#FF5252';
        labelText = '${isBuy ? "BUY" : "SELL"} ${lots.toStringAsFixed(2)}';
        labelClass = isBuy ? 'entry-buy' : 'entry-sell';
      }
      
      // Store for tap detection
      lines.writeln('positionPrices.push({ ticket: $ticket, price: $openPrice });');
      
      // Entry line - dashed for pending, solid for market
      final lineStyle = isPending ? 2 : 0;
      lines.writeln('''
        positionLines.push(series.createPriceLine({
          price: $openPrice,
          color: '$entryColor',
          lineWidth: 1,
          lineStyle: $lineStyle,
          axisLabelVisible: true,
          title: '',
        }));
        createPositionLabel($openPrice, '$labelText', '$entryColor', '$labelClass', $ticket);
      ''');
      
      // SL line
      if (sl > 0) {
        lines.writeln('''
          positionLines.push(series.createPriceLine({
            price: $sl,
            color: '#FF5252',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: '',
          }));
          createPositionLabel($sl, 'SL', '#FF5252', 'sl', $ticket);
        ''');
      }
      
      // TP line
      if (tp > 0) {
        lines.writeln('''
          positionLines.push(series.createPriceLine({
            price: $tp,
            color: '#00D4AA',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: '',
          }));
          createPositionLabel($tp, 'TP', '#00D4AA', 'tp', $ticket);
        ''');
      }
    }
    
    return lines.toString();
  }
  
  String _buildPositionsJson() {
    final positions = _getPositionsForSymbol();
    if (positions.isEmpty) return '[]';
    
    final buffer = StringBuffer('[');
    for (int i = 0; i < positions.length; i++) {
      if (i > 0) buffer.write(',');
      final pos = positions[i];
      final type = (pos['type']?.toString() ?? '').toLowerCase();
      final openPrice = _parseDouble(pos['openPrice']);
      final sl = _parseDouble(pos['sl']);
      final tp = _parseDouble(pos['tp']);
      final lots = _parseDouble(pos['lots']);
      final ticket = _parseInt(pos['ticket']);
      final isPending = pos['isPending'] == true;
      final isBuy = type.contains('buy');
      final isLimit = type.contains('limit');
      final isStop = type.contains('stop');
      buffer.write('{"ticket":$ticket,"openPrice":$openPrice,"sl":$sl,"tp":$tp,"lots":$lots,"isBuy":$isBuy,"isPending":$isPending,"isLimit":$isLimit,"isStop":$isStop}');
    }
    buffer.write(']');
    return buffer.toString();
  }

  String _getBrokerName() {
    if (_selectedAccountIndex == null || _selectedAccountIndex! >= widget.accounts.length) {
      return '';
    }
    final account = widget.accounts[_selectedAccountIndex!];
    return account['broker']?.toString() ?? '';
  }

  String _buildLightweightChartsHtml() {
    final positionLines = _buildPositionLinesJs();
    final brokerName = _getBrokerName();

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <script src="https://unpkg.com/lightweight-charts@4.1.0/dist/lightweight-charts.standalone.production.js"></script>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { 
      width: 100%; 
      height: 100%; 
      background-color: #0a0a0a;
      overflow: hidden;
    }
    #chart { 
      width: 100%; 
      height: 100%; 
    }
    #loading {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: #888;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 14px;
    }
    #symbol-label {
      position: absolute;
      top: 10px;
      left: 10px;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 16px;
      font-weight: bold;
      background: rgba(30, 30, 30, 0.8);
      padding: 6px 12px;
      border-radius: 6px;
      z-index: 10;
    }
    #timeframe-label {
      position: absolute;
      top: 48px;
      left: 10px;
      color: #fff;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 13px;
      font-weight: 500;
      background: rgba(30, 30, 30, 0.9);
      padding: 8px 12px;
      border-radius: 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      z-index: 10;
      display: flex;
      align-items: center;
      gap: 6px;
      cursor: pointer;
    }
    #timeframe-label:active {
      background: rgba(50, 50, 50, 0.95);
    }
    #timeframe-dropdown {
      position: absolute;
      top: 88px;
      left: 10px;
      background: rgba(30, 30, 30, 0.95);
      border-radius: 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      z-index: 20;
      display: none;
      flex-direction: column;
      min-width: 80px;
      overflow: hidden;
    }
    #timeframe-dropdown.show {
      display: flex;
    }
    .tf-option {
      padding: 10px 14px;
      color: #9CA3AF;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 13px;
      cursor: pointer;
      transition: background 0.15s;
    }
    .tf-option:hover, .tf-option:active {
      background: rgba(255, 255, 255, 0.1);
    }
    .tf-option.selected {
      color: #00D4AA;
      font-weight: 600;
    }
    #spread-label {
      position: absolute;
      top: 48px;
      left: 10px;
      margin-left: 0px;
      color: #9CA3AF;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 12px;
      font-weight: 500;
      background: rgba(30, 30, 30, 0.9);
      padding: 8px 10px;
      border-radius: 8px;
      border: 1px solid rgba(255, 255, 255, 0.1);
      z-index: 10;
    }
    #position-labels {
      position: absolute;
      left: 0;
      top: 0;
      bottom: 0;
      width: 100%;
      pointer-events: none;
      z-index: 5;
    }
    .pos-label {
      position: absolute;
      left: 6px;
      padding: 2px 6px;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 11px;
      font-weight: 600;
      border-radius: 3px;
      white-space: nowrap;
      transform: translateY(-50%);
      pointer-events: auto;
      cursor: pointer;
    }
    .pos-label.entry-buy {
      background: rgba(0, 212, 170, 0.2);
      color: #00D4AA;
    }
    .pos-label.entry-sell {
      background: rgba(255, 82, 82, 0.2);
      color: #FF5252;
    }
    .pos-label.sl {
      background: rgba(255, 82, 82, 0.2);
      color: #FF5252;
    }
    .pos-label.tp {
      background: rgba(0, 212, 170, 0.2);
      color: #00D4AA;
    }
  </style>
</head>
<body>
  <div id="chart"></div>
  <div id="position-labels"></div>
  <div id="symbol-label">$_currentSymbol${brokerName.isNotEmpty ? ' <span style="font-size: 12px; color: #9CA3AF;">$brokerName</span>' : ''}</div>
  <div id="timeframe-label" onclick="toggleTimeframeDropdown(event)">
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#00D4AA" stroke-width="2">
      <circle cx="12" cy="12" r="10"></circle>
      <polyline points="12 6 12 12 16 14"></polyline>
    </svg>
    <span id="tf-current">${_getTimeframeLabel()}</span>
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" stroke-width="2" id="tf-chevron">
      <polyline points="6 9 12 15 18 9"></polyline>
    </svg>
  </div>
  <div id="spread-label">--</div>
  <div id="timeframe-dropdown">
    ${_buildTimeframeOptionsHtml()}
  </div>
  <div id="loading">Loading chart data...</div>
  
  <script>
    let dropdownOpen = false;
    
    function toggleTimeframeDropdown(event) {
      event.stopPropagation();
      const dropdown = document.getElementById('timeframe-dropdown');
      const chevron = document.getElementById('tf-chevron');
      dropdownOpen = !dropdownOpen;
      if (dropdownOpen) {
        dropdown.classList.add('show');
        chevron.style.transform = 'rotate(180deg)';
      } else {
        dropdown.classList.remove('show');
        chevron.style.transform = 'rotate(0deg)';
      }
    }
    
    function selectTimeframe(value, label) {
      document.getElementById('tf-current').textContent = label;
      document.getElementById('timeframe-dropdown').classList.remove('show');
      document.getElementById('tf-chevron').style.transform = 'rotate(0deg)';
      dropdownOpen = false;
      
      // Update selected state
      document.querySelectorAll('.tf-option').forEach(el => {
        el.classList.remove('selected');
        if (el.dataset.value === value) el.classList.add('selected');
      });
      
      // Reposition spread label
      positionSpreadLabel();
      
      // Notify Flutter
      if (window.TimeframeSelect) {
        window.TimeframeSelect.postMessage(value);
      }
    }
    
    function positionSpreadLabel() {
      const tfLabel = document.getElementById('timeframe-label');
      const spreadLabel = document.getElementById('spread-label');
      if (tfLabel && spreadLabel) {
        const tfWidth = tfLabel.offsetWidth;
        spreadLabel.style.left = (10 + tfWidth + 6) + 'px';
      }
    }
    
    // Position spread label on load
    setTimeout(positionSpreadLabel, 100);
    
    // Close dropdown when clicking elsewhere
    document.addEventListener('click', function(e) {
      if (dropdownOpen && !e.target.closest('#timeframe-label') && !e.target.closest('#timeframe-dropdown')) {
        document.getElementById('timeframe-dropdown').classList.remove('show');
        document.getElementById('tf-chevron').style.transform = 'rotate(0deg)';
        dropdownOpen = false;
      }
    });
    
    function onPositionTap(ticket) {
      if (window.PositionTap) {
        window.PositionTap.postMessage(ticket.toString());
      }
    }
    
    let positionPrices = [];
    let positionLines = [];
    let lastPrice = 0;
    
    const chart = LightweightCharts.createChart(document.getElementById('chart'), {
      layout: {
        background: { type: 'solid', color: '#0a0a0a' },
        textColor: '#d1d4dc',
      },
      grid: {
        vertLines: { color: 'rgba(255, 255, 255, 0.06)' },
        horzLines: { color: 'rgba(255, 255, 255, 0.06)' },
      },
      crosshair: {
        mode: LightweightCharts.CrosshairMode.Normal,
      },
      rightPriceScale: {
        borderColor: 'rgba(255, 255, 255, 0.1)',
        scaleMargins: { top: 0.1, bottom: 0.2 },
      },
      timeScale: {
        borderColor: 'rgba(255, 255, 255, 0.1)',
        timeVisible: true,
        secondsVisible: false,
        rightOffset: 50,
      },
      handleScroll: true,
      handleScale: true,
    });

    const series = chart.addCandlestickSeries({
      upColor: '#00D4AA',
      downColor: '#FF5252',
      borderDownColor: '#FF5252',
      borderUpColor: '#00D4AA',
      wickDownColor: '#FF5252',
      wickUpColor: '#00D4AA',
    });

    // Touch handler for position lines
    let touchStartX = 0;
    let touchStartY = 0;
    
    document.addEventListener('touchstart', (event) => {
      touchStartX = event.touches[0].clientX;
      touchStartY = event.touches[0].clientY;
    }, { passive: true });
    
    document.addEventListener('touchend', (event) => {
      if (positionPrices.length === 0) return;
      
      const touchEndX = event.changedTouches[0].clientX;
      const touchEndY = event.changedTouches[0].clientY;
      
      const moveX = Math.abs(touchEndX - touchStartX);
      const moveY = Math.abs(touchEndY - touchStartY);
      if (moveX > 10 || moveY > 10) return;
      
      const chartContainer = document.getElementById('chart');
      const rect = chartContainer.getBoundingClientRect();
      const tapX = touchEndX - rect.left;
      const tapY = touchEndY - rect.top;
      
      if (tapX < rect.width - 120) return;
      
      const tapPrice = series.coordinateToPrice(tapY);
      if (tapPrice === null) return;
      
      let closestPos = null;
      let closestDistance = Infinity;
      
      for (const pos of positionPrices) {
        const distance = Math.abs(tapPrice - pos.price);
        if (distance < closestDistance) {
          closestDistance = distance;
          closestPos = pos;
        }
      }
      
      if (closestPos) {
        const tolerance = Math.abs(closestPos.price * 0.02);
        if (closestDistance <= tolerance) {
          onPositionTap(closestPos.ticket);
        }
      }
    }, { passive: true });

    window.addEventListener('resize', () => {
      chart.applyOptions({ width: window.innerWidth, height: window.innerHeight });
    });

    let priceLines = [];  // Track price lines to clear them
    let chartInitialized = false;  // Only setData once
    let priceDecimals = 5;  // Default, will be detected from data
    
    // Detect decimals from a price value
    function detectDecimals(price) {
      const str = price.toString();
      const dotIndex = str.indexOf('.');
      if (dotIndex === -1) return 0;
      return str.length - dotIndex - 1;
    }
    
    // Function to set full chart data
    function setFullChartData(candles) {
      if (!candles || candles.length === 0) return;
      
      // Detect decimals from first candle's close price
      priceDecimals = detectDecimals(candles[0].close);
      // Configure price scale precision
      series.applyOptions({
        priceFormat: {
          type: 'price',
          precision: priceDecimals,
          minMove: Math.pow(10, -priceDecimals),
        },
      });
      
      // Always set full data
      series.setData(candles);
      document.getElementById('loading').style.display = 'none';
      
      // Add position lines only once
      if (!chartInitialized) {
        chartInitialized = true;
        $positionLines
        // Fit content only on first load
        chart.timeScale().fitContent();
      }
      
      const lastCandle = candles[candles.length - 1];
      lastPrice = lastCandle.close;
    }
    
    // Function to update just the last candle (for live updates)
    function updateLastCandle(candle) {
      if (!candle) return;
      series.update(candle);
      lastPrice = candle.close;
    }
    
    // Legacy function for compatibility
    function setChartData(candles) {
      setFullChartData(candles);
    }
    
    // Function to update current candle
    function updateCandle(candle) {
      updateLastCandle(candle);
    }
    
    // Bid/Ask price lines
    let bidLine = null;
    let askLine = null;
    let bidAskVisible = false;
    let currentBid = null;
    let currentAsk = null;
    
    function showBidAskLines(bid, ask) {
      bidAskVisible = true;
      if (bid) currentBid = bid;
      if (ask) currentAsk = ask;
      
      // Hide the default price line
      series.applyOptions({
        lastValueVisible: false,
        priceLineVisible: false,
      });
      
      if (currentBid && currentAsk) {
        updateBidAskLines(currentBid, currentAsk);
      }
    }
    
    function hideBidAskLines() {
      bidAskVisible = false;
      // Remove bid/ask lines
      if (bidLine) {
        series.removePriceLine(bidLine);
        bidLine = null;
      }
      if (askLine) {
        series.removePriceLine(askLine);
        askLine = null;
      }
      // Show the default price line again
      series.applyOptions({
        lastValueVisible: true,
        priceLineVisible: true,
      });
    }
    
    function updateBidAsk(bid, ask) {
      currentBid = bid;
      currentAsk = ask;
      
      // Update spread display - show as integer points
      if (bid && ask && bid > 0) {
        const spread = ask - bid;
        // Determine multiplier based on price level to get integer points
        let multiplier = 100000; // Default for most forex (5 decimals)
        if (bid > 1000) multiplier = 100; // Gold, indices
        else if (bid > 10) multiplier = 1000; // JPY pairs
        else if (bid < 0.1) multiplier = 1000000; // Some crypto
        
        const spreadPoints = Math.round(spread * multiplier);
        document.getElementById('spread-label').textContent = 'Spread ' + spreadPoints;
      }
      
      if (bidAskVisible) {
        updateBidAskLines(bid, ask);
      }
    }
    
    function updateBidAskLines(bid, ask) {
      if (!bid || !ask) return;
      
      // Remove existing lines
      if (bidLine) {
        series.removePriceLine(bidLine);
      }
      if (askLine) {
        series.removePriceLine(askLine);
      }
      
      // Create new lines
      bidLine = series.createPriceLine({
        price: bid,
        color: '#FF5252',
        lineWidth: 1,
        lineStyle: 2, // Dashed
        axisLabelVisible: true,
        title: '',
      });
      
      askLine = series.createPriceLine({
        price: ask,
        color: '#00D4AA',
        lineWidth: 1,
        lineStyle: 2, // Dashed
        axisLabelVisible: true,
        title: '',
      });
    }
    
    // Update position lines - removes old ones and creates new ones
    function updatePositions(positions) {
      // Remove all existing position lines
      for (const line of positionLines) {
        try {
          series.removePriceLine(line);
        } catch (e) {}
      }
      positionLines = [];
      positionPrices = [];
      
      // Clear HTML labels
      document.getElementById('position-labels').innerHTML = '';
      
      // Create new position lines
      for (const pos of positions) {
        // Determine colors and labels based on type
        let entryColor, labelText, labelClass, lineStyle;
        const lotsStr = pos.lots.toFixed(2);
        
        if (pos.isPending) {
          // Pending orders use muted colors and dashed lines
          entryColor = pos.isBuy ? '#00A080' : '#CC4444';
          lineStyle = 2; // Dashed for pending
          if (pos.isLimit) {
            labelText = (pos.isBuy ? 'BUY' : 'SELL') + ' LMT ' + lotsStr;
          } else if (pos.isStop) {
            labelText = (pos.isBuy ? 'BUY' : 'SELL') + ' STP ' + lotsStr;
          } else {
            labelText = (pos.isBuy ? 'BUY' : 'SELL') + ' ' + lotsStr;
          }
          labelClass = pos.isBuy ? 'entry-buy pending' : 'entry-sell pending';
        } else {
          // Market orders use solid lines
          entryColor = pos.isBuy ? '#00D4AA' : '#FF5252';
          lineStyle = 0; // Solid for market
          labelText = (pos.isBuy ? 'BUY ' : 'SELL ') + lotsStr;
          labelClass = pos.isBuy ? 'entry-buy' : 'entry-sell';
        }
        
        positionPrices.push({ ticket: pos.ticket, price: pos.openPrice });
        
        // Entry line
        positionLines.push(series.createPriceLine({
          price: pos.openPrice,
          color: entryColor,
          lineWidth: 1,
          lineStyle: lineStyle,
          axisLabelVisible: true,
          title: '',
        }));
        
        // Create HTML label on left for entry
        createPositionLabel(pos.openPrice, labelText, entryColor, labelClass, pos.ticket);
        
        // SL line
        if (pos.sl > 0) {
          positionLines.push(series.createPriceLine({
            price: pos.sl,
            color: '#FF5252',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: '',
          }));
          createPositionLabel(pos.sl, 'SL', '#FF5252', 'sl', pos.ticket);
        }
        
        // TP line
        if (pos.tp > 0) {
          positionLines.push(series.createPriceLine({
            price: pos.tp,
            color: '#00D4AA',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: '',
          }));
          createPositionLabel(pos.tp, 'TP', '#00D4AA', 'tp', pos.ticket);
        }
      }
    }
    
    function createPositionLabel(price, text, color, type, ticket) {
      const label = document.createElement('div');
      label.className = 'pos-label ' + type;
      label.textContent = text;
      label.style.color = color;
      label.dataset.price = price;
      label.dataset.ticket = ticket;
      label.onclick = function() {
        onPositionTap(ticket);
      };
      document.getElementById('position-labels').appendChild(label);
      updateLabelPosition(label, price);
    }
    
    function updateLabelPosition(label, price) {
      const y = series.priceToCoordinate(price);
      if (y !== null) {
        label.style.top = y + 'px';
        label.style.display = 'block';
      } else {
        label.style.display = 'none';
      }
    }
    
    function updateAllLabelPositions() {
      const labels = document.querySelectorAll('.pos-label');
      labels.forEach(label => {
        const price = parseFloat(label.dataset.price);
        updateLabelPosition(label, price);
      });
    }
    
    // Update label positions when chart scrolls/zooms
    chart.timeScale().subscribeVisibleLogicalRangeChange(updateAllLabelPositions);
    chart.subscribeCrosshairMove(updateAllLabelPositions);
    
    // Show loading state
    document.getElementById('loading').style.display = 'block';
    
    // Notify Flutter that chart is ready after a small delay to ensure everything is loaded
    setTimeout(function() {
      if (window.ChartReady) {
        window.ChartReady.postMessage('ready');
      }
    }, 100);
  </script>
</body>
</html>
''';
  }

  void _loadChart() {
    // Close search overlay and unfocus
    _symbolFocusNode.unfocus();
    setState(() {
      _showSearchOverlay = false;
    });
    
    // Stop polling while switching symbols
    _stopChartPolling();
    
    final symbol = _symbolController.text.trim().toUpperCase();
    
    // Add to recent searches if not empty
    if (symbol.isNotEmpty) {
      _addToRecentSearches(symbol);
    }
    
    // Mark chart as not ready until _onChartReady fires
    _chartReady = false;
    
    setState(() {
      _currentSymbol = symbol;
      _isLoading = true;
      _hasReceivedData = false;
      _currentBid = null;
      _currentAsk = null;
    });
    
    _savePreferences();
    _controller.loadHtmlString(_buildLightweightChartsHtml());
  }
  
  void _onFocusChange() {
    if (_symbolFocusNode.hasFocus) {
      setState(() {
        _showSearchOverlay = true;
      });
    }
  }
  
  void _closeSearchOverlay() {
    _symbolFocusNode.unfocus();
    setState(() {
      _showSearchOverlay = false;
    });
  }
  
  void _selectSymbol(String symbol) {
    _symbolController.text = symbol;
    _loadChart();
  }
  
  void _toggleBidAskLines() {
    setState(() {
      _showBidAskLines = !_showBidAskLines;
    });
    
    // Save preference
    _savePreferences();
    
    if (_showBidAskLines) {
      // Show bid/ask lines with current values if available
      if (_currentBid != null && _currentAsk != null) {
        _controller.runJavaScript('showBidAskLines($_currentBid, $_currentAsk);');
      } else {
        _controller.runJavaScript('showBidAskLines(null, null);');
      }
    } else {
      _controller.runJavaScript('hideBidAskLines();');
    }
  }
  
  void _openNewOrder(String orderType) {
    // Stop polling while on another screen
    _stopChartPolling();
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NewOrderScreen(
          accounts: widget.accounts,
          accountNames: widget.accountNames,
          mainAccountNum: widget.mainAccountNum,
          lotRatios: widget.lotRatios,
          preferredPairs: widget.preferredPairs,
          symbolSuffixes: widget.symbolSuffixes,
          initialSymbol: _currentSymbol,
          initialOrderType: orderType,
          onPlaceOrder: widget.onPlaceOrder,
        ),
      ),
    ).then((_) {
      // Resume polling when returning to chart
      if (mounted && _isAppInForeground) {
        _startChartPolling();
        // Force update position lines after a short delay to allow positions to refresh
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _onPositionsChanged();
          }
        });
      }
    });
  }
  
  Future<void> _addToRecentSearches(String symbol) async {
    _recentSearches.remove(symbol); // Remove if exists
    _recentSearches.insert(0, symbol); // Add to front
    if (_recentSearches.length > 10) {
      _recentSearches = _recentSearches.sublist(0, 10); // Keep max 10
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('chart_recent_searches', _recentSearches);
  }
  
  Future<void> _clearRecentSearches() async {
    setState(() {
      _recentSearches = [];
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('chart_recent_searches');
  }

  List<String> _getUniqueSymbols() {
    final symbols = <String>{};
    final positions = _getPositionsForAccount();
    for (final pos in positions) {
      final symbol = pos['symbol'] as String?;
      if (symbol != null && symbol.isNotEmpty) {
        symbols.add(symbol);
      }
    }
    // Return sorted alphabetically
    return symbols.toList()..sort();
  }

  int _getPositionCountForSymbol(String symbol) {
    return _getPositionsForAccount().where((p) => 
      (p['symbol']?.toString().toUpperCase() ?? '') == symbol.toUpperCase()
    ).length;
  }

  String _getSelectedAccountName() {
    if (_selectedAccountIndex == null || _selectedAccountIndex! >= widget.accounts.length) {
      return 'Account';
    }
    final account = widget.accounts[_selectedAccountIndex!];
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  String _getTimeframeLabel() {
    return _timeframes.firstWhere((tf) => tf['value'] == _currentInterval)['label']!;
  }

  String _buildTimeframeOptionsHtml() {
    final buffer = StringBuffer();
    for (final tf in _timeframes) {
      final isSelected = tf['value'] == _currentInterval;
      buffer.writeln('''
        <div class="tf-option${isSelected ? ' selected' : ''}" 
             data-value="${tf['value']}" 
             onclick="selectTimeframe('${tf['value']}', '${tf['label']}')">${tf['label']}</div>
      ''');
    }
    return buffer.toString();
  }

  Widget _buildPopupMenuButton<T>({
    required String value,
    IconData? icon,
    int badge = 0,
    required List<PopupMenuItem<T>> items,
    required void Function(T) onSelected,
  }) {
    return PopupMenuButton<T>(
      onSelected: onSelected,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(0, 40),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.primary, size: 16),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary, size: 18),
          ],
        ),
      ),
      itemBuilder: (context) => items,
    );
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    // Remove position listener
    widget.positionsNotifier.removeListener(_onPositionsChanged);
    // Stop polling - this is all we need now (no more subscribe/unsubscribe)
    _stopChartPolling();
    _chartDataSubscription?.cancel();
    _symbolFocusNode.removeListener(_onFocusChange);
    _symbolController.dispose();
    _symbolFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: widget.positionsNotifier,
      builder: (context, positions, child) {
        final uniqueSymbols = _getUniqueSymbols();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: TextField(
                      controller: _symbolController,
                      focusNode: _symbolFocusNode,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1),
                      textCapitalization: TextCapitalization.characters,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: const InputDecoration(
                        hintText: 'Symbol',
                        hintStyle: TextStyle(color: AppColors.textSecondary, height: 1),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadChart(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _loadChart();
                  },
                  child: Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary, width: 1),
                    ),
                    child: const Icon(Icons.search, color: AppColors.primary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          body: Stack(
            children: [
              SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Dropdown selectors row: Account | Symbol
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: AppColors.background,
                      child: Row(
                        children: [
                          // Account dropdown
                          if (widget.accounts.isNotEmpty)
                            Expanded(
                              child: _buildPopupMenuButton(
                                value: _getSelectedAccountName(),
                                items: List.generate(widget.accounts.length, (index) {
                                  final account = widget.accounts[index];
                                  final accountNum = account['account']?.toString() ?? '';
                                  final accountName = widget.accountNames[accountNum] ?? accountNum;
                                  final isSelected = _selectedAccountIndex == index;
                                  return PopupMenuItem<int>(
                                    value: index,
                                child: Text(
                                  accountName,
                                  style: TextStyle(
                                    color: isSelected ? AppColors.primary : Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              );
                            }),
                            onSelected: (value) {
                              setState(() {
                                _selectedAccountIndex = value;
                              });
                              _loadChart();
                            },
                          ),
                        ),
                      if (widget.accounts.isNotEmpty)
                        const SizedBox(width: 8),
                      // Symbol dropdown
                      if (uniqueSymbols.isNotEmpty)
                        Expanded(
                          child: _buildPopupMenuButton(
                            value: _currentSymbol,
                            badge: _getPositionCountForSymbol(_currentSymbol),
                            items: uniqueSymbols.map((symbol) {
                              final isSelected = symbol.toUpperCase() == _currentSymbol.toUpperCase();
                              final posCount = _getPositionCountForSymbol(symbol);
                              return PopupMenuItem<String>(
                                value: symbol,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      symbol,
                                      style: TextStyle(
                                        color: isSelected ? AppColors.primary : Colors.white,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (posCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          '$posCount',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onSelected: (value) {
                              _selectSymbol(value);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                
                // Chart with buy/sell buttons overlay
                Expanded(
                  child: Stack(
                    children: [
                      WebViewWidget(controller: _controller),
                      if (_isLoading)
                        Container(
                          color: AppColors.background,
                          child: const Center(
                            child: CircularProgressIndicator(color: AppColors.primary),
                          ),
                        ),
                      // B/A toggle - top right
                      Positioned(
                        top: 10,
                        right: 10,
                        child: GestureDetector(
                          onTap: _toggleBidAskLines,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _showBidAskLines 
                                    ? AppColors.primary 
                                    : AppColors.border,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showBidAskLines ? Icons.check_box : Icons.check_box_outline_blank,
                                  color: _showBidAskLines ? AppColors.primary : AppColors.textSecondary,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'B/A',
                                  style: TextStyle(
                                    color: _showBidAskLines ? AppColors.primary : AppColors.textSecondary,
                                    fontSize: 12,
                                    fontWeight: _showBidAskLines ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Buy/Sell buttons at bottom (hidden when keyboard is open)
                      if (MediaQuery.of(context).viewInsets.bottom == 0)
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 36,
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _openNewOrder('buy'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'BUY',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _openNewOrder('sell'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF5252),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Center(
                                      child: Text(
                                        'SELL',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Search overlay
          if (_showSearchOverlay)
            _buildSearchOverlay(),
            ],
          ),
          bottomNavigationBar: widget.bottomNavBar,
        );
      },
    );
  }
  
  Widget _buildSearchOverlay() {
    final brokerName = _getBrokerName();
    
    return GestureDetector(
      onTap: _closeSearchOverlay,
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with broker and close button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (brokerName.isNotEmpty)
                      Text(
                        brokerName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: _closeSearchOverlay,
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              
              // Recent searches
              if (_recentSearches.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'RECENT',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearRecentSearches,
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _recentSearches.map((symbol) {
                      return GestureDetector(
                        onTap: () => _selectSymbol(symbol),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            symbol,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              
              // Preferred symbols
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'POPULAR',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _preferredSymbols.map((symbol) {
                      return GestureDetector(
                        onTap: () => _selectSymbol(symbol),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            symbol,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}