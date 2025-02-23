from datetime import datetime
from pydantic import BaseModel, Field
from typing import List, Optional, Dict
from database.models import DebateStatus

class DebateAgentBase(BaseModel):
    name: str
    model_used: str
    temperature: float
    context: str

class DebateAgent(DebateAgentBase):
    id: int
    debate_id: int

    class Config:
        from_attributes = True

class DebateMessageBase(BaseModel):
    agent_name: str
    model_used: str
    temperature: float
    content: str
    is_moderator: bool = False
    is_final: bool = False

class DebateMessageCreate(DebateMessageBase):
    pass

class DebateMessage(DebateMessageBase):
    id: int
    debate_id: int
    timestamp: str
    is_final: bool

    class Config:
        from_attributes = True

class DebateBase(BaseModel):
    topic: str

class DebateCreate(DebateBase):
    agents: Optional[List[Dict]] = None

class Debate(DebateBase):
    id: int
    created_at: datetime
    status: DebateStatus = Field(default=DebateStatus.ACTIVE)
    last_activity: datetime = Field(default_factory=datetime.utcnow)
    timeout_duration: int = 3600
    consensus_reached: bool = False
    messages: List[DebateMessage] = []
    agents: List[DebateAgent] = []

    class Config:
        from_attributes = True
