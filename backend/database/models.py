from sqlalchemy import Column, Integer, String, DateTime, Boolean, ForeignKey, Float, Enum
from sqlalchemy.orm import relationship
from datetime import datetime, timedelta
import enum
from . import Base

class DebateStatus(enum.Enum):
    ACTIVE = "active"
    PAUSED = "paused"
    STOPPED = "stopped"
    TIMEOUT = "timeout"  # Added for debates that were stopped due to inactivity

class Debate(Base):
    __tablename__ = "debates"

    id = Column(Integer, primary_key=True, index=True)
    topic = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    status = Column(Enum(DebateStatus), default=DebateStatus.ACTIVE)
    last_activity = Column(DateTime, default=datetime.utcnow)
    timeout_duration = Column(Integer, default=3600)  # Default 1 hour in seconds
    consensus_reached = Column(Boolean, default=False)

    messages = relationship("DebateMessage", back_populates="debate")
    agents = relationship("DebateAgent", back_populates="debate")


class DebateMessage(Base):
    __tablename__ = "debate_messages"

    id = Column(Integer, primary_key=True, index=True)
    debate_id = Column(Integer, ForeignKey("debates.id"))
    agent_name = Column(String, nullable=False)
    model_used = Column(String, nullable=False)
    temperature = Column(Float, nullable=False)
    content = Column(String, nullable=False)
    timestamp = Column(DateTime, default=datetime.utcnow)
    is_moderator = Column(Boolean, default=False)
    is_final = Column(Boolean, default=False)

    debate = relationship("Debate", back_populates="messages")


class DebateAgent(Base):
    __tablename__ = "debate_agents"

    id = Column(Integer, primary_key=True, index=True)
    debate_id = Column(Integer, ForeignKey("debates.id"), nullable=False)
    name = Column(String, nullable=False)  # Nom de l'agent
    model_used = Column(String, nullable=False)  # Modèle IA utilisé (GPT-4, Gemini, etc.)
    temperature = Column(Float, nullable=False)  # Température du modèle
    context = Column(String, nullable=False)
    debate = relationship("Debate", back_populates="agents")
