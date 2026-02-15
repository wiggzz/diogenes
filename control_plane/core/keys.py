"""API key management logic."""

from __future__ import annotations

import hashlib
import secrets
import time

from control_plane.core.interfaces import StateStore


KEY_PREFIX = "dio-"
KEY_SECRET_BYTES = 24


def _hash_api_key(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_key(email: str, name: str, state: StateStore) -> dict:
    """Create and persist a new API key for a user.

    Returns both metadata and the raw token (only once).
    """
    token = f"{KEY_PREFIX}{secrets.token_urlsafe(KEY_SECRET_BYTES)}"
    now = int(time.time())
    key_hash = _hash_api_key(token)

    record = {
        "key_hash": key_hash,
        "email": email,
        "name": name,
        "created_at": now,
        "last_used_at": now,
    }
    state.put_api_key(record)

    return {
        "key": token,
        "key_id": key_hash,
        "name": name,
        "created_at": now,
        "last_used_at": now,
    }


def list_keys(email: str, state: StateStore) -> list[dict]:
    """List API key metadata for a user (never returns raw key)."""
    keys = state.list_api_keys(email)
    return [
        {
            "key_id": item["key_hash"],
            "name": item.get("name", "default"),
            "created_at": item.get("created_at"),
            "last_used_at": item.get("last_used_at"),
        }
        for item in sorted(keys, key=lambda item: item.get("created_at", 0), reverse=True)
    ]


def delete_key(key_hash: str, email: str, state: StateStore) -> bool:
    """Delete a key only if it belongs to the requesting user."""
    existing = state.get_api_key(key_hash)
    if existing is None or existing.get("email") != email:
        return False

    state.delete_api_key(key_hash)
    return True
