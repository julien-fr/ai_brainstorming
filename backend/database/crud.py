from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.sql import func
from sqlalchemy.orm import selectinload
from .models import Debate, DebateMessage, DebateAgent, DebateStatus
from schemas.debate import DebateCreate, DebateMessageCreate
from datetime import datetime, timedelta

# Asynchronous operations
async def async_create_debate(db: AsyncSession, debate: DebateCreate, agents: list):
    db_debate = Debate(topic=debate.topic, status=DebateStatus.ACTIVE)
    db.add(db_debate)
    await db.commit()
    await db.refresh(db_debate)

    try:
        print("agents:", agents)
        for agent in agents:
            print(f"debate_id: {db_debate.id}, name: {agent['name']}, model_used: {agent['model_used']}, temperature: {agent['temperature']}")
            db_agent = DebateAgent(
                debate_id=db_debate.id,
                name=agent["name"],
                model_used=agent["model_used"],
                temperature=agent["temperature"],
                context=agent["context"]
            )
            db.add(db_agent)

        await db.commit()
        await db.refresh(db_debate)

        # Eagerly load the agents and messages relationships
        result = await db.execute(
            select(Debate)
            .options(selectinload(Debate.agents), selectinload(Debate.messages))
            .filter(Debate.id == db_debate.id)
        )
        db_debate = result.scalar_one_or_none()
        return db_debate
    except Exception as e:
        print(f"Error creating debate agents: {e}")
        await db.rollback()
        raise

async def async_get_debate(db: AsyncSession, debate_id: int):
    result = await db.execute(
        select(Debate)
        .options(selectinload(Debate.messages), selectinload(Debate.agents))
        .filter(Debate.id == debate_id)
    )
    return result.scalar_one_or_none()

async def async_get_debates(db: AsyncSession):
    result = await db.execute(
        select(Debate)
        .options(selectinload(Debate.messages), selectinload(Debate.agents))
    )
    return result.scalars().all()

async def async_add_message_to_debate(db: AsyncSession, debate_id: int, message: DebateMessageCreate):
    db_message = DebateMessage(
        debate_id=debate_id,
        agent_name=message.agent_name,
        model_used=message.model_used,
        temperature=message.temperature,
        content=message.content.encode('utf-8'),
        is_moderator=message.is_moderator,
        is_final=message.is_final,
        timestamp=datetime.utcnow()
    )
    db.add(db_message)
    await db.commit()
    await db.refresh(db_message)
    return db_message

async def async_get_debate_messages(db: AsyncSession, debate_id: int):
    result = await db.execute(
        select(DebateMessage).filter(DebateMessage.debate_id == debate_id)
    )
    return result.scalars().all()

async def async_get_debate_agents(db: AsyncSession, debate_id: int):
    result = await db.execute(
        select(DebateAgent).filter(DebateAgent.debate_id == debate_id)
    )
    return result.scalars().all()

async def async_update_debate_status(db: AsyncSession, debate: Debate, new_status: DebateStatus):
    """Update debate status and last_activity timestamp asynchronously."""
    debate.status = new_status
    debate.last_activity = datetime.utcnow()
    await db.commit()
    return debate

async def async_update_last_activity(db: AsyncSession, debate: Debate):
    """Update the last_activity timestamp of a debate asynchronously."""
    debate.last_activity = datetime.utcnow()
    await db.commit()
    return debate

async def async_close_debate(db: AsyncSession, debate: Debate):
    """Close a debate by setting its status to STOPPED asynchronously."""
    return await async_update_debate_status(db, debate, DebateStatus.STOPPED)

async def check_timed_out_debates(db: AsyncSession):
    """Check for debates that have timed out due to inactivity asynchronously."""
    current_time = datetime.utcnow()
    
    # Get active and paused debates
    result = await db.execute(
        select(Debate).filter(
            Debate.status.in_([DebateStatus.ACTIVE, DebateStatus.PAUSED])
        )
    )
    active_debates = result.scalars().all()
    
    timed_out_debates = []
    for debate in active_debates:
        timeout = timedelta(seconds=debate.timeout_duration)
        if current_time - debate.last_activity > timeout:
            debate.status = DebateStatus.TIMEOUT
            timed_out_debates.append(debate)
    
    if timed_out_debates:
        await db.commit()
    
    return timed_out_debates

async def async_count_debate_messages(db: AsyncSession, debate_id: int) -> int:
    result = await db.execute(select(func.count()).select_from(DebateMessage).where(DebateMessage.debate_id == debate_id))
    return result.scalar()
