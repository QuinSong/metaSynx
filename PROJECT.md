# MetaSynx - Multi-Terminal MT4 Trade Copier & Manager

## Project Overview

MetaSynx is a mobile-first trade management system that allows controlling multiple MT4 terminals from a single mobile app. It consists of three main components that communicate via a WebSocket relay server.

**Key Features:**
- Monitor multiple MT4 accounts in real-time
- Place market, limit, and stop orders across multiple terminals simultaneously
- Close/modify positions with live P/L updates
- Partial position close with lot ratio support
- Risk calculator with broker pip values
- TradingView-style charts with live MT4 data and position lines
- Pending order management (cancel/modify)
- Trade history with filtering
- Proportional lot sizing across accounts
- QR code pairing for secure connection
- Bottom navigation bar for easy screen switching

---

## Architecture

```
┌─────────────────┐     WebSocket      ┌──────────────────┐     File I/O      ┌─────────────────┐
│   Mobile App    │◄──────────────────►│  Windows Bridge  │◄────────────────►│   MT4 EA(s)     │
│   (Flutter)     │                    │   (Flutter)      │                   │   (MQL4)        │
└─────────────────┘                    └──────────────────┘                   └─────────────────┘
        │                                      │
        │                                      │
        ▼                                      ▼
┌─────────────────┐                    ┌──────────────────┐
│  Relay Server   │◄──────────────────►│  MT4 Common      │
│  (FastAPI)      │     WebSocket      │  Files Folder    │
└─────────────────┘                    └──────────────────┘
```

### Communication Flow

1. **Mobile ↔ Relay Server ↔ Windows Bridge**: WebSocket messages (JSON)
2. **Windows Bridge ↔ MT4 EA**: File-based communication in MT4 Common Files folder
   - `status_X.json` - Account info (balance, equity, margin)
   - `positions_X.json` - Open positions and pending orders
   - `command_X.json` - Commands from app (orders, close, modify, cancel)
   - `response_X.json` - Command results and symbol info
   - `chart_X.json` - OHLC candle data for charts
   - `history_X.json` - Trade history
   - `terminal_index.json` - Maps account numbers to terminal indices

---

## Folder Structure

```
metaSynx/
├── app/                          # Mobile App (Flutter - iOS/Android)
│   ├── android/                  # Android platform files
│   ├── ios/                      # iOS platform files
│   └── lib/
│       ├── main.dart             # App entry point
│       ├── core/
│       │   └── theme.dart        # Colors, text styles, constants
│       ├── components/
│       │   ├── connection_card.dart       # Connection status card
│       │   ├── qr_scanner_overlay.dart    # QR scanner overlay widget
│       │   └── scan_button.dart           # Scan button component
│       ├── screens/
│       │   ├── screens.dart               # Barrel export file
│       │   ├── home.dart                  # Main screen - accounts, nav bar
│       │   ├── account.dart               # Account detail - positions/orders
│       │   ├── position.dart              # Position detail - close/modify
│       │   ├── new_order.dart             # Place new orders (market/limit/stop)
│       │   ├── chart.dart                 # Live MT4 charts with positions
│       │   ├── history.dart               # Trade history screen
│       │   ├── risk_calculator.dart       # Position sizing calculator
│       │   ├── qr_scanner.dart            # QR code scanner for pairing
│       │   └── settings/
│       │       ├── settings.dart           # Main settings screen
│       │       ├── account_names.dart      # Custom account names
│       │       ├── lot_sizing.dart         # Main account & lot ratios
│       │       ├── symbol_suffixes.dart    # Broker symbol suffixes
│       │       └── preferred_symbols.dart  # Quick-select symbols
│       ├── services/
│       │   └── relay_connection.dart      # WebSocket connection service
│       └── utils/
│           └── formatters.dart            # Number formatting utilities
│
├── win_bridge/                   # Windows Bridge App (Flutter - Windows)
│   ├── windows/                  # Windows platform files
│   └── lib/
│       ├── main.dart             # Bridge app entry point
│       ├── core/
│       │   ├── config.dart       # Server URL, API key
│       │   └── theme.dart        # Windows app theme
│       ├── components/
│       │   ├── components.dart            # Barrel export file
│       │   ├── activity_log.dart          # Activity log widget
│       │   ├── info_row.dart              # Info row component
│       │   ├── mobile_device_card.dart    # Mobile device info card
│       │   ├── paired_status.dart         # Pairing status indicator
│       │   ├── qr_code_display.dart       # QR code display widget
│       │   ├── room_id_display.dart       # Room ID display
│       │   └── status_indicator.dart      # Status indicator component
│       ├── screens/
│       │   └── home_screen.dart           # Main bridge UI
│       └── services/
│           ├── services.dart              # Barrel export file
│           ├── ea_service.dart            # MT4 file communication
│           ├── relay_connection.dart      # WebSocket to relay
│           └── room_service.dart          # Room creation API
│
├── server/                       # Relay Server (Python/FastAPI)
│   ├── websocket_relay.py        # Main relay server
│   └── metasynx-relay.service    # Systemd service file
│
├── MetaSynxEA.mq4                # MT4 Expert Advisor
└── PROJECT.md                    # This documentation file
```

