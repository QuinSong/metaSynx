//+------------------------------------------------------------------+
//|                                                  MetaSynxEA.mq4  |
//|                                          MetaSynx Bridge Client  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MetaSynx"
#property link      ""
#property version   "2.10"
#property strict

//+------------------------------------------------------------------+
//| Configuration                                                     |
//+------------------------------------------------------------------+
input string   BridgeFolder = "MetaSynx";  // Folder for bridge communication
input int      UpdateIntervalMs = 500;      // Update interval in milliseconds

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
string g_dataPath;
string g_commandFile;
string g_responseFile;
string g_statusFile;
string g_positionsFile;
string g_chartFile;
int    g_terminalIndex = -1;
string g_lastCommandHash = "";

// Chart subscription state
bool   g_chartSubscribed = false;
string g_chartSymbol = "";
int    g_chartTimeframe = PERIOD_M15;
int    g_chartDelayCount = 0;  // Delay counter to let history be read

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_dataPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + BridgeFolder + "\\";
   
   if(!FolderCreate(BridgeFolder, FILE_COMMON)) { }
   
   g_terminalIndex = GetTerminalIndex();
   
   g_statusFile = BridgeFolder + "\\status_" + IntegerToString(g_terminalIndex) + ".json";
   g_commandFile = BridgeFolder + "\\command_" + IntegerToString(g_terminalIndex) + ".json";
   g_responseFile = BridgeFolder + "\\response_" + IntegerToString(g_terminalIndex) + ".json";
   g_positionsFile = BridgeFolder + "\\positions_" + IntegerToString(g_terminalIndex) + ".json";
   g_chartFile = BridgeFolder + "\\chart_" + IntegerToString(g_terminalIndex) + ".json";
   
   Print("MetaSynx EA v2.10 initialized - Terminal Index: ", g_terminalIndex, " Account: ", AccountNumber());
   
   WriteAccountStatus();
   WritePositions();
   
   EventSetMillisecondTimer(UpdateIntervalMs);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(FileIsExist(g_statusFile, FILE_COMMON)) FileDelete(g_statusFile, FILE_COMMON);
   if(FileIsExist(g_positionsFile, FILE_COMMON)) FileDelete(g_positionsFile, FILE_COMMON);
   if(FileIsExist(g_chartFile, FILE_COMMON)) FileDelete(g_chartFile, FILE_COMMON);
   Print("MetaSynx EA deinitialized");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   CheckAndProcessCommands();
   WriteAccountStatus();
   WritePositions();
   
   // If chart is subscribed, update the current candle
   if(g_chartSubscribed)
   {
      // Wait for delay to expire before sending updates
      // This gives the bridge time to read the history first
      if(g_chartDelayCount > 0)
      {
         g_chartDelayCount--;
      }
      else
      {
         WriteChartUpdate();
      }
   }
}

