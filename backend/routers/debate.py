from typing import List, Dict, Optional, Any
from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, BackgroundTasks, Body
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from database import get_db, get_async_db, crud, SQLALCHEMY_DATABASE_URL
from schemas import debate as debate_schema
from models import ai_agent
from database.models import DebateAgent, Debate, DebateStatus
from services import ai_discussion
import asyncio
from datetime import datetime
from fastapi.encoders import jsonable_encoder
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

router = APIRouter()

class WebSocketManager:
    def __init__(self):
        self.active_connections: Dict[int, List[WebSocket]] = {}
        self.background_task = None

    async def start_timeout_checker(self) -> None:
        """Start the periodic task to check for timed-out debates."""
        async def check_timeouts() -> None:
            while True:
                try:
                    async for db in get_async_db():
                        try:
                            timed_out = await crud.check_timed_out_debates(db)
                            for debate in timed_out:
                                if debate.id in self.active_connections:
                                    await self.broadcast(debate.id, {
                                        "type": "debate_timeout",
                                        "message": "Debate timed out due to inactivity"
                                    })
                                    # Close all connections for this debate
                                    for ws in self.active_connections[debate.id][:]:
                                        try:
                                            await ws.close()
                                        except Exception as e:
                                            logger.error(f"Error closing websocket: {e}")
                                        await self.disconnect(debate.id, ws)
                        except Exception as e:
                            logger.error(f"Error checking timeouts: {e}")
                            continue
                except Exception as e:
                    logger.error(f"Error getting async session: {e}")
                await asyncio.sleep(30)  # Check every 30 seconds

        self.background_task = asyncio.create_task(check_timeouts())

    async def connect(self, debate_id: int, websocket: WebSocket, db: AsyncSession) -> None:
        try:
            await websocket.accept()
            if debate_id not in self.active_connections:
                self.active_connections[debate_id] = []
            self.active_connections[debate_id].append(websocket)
            
            # Update last_activity when a new connection is established
            debate = await crud.async_get_debate(db, debate_id)
            if debate:
                await crud.async_update_last_activity(db, debate)
                
        except Exception as e:
            logger.error(f"Error accepting websocket connection: {e}")

    async def disconnect(self, debate_id: int, websocket: WebSocket) -> None:
        if debate_id in self.active_connections:
            self.active_connections[debate_id].remove(websocket)
            # If this was the last connection, note the timestamp
            if not self.active_connections[debate_id]:
                logger.info(f"Last connection closed for debate {debate_id}")
            try:
                await websocket.close()
            except Exception as e:
                logger.error(f"Error closing websocket: {e}")

    async def broadcast(self, debate_id: int, message: dict) -> None:
        if debate_id in self.active_connections:
            for connection in self.active_connections[debate_id]:
                try:
                    await connection.send_json(message)
                except Exception as e:
                    logger.error(f"Error broadcasting to connection: {e}")
                    await self.disconnect(debate.id, connection)

    def get_active_connections_count(self, debate_id: int) -> int:
        """Get the number of active connections for a debate."""
        return len(self.active_connections.get(debate_id, []))

manager = WebSocketManager()

@router.on_event("startup")
async def startup_event() -> None:
    """Initialize the WebSocket manager's timeout checker when FastAPI starts."""
    await manager.start_timeout_checker()

@router.post("/debates/", response_model=debate_schema.Debate)
async def create_debate(
    debate: debate_schema.DebateCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_async_db)
) -> debate_schema.Debate:
    # Create the debate
    db_debate = await crud.async_create_debate(db=db, debate=debate, agents=debate.agents or [])

    # Eagerly load the agents for the debate
    db_debate = await db.get(Debate, db_debate.id)
    if not db_debate:
        raise HTTPException(status_code=404, detail="Debate not found")

    agents_list = [
        {
            "name": agent.name,
            "context": agent.context,
            "model_used": agent.model_used,
            "temperature": agent.temperature
        }
        for agent in db_debate.agents or []
    ]
    logger.info(f"🔹 Agents IA chargés : {agents_list}")

    return db_debate

@router.websocket("/ws/debate/{debate_id}")
async def websocket_endpoint(websocket: WebSocket, debate_id: int, db: AsyncSession = Depends(get_async_db)) -> None:
    await manager.connect(debate_id, websocket, db)
    try:
        while True:
            data = await websocket.receive_json()
            await handle_message(debate_id, data, websocket, db)
    except WebSocketDisconnect:
        await manager.disconnect(debate_id, websocket)

