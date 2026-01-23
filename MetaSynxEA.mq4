//+------------------------------------------------------------------+
//|                                                  MetaSynxEA.mq4  |
//|                                          MetaSynx Bridge Client  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "MetaSynx"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Configuration                                                     |
//+------------------------------------------------------------------+
input string   BridgeFolder = "MetaSynx";  // Folder for bridge communication
input int      UpdateIntervalMs = 1000;     // Update interval in milliseconds

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
string g_dataPath;
string g_commandFile;
string g_responseFile;
string g_statusFile;
int    g_terminalIndex = -1;
datetime g_lastCommandCheck = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Set up file paths in common data folder
   g_dataPath = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + BridgeFolder + "\\";
   
   // Create directory if it doesn't exist
   if(!FolderCreate(BridgeFolder, FILE_COMMON))
   {
      // Folder might already exist, that's OK
   }
   
   // Determine terminal index based on account number
   g_terminalIndex = GetTerminalIndex();
   
   // Set up file names
   g_statusFile = g_dataPath + "status_" + IntegerToString(g_terminalIndex) + ".json";
   g_commandFile = g_dataPath + "commands.json";
   g_responseFile = g_dataPath + "response_" + IntegerToString(g_terminalIndex) + ".json";
   
   Print("MetaSynx EA initialized");
   Print("Terminal Index: ", g_terminalIndex);
   Print("Data Path: ", g_dataPath);
   Print("Account: ", AccountNumber());
   
   // Write initial status
   WriteAccountStatus();
   
   // Set timer for regular updates
   EventSetMillisecondTimer(UpdateIntervalMs);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   
   // Clean up status file on exit
   if(FileIsExist(BridgeFolder + "\\status_" + IntegerToString(g_terminalIndex) + ".json", FILE_COMMON))
   {
      FileDelete(BridgeFolder + "\\status_" + IntegerToString(g_terminalIndex) + ".json", FILE_COMMON);
   }
   
   Print("MetaSynx EA deinitialized");
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Update account status
   WriteAccountStatus();
   
   // Check for commands
   CheckAndProcessCommands();
}

//+------------------------------------------------------------------+
//| Get unique terminal index based on account                        |
//+------------------------------------------------------------------+
int GetTerminalIndex()
{
   // Use account number to create a simple index
   // In production, you might want a more sophisticated method
   long accountNum = AccountNumber();
   
   // Read existing terminals to find our index or assign new one
   string indexFile = BridgeFolder + "\\terminal_index.json";
   
   int handle = FileOpen(indexFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      string content = "";
      while(!FileIsEnding(handle))
      {
         content += FileReadString(handle);
      }
      FileClose(handle);
      
      // Parse to find existing index for this account
      // Simple parsing - look for our account number
      string searchStr = "\"" + IntegerToString(accountNum) + "\":";
      int pos = StringFind(content, searchStr);
      if(pos >= 0)
      {
         int indexStart = pos + StringLen(searchStr);
         int indexEnd = StringFind(content, ",", indexStart);
         if(indexEnd < 0) indexEnd = StringFind(content, "}", indexStart);
         if(indexEnd > indexStart)
         {
            string indexStr = StringSubstr(content, indexStart, indexEnd - indexStart);
            return (int)StringToInteger(indexStr);
         }
      }
   }
   
   // Assign new index (0-9)
   for(int i = 0; i < 10; i++)
   {
      string statusFile = BridgeFolder + "\\status_" + IntegerToString(i) + ".json";
      if(!FileIsExist(statusFile, FILE_COMMON))
      {
         // Save index mapping
         SaveTerminalIndex(accountNum, i);
         return i;
      }
   }
   
   return 0; // Fallback
}

