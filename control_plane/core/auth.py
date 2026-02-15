"""Authentication helpers for API key validation."""

from __future__ import annotations

import hashlib
import time

from control_plane.core.interfaces import StateStore


def hash_api_key(token: str) -> str:
    """Return SHA-256 hex digest for an API token."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def validate_api_key(token: str, state: StateStore) -> tuple[bool, str | None]:
    """Validate a raw API key token against stored key hashes.

    Returns:
        (is_valid, email)
    """
    if not token or not token.startswith("dio-"):
        return False, None

    key_hash = hash_api_key(token)
    record = state.get_api_key(key_hash)
    if record is None:
        return False, None

    state.update_api_key_last_used(key_hash, int(time.time()))
    return True, record.get("email")