async def handle_message(debate_id: int, data: dict, websocket: WebSocket, db: AsyncSession) -> None:
    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        await websocket.send_json({"error": "Debate not found"})
        return

    agents_list = [
        debate_schema.DebateAgent(
            id=agent.id,
            debate_id=agent.debate_id,
            name=agent.name,
            model_used=agent.model_used,
            temperature=agent.temperature,
            context=agent.context
        ) for agent in debate.agents
    ]

    print(agents_list)

    if data["type"] == "restart":
        await crud.async_update_debate_status(db, debate, DebateStatus.ACTIVE)
        await manager.broadcast(debate_id, {"type": "debate_status", "status": "ACTIVE"})
        asyncio.ensure_future(ai_collab.run_discussion(debate_id, agents_list, websocket, db))
    
    elif data["type"] == "pause":
        await crud.async_update_debate_status(db, debate, DebateStatus.PAUSED)
        await manager.broadcast(debate_id, {"type": "debate_status", "status": "PAUSED"})
    
    elif data["type"] == "stop":
        await crud.async_update_debate_status(db, debate, DebateStatus.STOPPED)
        await manager.broadcast(debate_id, {"type": "debate_status", "status": "STOPPED"})
    
    elif data["type"] == "message":
        response = await ai_collab.generate_response(data["agent"], debate_id, [], websocket, db, [])
        await manager.broadcast(debate_id, {"type": "message", "content": response})

@router.post("/debates/{debate_id}/messages/", response_model=debate_schema.DebateMessage)
async def create_message(
    debate_id: int,
    message: debate_schema.DebateMessageCreate,
    db: AsyncSession = Depends(get_async_db)
) -> debate_schema.DebateMessage:
    debate = await crud.async_get_debate(db, debate_id)
    if debate is None:
        raise HTTPException(status_code=404, detail="Debate not found")
    
    # Update last_activity
    await crud.async_update_last_activity(db, debate)
    
    message.content = message.content.encode('utf-8')
    return await crud.async_add_message_to_debate(db, debate_id, message)

@router.post("/debates/{debate_id}/restart/")
async def restart_debate(
    debate_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_async_db)
) -> Dict[str, str]:
    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        raise HTTPException(status_code=404, detail="Débat non trouvé")

    # Get debate agents
    agents = await crud.async_get_debate_agents(db, debate_id)
    if not agents:
        raise HTTPException(status_code=400, detail="Aucun agent trouvé pour ce débat.")

    # Convert agents to list of dicts
    agents_list = [
        {
            "name": agent.name,
            "context": agent.context,
            "model_used": agent.model_used,
            "temperature": agent.temperature
        }
        for agent in agents
    ]

    # Wait for WebSocket connection
    max_attempts = 10
    attempt = 0
    while attempt < max_attempts:
        if debate_id in manager.active_connections and manager.active_connections[debate_id]:
            break
        attempt += 1
        await asyncio.sleep(0.5)  # Wait for 0.5 seconds

    if debate_id not in manager.active_connections or not manager.active_connections[debate_id]:
        return {"status": "waiting_for_ws"}

    # Update debate status and broadcast the change
    await crud.async_update_debate_status(db, debate, DebateStatus.ACTIVE)
    await crud.async_update_last_activity(db, debate)  # Reset last_activity

    websocket = manager.active_connections[debate_id][0]

    # Wait for initialization message from client
    try:
        logger.info("Waiting for initialization message from client...")
        timeout = 10  # seconds
        data = await asyncio.wait_for(websocket.receive_json(), timeout=timeout)
        logger.info(f"Received data: {data}")
        if "type" not in data or data["type"] != "initialize":
            logger.warning("Invalid initialization message.")
            await websocket.send_json({"type": "error", "message": "Invalid initialization message."})
            await websocket.close()
            return {"status": "error", "message": "Invalid initialization message."}
    except asyncio.TimeoutError:
        logger.warning("Timeout waiting for initialization message from client.")
        await websocket.send_json({"type": "error", "message": "Timeout waiting for initialization message."})
        await websocket.close()
        return {"status": "error", "message": "Invalid initialization message."}

    # Broadcast status change to all connected clients
    await manager.broadcast(debate_id, {
        "type": "debate_status",
        "status": DebateStatus.ACTIVE.value
    })

    # Broadcast existing messages
    messages = await crud.async_get_debate_messages(db, debate_id)
    for message in messages:
        await manager.broadcast(debate_id, jsonable_encoder(message))

    return {"status": "restarted"}

@router.post("/debates/{debate_id}/pause/")
async def pause_debate(debate_id: int, db: AsyncSession = Depends(get_async_db)) -> Dict[str, str]:
    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        raise HTTPException(status_code=404, detail="Débat non trouvé")

    new_status = DebateStatus.ACTIVE if debate.status == DebateStatus.PAUSED else DebateStatus.PAUSED
    logger.info(f"🚦 Pausing debate {debate_id}, current status: {new_status}")
    await crud.async_update_debate_status(db, debate, DebateStatus.ACTIVE)
    logger.info(f"✅ Debate {debate_id} status updated to: {new_status}")

    # Broadcast status change to all connected clients
    await manager.broadcast(debate_id, {
        "type": "debate_status",
        "status": new_status.value
    })

    return {"status": new_status.value, "type": "debate_status"}

