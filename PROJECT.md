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
MetaSynx/
├── app/                          # Mobile App (Flutter - iOS/Android)
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
├── win/                          # Windows Bridge App (Flutter - Windows)
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

### 2. Windows Bridge (`/win`)

**Purpose**: Bridges WebSocket (relay) to file system (MT4)

**Key Files:**
- **config.dart**: Server URL and API key constants
- **theme.dart** (62 lines): App colors and text styles
- **ea_service.dart** (405 lines): Reads/writes MT4 files, polls for updates
- **relay_connection.dart** (140 lines): WebSocket connection management
- **room_service.dart** (47 lines): Room creation API
- **home_screen.dart** (626 lines): QR code display, connection status, activity log

**Features:**
- Creates room on relay server
- Displays QR code for mobile pairing
- "Copy Code" button for manual pairing
- Monitors connected MT4 terminals
- Routes commands from mobile to correct EA
- Shows activity log with all actions
- Auto-reconnects on connection loss
- Clean, minimal Windows UI

### 3. Relay Server (`/server`)

**WebSocket relay** (430 lines) that:
- Creates rooms with unique IDs
- Manages pairing between mobile and bridge
- Routes messages bidirectionally
- Maintains heartbeat connections
- Handles disconnection gracefully
- Runs with SSL on port 443

### 4. MT4 Expert Advisor (`MetaSynxEA.mq4`)

**MQL4 EA** (1052 lines) that:
- Writes account status every 500ms
- Writes positions/orders every 500ms
- Writes history every 30 seconds
- Reads and executes commands
- Supports all order types
- Returns command results
- Provides chart data for live charts
- Handles symbol info requests

---

## Current Status

### ✅ Complete
- Full mobile app with all screens
- Windows Bridge application
- Relay server deployed at `server1.metasynx.io`
- MT4 EA with all features
- QR code pairing
- Real-time position updates
- Order placement (market/limit/stop)
- Position close (full/partial)
- Position modify (SL/TP)
- Pending order cancel/modify
- Trade history
- Risk calculator with live symbol info
- Live charts with MT4 data
- Multi-account lot ratio support
- Settings persistence

### 🔄 Testing Phase
- Internal testing with real MT4 accounts
- Performance optimization
- Bug fixes as discovered

### 📋 Future Considerations
- Firebase authentication for public release
- App Store / Play Store submission
- Push notifications for order fills
- Additional chart indicators

---

## Technical Details

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
cd win
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
scp server/websocket_relay.py USERNAME@YOUR_DOMAIN:/tmp/
scp server/metasynx-relay.service USERNAME@YOUR_DOMAIN:/tmp/
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
| - Screens | ~11,100 |
| - Core/Services/Components/Utils | ~600 |
| **Windows Bridge (Dart)** | ~1,200 |
| **MT4 EA (MQL4)** | ~1,050 |
| **Relay Server (Python)** | ~430 |
| **Total** | ~14,400 |

---

*Last Updated: January 29, 2026*
*EA Version: 2.10*
*Server: server1.metasynx.io*