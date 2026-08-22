"""Phase 05 demo API — minimal FastAPI service proving ECS Fargate -> RDS
Postgres connectivity behind an ALB. Deliberately small: this phase exists
to demonstrate the container/ALB/RDS infrastructure pattern, not to be a
second implementation of the Gratitude Journal (Phase 3 already covers the
Cognito auth story). No authentication here on purpose.
"""
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import psycopg2
from fastapi import FastAPI, HTTPException
from psycopg2.extras import RealDictCursor
from pydantic import BaseModel


def get_connection():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        connect_timeout=5,
    )


def init_schema():
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                CREATE TABLE IF NOT EXISTS notes (
                    id SERIAL PRIMARY KEY,
                    content TEXT NOT NULL,
                    created_at TIMESTAMPTZ NOT NULL
                )
                """
            )
        conn.commit()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_schema()
    yield


app = FastAPI(title="aws-portfolio-05-containers", lifespan=lifespan)


class NoteIn(BaseModel):
    content: str


@app.get("/health")
def health():
    # ALB target group + ECS container health check hit this. Deliberately
    # does NOT touch the database — a slow/unhealthy DB shouldn't cause the
    # ALB to cycle otherwise-healthy tasks.
    return {"status": "ok"}


@app.get("/notes")
def list_notes():
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, content, created_at FROM notes ORDER BY id DESC LIMIT 50")
            return cur.fetchall()


@app.post("/notes", status_code=201)
def create_note(note: NoteIn):
    content = note.content.strip()
    if not content:
        raise HTTPException(status_code=400, detail="content is required")

    now = datetime.now(timezone.utc)
    with get_connection() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "INSERT INTO notes (content, created_at) VALUES (%s, %s) RETURNING id, content, created_at",
                (content, now),
            )
            row = cur.fetchone()
        conn.commit()
    return row