@router.post("/debates/{debate_id}/stop/")
async def stop_debate(debate_id: int, db: AsyncSession = Depends(get_async_db)) -> Dict[str, str]:
    debate = await crud.async_get_debate(db, debate_id)
    if not debate:
        raise HTTPException(status_code=404, detail="Débat non trouvé")
    
    await crud.async_update_debate_status(db, debate, DebateStatus.STOPPED)
    
    # Broadcast status change to all connected clients
    await manager.broadcast(debate_id, {
        "type": "debate_status",
        "status": DebateStatus.STOPPED.value
    })
    
    return {"status": "stopped", "type": "debate_status"}

@router.get("/debates/{debate_id}", response_model=debate_schema.Debate)
async def read_debate(debate_id: int, db: AsyncSession = Depends(get_async_db)) -> debate_schema.Debate:
    db_debate = await crud.async_get_debate(db, debate_id)
    debate_data = []

    messages = [
            debate_schema.DebateMessage(
                id=msg.id,
                debate_id=msg.debate_id,
                agent_name=msg.agent_name,
                model_used=msg.model_used,
                temperature=msg.temperature,
                content=msg.content.decode('utf-8') if isinstance(msg.content, bytes) else msg.content,
                is_moderator=msg.is_moderator,
                is_final=msg.is_final if msg.is_final is not None else False,
                timestamp=msg.timestamp.isoformat() if msg.timestamp else datetime.utcnow().isoformat(),
            ) for msg in db_debate.messages
    ]
    agents = [
        debate_schema.DebateAgent(
            id=agent.id,
            debate_id=agent.debate_id,
            name=agent.name,
            model_used=agent.model_used,
            temperature=agent.temperature,
            context=agent.context
        ) for agent in db_debate.agents
    ]
    debate_data = debate_schema.Debate(
        id=db_debate.id,
        created_at=db_debate.created_at,
        status=db_debate.status,
        last_activity=db_debate.last_activity,
        timeout_duration=db_debate.timeout_duration,
        consensus_reached=db_debate.consensus_reached,
        messages=messages,
        agents=agents,
        topic=db_debate.topic
    )

    return debate_data

@router.get("/debates/", response_model=List[debate_schema.Debate])
async def read_debates(db: AsyncSession = Depends(get_async_db)) -> List[debate_schema.Debate]:
    db_debates = await crud.async_get_debates(db)
    debates_list = []
    for db_debate in db_debates:
        messages = [
            debate_schema.DebateMessage(
                id=msg.id,
                debate_id=msg.debate_id,
            agent_name=msg.agent_name,
            model_used=msg.model_used,
                temperature=msg.temperature,
                content=msg.content,
                is_moderator=msg.is_moderator,
                is_final=msg.is_final if msg.is_final is not None else False,
                timestamp=msg.timestamp.isoformat() if msg.timestamp else datetime.utcnow().isoformat(),
            ) for msg in db_debate.messages
        ]
        agents = [
            debate_schema.DebateAgent(
                id=agent.id,
                debate_id=agent.debate_id,
                name=agent.name,
                model_used=agent.model_used,
                temperature=agent.temperature,
                context=agent.context
            ) for agent in db_debate.agents
        ]
        debate_item = debate_schema.Debate(
            id=db_debate.id,
            created_at=db_debate.created_at,
            status=db_debate.status,
            last_activity=db_debate.last_activity,
            timeout_duration=db_debate.timeout_duration,
            consensus_reached=db_debate.consensus_reached,
            messages=messages,
            agents=agents,
            topic=db_debate.topic
        )
        debates_list.append(debate_item)
    return debates_list

@router.get("/debates/{debate_id}/messages/", response_model=List[debate_schema.DebateMessage])
async def get_debate_messages(debate_id: int, db: AsyncSession = Depends(get_async_db)):
    """
    Récupère l'historique des messages pour un débat donné.
    """
    messages = await crud.async_get_debate_messages(db, debate_id)
    if not messages:
        raise HTTPException(status_code=404, detail="Aucun message trouvé pour ce débat")
    
    return [
        debate_schema.DebateMessage(
            id=msg.id,
            debate_id=msg.debate_id,
            agent_name=msg.agent_name,
            model_used=msg.model_used,
            temperature=msg.temperature,
            content=msg.content,
            is_moderator=msg.is_moderator,
            is_final=msg.is_final if msg.is_final is not None else False,
            timestamp=msg.timestamp.isoformat() if msg.timestamp else datetime.utcnow().isoformat(),
        ) for msg in messages
    ]
