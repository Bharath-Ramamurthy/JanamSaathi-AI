# main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles


# SQLAlchemy Base & engine
from core.database import engine, Base

# Import SQLAlchemy models to register them with Base
import models  # Ensure your SQLAlchemy models are defined here

# Route modules
from routes import auth, rag_faiss, socket_connection, conversations

from ws.socket_manager import SocketManager
from ws.handlers.chat import handle_chat
from ws.handlers.assess import handle_assess
from ws.handlers.report import handle_report


# --- FastAPI App Initialization ---
app = FastAPI(
    title="MatrimAI Backend",
    description="AI-powered Matchmaking API",
    version="1.0.0"
)

# --- Create all tables (only needed if using SQLAlchemy models) ---
Base.metadata.create_all(bind=engine)

# --- CORS Middleware ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # During development; restrict origins in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


mgr = SocketManager.instance()
mgr.register_handler("chat", handle_chat)
mgr.register_handler("assess", handle_assess)
mgr.register_handler("view_report", handle_report)



# --- Include Routers ---
app.include_router(auth.router, prefix="/auth", tags=["Authentication"])
app.include_router(rag_faiss.router, tags=["Matchmaking"])
app.include_router(socket_connection.router, tags=["WebSocket Chat"])
app.include_router(conversations.router, tags=["Conversations"])
#app.include_router(horoscope.router, tags=["Horoscope"])

# --- Static Files (e.g., profile photos) ---
app.mount("/static", StaticFiles(directory="assets"), name="static")



# --- Root Endpoint ---
@app.get("/")
def home():
    """
    Basic health check endpoint.
    """
    print("Hi")
    return {"message": "Welcome to MatrimAI Backend"}
