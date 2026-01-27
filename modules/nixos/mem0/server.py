#!/usr/bin/env python3
import os
import json
import logging
from typing import Optional

from mcp.server.fastmcp import FastMCP
from pydantic import Field

os.environ["MEM0_TELEMETRY"] = "false"
os.environ["ANONYMIZED_TELEMETRY"] = "false"

from mem0 import Memory

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("mem0-mcp")

DATA_DIR = os.environ.get("MEM0_DATA_DIR", "/var/lib/mem0")
DEFAULT_USER_ID = os.environ.get("MEM0_DEFAULT_USER_ID", "default")

EMBEDDER_PROVIDER = os.environ.get("MEM0_EMBEDDER_PROVIDER", "openai")
EMBEDDER_MODEL = os.environ.get("MEM0_EMBEDDER_MODEL", "text-embedding-3-small")
LLM_PROVIDER = os.environ.get("MEM0_LLM_PROVIDER", "openai")
LLM_MODEL = os.environ.get("MEM0_LLM_MODEL", "gpt-4o-mini")

QDRANT_HOST = os.environ.get("MEM0_QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.environ.get("MEM0_QDRANT_PORT", "6333"))
QDRANT_PATH = os.environ.get("MEM0_QDRANT_PATH")

EMBEDDING_DIMS = {
    "voyageai": {"voyage-3": 1024, "voyage-3-lite": 512, "voyage-2": 1024},
    "openai": {"text-embedding-3-small": 1536, "text-embedding-3-large": 3072},
    "ollama": {"nomic-embed-text": 768, "mxbai-embed-large": 1024},
}


def get_embedding_dims() -> int:
    provider_dims = EMBEDDING_DIMS.get(EMBEDDER_PROVIDER, {})
    return provider_dims.get(EMBEDDER_MODEL, 1024)


def build_config() -> dict:
    config = {
        "version": "v1.1",
        "vector_store": {
            "provider": "qdrant",
            "config": {
                "collection_name": "mem0_memories",
                "embedding_model_dims": get_embedding_dims(),
            },
        },
        "embedder": {
            "provider": EMBEDDER_PROVIDER,
            "config": {
                "model": EMBEDDER_MODEL,
            },
        },
        "llm": {
            "provider": LLM_PROVIDER,
            "config": {
                "model": LLM_MODEL,
                "temperature": 0,
                "max_tokens": 2000,
            },
        },
    }

    if QDRANT_PATH:
        config["vector_store"]["config"]["path"] = QDRANT_PATH
    else:
        config["vector_store"]["config"]["host"] = QDRANT_HOST
        config["vector_store"]["config"]["port"] = QDRANT_PORT

    return config


logger.info(
    f"Initializing mem0 with {EMBEDDER_PROVIDER}/{EMBEDDER_MODEL} embeddings, {LLM_PROVIDER}/{LLM_MODEL} LLM"
)
memory = Memory.from_config(build_config())

mcp = FastMCP("mem0-self-hosted")


@mcp.tool()
def add_memory(
    content: str = Field(description="The content/fact to store as a memory"),
    user_id: Optional[str] = Field(
        default=None, description="User ID to associate with this memory"
    ),
    metadata: Optional[str] = Field(
        default=None, description="JSON string of additional metadata"
    ),
) -> str:
    """Add a new memory to the store. Returns the created memory details."""
    uid = user_id or DEFAULT_USER_ID
    meta = json.loads(metadata) if metadata else None

    result = memory.add(content, user_id=uid, metadata=meta)
    logger.info(f"Added memory for user {uid}: {content[:50]}...")
    return json.dumps(result, indent=2)


@mcp.tool()
def search_memories(
    query: str = Field(description="Search query to find relevant memories"),
    user_id: Optional[str] = Field(
        default=None, description="User ID to search memories for"
    ),
    limit: int = Field(default=10, description="Maximum number of results to return"),
) -> str:
    """Search for memories matching the query. Returns relevant memories with scores."""
    uid = user_id or DEFAULT_USER_ID

    results = memory.search(query, user_id=uid, limit=limit)
    logger.info(f"Search for '{query[:30]}...' returned {len(results)} results")
    return json.dumps(results, indent=2)


@mcp.tool()
def get_all_memories(
    user_id: Optional[str] = Field(
        default=None, description="User ID to get memories for"
    ),
) -> str:
    """Get all memories for a user."""
    uid = user_id or DEFAULT_USER_ID

    results = memory.get_all(user_id=uid)
    logger.info(f"Retrieved {len(results)} memories for user {uid}")
    return json.dumps(results, indent=2)


@mcp.tool()
def get_memory(
    memory_id: str = Field(description="The ID of the memory to retrieve"),
) -> str:
    """Get a specific memory by ID."""
    result = memory.get(memory_id)
    return json.dumps(result, indent=2)


@mcp.tool()
def update_memory(
    memory_id: str = Field(description="The ID of the memory to update"),
    content: str = Field(description="The new content for the memory"),
) -> str:
    """Update an existing memory's content."""
    result = memory.update(memory_id, content)
    logger.info(f"Updated memory {memory_id}")
    return json.dumps(result, indent=2)


@mcp.tool()
def delete_memory(
    memory_id: str = Field(description="The ID of the memory to delete"),
) -> str:
    """Delete a specific memory by ID."""
    memory.delete(memory_id)
    logger.info(f"Deleted memory {memory_id}")
    return json.dumps({"status": "deleted", "memory_id": memory_id})


@mcp.tool()
def delete_all_memories(
    user_id: Optional[str] = Field(
        default=None, description="User ID to delete all memories for"
    ),
) -> str:
    """Delete all memories for a user. Use with caution!"""
    uid = user_id or DEFAULT_USER_ID

    memory.delete_all(user_id=uid)
    logger.info(f"Deleted all memories for user {uid}")
    return json.dumps({"status": "deleted_all", "user_id": uid})


@mcp.tool()
def get_memory_history(
    memory_id: str = Field(description="The ID of the memory to get history for"),
) -> str:
    """Get the history/versions of a specific memory."""
    result = memory.history(memory_id)
    return json.dumps(result, indent=2)


if __name__ == "__main__":
    import sys

    host = "127.0.0.1"
    port = 8050

    args = sys.argv[1:]
    for i, arg in enumerate(args):
        if arg == "--host" and i + 1 < len(args):
            host = args[i + 1]
        elif arg == "--port" and i + 1 < len(args):
            port = int(args[i + 1])

    logger.info(f"Starting mem0 MCP server on {host}:{port}")
    mcp.run(transport="sse", host=host, port=port)
