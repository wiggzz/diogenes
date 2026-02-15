"""API key authentication helpers."""

from __future__ import annotations

import hashlib
import hmac

from control_plane.core.interfaces import StateStore


def hash_api_key(token: str) -> str:
    """Return SHA-256 hash for a raw API token."""
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def validate_api_key(token: str, state: StateStore) -> tuple[bool, str]:
    """Validate a raw API token against the state store.

    Returns:
        (is_valid, email)
    """
    key_hash = hash_api_key(token)
    record = state.get_api_key(key_hash)
    if not record:
        return False, ""

    expected_hash = record.get("key_hash", "")
    if not hmac.compare_digest(expected_hash, key_hash):
        return False, ""

    return True, record.get("email", "")
