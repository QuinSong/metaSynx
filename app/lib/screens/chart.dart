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
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
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
    required List<int> accountIndices,
    required bool useRatios,
    required bool applySuffix,
  }) onPlaceOrder;

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
    this.chartDataStream,
    this.onRequestChartData,
    required this.symbolSuffixes,
    required this.lotRatios,
    required this.preferredPairs,
    required this.onPlaceOrder,
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
  ];

  bool get _useMT4Data => 
      widget.chartDataStream != null && 
      widget.onRequestChartData != null;

  @override
  void initState() {
    super.initState();
    
    // Register for app lifecycle changes
    WidgetsBinding.instance.addObserver(this);
    
    // Initialize WebView controller first (synchronous)
    _initWebView();
    
    // Then load preferences (async)
    _loadSavedPreferences();
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
    
    // Load recent searches
    _recentSearches = prefs.getStringList('chart_recent_searches') ?? [];
    
    // Validate and set account index
    if (savedAccountIndex != null && savedAccountIndex < widget.accounts.length) {
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
    // Chart is initialized, now start polling for data from MT4
    if (_useMT4Data && _selectedAccountIndex != null) {
      _hasReceivedData = false;
      
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
    // Verify data matches current request (ignore stale responses)
    final dataSymbol = data['symbol'] as String?;
    final dataTimeframe = data['timeframe']?.toString();
    
    if (dataSymbol != null && dataSymbol != _currentSymbol) return;
    if (dataTimeframe != null && dataTimeframe != _currentInterval) return;
    
    final candles = data['candles'] as List?;
    if (candles != null && candles.isNotEmpty) {
      final candlesJson = _candlesToJson(candles);
      _controller.runJavaScript('setChartData($candlesJson);');
      
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
          symbolSuffixes: widget.symbolSuffixes,
          lotRatios: widget.lotRatios,
          preferredPairs: widget.preferredPairs,
          onPlaceOrder: widget.onPlaceOrder,
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
      final entryColor = isBuy ? '#00D4AA' : '#FF5252';
      
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
            color: '#00D4AA',
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
  </style>
</head>
<body>
  <div id="chart"></div>
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
      
      // Notify Flutter
      if (window.TimeframeSelect) {
        window.TimeframeSelect.postMessage(value);
      }
    }
    
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
    
    // Function to set initial chart data (called once)
    function setChartData(candles) {
      if (!candles || candles.length === 0) return;
      
      // Detect decimals from first candle's close price
      if (candles.length > 0) {
        priceDecimals = detectDecimals(candles[0].close);
        // Configure price scale precision
        series.applyOptions({
          priceFormat: {
            type: 'price',
            precision: priceDecimals,
            minMove: Math.pow(10, -priceDecimals),
          },
        });
      }
      
      if (!chartInitialized) {
        // First time - set all data and position lines
        chartInitialized = true;
        series.setData(candles);
        document.getElementById('loading').style.display = 'none';
        
        // Add position lines only once
        $positionLines
        
        chart.timeScale().fitContent();
      } else {
        // Subsequent updates - only update the last candle
        const lastCandle = candles[candles.length - 1];
        series.update(lastCandle);
      }
      
      const lastCandle = candles[candles.length - 1];
      lastPrice = lastCandle.close;
    }
    
    // Function to update current candle
    function updateCandle(candle) {
      series.update(candle);
      lastPrice = candle.close;
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
    
    setState(() {
      _currentSymbol = symbol;
      _isLoading = true;
      _hasReceivedData = false;
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
  
  void _openNewOrder(String orderType) {
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
    );
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
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
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