//+------------------------------------------------------------------+
//| Get unique terminal index                                         |
//+------------------------------------------------------------------+
int GetTerminalIndex()
{
   long accountNum = AccountNumber();
   string indexFile = BridgeFolder + "\\terminal_index.json";
   
   int handle = FileOpen(indexFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      string content = "";
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);
      
      string searchStr = "\"" + IntegerToString(accountNum) + "\":";
      int pos = StringFind(content, searchStr);
      if(pos >= 0)
      {
         int indexStart = pos + StringLen(searchStr);
         int indexEnd = StringFind(content, ",", indexStart);
         if(indexEnd < 0) indexEnd = StringFind(content, "}", indexStart);
         if(indexEnd > indexStart)
            return (int)StringToInteger(StringSubstr(content, indexStart, indexEnd - indexStart));
      }
   }
   
   for(int i = 0; i < 10; i++)
   {
      if(!FileIsExist(BridgeFolder + "\\status_" + IntegerToString(i) + ".json", FILE_COMMON))
      {
         SaveTerminalIndex(accountNum, i);
         return i;
      }
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Save terminal index mapping                                       |
//+------------------------------------------------------------------+
void SaveTerminalIndex(long accountNum, int index)
{
   string indexFile = BridgeFolder + "\\terminal_index.json";
   string content = "";
   
   int handle = FileOpen(indexFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      while(!FileIsEnding(handle)) content += FileReadString(handle);
      FileClose(handle);
   }
   
   if(StringLen(content) < 2)
      content = "{\"" + IntegerToString(accountNum) + "\":" + IntegerToString(index) + "}";
   else
   {
      int closePos = StringFind(content, "}");
      if(closePos > 0)
         content = StringSubstr(content, 0, closePos) + ",\"" + IntegerToString(accountNum) + "\":" + IntegerToString(index) + "}";
   }
   
   handle = FileOpen(indexFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, content);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Write account status                                              |
//+------------------------------------------------------------------+
void WriteAccountStatus()
{
   string json = "{";
   json += "\"index\":" + IntegerToString(g_terminalIndex) + ",";
   json += "\"account\":\"" + IntegerToString(AccountNumber()) + "\",";
   json += "\"name\":\"" + AccountName() + "\",";
   json += "\"broker\":\"" + AccountCompany() + "\",";
   json += "\"server\":\"" + AccountServer() + "\",";
   json += "\"currency\":\"" + AccountCurrency() + "\",";
   json += "\"balance\":" + DoubleToString(AccountBalance(), 2) + ",";
   json += "\"equity\":" + DoubleToString(AccountEquity(), 2) + ",";
   json += "\"margin\":" + DoubleToString(AccountMargin(), 2) + ",";
   json += "\"freeMargin\":" + DoubleToString(AccountFreeMargin(), 2) + ",";
   json += "\"marginLevel\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2) + ",";
   json += "\"leverage\":" + IntegerToString(AccountLeverage()) + ",";
   json += "\"openPositions\":" + IntegerToString(OrdersTotal()) + ",";
   json += "\"profit\":" + DoubleToString(AccountProfit(), 2) + ",";
   json += "\"lastUpdate\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";
   json += "\"connected\":" + (IsConnected() ? "true" : "false") + ",";
   json += "\"tradeAllowed\":" + (IsTradeAllowed() ? "true" : "false");
   json += "}";
   
   int handle = FileOpen(g_statusFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Write positions                                                   |
//+------------------------------------------------------------------+
void WritePositions()
{
   string json = "{\"index\":" + IntegerToString(g_terminalIndex) + ",\"positions\":[";
   
   bool first = true;
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(!first) json += ",";
         first = false;
         
         int orderType = OrderType();
         bool isPending = (orderType >= OP_BUYLIMIT);
         
         double currentPrice = 0;
         if(!isPending)
         {
            currentPrice = orderType == OP_BUY ? 
               MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
         }
         
         json += "{";
         json += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
         json += "\"symbol\":\"" + OrderSymbol() + "\",";
         json += "\"type\":\"" + GetOrderTypeString(orderType) + "\",";
         json += "\"lots\":" + DoubleToString(OrderLots(), 2) + ",";
         json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), 5) + ",";
         json += "\"currentPrice\":" + DoubleToString(currentPrice, 5) + ",";
         json += "\"sl\":" + DoubleToString(OrderStopLoss(), 5) + ",";
         json += "\"tp\":" + DoubleToString(OrderTakeProfit(), 5) + ",";
         json += "\"profit\":" + DoubleToString(isPending ? 0 : OrderProfit(), 2) + ",";
         json += "\"swap\":" + DoubleToString(isPending ? 0 : OrderSwap(), 2) + ",";
         json += "\"commission\":" + DoubleToString(isPending ? 0 : OrderCommission(), 2) + ",";
         json += "\"openTime\":\"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS) + "\",";
         json += "\"comment\":\"" + OrderComment() + "\",";
         json += "\"magic\":" + IntegerToString(OrderMagicNumber()) + ",";
         json += "\"isPending\":" + (isPending ? "true" : "false");
         json += "}";
      }
   }
   
   json += "]}";
   
   int handle = FileOpen(g_positionsFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Write chart data (historical + current)                           |
//+------------------------------------------------------------------+
void WriteChartData(string symbol, int timeframe, int count)
{
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double bid = MarketInfo(symbol, MODE_BID);
   double ask = MarketInfo(symbol, MODE_ASK);
   
   string json = "{";
   json += "\"type\":\"history\",";
   json += "\"symbol\":\"" + symbol + "\",";
   json += "\"timeframe\":" + IntegerToString(timeframe) + ",";
   json += "\"bid\":" + DoubleToString(bid, digits) + ",";
   json += "\"ask\":" + DoubleToString(ask, digits) + ",";
   json += "\"candles\":[";
   
   int available = iBars(symbol, timeframe);
   int barsToGet = MathMin(count, available);
   
   bool first = true;
   for(int i = barsToGet - 1; i >= 0; i--)
   {
      if(!first) json += ",";
      first = false;
      
      datetime barTime = iTime(symbol, timeframe, i);
      double open = iOpen(symbol, timeframe, i);
      double high = iHigh(symbol, timeframe, i);
      double low = iLow(symbol, timeframe, i);
      double close = iClose(symbol, timeframe, i);
      
      json += "{";
      json += "\"time\":" + IntegerToString((long)barTime) + ",";
      json += "\"open\":" + DoubleToString(open, digits) + ",";
      json += "\"high\":" + DoubleToString(high, digits) + ",";
      json += "\"low\":" + DoubleToString(low, digits) + ",";
      json += "\"close\":" + DoubleToString(close, digits);
      json += "}";
   }
   
   json += "]}";
   
   int handle = FileOpen(g_chartFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
   
   Print("Chart data written: ", symbol, " TF:", timeframe, " bars:", barsToGet);
}

//+------------------------------------------------------------------+
//| Write chart update (current candle only)                          |
//+------------------------------------------------------------------+
void WriteChartUpdate()
{
   if(!g_chartSubscribed || g_chartSymbol == "") return;
   
   int digits = (int)MarketInfo(g_chartSymbol, MODE_DIGITS);
   
   datetime barTime = iTime(g_chartSymbol, g_chartTimeframe, 0);
   double open = iOpen(g_chartSymbol, g_chartTimeframe, 0);
   double high = iHigh(g_chartSymbol, g_chartTimeframe, 0);
   double low = iLow(g_chartSymbol, g_chartTimeframe, 0);
   double close = iClose(g_chartSymbol, g_chartTimeframe, 0);
   
   string json = "{";
   json += "\"type\":\"update\",";
   json += "\"symbol\":\"" + g_chartSymbol + "\",";
   json += "\"timeframe\":" + IntegerToString(g_chartTimeframe) + ",";
   json += "\"candle\":{";
   json += "\"time\":" + IntegerToString((long)barTime) + ",";
   json += "\"open\":" + DoubleToString(open, digits) + ",";
   json += "\"high\":" + DoubleToString(high, digits) + ",";
   json += "\"low\":" + DoubleToString(low, digits) + ",";
   json += "\"close\":" + DoubleToString(close, digits);
   json += "}}";
   
   int handle = FileOpen(g_chartFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Convert timeframe string to MT4 period                            |
//+------------------------------------------------------------------+
int StringToTimeframe(string tf)
{
   if(tf == "M1" || tf == "1") return PERIOD_M1;
   if(tf == "M5" || tf == "5") return PERIOD_M5;
   if(tf == "M15" || tf == "15") return PERIOD_M15;
   if(tf == "M30" || tf == "30") return PERIOD_M30;
   if(tf == "H1" || tf == "60") return PERIOD_H1;
   if(tf == "H4" || tf == "240") return PERIOD_H4;
   if(tf == "D1" || tf == "D") return PERIOD_D1;
   if(tf == "W1" || tf == "W") return PERIOD_W1;
   if(tf == "MN1" || tf == "MN") return PERIOD_MN1;
   return PERIOD_M15;
}

//+------------------------------------------------------------------+
//| Check and process commands                                        |
//+------------------------------------------------------------------+
void CheckAndProcessCommands()
{
   if(!FileIsExist(g_commandFile, FILE_COMMON)) return;
   
   int handle = FileOpen(g_commandFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE) return;
   
   string content = "";
   while(!FileIsEnding(handle)) content += FileReadString(handle);
   FileClose(handle);
   
   if(StringLen(content) < 5)
   {
      FileDelete(g_commandFile, FILE_COMMON);
      return;
   }
   
   // Use content hash to avoid duplicate processing
   if(content == g_lastCommandHash) return;
   g_lastCommandHash = content;
   
   Print("Processing command: ", content);
   ProcessCommand(content);
   
   FileDelete(g_commandFile, FILE_COMMON);
}

//+------------------------------------------------------------------+
//| Process command                                                   |
//+------------------------------------------------------------------+
void ProcessCommand(string jsonCommand)
{
   string action = ExtractJsonString(jsonCommand, "action");
   if(action == "") return;
   
   if(action == "place_order")
   {
      PlaceOrder(
         ExtractJsonString(jsonCommand, "symbol"),
         ExtractJsonString(jsonCommand, "type"),
         StringToDouble(ExtractJsonString(jsonCommand, "lots")),
         StringToDouble(ExtractJsonString(jsonCommand, "sl")),
         StringToDouble(ExtractJsonString(jsonCommand, "tp")),
         StringToDouble(ExtractJsonString(jsonCommand, "price")),
         (int)StringToInteger(ExtractJsonString(jsonCommand, "magic"))
      );
   }
   else if(action == "close_position")
   {
      int ticket = (int)StringToInteger(ExtractJsonString(jsonCommand, "ticket"));
      Print("CLOSE COMMAND: ticket=", ticket);
      ClosePosition(ticket);
   }
   else if(action == "modify_position")
   {
      int ticket = (int)StringToInteger(ExtractJsonString(jsonCommand, "ticket"));
      double sl = StringToDouble(ExtractJsonString(jsonCommand, "sl"));
      double tp = StringToDouble(ExtractJsonString(jsonCommand, "tp"));
      Print("MODIFY COMMAND: ticket=", ticket, " sl=", sl, " tp=", tp);
      ModifyPosition(ticket, sl, tp);
   }
   else if(action == "get_chart_data")
   {
      string symbol = ExtractJsonString(jsonCommand, "symbol");
      string tf = ExtractJsonString(jsonCommand, "timeframe");
      int count = (int)StringToInteger(ExtractJsonString(jsonCommand, "count"));
      if(count <= 0) count = 200;
      
      // Ensure symbol is in Market Watch
      SymbolSelect(symbol, true);
      
      int timeframe = StringToTimeframe(tf);
      Print("CHART DATA: symbol=", symbol, " tf=", tf, " (", timeframe, ") count=", count);
      WriteChartData(symbol, timeframe, count);
   }
   else if(action == "subscribe_chart")
   {
      g_chartSymbol = ExtractJsonString(jsonCommand, "symbol");
      string tf = ExtractJsonString(jsonCommand, "timeframe");
      g_chartTimeframe = StringToTimeframe(tf);
      Print("CHART SUBSCRIBE: symbol=", g_chartSymbol, " tf=", g_chartTimeframe);
      
      // Send initial history data
      WriteChartData(g_chartSymbol, g_chartTimeframe, 200);
      
      // Start subscription but delay updates for ~2 seconds (4 timer cycles at 500ms)
      // This gives the bridge time to read the history data
      g_chartDelayCount = 4;
      g_chartSubscribed = true;
   }
   else if(action == "unsubscribe_chart")
   {
      g_chartSubscribed = false;
      g_chartSymbol = "";
      Print("CHART UNSUBSCRIBE");
   }
   else if(action == "get_history")
   {
      string period = ExtractJsonString(jsonCommand, "period"); // today, week, month
      Print("HISTORY REQUEST: period=", period);
      WriteHistory(period);
   }
}

//+------------------------------------------------------------------+
//| Write closed positions history                                     |
//+------------------------------------------------------------------+
void WriteHistory(string period)
{
   datetime startTime;
   datetime now = TimeCurrent();
   
   // Calculate start time based on period
   if(period == "today")
   {
      // Start of today (midnight)
      startTime = now - (now % 86400);
   }
   else if(period == "week")
   {
      // 7 days ago
      startTime = now - (7 * 86400);
   }
   else if(period == "month")
   {
      // 30 days ago
      startTime = now - (30 * 86400);
   }
   else
   {
      // Default to today
      startTime = now - (now % 86400);
   }
   
   string json = "{\"index\":" + IntegerToString(g_terminalIndex) + ",";
   json += "\"account\":\"" + IntegerToString(AccountNumber()) + "\",";
   json += "\"period\":\"" + period + "\",";
   json += "\"history\":[";
   
   int count = 0;
   int total = OrdersHistoryTotal();
   
   for(int i = total - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      
      // Only include orders closed after start time
      if(OrderCloseTime() < startTime) continue;
      
      // Only include actual trades (buy/sell), not pending orders
      if(OrderType() > OP_SELL) continue;
      
      if(count > 0) json += ",";
      
      json += "{";
      json += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
      json += "\"symbol\":\"" + OrderSymbol() + "\",";
      json += "\"type\":\"" + GetOrderTypeString(OrderType()) + "\",";
      json += "\"lots\":" + DoubleToString(OrderLots(), 2) + ",";
      json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS)) + ",";
      json += "\"closePrice\":" + DoubleToString(OrderClosePrice(), (int)MarketInfo(OrderSymbol(), MODE_DIGITS)) + ",";
      json += "\"openTime\":" + IntegerToString((int)OrderOpenTime()) + ",";
      json += "\"closeTime\":" + IntegerToString((int)OrderCloseTime()) + ",";
      json += "\"profit\":" + DoubleToString(OrderProfit(), 2) + ",";
      json += "\"swap\":" + DoubleToString(OrderSwap(), 2) + ",";
      json += "\"commission\":" + DoubleToString(OrderCommission(), 2) + ",";
      json += "\"magic\":" + IntegerToString(OrderMagicNumber());
      json += "}";
      
      count++;
      
      // Limit to 500 trades to avoid huge files
      if(count >= 500) break;
   }
   
   json += "]}";
   
   // Write to history file
   string filename = BridgeFolder + "\\history_" + IntegerToString(g_terminalIndex) + ".json";
   int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
      Print("History written: ", count, " trades for period ", period);
   }
}

//+------------------------------------------------------------------+
//| Place order                                                       |
//+------------------------------------------------------------------+
void PlaceOrder(string symbol, string type, double lots, double sl, double tp, double pendingPrice, int magic)
{
   // Ensure symbol is in Market Watch
   if(!SymbolSelect(symbol, true))
   {
      Print("Warning: Could not add symbol to Market Watch: ", symbol);
   }
   
   // Wait a moment for symbol data to load
   Sleep(100);
   RefreshRates();
   
   int orderType;
   double price;
   color arrowColor;
   bool isPending = false;
   
   // Market orders
   if(type == "buy") { orderType = OP_BUY; price = MarketInfo(symbol, MODE_ASK); arrowColor = clrGreen; }
   else if(type == "sell") { orderType = OP_SELL; price = MarketInfo(symbol, MODE_BID); arrowColor = clrRed; }
   // Pending orders
   else if(type == "buy_limit") { orderType = OP_BUYLIMIT; price = pendingPrice; arrowColor = clrGreen; isPending = true; }
   else if(type == "sell_limit") { orderType = OP_SELLLIMIT; price = pendingPrice; arrowColor = clrRed; isPending = true; }
   else if(type == "buy_stop") { orderType = OP_BUYSTOP; price = pendingPrice; arrowColor = clrGreen; isPending = true; }
   else if(type == "sell_stop") { orderType = OP_SELLSTOP; price = pendingPrice; arrowColor = clrRed; isPending = true; }
   else { WriteResponse(false, "Invalid order type: " + type, 0); return; }
   
   // Check if symbol data is available
   if(MarketInfo(symbol, MODE_BID) == 0)
   {
      // Try waiting a bit longer for data
      Sleep(500);
      RefreshRates();
      if(MarketInfo(symbol, MODE_BID) == 0)
      {
         WriteResponse(false, "Symbol not available: " + symbol, 0);
         return;
      }
   }
   
   // For pending orders, validate the price
   if(isPending && pendingPrice <= 0)
   {
      WriteResponse(false, "Invalid pending order price", 0);
      return;
   }
   
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   lots = NormalizeDouble(MathRound(MathMax(minLot, MathMin(maxLot, lots)) / lotStep) * lotStep, 2);
   
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   price = NormalizeDouble(price, digits);
   if(sl > 0) sl = NormalizeDouble(sl, digits);
   if(tp > 0) tp = NormalizeDouble(tp, digits);
   
   int ticket = OrderSend(symbol, orderType, lots, price, 30, sl, tp, "MetaSynx", magic, 0, arrowColor);
   
   string orderTypeStr = isPending ? type : (type == "buy" ? "market buy" : "market sell");
   if(ticket > 0) { WriteResponse(true, "Order placed", ticket); Print("Order placed (", orderTypeStr, "): ", ticket); }
   else { int err = GetLastError(); WriteResponse(false, "Error " + IntegerToString(err), 0); Print("Order failed: ", err); }
}

//+------------------------------------------------------------------+
//| Close position                                                    |
//+------------------------------------------------------------------+
void ClosePosition(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("CLOSE FAILED: Ticket not found: ", ticket);
      WriteResponse(false, "Ticket not found", ticket);
      return;
   }
   
   if(OrderCloseTime() != 0)
   {
      Print("CLOSE FAILED: Already closed: ", ticket);
      WriteResponse(false, "Already closed", ticket);
      return;
   }
   
   RefreshRates();
   
   string symbol = OrderSymbol();
   double lots = OrderLots();
   int orderType = OrderType();
   double price = orderType == OP_BUY ? MarketInfo(symbol, MODE_BID) : MarketInfo(symbol, MODE_ASK);
   price = NormalizeDouble(price, (int)MarketInfo(symbol, MODE_DIGITS));
   
   Print("CLOSING: ticket=", ticket, " symbol=", symbol, " lots=", lots, " price=", price);
   
   bool result = OrderClose(ticket, lots, price, 30, clrYellow);
   
   if(result)
   {
      Print("CLOSE SUCCESS: ", ticket);
      WriteResponse(true, "Closed", ticket);
   }
   else
   {
      int err = GetLastError();
      Print("CLOSE FAILED: ", ticket, " error=", err);
      WriteResponse(false, "Error " + IntegerToString(err), ticket);
   }
}

//+------------------------------------------------------------------+
//| Modify position                                                   |
//| sl/tp: -1 = keep existing, 0 = remove, >0 = set new value        |
//+------------------------------------------------------------------+
void ModifyPosition(int ticket, double sl, double tp)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Print("MODIFY FAILED: Ticket not found: ", ticket);
      WriteResponse(false, "Ticket not found", ticket);
      return;
   }
   
   if(OrderCloseTime() != 0)
   {
      Print("MODIFY FAILED: Already closed: ", ticket);
      WriteResponse(false, "Already closed", ticket);
      return;
   }
   
   int digits = (int)MarketInfo(OrderSymbol(), MODE_DIGITS);
   
   // -1 means keep existing, 0 means remove, >0 means set new value
   double newSL;
   if(sl < 0) newSL = OrderStopLoss();        // Keep existing
   else if(sl == 0) newSL = 0;                 // Remove SL
   else newSL = NormalizeDouble(sl, digits);   // Set new value
   
   double newTP;
   if(tp < 0) newTP = OrderTakeProfit();       // Keep existing
   else if(tp == 0) newTP = 0;                 // Remove TP
   else newTP = NormalizeDouble(tp, digits);   // Set new value
   
   Print("MODIFYING: ticket=", ticket, " newSL=", newSL, " newTP=", newTP);
   
   bool result = OrderModify(ticket, OrderOpenPrice(), newSL, newTP, 0, clrBlue);
   
   if(result)
   {
      Print("MODIFY SUCCESS: ", ticket);
      WriteResponse(true, "Modified", ticket);
   }
   else
   {
      int err = GetLastError();
      if(err == 1) { WriteResponse(true, "No change needed", ticket); }
      else { Print("MODIFY FAILED: ", ticket, " error=", err); WriteResponse(false, "Error " + IntegerToString(err), ticket); }
   }
}

