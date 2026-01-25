import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/theme.dart';
import 'position_detail_screen.dart';

class ChartScreen extends StatefulWidget {
  final List<Map<String, dynamic>> positions;
  final ValueNotifier<List<Map<String, dynamic>>> positionsNotifier;
  final List<Map<String, dynamic>> accounts;
  final String? initialSymbol;
  final void Function(int ticket, int terminalIndex) onClosePosition;
  final void Function(int ticket, int terminalIndex, double? sl, double? tp) onModifyPosition;
  final VoidCallback onRefreshAllPositions;
  final Map<String, String> accountNames;
  final bool includeCommissionSwap;
  final bool showPLPercent;
  final bool confirmBeforeClose;
  final void Function(bool) onConfirmBeforeCloseChanged;

  const ChartScreen({
    super.key,
    required this.positions,
    required this.positionsNotifier,
    required this.accounts,
    this.initialSymbol,
    required this.onClosePosition,
    required this.onModifyPosition,
    required this.onRefreshAllPositions,
    required this.accountNames,
    required this.includeCommissionSwap,
    required this.showPLPercent,
    required this.confirmBeforeClose,
    required this.onConfirmBeforeCloseChanged,
  });

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  late WebViewController _controller;
  String _currentSymbol = 'EURUSD';
  String _currentInterval = '15';
  bool _isLoading = true;
  int? _selectedAccountIndex; // null means show all accounts
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
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadHtmlString(_buildLightweightChartsHtml());
  }

  void _handlePositionTap(String ticketStr) {
    final ticket = int.tryParse(ticketStr);
    if (ticket == null) return;
    
    // Find the position with this ticket
    final position = widget.positions.firstWhere(
      (p) => _parseInt(p['ticket']) == ticket,
      orElse: () => <String, dynamic>{},
    );
    
    if (position.isEmpty) return;
    
    // Navigate to position detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PositionDetailScreen(
          position: position,
          positionsNotifier: widget.positionsNotifier,
          accounts: widget.accounts,
          onClosePosition: widget.onClosePosition,
          onModifyPosition: widget.onModifyPosition,
          onRefreshAllPositions: widget.onRefreshAllPositions,
          accountNames: widget.accountNames,
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
    // Use live positions from notifier
    return widget.positionsNotifier.value;
  }

  List<Map<String, dynamic>> _getPositionsForSymbol() {
    return _getCurrentPositions().where((p) {
      // Filter by symbol
      final symbolMatch = (p['symbol']?.toString().toUpperCase() ?? '') == _currentSymbol.toUpperCase();
      if (!symbolMatch) return false;
      
      // Filter by selected account if one is selected
      if (_selectedAccountIndex != null) {
        final terminalIndex = _parseInt(p['terminalIndex']);
        return terminalIndex == _selectedAccountIndex;
      }
      
      return true;
    }).toList();
  }

  List<Map<String, dynamic>> _getPositionsForAccount() {
    // Get all positions for selected account
    if (_selectedAccountIndex == null) return _getCurrentPositions();
    return _getCurrentPositions().where((p) {
      final terminalIndex = _parseInt(p['terminalIndex']);
      return terminalIndex == _selectedAccountIndex;
    }).toList();
  }

  String _getAccountName(int index) {
    if (index < 0 || index >= widget.accounts.length) return 'Account $index';
    final account = widget.accounts[index];
    final accountNum = account['account']?.toString() ?? '';
    return widget.accountNames[accountNum] ?? accountNum;
  }

  String _buildPositionLinesJs() {
    final positions = _getPositionsForSymbol();
    if (positions.isEmpty) return '';
    
    final lines = StringBuffer();
    
    // Populate the global positionPrices array for click detection
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
      
      // Store position price for click detection
      lines.writeln('''
        positionPrices.push({ ticket: $ticket, price: $openPrice });
      ''');
      
      // Entry line - spans full chart
      lines.writeln('''
        series.createPriceLine({
          price: $openPrice,
          color: '$entryColor',
          lineWidth: 2,
          lineStyle: 0,
          axisLabelVisible: true,
          title: '${type.toUpperCase()} ${lots.toStringAsFixed(2)}',
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

  String _getDataFeedSymbol() {
    final symbol = _currentSymbol.toUpperCase();
    
    // Map symbols to Binance format for crypto
    if (_isCryptoPair(symbol)) {
      if (symbol == 'BTCUSD') return 'BTCUSDT';
      if (symbol == 'ETHUSD') return 'ETHUSDT';
      return symbol.replaceAll('USD', 'USDT');
    }
    
    return symbol;
  }

  String _buildLightweightChartsHtml() {
    final positionLines = _buildPositionLinesJs();
    final feedSymbol = _getDataFeedSymbol();
    final isCrypto = _isCryptoPair(_currentSymbol);

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
    #error {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      color: #FF5252;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      font-size: 14px;
      text-align: center;
      padding: 20px;
      display: none;
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
  <div id="error">Unable to load chart data.<br>Please check symbol and try again.</div>
  
  <script>
    // Function to handle position tap
    function onPositionTap(ticket) {
      if (window.PositionTap) {
        window.PositionTap.postMessage(ticket.toString());
      }
    }
    
    // Position prices will be populated after data loads
    let positionPrices = [];
    
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
        scaleMargins: {
          top: 0.1,
          bottom: 0.2,
        },
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

    // Touch handler for tapping on position price line labels
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
      
      // Check if it's a tap (not a swipe) - less than 10px movement
      const moveX = Math.abs(touchEndX - touchStartX);
      const moveY = Math.abs(touchEndY - touchStartY);
      if (moveX > 10 || moveY > 10) return;
      
      const chartContainer = document.getElementById('chart');
      const rect = chartContainer.getBoundingClientRect();
      const tapX = touchEndX - rect.left;
      const tapY = touchEndY - rect.top;
      
      // Only trigger if tap is on the right side (price scale area - last 120px)
      const chartWidth = rect.width;
      if (tapX < chartWidth - 120) return;
      
      // Get the price at tap point
      const tapPrice = series.coordinateToPrice(tapY);
      if (tapPrice === null) return;
      
      // Find the closest position to the tap price
      let closestPos = null;
      let closestDistance = Infinity;
      
      for (const pos of positionPrices) {
        const distance = Math.abs(tapPrice - pos.price);
        if (distance < closestDistance) {
          closestDistance = distance;
          closestPos = pos;
        }
      }
      
      // Check if closest position is within tolerance (2% of price for easier tapping)
      if (closestPos) {
        const tolerance = Math.abs(closestPos.price * 0.02);
        if (closestDistance <= tolerance) {
          onPositionTap(closestPos.ticket);
        }
      }
    }, { passive: true });

    // Resize handler
    window.addEventListener('resize', () => {
      chart.applyOptions({ width: window.innerWidth, height: window.innerHeight });
    });

    // Price label update
    const priceLabel = document.getElementById('price-label');
    
    series.priceScale().applyOptions({
      autoScale: true,
    });

    ${isCrypto ? _buildBinanceDataFeed(feedSymbol, positionLines) : _buildForexDataFeed(feedSymbol, positionLines)}
  </script>
</body>
</html>
''';
  }

  String _getBinanceInterval() {
    switch (_currentInterval) {
      case '1': return '1m';
      case '5': return '5m';
      case '15': return '15m';
      case '30': return '30m';
      case '60': return '1h';
      case '240': return '4h';
      case 'D': return '1d';
      case 'W': return '1w';
      default: return '15m';
    }
  }

  int _getIntervalSeconds() {
    switch (_currentInterval) {
      case '1': return 60;
      case '5': return 300;
      case '15': return 900;
      case '30': return 1800;
      case '60': return 3600;
      case '240': return 14400;
      case 'D': return 86400;
      case 'W': return 604800;
      default: return 900;
    }
  }

  String _buildBinanceDataFeed(String symbol, String positionLines) {
    final binanceInterval = _getBinanceInterval();
    return '''
    // Fetch historical data from Binance
    async function loadData() {
      try {
        const response = await fetch('https://api.binance.com/api/v3/klines?symbol=$symbol&interval=$binanceInterval&limit=500');
        const data = await response.json();
        
        if (!Array.isArray(data) || data.length === 0) {
          throw new Error('No data received');
        }
        
        const candleData = data.map(d => ({
          time: d[0] / 1000,
          open: parseFloat(d[1]),
          high: parseFloat(d[2]),
          low: parseFloat(d[3]),
          close: parseFloat(d[4]),
        }));
        
        series.setData(candleData);
        document.getElementById('loading').style.display = 'none';
        
        // Update price label with latest
        const lastCandle = candleData[candleData.length - 1];
        priceLabel.textContent = lastCandle.close.toFixed(2);
        
        // Add position lines
        $positionLines
        
        // Subscribe to real-time updates
        const ws = new WebSocket('wss://stream.binance.com:9443/ws/${symbol.toLowerCase()}@kline_$binanceInterval');
        
        ws.onmessage = (event) => {
          const msg = JSON.parse(event.data);
          const candle = msg.k;
          
          const updatedCandle = {
            time: candle.t / 1000,
            open: parseFloat(candle.o),
            high: parseFloat(candle.h),
            low: parseFloat(candle.l),
            close: parseFloat(candle.c),
          };
          
          series.update(updatedCandle);
          
          // Update price label
          const color = parseFloat(candle.c) >= parseFloat(candle.o) ? '#00E676' : '#FF5252';
          priceLabel.textContent = parseFloat(candle.c).toFixed(2);
          priceLabel.style.color = color;
        };
        
        ws.onerror = (err) => {
          console.error('WebSocket error:', err);
        };
        
      } catch (error) {
        console.error('Error loading data:', error);
        document.getElementById('loading').style.display = 'none';
        document.getElementById('error').style.display = 'block';
      }
    }
    
    loadData();
    ''';
  }

  String _buildForexDataFeed(String symbol, String positionLines) {
    // For forex, we'll use a free API or generate sample data
    // Since most free forex APIs require keys, we'll show a message for now
    final intervalSeconds = _getIntervalSeconds();
    return '''
    // Forex data - using sample data (replace with your preferred forex data provider)
    async function loadData() {
      try {
        // Generate sample forex data for demonstration
        // In production, replace with your forex data API
        const now = Math.floor(Date.now() / 1000);
        const interval = $intervalSeconds;
        const candleData = [];
        
        // Determine base price based on symbol
        let basePrice = 1.0850; // EURUSD default
        if ('$symbol'.includes('JPY')) basePrice = 156.50;
        if ('$symbol'.includes('XAU')) basePrice = 2650.00;
        if ('$symbol'.includes('XAG')) basePrice = 31.50;
        if ('$symbol'.includes('GBP')) basePrice = 1.2650;
        if ('$symbol'.includes('AUD')) basePrice = 0.6550;
        if ('$symbol'.includes('CAD')) basePrice = 1.3550;
        if ('$symbol'.includes('CHF')) basePrice = 0.8850;
        
        // Generate 200 candles of sample data
        for (let i = 200; i >= 0; i--) {
          const time = now - (i * interval);
          const volatility = basePrice * 0.0005;
          const open = basePrice + (Math.random() - 0.5) * volatility * 2;
          const close = open + (Math.random() - 0.5) * volatility * 2;
          const high = Math.max(open, close) + Math.random() * volatility;
          const low = Math.min(open, close) - Math.random() * volatility;
          
          candleData.push({ time, open, high, low, close });
          basePrice = close;
        }
        
        series.setData(candleData);
        document.getElementById('loading').style.display = 'none';
        
        // Update price label
        const lastCandle = candleData[candleData.length - 1];
        const decimals = '$symbol'.includes('JPY') ? 3 : ('$symbol'.includes('XAU') ? 2 : 5);
        priceLabel.textContent = lastCandle.close.toFixed(decimals);
        
        // Add position lines
        $positionLines
        
        // Simulate live updates
        setInterval(() => {
          const lastData = candleData[candleData.length - 1];
          const volatility = lastData.close * 0.0001;
          const newClose = lastData.close + (Math.random() - 0.5) * volatility * 2;
          const newHigh = Math.max(lastData.high, newClose);
          const newLow = Math.min(lastData.low, newClose);
          
          const updatedCandle = {
            time: lastData.time,
            open: lastData.open,
            high: newHigh,
            low: newLow,
            close: newClose,
          };
          
          series.update(updatedCandle);
          candleData[candleData.length - 1] = updatedCandle;
          
          // Update price label
          const color = newClose >= lastData.open ? '#00E676' : '#FF5252';
          priceLabel.textContent = newClose.toFixed(decimals);
          priceLabel.style.color = color;
        }, 1000);
        
      } catch (error) {
        console.error('Error:', error);
        document.getElementById('loading').style.display = 'none';
        document.getElementById('error').style.display = 'block';
      }
    }
    
    loadData();
    ''';
  }

  bool _isCryptoPair(String symbol) {
    final cryptoPairs = [
      'BTCUSD', 'ETHUSD', 'BTCUSDT', 'ETHUSDT', 'XRPUSD', 'LTCUSD', 
      'BCHUSD', 'ADAUSD', 'DOTUSD', 'LINKUSD', 'SOLUSD', 'BNBUSD',
      'BTCUSDT', 'ETHUSDT', 'BNBUSDT', 'SOLUSDT', 'XRPUSDT',
    ];
    return cryptoPairs.contains(symbol.toUpperCase());
  }

  void _loadChart() {
    setState(() {
      _currentSymbol = _symbolController.text.trim().toUpperCase();
      _isLoading = true;
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
      body: Column(
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
                    // Account buttons
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
                    final isSelected = symbol == _currentSymbol;
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
    );
      },
    );
  }
}