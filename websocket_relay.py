"""
WebSocket Relay for MT4 Bridge Pairing
Add this to your existing FastAPI server

Usage:
    from websocket_relay import router as relay_router
    app.include_router(relay_router, prefix="/ws")
"""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException, Header, Request
from typing import Optional
import asyncio
import json
import secrets
from dataclasses import dataclass, field
from datetime import datetime, timedelta

router = APIRouter()

# ============================================
# CONFIGURATION
# ============================================

API_KEY = "YOUR_API_KEY_HERE"  # Set this to match your existing API key
ROOM_EXPIRY_MINUTES = 30       # Room expires if no activity
ROOM_CODE_LENGTH = 8           # Length of room codes
ROOM_SECRET_LENGTH = 16        # Length of room secrets
MAX_ROOMS_PER_IP = 10          # Prevent abuse

# ============================================
# DATA STRUCTURES
# ============================================

@dataclass
class RoomParticipant:
    websocket: WebSocket
    role: str  # "bridge" or "mobile"
    connected_at: datetime = field(default_factory=datetime.now)
    device_name: Optional[str] = None


@dataclass
class Room:
    room_id: str
    room_secret: str  # Secret required to join
    created_at: datetime = field(default_factory=datetime.now)
    last_activity: datetime = field(default_factory=datetime.now)
    creator_ip: Optional[str] = None
    bridge: Optional[RoomParticipant] = None
    mobile: Optional[RoomParticipant] = None
    
    def is_expired(self) -> bool:
        return datetime.now() - self.last_activity > timedelta(minutes=ROOM_EXPIRY_MINUTES)
    
    def touch(self):
        self.last_activity = datetime.now()


# ============================================
# ROOM MANAGER
# ============================================

class RelayManager:
    def __init__(self):
        self.rooms: dict[str, Room] = {}
        self._cleanup_task: Optional[asyncio.Task] = None
    
    def start_cleanup_task(self):
        """Start background task to clean expired rooms"""
        if self._cleanup_task is None:
            self._cleanup_task = asyncio.create_task(self._cleanup_loop())
    
    async def _cleanup_loop(self):
        """Periodically remove expired rooms"""
        while True:
            await asyncio.sleep(60)  # Check every minute
            expired = [rid for rid, room in self.rooms.items() if room.is_expired()]
            for rid in expired:
                await self.close_room(rid)
    
    def generate_room_id(self) -> str:
        """Generate a unique room ID"""
        while True:
            room_id = secrets.token_urlsafe(ROOM_CODE_LENGTH)[:ROOM_CODE_LENGTH].upper()
            if room_id not in self.rooms:
                return room_id
    
    def generate_room_secret(self) -> str:
        """Generate a room secret"""
        return secrets.token_urlsafe(ROOM_SECRET_LENGTH)[:ROOM_SECRET_LENGTH]
    
    def create_room(self, creator_ip: Optional[str] = None) -> tuple[str, str]:
        """Create a new room and return its ID and secret"""
        room_id = self.generate_room_id()
        room_secret = self.generate_room_secret()
        self.rooms[room_id] = Room(
            room_id=room_id,
            room_secret=room_secret,
            creator_ip=creator_ip
        )
        return room_id, room_secret
    
    def get_room(self, room_id: str) -> Optional[Room]:
        """Get a room by ID"""
        return self.rooms.get(room_id.upper())
    
    def validate_secret(self, room_id: str, secret: str) -> bool:
        """Validate a room secret"""
        room = self.get_room(room_id)
        if not room:
            return False
        return secrets.compare_digest(room.room_secret, secret)
    
    async def close_room(self, room_id: str):
        """Close a room and disconnect participants"""
        room = self.rooms.pop(room_id.upper(), None)
        if room:
            if room.bridge:
                try:
                    await room.bridge.websocket.close()
                except:
                    pass
            if room.mobile:
                try:
                    await room.mobile.websocket.close()
                except:
                    pass
    
    async def join_room(
        self, 
        room_id: str, 
        websocket: WebSocket, 
        role: str, 
        device_name: str = None
    ) -> bool:
        """Join a room as bridge or mobile"""
        room = self.get_room(room_id)
        if not room:
            return False
        
        participant = RoomParticipant(
            websocket=websocket,
            role=role,
            device_name=device_name
        )
        
        if role == "bridge":
            if room.bridge:
                # Disconnect existing bridge
                try:
                    await room.bridge.websocket.close()
                except:
                    pass
            room.bridge = participant
        elif role == "mobile":
            if room.mobile:
                # Disconnect existing mobile
                try:
                    await room.mobile.websocket.close()
                except:
                    pass
            room.mobile = participant
        
        room.touch()
        
        # Notify both parties if paired
        await self._notify_pairing_status(room)
        
        return True
    
    async def leave_room(self, room_id: str, role: str):
        """Leave a room"""
        room = self.get_room(room_id)
        if not room:
            return
        
        if role == "bridge":
            room.bridge = None
        elif role == "mobile":
            room.mobile = None
        
        # Notify remaining participant
        await self._notify_pairing_status(room)
    
    async def _notify_pairing_status(self, room: Room):
        """Notify participants about pairing status"""
        is_paired = room.bridge is not None and room.mobile is not None
        
        status_msg = json.dumps({
            "type": "pairing_status",
            "paired": is_paired,
            "bridge_connected": room.bridge is not None,
            "mobile_connected": room.mobile is not None,
            "mobile_device": room.mobile.device_name if room.mobile else None,
        })
        
        if room.bridge:
            try:
                await room.bridge.websocket.send_text(status_msg)
            except:
                pass
        
        if room.mobile:
            try:
                await room.mobile.websocket.send_text(status_msg)
            except:
                pass
    
    async def relay_message(self, room_id: str, from_role: str, message: str):
        """Relay a message from one participant to the other"""
        room = self.get_room(room_id)
        if not room:
            return
        
        room.touch()
        
        # Determine recipient
        if from_role == "bridge" and room.mobile:
            try:
                await room.mobile.websocket.send_text(message)
            except:
                pass
        elif from_role == "mobile" and room.bridge:
            try:
                await room.bridge.websocket.send_text(message)
            except:
                pass


