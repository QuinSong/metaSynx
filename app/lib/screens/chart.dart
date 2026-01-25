import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/theme.dart';
import 'position.dart';

class ChartScreen extends StatefulWidget {
  final List<Map<String, dynamic>> positions;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final List<Map<String, dynamic>> accounts;
  final String? initialSymbol;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final Map<String, String> accountNames;
  final String? mainAccountNum;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;
  // MT4 chart data
  final ValueNotifier<Map<String, dynamic>?>? chartDataNotifier;
  final void Function(String symbol, String timeframe, int terminalIndex)? onSubscribeChart;
  final void Function(int terminalIndex)? onUnsubscribeChart;

  const ChartScreen({
    super.key,
    required this.positions,
    required this.positionsNotifier,
    required this.accounts,
    this.initialSymbol,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.accountNames,
    this.mainAccountNum,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onConfirmBeforeCloseChanged,
    this.chartDataNotifier,
    this.onSubscribeChart,
    this.onUnsubscribeChart,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late WebViewController _controller;
  String _currentSymbol = 'EURUSD';
  String _currentInterval = '15';
  bool _isLoading = true;
  bool _hasReceivedData = false;
  int? _selectedAccountIndex;
  final TextEditingController _symbolController = TextEditingController();

  final List<Map<String, String>> _timeframes = [
    {'label': '1m', 'value': '1'},
    {'label': '5m', 'value': '5'},
    {'label': '15m', 'value': '15'},
    {'label': '30m', 'value': '30'},
    {'label': '1H', 'value': '60'},
    {'label': '4H', 'value': '240'},
    {'label': '1D', 'value': 'D'},
    {'label': '1W', 'value': 'W'},
  ];

  bool get _useMT4Data => 
      widget.chartDataNotifier != null && 
      widget.onSubscribeChart != null && 
      widget.onUnsubscribeChart != null;

  @override
  void initState() {
    super.initState();
    
    // Set first account as default
    if (widget.accounts.isNotEmpty) {
      _selectedAccountIndex = 0;
    }
    
    // Set initial symbol
    if (widget.initialSymbol != null && widget.initialSymbol!.isNotEmpty) {
      _currentSymbol = widget.initialSymbol!;
    } else if (widget.positions.isNotEmpty) {
      _currentSymbol = widget.positions.first['symbol'] as String? ?? 'EURUSD';
    }
    _symbolController.text = _currentSymbol;
    
    // Listen for chart data updates
    if (_useMT4Data) {
      widget.chartDataNotifier!.addListener(_onChartDataReceived);
    }
    
    _initWebView();
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
    // Chart is initialized, now request data from MT4
    if (_useMT4Data && _selectedAccountIndex != null) {
      _hasReceivedData = false;
      widget.onSubscribeChart!(_currentSymbol, _currentInterval, _selectedAccountIndex!);
      
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

  void _onChartDataReceived() {
    final data = widget.chartDataNotifier?.value;
    if (data == null) return;
    
    final type = data['type'] as String?;
    debugPrint('Chart data received: type=$type');
    
    if (type == 'history') {
      // Initial historical data
      final candles = data['candles'] as List?;
      if (candles != null && candles.isNotEmpty) {
        _hasReceivedData = true;
        final candlesJson = _candlesToJson(candles);
        _controller.runJavaScript('setChartData($candlesJson);');
        setState(() => _isLoading = false);
        debugPrint('Chart history set: ${candles.length} candles');
      }
    } else if (type == 'update') {
      // Live candle update
      final candle = data['candle'] as Map<String, dynamic>?;
      debugPrint('Chart update: candle=$candle, hasReceivedData=$_hasReceivedData');
      if (candle != null && _hasReceivedData) {
        final candleJson = _candleToJson(candle);
        _controller.runJavaScript('updateCandle($candleJson);');
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
    
    final position = widget.positions.firstWhere(
      (p) => _parseInt(p['ticket']) == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (position.isEmpty) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PositionDetailScreen(
          position: position,
          positionsNotifier: widget.positionsNotifier,
          accounts: widget.accounts,
          onClosePosition: widget.onClosePosition,
          onModifyPosition: widget.onModifyPosition,
          accountNames: widget.accountNames,
          mainAccountNum: widget.mainAccountNum,
          includeCommissionSwap: widget.includeCommissionSwap,
          showPLPercent: widget.showPLPercent,
          confirmBeforeClose: widget.confirmBeforeClose,
          onConfirmBeforeCloseChanged: widget.onConfirmBeforeCloseChanged,
        ),
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
    lines.writeln('positionPrices = [];');
    
    for (int i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final type = (pos['type']?.toString() ?? '').toLowerCase();
      final openPrice = _parseDouble(pos['openPrice']);
      final sl = _parseDouble(pos['sl']);
      final tp = _parseDouble(pos['tp']);
      final lots = _parseDouble(pos['lots']);
      final ticket = _parseInt(pos['ticket']);
      final isBuy = type == 'buy';
      final entryColor = isBuy ? '#00E676' : '#FF5252';
      
      lines.writeln('positionPrices.push({ ticket: $ticket, price: $openPrice });');
      
      // Entry line
      lines.writeln('''
        series.createPriceLine({
          price: $openPrice,
          color: '$entryColor',
          lineWidth: 2,
          lineStyle: 0,
          axisLabelVisible: true,
          title: '${isBuy ? "BUY" : "SELL"} ${lots.toStringAsFixed(2)}',
        });
      ''');
      
      // SL line
      if (sl > 0) {
        lines.writeln('''
          series.createPriceLine({
            price: $sl,
            color: '#FF5252',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: 'SL',
          });
        ''');
      }
      
      // TP line
      if (tp > 0) {
        lines.writeln('''
          series.createPriceLine({
            price: $tp,
            color: '#00E676',
            lineWidth: 1,
            lineStyle: 2,
            axisLabelVisible: true,
            title: 'TP',
          });
        ''');
      }
    }
    
    return lines.toString();
  }

  String _buildLightweightChartsHtml() {
    final positionLines = _buildPositionLinesJs();

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
    #price-label {
      position: absolute;
      top: 10px;
      right: 10px;
      color: #00E676;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 18px;
      font-weight: bold;
      background: rgba(30, 30, 30, 0.8);
      padding: 6px 12px;
      border-radius: 6px;
      z-index: 10;
    }
  </style>
</head>
<body>
  <div id="chart"></div>
  <div id="symbol-label">$_currentSymbol</div>
  <div id="price-label">--</div>
  <div id="loading">Loading chart data...</div>
  
  <script>
    function onPositionTap(ticket) {
      if (window.PositionTap) {
        window.PositionTap.postMessage(ticket.toString());
      }
    }
    
    let positionPrices = [];
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
      },
      handleScroll: true,
      handleScale: true,
    });

    const series = chart.addCandlestickSeries({
      upColor: '#00E676',
      downColor: '#FF5252',
      borderDownColor: '#FF5252',
      borderUpColor: '#00E676',
      wickDownColor: '#FF5252',
      wickUpColor: '#00E676',
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

    const priceLabel = document.getElementById('price-label');
    
    // Function to set initial chart data
    function setChartData(candles) {
      if (!candles || candles.length === 0) return;
      
      series.setData(candles);
      document.getElementById('loading').style.display = 'none';
      
      const lastCandle = candles[candles.length - 1];
      lastPrice = lastCandle.close;
      updatePriceLabel(lastCandle.close, lastCandle.open);
      
      // Add position lines after data is loaded
      $positionLines
      
      chart.timeScale().fitContent();
    }
    
    // Function to update current candle
    function updateCandle(candle) {
      series.update(candle);
      lastPrice = candle.close;
      updatePriceLabel(candle.close, candle.open);
    }
    
    // Function to update price label
    function updatePriceLabel(close, open) {
      const decimals = close > 10 ? 2 : (close > 1 ? 4 : 5);
      priceLabel.textContent = close.toFixed(decimals);
      priceLabel.style.color = close >= open ? '#00E676' : '#FF5252';
    }
    
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
    // Unsubscribe from current chart data
    if (_useMT4Data && _selectedAccountIndex != null) {
      widget.onUnsubscribeChart!(_selectedAccountIndex!);
    }
    
    setState(() {
      _currentSymbol = _symbolController.text.trim().toUpperCase();
      _isLoading = true;
      _hasReceivedData = false;
    });
    
    _controller.loadHtmlString(_buildLightweightChartsHtml());
  }

  Set<String> _getUniqueSymbols() {
    final symbols = <String>{};
    final positions = _getPositionsForAccount();
    for (final pos in positions) {
      final symbol = pos['symbol'] as String?;
      if (symbol != null && symbol.isNotEmpty) {
        symbols.add(symbol);
      }
    }
    return symbols;
  }

  int _getPositionCountForSymbol(String symbol) {
    return _getPositionsForAccount().where((p) => 
      (p['symbol']?.toString().toUpperCase() ?? '') == symbol.toUpperCase()
    ).length;
  }

  @override
  void dispose() {
    // Unsubscribe from chart data when leaving screen
    if (_useMT4Data && _selectedAccountIndex != null) {
      widget.onUnsubscribeChart!(_selectedAccountIndex!);
    }
    
    if (_useMT4Data) {
      widget.chartDataNotifier!.removeListener(_onChartDataReceived);
    }
    
    _symbolController.dispose();
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
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _symbolController,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Symbol',
                        hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadChart(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: _loadChart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('GO', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                // Account selector row
                if (widget.accounts.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppColors.surface,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...List.generate(widget.accounts.length, (index) {
                            final account = widget.accounts[index];
                            final accountNum = account['account']?.toString() ?? '';
                            final accountName = widget.accountNames[accountNum] ?? accountNum;
                            final isSelected = _selectedAccountIndex == index;
                            
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedAccountIndex = index;
                                  });
                                  _loadChart();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primaryWithOpacity(0.2)
                                        : AppColors.background,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.border,
                                    ),
                                  ),
                                  child: Text(
                                    accountName,
                                    style: TextStyle(
                                      color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                
                // Timeframe selector row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: AppColors.surface,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _timeframes.map((tf) {
                        final isSelected = tf['value'] == _currentInterval;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentInterval = tf['value']!;
                              });
                              _loadChart();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.border,
                                ),
                              ),
                              child: Text(
                                tf['label']!,
                                style: TextStyle(
                                  color: isSelected ? Colors.black : AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                
                // Quick symbol buttons from open positions
                if (uniqueSymbols.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: AppColors.background,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: uniqueSymbols.map((symbol) {
                          final isSelected = symbol.toUpperCase() == _currentSymbol.toUpperCase();
                          final posCount = _getPositionCountForSymbol(symbol);
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () {
                                _symbolController.text = symbol;
                                _loadChart();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected 
                                      ? AppColors.primaryWithOpacity(0.2) 
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected ? AppColors.primary : AppColors.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      symbol,
                                      style: TextStyle(
                                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    if (posCount > 0) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.primary : AppColors.textMuted,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '$posCount',
                                          style: TextStyle(
                                            color: isSelected ? Colors.black : AppColors.surface,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                
                // Chart
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
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}