//+------------------------------------------------------------------+
//| Save terminal index mapping                                       |
//+------------------------------------------------------------------+
void SaveTerminalIndex(long accountNum, int index)
{
   string indexFile = BridgeFolder + "\\terminal_index.json";
   string content = "";
   
   // Read existing content
   int handle = FileOpen(indexFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      while(!FileIsEnding(handle))
      {
         content += FileReadString(handle);
      }
      FileClose(handle);
   }
   
   // Add or update our entry
   if(StringLen(content) < 2)
   {
      content = "{\"" + IntegerToString(accountNum) + "\":" + IntegerToString(index) + "}";
   }
   else
   {
      // Insert before closing brace
      int closePos = StringFind(content, "}");
      if(closePos > 0)
      {
         content = StringSubstr(content, 0, closePos) + ",\"" + IntegerToString(accountNum) + "\":" + IntegerToString(index) + "}";
      }
   }
   
   // Write back
   handle = FileOpen(indexFile, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, content);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Write account status to file                                      |
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
   
   string fileName = BridgeFolder + "\\status_" + IntegerToString(g_terminalIndex) + ".json";
   int handle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
   else
   {
      Print("Error writing status file: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Check and process commands from bridge                            |
//+------------------------------------------------------------------+
void CheckAndProcessCommands()
{
   string commandFile = BridgeFolder + "\\commands.json";
   
   if(!FileIsExist(commandFile, FILE_COMMON))
      return;
   
   // Check file modification time
   datetime fileTime = (datetime)FileGetInteger(commandFile, FILE_MODIFY_DATE, FILE_COMMON);
   if(fileTime <= g_lastCommandCheck)
      return;
   
   g_lastCommandCheck = fileTime;
   
   // Read command file
   int handle = FileOpen(commandFile, FILE_READ|FILE_TXT|FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return;
   
   string content = "";
   while(!FileIsEnding(handle))
   {
      content += FileReadString(handle);
   }
   FileClose(handle);
   
   if(StringLen(content) < 5)
      return;
   
   // Parse and process command
   ProcessCommand(content);
}

//+------------------------------------------------------------------+
//| Process a command from the bridge                                 |
//+------------------------------------------------------------------+
void ProcessCommand(string jsonCommand)
{
   Print("Processing command: ", jsonCommand);
   
   // Extract action
   string action = ExtractJsonString(jsonCommand, "action");
   
   if(action == "")
      return;
   
   // Check if this command is for us (check targetIndex or targetAll)
   string targetIndexStr = ExtractJsonString(jsonCommand, "targetIndex");
   bool targetAll = (StringFind(jsonCommand, "\"targetAll\":true") >= 0);
   
   if(!targetAll && targetIndexStr != "")
   {
      int targetIndex = (int)StringToInteger(targetIndexStr);
      if(targetIndex != g_terminalIndex)
         return; // Not for us
   }
   
   // Process based on action
   if(action == "get_positions")
   {
      WritePositions();
   }
   else if(action == "place_order")
   {
      string symbol = ExtractJsonString(jsonCommand, "symbol");
      string type = ExtractJsonString(jsonCommand, "type");
      double lots = StringToDouble(ExtractJsonString(jsonCommand, "lots"));
      double sl = StringToDouble(ExtractJsonString(jsonCommand, "sl"));
      double tp = StringToDouble(ExtractJsonString(jsonCommand, "tp"));
      
      PlaceOrder(symbol, type, lots, sl, tp);
   }
   else if(action == "close_position")
   {
      int ticket = (int)StringToInteger(ExtractJsonString(jsonCommand, "ticket"));
      ClosePosition(ticket);
   }
   else if(action == "modify_position")
   {
      int ticket = (int)StringToInteger(ExtractJsonString(jsonCommand, "ticket"));
      double sl = StringToDouble(ExtractJsonString(jsonCommand, "sl"));
      double tp = StringToDouble(ExtractJsonString(jsonCommand, "tp"));
      
      ModifyPosition(ticket, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Write open positions to file                                      |
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
         
         json += "{";
         json += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
         json += "\"symbol\":\"" + OrderSymbol() + "\",";
         json += "\"type\":\"" + GetOrderTypeString(OrderType()) + "\",";
         json += "\"lots\":" + DoubleToString(OrderLots(), 2) + ",";
         json += "\"openPrice\":" + DoubleToString(OrderOpenPrice(), 5) + ",";
         json += "\"currentPrice\":" + DoubleToString(OrderType() == OP_BUY ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK), 5) + ",";
         json += "\"sl\":" + DoubleToString(OrderStopLoss(), 5) + ",";
         json += "\"tp\":" + DoubleToString(OrderTakeProfit(), 5) + ",";
         json += "\"profit\":" + DoubleToString(OrderProfit(), 2) + ",";
         json += "\"swap\":" + DoubleToString(OrderSwap(), 2) + ",";
         json += "\"commission\":" + DoubleToString(OrderCommission(), 2) + ",";
         json += "\"openTime\":\"" + TimeToString(OrderOpenTime(), TIME_DATE|TIME_SECONDS) + "\",";
         json += "\"comment\":\"" + OrderComment() + "\",";
         json += "\"magic\":" + IntegerToString(OrderMagicNumber());
         json += "}";
      }
   }
   
   json += "]}";
   
   string fileName = BridgeFolder + "\\positions_" + IntegerToString(g_terminalIndex) + ".json";
   int handle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Place a new order                                                 |
//+------------------------------------------------------------------+
void PlaceOrder(string symbol, string type, double lots, double sl, double tp)
{
   int orderType;
   double price;
   
   if(type == "buy")
   {
      orderType = OP_BUY;
      price = MarketInfo(symbol, MODE_ASK);
   }
   else if(type == "sell")
   {
      orderType = OP_SELL;
      price = MarketInfo(symbol, MODE_BID);
   }
   else
   {
      WriteResponse(false, "Invalid order type: " + type, 0);
      return;
   }
   
   // Validate symbol
   if(MarketInfo(symbol, MODE_BID) == 0)
   {
      WriteResponse(false, "Invalid symbol: " + symbol, 0);
      return;
   }
   
   int ticket = OrderSend(symbol, orderType, lots, price, 3, sl, tp, "MetaSynx", 0, 0, clrNONE);
   
   if(ticket > 0)
   {
      WriteResponse(true, "Order placed successfully", ticket);
      Print("Order placed: ", symbol, " ", type, " ", lots, " lots, ticket: ", ticket);
   }
   else
   {
      int error = GetLastError();
      WriteResponse(false, "Order failed: " + IntegerToString(error) + " - " + ErrorDescription(error), 0);
      Print("Order failed: ", error, " - ", ErrorDescription(error));
   }
}

//+------------------------------------------------------------------+
//| Close a position                                                  |
//+------------------------------------------------------------------+
void ClosePosition(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      WriteResponse(false, "Ticket not found: " + IntegerToString(ticket), 0);
      return;
   }
   
   double price = OrderType() == OP_BUY ? MarketInfo(OrderSymbol(), MODE_BID) : MarketInfo(OrderSymbol(), MODE_ASK);
   
   bool result = OrderClose(ticket, OrderLots(), price, 3, clrNONE);
   
   if(result)
   {
      WriteResponse(true, "Position closed successfully", ticket);
      Print("Position closed: ", ticket);
   }
   else
   {
      int error = GetLastError();
      WriteResponse(false, "Close failed: " + IntegerToString(error) + " - " + ErrorDescription(error), ticket);
      Print("Close failed: ", error, " - ", ErrorDescription(error));
   }
}

//+------------------------------------------------------------------+
//| Modify a position                                                 |
//+------------------------------------------------------------------+
void ModifyPosition(int ticket, double sl, double tp)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      WriteResponse(false, "Ticket not found: " + IntegerToString(ticket), 0);
      return;
   }
   
   bool result = OrderModify(ticket, OrderOpenPrice(), sl, tp, 0, clrNONE);
   
   if(result)
   {
      WriteResponse(true, "Position modified successfully", ticket);
      Print("Position modified: ", ticket);
   }
   else
   {
      int error = GetLastError();
      WriteResponse(false, "Modify failed: " + IntegerToString(error) + " - " + ErrorDescription(error), ticket);
      Print("Modify failed: ", error, " - ", ErrorDescription(error));
   }
}

//+------------------------------------------------------------------+
//| Write response to file                                            |
//+------------------------------------------------------------------+
void WriteResponse(bool success, string message, int ticket)
{
   string json = "{";
   json += "\"index\":" + IntegerToString(g_terminalIndex) + ",";
   json += "\"success\":" + (success ? "true" : "false") + ",";
   json += "\"message\":\"" + message + "\",";
   json += "\"ticket\":" + IntegerToString(ticket) + ",";
   json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\"";
   json += "}";
   
   string fileName = BridgeFolder + "\\response_" + IntegerToString(g_terminalIndex) + ".json";
   int handle = FileOpen(fileName, FILE_WRITE|FILE_TXT|FILE_COMMON);
   if(handle != INVALID_HANDLE)
   {
      FileWriteString(handle, json);
      FileClose(handle);
   }
}

//+------------------------------------------------------------------+
//| Extract string value from JSON                                    |
//+------------------------------------------------------------------+
string ExtractJsonString(string json, string key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json, searchKey);
   if(pos < 0)
      return "";
   
   int valueStart = pos + StringLen(searchKey);
   
   // Skip whitespace
   while(valueStart < StringLen(json) && StringGetCharacter(json, valueStart) == ' ')
      valueStart++;
   
   if(valueStart >= StringLen(json))
      return "";
   
   // Check if value is quoted string or number
   if(StringGetCharacter(json, valueStart) == '"')
   {
      valueStart++;
      int valueEnd = StringFind(json, "\"", valueStart);
      if(valueEnd > valueStart)
         return StringSubstr(json, valueStart, valueEnd - valueStart);
   }
   else
   {
      // Number or boolean
      int valueEnd = valueStart;
      while(valueEnd < StringLen(json))
      {
         ushort c = StringGetCharacter(json, valueEnd);
         if(c == ',' || c == '}' || c == ' ' || c == '\n' || c == '\r')
            break;
         valueEnd++;
      }
      return StringSubstr(json, valueStart, valueEnd - valueStart);
   }
   
   return "";
}