---

## Component Details

### 1. Mobile App (`/app`)

**Main Screen (home.dart)** - 1167 lines
- Bottom navigation bar (Home, Chart, History, Settings)
- Connection status card with QR scanner button
- Lists all connected MT4 accounts with balance/equity/P/L
- Shows total across all accounts
- Calculator icon for risk calculator
- FAB button for new orders
- Sorts accounts with main account first
- App lifecycle handling (pauses polling in background)

**Account Detail (account.dart)** - 1414 lines
- Shows single account's positions and pending orders
- ORDERS section for pending limit/stop orders with cancel/edit buttons
- POSITIONS section with expandable position cards
- Filter by symbol (persisted per account)
- Real-time P/L updates
- Tap left side of card to expand, right side to navigate

**Position Detail (position.dart)** - 1379 lines
- Full position information with gradient header
- Modify SL/TP with validation against current price
- Close position with optional confirmation dialog
- **Partial close** - close portion of position with lot ratio support
- Navigate to chart
- Shows commission/swap if enabled
- P/L percentage display

**New Order (new_order.dart)** - 947 lines
- Symbol input with toggleable suffix
- Buy/Sell buttons
- **Execution mode**: Market, Limit, Stop
- Price field for pending orders
- Lot size with +/- controls
- Optional SL/TP
- Target: specific account, all accounts, or main account only
- Preferred symbols quick-select
- Accepts pre-filled values from risk calculator

**Chart (chart.dart)** - 2443 lines
- Uses TradingView Lightweight Charts via WebView
- **Live MT4 data feed** - real candles from broker
- Position entry lines (green=buy, red=sell) with lot labels
- Pending order lines (dashed, muted colors)
- SL/TP lines
- Bid/Ask price lines (toggleable)
- Spread display
- Tap position lines to navigate to position detail
- Tap pending order lines for edit/cancel popup
- Account selector, timeframe selector (M1-MN)
- Symbol search overlay with recent/popular symbols
- Buy/Sell buttons to open new order screen

**History (history.dart)** - 582 lines
- Period tabs: Today, Week, Month
- Account filter dropdown
- Symbol filter dropdown
- Trade cards showing entry/exit prices, P/L, lots
- Commission/swap display if enabled

**Risk Calculator (risk_calculator.dart)** - 1022 lines
- Account selection with balance display
- Symbol input with suffix toggle
- **Search button** fetches live symbol info from MT4
- Auto-fills entry price with current bid/ask
- SL/TP hint values based on pip distance
- Risk mode: Percentage or Fixed Amount
- Quick risk buttons (0.5%, 1%, 2%, 3%, 5%)
- Calculates position size based on risk
- Displays:
  - Pip value (from broker or estimated)
  - Position size in lots
  - Potential loss/profit
  - SL/TP distance in pips
  - Risk:Reward ratio with visual bar
- Opens New Order screen with calculated values

