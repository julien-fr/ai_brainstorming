from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import Session

SQLALCHEMY_DATABASE_URL = "sqlite:///./ai_brainstorming.db"
ASYNC_SQLALCHEMY_DATABASE_URL = "sqlite+aiosqlite:///./ai_brainstorming.db"

# Sync engine for normal operations
engine = create_engine(
    SQLALCHEMY_DATABASE_URL, connect_args={"check_same_thread": False}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Async engine for background tasks
async_engine = create_async_engine(
    ASYNC_SQLALCHEMY_DATABASE_URL,
    connect_args={"check_same_thread": False}
)
AsyncSessionLocal = sessionmaker(
    bind=async_engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False
)

Base = declarative_base()

def get_db():
    """Get a synchronous database session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_async_db():
    """Get an asynchronous database session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()

# Create tables at startup
def init_db():
    Base.metadata.create_all(bind=engine)