//+------------------------------------------------------------------+
//| Get order type as string                                          |
//+------------------------------------------------------------------+
string GetOrderTypeString(int type)
{
   switch(type)
   {
      case OP_BUY:       return "buy";
      case OP_SELL:      return "sell";
      case OP_BUYLIMIT:  return "buy_limit";
      case OP_SELLLIMIT: return "sell_limit";
      case OP_BUYSTOP:   return "buy_stop";
      case OP_SELLSTOP:  return "sell_stop";
      default:           return "unknown";
   }
}

//+------------------------------------------------------------------+
//| Error description                                                 |
//+------------------------------------------------------------------+
string ErrorDescription(int error)
{
   switch(error)
   {
      case 0:   return "No error";
      case 1:   return "No error but result unknown";
      case 2:   return "Common error";
      case 3:   return "Invalid trade parameters";
      case 4:   return "Trade server is busy";
      case 5:   return "Old version of client terminal";
      case 6:   return "No connection with trade server";
      case 7:   return "Not enough rights";
      case 8:   return "Too frequent requests";
      case 9:   return "Malfunctional trade operation";
      case 64:  return "Account disabled";
      case 65:  return "Invalid account";
      case 128: return "Trade timeout";
      case 129: return "Invalid price";
      case 130: return "Invalid stops";
      case 131: return "Invalid trade volume";
      case 132: return "Market is closed";
      case 133: return "Trade is disabled";
      case 134: return "Not enough money";
      case 135: return "Price changed";
      case 136: return "Off quotes";
      case 137: return "Broker is busy";
      case 138: return "Requote";
      case 139: return "Order is locked";
      case 140: return "Buy orders only allowed";
      case 141: return "Too many requests";
      case 145: return "Modification denied because order is too close to market";
      case 146: return "Trade context is busy";
      case 147: return "Expirations are denied by broker";
      case 148: return "Number of open and pending orders has reached the limit";
      case 149: return "Hedging is prohibited";
      case 150: return "Prohibited by FIFO rules";
      default:  return "Unknown error";
   }
}

//+------------------------------------------------------------------+
//| Tick function (not used but required)                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Status updates handled by timer
}
//+------------------------------------------------------------------+