**Settings (settings/)**
- **settings.dart** (534 lines): Main settings screen with navigation cards
  - Include Commission/Swap toggle
  - Show P/L as % toggle
  - Confirm Before Close toggle
- **account_names.dart** (241 lines): Custom display names for accounts
- **lot_sizing.dart** (444 lines): Set main account + lot ratios
- **symbol_suffixes.dart** (331 lines): Per-account suffixes (e.g., ".pro", "-VIP")
- **preferred_symbols.dart** (424 lines): Quick-select list for new orders

**Services & Utils**
- **relay_connection.dart** (177 lines): WebSocket connection management
- **formatters.dart** (17 lines): Number formatting with thousand separators

### 2. Windows Bridge (`/win_bridge`)

**Purpose**: Bridges WebSocket (relay) to file system (MT4)

**Key Files:**
- **config.dart**: Server URL and API key constants
- **theme.dart** (62 lines): App colors and text styles
- **ea_service.dart** (405 lines): Reads/writes MT4 files, polls for updates
- **relay_connection.dart** (140 lines): WebSocket connection management
- **room_service.dart** (47 lines): Room creation API
- **home_screen.dart** (626 lines): QR code display, connection status, activity log

**Message Handling (in home_screen.dart):**
- `get_accounts` → Reads all `status_X.json` files
- `get_positions` → Reads `positions_X.json` files (includes pending orders)
- `place_order` → Writes to `command_X.json`
- `close_position` → Writes to `command_X.json` (supports partial close)
- `modify_position` → Writes to `command_X.json`
- `cancel_order` → Writes to `command_X.json`
- `modify_pending` → Writes to `command_X.json`
- `get_chart_data` → Writes to `command_X.json`, reads `chart_X.json`
- `get_history` → Writes to `command_X.json`, reads `history_X.json`
- `get_symbol_info` → Writes to `command_X.json`, reads `response_X.json`

### 3. MT4 Expert Advisor (`MetaSynxEA.mq4`)

**Version**: 2.10 (1052 lines)

**Features:**
- Multi-terminal support via unique terminal index
- Writes account status every 500ms
- Writes positions and pending orders every 500ms
- Chart data on request (200 bars history)
- Trade history on request
- Symbol info with pip value for risk calculator
- Auto-adds symbol to Market Watch if needed

**Supported Commands:**
- `place_order` - Market, limit, and stop orders
- `close_position` - Full or partial close
- `modify_position` - Change SL/TP
- `cancel_order` - Cancel pending order
- `modify_pending` - Change pending order price
- `get_chart_data` - Returns OHLC candles
- `get_history` - Returns closed trades
- `get_symbol_info` - Returns pip value, lot constraints, current price