//+------------------------------------------------------------------+
//| Write response                                                    |
//+------------------------------------------------------------------+
void WriteResponse(bool success, string message, int ticket)
{
   string json = "{\"index\":" + IntegerToString(g_terminalIndex) + ",";
   json += "\"account\":\"" + IntegerToString(AccountNumber()) + "\",";
   json += "\"success\":" + (success ? "true" : "false") + ",";
   json += "\"message\":\"" + message + "\",";
   json += "\"ticket\":" + IntegerToString(ticket) + "}";
   
   int handle = FileOpen(g_responseFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE) { FileWriteString(handle, json); FileClose(handle); }
}

//+------------------------------------------------------------------+
//| Extract JSON string                                               |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json, searchKey);
   if(pos < 0) return "";
   
   int valueStart = pos + StringLen(searchKey);
   while(valueStart < StringLen(json) && StringGetCharacter(json, valueStart) == ' ') valueStart++;
   if(valueStart >= StringLen(json)) return "";
   
   if(StringGetCharacter(json, valueStart) == '"')
   {
      valueStart++;
      int valueEnd = StringFind(json, "\"", valueStart);
      if(valueEnd > valueStart) return StringSubstr(json, valueStart, valueEnd - valueStart);
   }
   else
   {
      int valueEnd = valueStart;
      while(valueEnd < StringLen(json))
      {
         ushort c = StringGetCharacter(json, valueEnd);
         if(c == ',' || c == '}' || c == ' ' || c == '\n' || c == '\r') break;
         valueEnd++;
      }
      return StringSubstr(json, valueStart, valueEnd - valueStart);
   }
   return "";
}

//+------------------------------------------------------------------+
//| Get order type string                                             |
//+------------------------------------------------------------------+
string GetOrderTypeString(int type)
{
   switch(type)
   {
      case OP_BUY: return "buy";
      case OP_SELL: return "sell";
      case OP_BUYLIMIT: return "buy_limit";
      case OP_SELLLIMIT: return "sell_limit";
      case OP_BUYSTOP: return "buy_stop";
      case OP_SELLSTOP: return "sell_stop";
      default: return "unknown";
   }
}

void OnTick() { }