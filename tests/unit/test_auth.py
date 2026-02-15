"""Unit tests for auth core logic (Phase 3)."""

from __future__ import annotations

from control_plane.core import auth


def test_validate_api_key_accepts_existing_key_and_updates_last_used(state, monkeypatch):
    token = "dio-valid-token"
    key_hash = auth.hash_api_key(token)
    state.put_api_key(
        {
            "key_hash": key_hash,
            "email": "user@example.com",
            "name": "laptop",
            "created_at": 10,
            "last_used_at": 10,
        }
    )
    monkeypatch.setattr(auth.time, "time", lambda: 111)

    authorized, email = auth.validate_api_key(token, state)

    assert authorized is True
    assert email == "user@example.com"
    assert state.get_api_key(key_hash)["last_used_at"] == 111


def test_validate_api_key_rejects_invalid_or_missing(state):
    assert auth.validate_api_key("", state) == (False, None)
    assert auth.validate_api_key("Bearer something", state) == (False, None)
    assert auth.validate_api_key("dio-missing", state) == (False, None)