**File Locations:**
All files in: `%APPDATA%\MetaQuotes\Terminal\Common\Files\MetaSynx\`

**Command Format (command_X.json):**
```json
{"action": "place_order", "symbol": "XAUUSD", "type": "buy", "lots": 0.1, "sl": 0, "tp": 0, "magic": 123456}
{"action": "place_order", "symbol": "EURUSD", "type": "buy_limit", "lots": 0.1, "price": 1.0850, "sl": 1.0800, "tp": 1.0950}
{"action": "close_position", "ticket": 12345}
{"action": "close_position", "ticket": 12345, "lots": 0.05}
{"action": "modify_position", "ticket": 12345, "sl": 1.2000, "tp": 1.3000}
{"action": "cancel_order", "ticket": 12345}
{"action": "modify_pending", "ticket": 12345, "price": 1.0860}
{"action": "get_chart_data", "symbol": "EURUSD", "timeframe": "H1", "count": 200}
{"action": "get_history", "period": "week"}
{"action": "get_symbol_info", "symbol": "EURUSD"}
```

**Order Types:**
- `buy` / `sell` - Market orders
- `buy_limit` / `sell_limit` - Limit orders
- `buy_stop` / `sell_stop` - Stop orders

**Modify SL/TP Values:**
- `-1` = Keep existing value
- `0` = Remove SL/TP
- `>0` = Set new value

**Symbol Info Response:**
```json
{
  "type": "symbol_info",
  "symbol": "EURUSD-VIP",
  "valid": true,
  "pipValue": 10.0,
  "pipSize": 0.0001,
  "digits": 5,
  "minLot": 0.01,
  "maxLot": 100.0,
  "lotStep": 0.01,
  "bid": 1.08500,
  "ask": 1.08520,
  "spread": 20
}
```

### 4. Relay Server (`websocket_relay.py`)

**FastAPI WebSocket Relay** (394 lines)

**Endpoints:**
- `POST /ws/relay/create-room` - Creates new room, returns room_id + room_secret
- `GET /ws/relay/room/{room_id}/status` - Check room status
- `WS /ws/relay/{room_id}` - WebSocket connection for room

**Features:**
- Room-based pairing (bridge creates room, mobile joins)
- Secret-based authentication
- Message forwarding between bridge and mobile
- Pairing status notifications
- Auto-cleanup of stale rooms (30 min expiry)
- Rate limiting (max 10 rooms per IP)

---

## Data Models

### Account Status (status_X.json)
```json
{
  "index": 0,
  "account": "12345678",
  "name": "Account Name",
  "broker": "Broker Name",
  "server": "server.broker.com",
  "currency": "USD",
  "balance": 10000.00,
  "equity": 10250.50,
  "margin": 500.00,
  "freeMargin": 9750.50,
  "marginLevel": 2050.10,
  "leverage": 100,
  "openPositions": 3,
  "profit": 250.50,
  "lastUpdate": "2025.01.28 10:30:00",
  "connected": true,
  "tradeAllowed": true
}
```

### Positions (positions_X.json)
```json
{
  "index": 0,
  "positions": [
    {
      "ticket": 12345,
      "symbol": "XAUUSD",
      "type": "buy",
      "lots": 0.10,
      "openPrice": 2650.50000,
      "currentPrice": 2655.00000,
      "sl": 2640.00000,
      "tp": 2670.00000,
      "profit": 45.00,
      "swap": -1.50,
      "commission": -2.00,
      "openTime": "2025.01.28 10:30:00",
      "comment": "",
      "magic": 123456
    },
    {
      "ticket": 12346,
      "symbol": "EURUSD",
      "type": "buy_limit",
      "lots": 0.50,
      "openPrice": 1.08500,
      "currentPrice": 1.08650,
      "sl": 1.08000,
      "tp": 1.09500,
      "profit": 0,
      "swap": 0,
      "commission": 0,
      "openTime": "2025.01.28 11:00:00",
      "comment": "",
      "magic": 123457
    }
  ]
}
```

### Chart Data (chart_X.json)
```json
{
  "index": 0,
  "symbol": "EURUSD",
  "timeframe": "H1",
  "bid": 1.08500,
  "ask": 1.08520,
  "candles": [
    {"time": 1706428800, "open": 1.0845, "high": 1.0860, "low": 1.0840, "close": 1.0855},
    ...
  ]
}
```

### History (history_X.json)
```json
{
  "index": 0,
  "trades": [
    {
      "ticket": 12340,
      "symbol": "XAUUSD",
      "type": "buy",
      "lots": 0.10,
      "openPrice": 2640.00,
      "closePrice": 2660.00,
      "openTime": "2025.01.27 09:00:00",
      "closeTime": "2025.01.27 15:30:00",
      "profit": 200.00,
      "swap": -1.50,
      "commission": -2.00
    }
  ]
}
```

---

## Key Settings (Stored in SharedPreferences)

| Key | Type | Description |
|-----|------|-------------|
| `account_names` | JSON Map | Custom display names for accounts |
| `main_account` | String | Account number of main account for lot sizing |
| `lot_ratios` | JSON Map | Lot multipliers per account (e.g., {"123": 1.0, "456": 0.5}) |
| `symbol_suffixes` | JSON Map | Symbol suffixes per account (e.g., {"123": "-VIP"}) |
| `preferred_pairs` | JSON List | Quick-select symbols for new orders |
| `include_commission_swap` | bool | Include commission/swap in P/L display |
| `show_pl_percent` | bool | Show P/L as percentage of balance |
| `confirm_before_close` | bool | Show confirmation dialog before closing |
| `last_connection` | JSON | Last successful connection config for auto-reconnect |
| `pair_filter_X` | String | Last selected symbol filter for account X |
| `chart_account` | String | Last selected account for chart |
| `chart_symbol` | String | Last selected symbol for chart |
| `chart_timeframe` | String | Last selected timeframe for chart |
| `chart_show_ba` | bool | Show bid/ask lines on chart |
| `calc_symbol` | String | Last symbol used in risk calculator |
| `calc_risk_percent` | String | Last risk % used in calculator |
| `last_lots` | String | Last lot size used in new order |

---

## Color Scheme (theme.dart)

```dart
background: #0a0a0a (near black)
surface: #141414 (dark gray)
surfaceAlt: #1a1a1a (slightly lighter)
primary: #00D4AA (teal/cyan - main accent)
textPrimary: #FFFFFF
textSecondary: #888888
textMuted: #555555
profit/success: #00E676 (green)
loss/error: #FF5252 (red)
warning/info: #FFA726 (orange)
border: #2a2a2a
```

---

## Development Notes

### Symbol Handling
- Symbols include broker suffixes (e.g., "XAUUSD-VIP", "EURUSD.pro")
- Symbol suffixes can be configured per account in settings
- When placing orders, suffix is applied based on target account
- Risk calculator adds suffix when fetching symbol info

### Lot Sizing Logic
When "All Accounts" selected:
1. Main account gets exact lot size entered
2. Other accounts get: `enteredLots * accountRatio`
3. If no ratio set, account uses 1.0 ratio

### Partial Close Logic
1. User enters lots to close in position detail
2. For main account: uses entered lots directly
3. For other accounts: `lotsToClose = enteredLots * lotRatio`
4. Validates lots don't exceed position size
5. EA normalizes to lot step and ensures remaining position >= minLot

### Risk Calculator Flow
1. User selects account and enters symbol
2. Taps "Search" to fetch symbol info from MT4
3. EA adds symbol to Market Watch if needed (with retry)
4. Returns pip value, lot constraints, current price
5. Calculator uses broker pip value (or estimate if unavailable)
6. Calculates: `lotSize = riskAmount / (slPips × pipValue)`
7. Tapping BUY/SELL opens New Order with pre-filled values

### Pending Order Types
| Type | Description | Execution |
|------|-------------|-----------|
| buy_limit | Buy below current price | When price drops to order price |
| sell_limit | Sell above current price | When price rises to order price |
| buy_stop | Buy above current price | When price rises to order price |
| sell_stop | Sell below current price | When price drops to order price |

### Chart Data
- Data fetched directly from MT4 broker
- 200 bars history on load
- Polling every 1 second for updates
- Bid/Ask prices included for spread calculation
- Position lines update in real-time

### Error Handling
- Commands have timeout waiting for EA processing
- Stale status files (>10 seconds old) are ignored
- WebSocket auto-reconnects on disconnect
- Symbol not found returns error from EA
- Invalid positions/orders handled gracefully

---

## Quick Reference - Message Types

### Mobile → Bridge
| Action | Description |
|--------|-------------|
| `ping` | Heartbeat |
| `get_accounts` | Request account list |
| `get_positions` | Request positions and pending orders |
| `place_order` | Place market, limit, or stop order |
| `close_position` | Close position (full or partial) |
| `modify_position` | Modify SL/TP |
| `cancel_order` | Cancel pending order |
| `modify_pending` | Modify pending order price |
| `get_chart_data` | Request candle data |
| `get_history` | Request trade history |
| `get_symbol_info` | Request symbol info for calculator |

### Bridge → Mobile
| Action | Description |
|--------|-------------|
| `pong` | Heartbeat response |
| `accounts_list` | Account data array |
| `positions_list` | Positions and pending orders array |
| `order_result` | Order execution result |
| `chart_data` | OHLC candle data with bid/ask |
| `history_data` | Trade history array |
| `symbol_info` | Symbol info for calculator |

---

## Build & Run

### Mobile App
```bash
cd app
flutter pub get
flutter run
```

### Windows Bridge
```bash
cd win_bridge
flutter pub get
flutter run -d windows
```

### MT4 EA
1. Copy `MetaSynxEA.mq4` to MT4 `Experts` folder
2. Compile in MetaEditor
3. Attach to any chart (one per terminal)
4. Enable "Allow DLL imports" and "Allow live trading"

### Relay Server

**Production Server:** `https://server1.metasynx.io`