# Global manager instance
manager = RelayManager()

# ============================================
# REST ENDPOINTS
# ============================================

@router.post("/relay/create-room")
async def create_room(
    request: Request,
    x_api_key: str = Header(..., alias="x-api-key")
):
    """
    Create a new relay room. Called by Windows Bridge.
    Returns a room_id and room_secret to encode in QR code.
    """
    # Validate API key
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    # Get client IP for rate limiting
    client_ip = request.client.host if request.client else "unknown"
    
    # Check rate limit per IP
    rooms_by_ip = sum(1 for room in manager.rooms.values() 
                      if getattr(room, 'creator_ip', None) == client_ip)
    if rooms_by_ip >= MAX_ROOMS_PER_IP:
        raise HTTPException(
            status_code=429, 
            detail=f"Too many rooms. Maximum {MAX_ROOMS_PER_IP} active rooms per IP."
        )
    
    manager.start_cleanup_task()
    room_id, room_secret = manager.create_room(creator_ip=client_ip)
    
    return {
        "room_id": room_id,
        "room_secret": room_secret,
        "websocket_url": f"wss://vps2.bk.harmonicmarkets.com:8443/ws/relay/{room_id}",
        "expires_in_minutes": ROOM_EXPIRY_MINUTES
    }


@router.get("/relay/room/{room_id}/status")
async def get_room_status(room_id: str, x_api_key: str = Header(..., alias="x-api-key")):
    """Check if a room exists and its status"""
    # Validate API key
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")
    
    room = manager.get_room(room_id)
    if not room:
        raise HTTPException(status_code=404, detail="Room not found")
    
    return {
        "room_id": room_id,
        "bridge_connected": room.bridge is not None,
        "mobile_connected": room.mobile is not None,
        "created_at": room.created_at.isoformat(),
        "expires_at": (room.last_activity + timedelta(minutes=ROOM_EXPIRY_MINUTES)).isoformat()
    }


# ============================================
# WEBSOCKET ENDPOINT
# ============================================

@router.websocket("/relay/{room_id}")
async def websocket_relay(websocket: WebSocket, room_id: str):
    """
    WebSocket endpoint for relay communication.
    
    First message must be:
    {
        "type": "join", 
        "role": "bridge"|"mobile", 
        "secret": "room_secret_here",
        "device_name": "optional"
    }
    
    Subsequent messages are relayed to the paired participant.
    """
    await websocket.accept()
    
    room = manager.get_room(room_id)
    if not room:
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": "Room not found or expired"
        }))
        await websocket.close()
        return
    
    role = None
    
    try:
        # Wait for join message
        join_data = await asyncio.wait_for(
            websocket.receive_text(),
            timeout=10.0
        )
        join_msg = json.loads(join_data)
        
        if join_msg.get("type") != "join":
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": "First message must be join"
            }))
            await websocket.close()
            return
        
        # Validate room secret
        provided_secret = join_msg.get("secret", "")
        if not manager.validate_secret(room_id, provided_secret):
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": "Invalid room secret"
            }))
            await websocket.close()
            return
        
        role = join_msg.get("role")
        if role not in ("bridge", "mobile"):
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": "Role must be 'bridge' or 'mobile'"
            }))
            await websocket.close()
            return
        
        device_name = join_msg.get("device_name", "Unknown")
        
        # Join the room
        success = await manager.join_room(room_id, websocket, role, device_name)
        if not success:
            await websocket.send_text(json.dumps({
                "type": "error",
                "message": "Failed to join room"
            }))
            await websocket.close()
            return
        
        # Send confirmation
        await websocket.send_text(json.dumps({
            "type": "joined",
            "room_id": room_id,
            "role": role
        }))
        
        # Main message loop - relay messages between participants
        while True:
            message = await websocket.receive_text()
            await manager.relay_message(room_id, role, message)
    
    except asyncio.TimeoutError:
        await websocket.send_text(json.dumps({
            "type": "error",
            "message": "Join timeout"
        }))
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        if role:
            await manager.leave_room(room_id, role)