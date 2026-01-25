# MetaSynx - Multi-Terminal MT4 Trade Copier & Manager

## Project Overview

MetaSynx is a mobile-first trade management system that allows controlling multiple MT4 terminals from a single mobile app. It consists of three main components that communicate via a WebSocket relay server.

**Key Features:**
- Monitor multiple MT4 accounts in real-time
- Place trades across multiple terminals simultaneously
- Close/modify positions with live P/L updates
- TradingView-style charts with position lines (using Lightweight Charts)
- Proportional lot sizing across accounts
- QR code pairing for secure connection

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
   - `positions_X.json` - Open positions
   - `command_X.json` - Commands from app (orders, close, modify)
   - `response_X.json` - Command results
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
│       │   ├── home.dart                  # Main screen - accounts list, totals
│       │   ├── account.dart               # Account detail - positions list
│       │   ├── position.dart              # Position detail - close/modify
│       │   ├── new_order.dart             # Place new orders
│       │   ├── chart.dart                 # TradingView charts with positions
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
├── MetaSynxEA.mq4                # MT4 Expert Advisor (v2.00)
├── websocket_relay.py            # FastAPI WebSocket relay server
└── PROJECT.md                    # This documentation file
```

---

## Component Details

### 1. Mobile App (`/app`)

**Main Screen (home.dart)** - 902 lines
- Shows connection status card with QR scanner button
- Lists all connected MT4 accounts with balance/equity/P/L
- Shows total across all accounts
- FAB button for new orders
- Settings gear icon
- Sorts accounts with main account first

**Account Detail (account.dart)** - 859 lines
- Shows single account's positions
- Expandable position cards (tap left to expand, right to navigate)
- Filter by symbol (persisted per account)
- Real-time P/L updates

**Position Detail (position.dart)** - 1088 lines
- Full position information
- Modify SL/TP with validation
- Close position with optional confirmation dialog
- Navigate to chart
- Shows commission/swap if enabled

**New Order (new_order.dart)** - 756 lines
- Symbol input with suffix toggle
- Buy/Sell buttons
- Lot size with +/- controls
- Optional SL/TP
- Target: specific account, all accounts, or main account only
- Preferred symbols quick-select

**Chart (chart.dart)** - 936 lines
- Uses TradingView Lightweight Charts via WebView
- External data feed (currently placeholder - future: MT4 direct feed)
- Position entry lines (green=buy, red=sell)
- SL/TP lines (dashed)
- Tap position lines to navigate to position detail
- Account selector, timeframe selector
- Quick symbol buttons from open positions

**Settings (settings/)**
- **settings.dart** (537 lines): Main settings screen with navigation cards
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
- **config.dart** (2 lines): Server URL and API key constants
- **theme.dart** (62 lines): App colors and text styles
- **ea_service.dart** (228 lines): Reads/writes MT4 files, polls for updates
- **relay_connection.dart** (140 lines): WebSocket connection management
- **room_service.dart** (47 lines): Room creation API
- **home_screen.dart** (479 lines): QR code display, connection status, activity log

**Message Handling (in home_screen.dart):**
- `get_accounts` → Reads all `status_X.json` files
- `get_positions` → Reads `positions_X.json` files
- `place_order` → Writes to `command_X.json`
- `close_position` → Writes to `command_X.json`
- `modify_position` → Writes to `command_X.json`

### 3. MT4 Expert Advisor (`MetaSynxEA.mq4`)

**Version**: 2.00 (478 lines)

**Features:**
- Multi-terminal support via unique terminal index
- Writes account status every 500ms
- Writes positions every 500ms
- Processes commands: place_order, close_position, modify_position

**File Locations:**
All files in: `%APPDATA%\MetaQuotes\Terminal\Common\Files\MetaSynx\`

**Command Format (command_X.json):**
```json
{"action": "place_order", "symbol": "XAUUSD", "type": "buy", "lots": 0.1, "sl": 0, "tp": 0, "magic": 123456}
{"action": "close_position", "ticket": 12345}
{"action": "modify_position", "ticket": 12345, "sl": 1.2000, "tp": 1.3000}
```

**Modify SL/TP Values:**
- `-1` = Keep existing value
- `0` = Remove SL/TP
- `>0` = Set new value

### 4. Relay Server (`websocket_relay.py`)

**FastAPI WebSocket Relay** (395 lines)

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
  "lastUpdate": "2025.01.25 10:30:00",
  "connected": true,
  "tradeAllowed": true
}
```

### Position (positions_X.json)
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
      "openTime": "2025.01.25 10:30:00",
      "comment": "",
      "magic": 123456
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

### Lot Sizing Logic
When "All Accounts" selected:
1. Main account gets exact lot size entered
2. Other accounts get: `enteredLots * accountRatio`
3. If no ratio set, account uses 1.0 ratio

### Position Matching
- Positions matched by exact symbol (case-insensitive)
- Terminal index used to identify which MT4 terminal

### Error Handling
- Commands have 2-second timeout waiting for EA processing
- Stale status files (>10 seconds old) are ignored
- WebSocket auto-reconnects on disconnect

---

## Future Enhancements (Planned)

1. **MT4 Direct Chart Data** - Get candle data directly from MT4 for exact broker prices
2. **Partial close** - Close portion of position
3. **Pending orders** - Limit/stop orders
4. **Trade history** - View closed trades
5. **Push notifications** - Alerts for SL/TP hits
6. **Risk calculator** - Position sizing based on risk %

---

## Quick Reference - Message Types

### Mobile → Bridge
| Action | Description |
|--------|-------------|
| `ping` | Heartbeat |
| `get_accounts` | Request account list |
| `get_positions` | Request positions (optional targetIndex) |
| `place_order` | Place new order |
| `close_position` | Close position by ticket |
| `modify_position` | Modify SL/TP |

### Bridge → Mobile
| Action | Description |
|--------|-------------|
| `pong` | Heartbeat response |
| `accounts_list` | Account data array |
| `positions_list` | Positions array |
| `order_result` | Order execution result |

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
```bash
pip install fastapi uvicorn websockets
# Add router to your FastAPI app:
# from websocket_relay import router as relay_router
# app.include_router(relay_router, prefix="/ws")
uvicorn main:app --host 0.0.0.0 --port 8443 --ssl-keyfile key.pem --ssl-certfile cert.pem
```

---

*Last Updated: January 25, 2026*
*EA Version: 2.00*
*Total Lines of Code: ~8,755 (Dart) + 478 (MQL4) + 395 (Python)*