See [Server Deployment Guide](#server-deployment-guide) below for full setup instructions.

---

## Server Deployment Guide

Complete instructions for deploying the relay server on a new Google Cloud VM.

### Prerequisites
- Google Cloud VM (Ubuntu 22.04+ recommended)
- Domain pointing to VM IP (e.g., `server1.metasynx.io`)
- SSL certificate (Let's Encrypt)
- Port 443 open in firewall

### Step 1: Set Up SSL Certificate (if not done)
```bash
sudo apt update
sudo apt install certbot -y
sudo certbot certonly --standalone -d YOUR_DOMAIN
```

### Step 2: Copy Files to Server
From your local machine:
```bash
scp server/websocket_relay.py quinsong@34.147.82.105:/tmp/
scp server/metasynx-relay.service quinsong@34.147.82.105:/tmp/
```

### Step 3: SSH and Install
```bash
ssh USERNAME@YOUR_DOMAIN

# Create directory and move files
sudo mkdir -p /opt/metasynx
sudo mv /tmp/websocket_relay.py /opt/metasynx/
sudo mv /tmp/metasynx-relay.service /etc/systemd/system/

# Create virtual environment and install dependencies
sudo python3 -m venv /opt/metasynx/venv
sudo /opt/metasynx/venv/bin/pip install fastapi uvicorn websockets

# Make executable
sudo chmod +x /opt/metasynx/websocket_relay.py
```

### Step 4: Update Configuration
Edit `/opt/metasynx/websocket_relay.py` and update:
```python
SERVER_HOST = "YOUR_DOMAIN"  # e.g., "server1.metasynx.io"
```

Also update the SSL paths in the file if different:
```python
parser.add_argument("--cert", default="/etc/letsencrypt/live/YOUR_DOMAIN/fullchain.pem")
parser.add_argument("--key", default="/etc/letsencrypt/live/YOUR_DOMAIN/privkey.pem")
```

### Step 5: Enable and Start Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable metasynx-relay
sudo systemctl start metasynx-relay
sudo systemctl status metasynx-relay
```

### Step 6: Open Firewall (Google Cloud)
```bash
gcloud compute firewall-rules create allow-https \
    --allow tcp:443 \
    --source-ranges 0.0.0.0/0 \
    --description "Allow HTTPS traffic"
```

### Step 7: Verify
```bash
curl https://YOUR_DOMAIN/health
# Should return: {"status":"healthy"}
```

### Useful Commands
```bash
# View logs
sudo journalctl -u metasynx-relay -f

# Restart service
sudo systemctl restart metasynx-relay

# Stop service
sudo systemctl stop metasynx-relay

# Check status
sudo systemctl status metasynx-relay
```

### Server Configuration

| Setting | Value |
|---------|-------|
| Server URL | `server1.metasynx.io` |
| Port | `443` |
| API Key | `msxkey2026` |
| SSL Cert | `/etc/letsencrypt/live/server1.metasynx.io/fullchain.pem` |
| SSL Key | `/etc/letsencrypt/live/server1.metasynx.io/privkey.pem` |
| Install Path | `/opt/metasynx/` |
| Venv Path | `/opt/metasynx/venv/` |

---

## Line Count Summary

| Component | Lines |
|-----------|-------|
| **Mobile App (Dart)** | |
| - Screens | 11,107 |
| - Core/Services/Components/Utils | 612 |
| **Windows Bridge (Dart)** | 1,221 |
| **MT4 EA (MQL4)** | 1,052 |
| **Relay Server (Python)** | 430 |
| **Total** | ~14,422 |

---

*Last Updated: January 28, 2026*
*EA Version: 2.10*
*Server: server1.metasynx.io*