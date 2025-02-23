import uvicorn
from contextlib import asynccontextmanager
from fastapi import FastAPI, Depends, WebSocket
from fastapi.middleware.cors import CORSMiddleware
from database import init_db, get_db
from routers import debate as debate_router
import asyncio

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for FastAPI application."""
    # Startup
    init_db()
    await debate_router.manager.start_timeout_checker()
    
    yield  # Application running
    
    # Shutdown
    if debate_router.manager.background_task:
        debate_router.manager.background_task.cancel()
        try:
            await debate_router.manager.background_task
        except asyncio.CancelledError:
            pass

app = FastAPI(
    title="AI Brainstorming API",
    description="Real-time AI debate platform",
    version="0.1.0",
    lifespan=lifespan
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

app.include_router(debate_router.router)

@app.get("/")
async def read_root():
    return {"message": "AI Brainstorming Backend"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=9090, workers=1, reload=True)
