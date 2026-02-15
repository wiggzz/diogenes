"""Unit tests for API key management logic (Phase 3)."""

from __future__ import annotations

from control_plane.core import keys


def test_create_key_returns_token_and_persists_hash(state, monkeypatch):
    monkeypatch.setattr(keys.secrets, "token_urlsafe", lambda n: "abc123")
    monkeypatch.setattr(keys.time, "time", lambda: 222)

    created = keys.create_key("user@example.com", "laptop", state)

    assert created["key"] == "dio-abc123"
    assert created["name"] == "laptop"
    assert created["created_at"] == 222

    saved = state.get_api_key(created["key_id"])
    assert saved is not None
    assert saved["email"] == "user@example.com"
    assert saved["name"] == "laptop"
    assert saved["last_used_at"] == 222


def test_list_keys_returns_metadata_without_secret(state):
    state.put_api_key(
        {
            "key_hash": "hash-1",
            "email": "user@example.com",
            "name": "older",
            "created_at": 100,
            "last_used_at": 150,
        }
    )
    state.put_api_key(
        {
            "key_hash": "hash-2",
            "email": "user@example.com",
            "name": "newer",
            "created_at": 200,
            "last_used_at": 250,
        }
    )

    listed = keys.list_keys("user@example.com", state)

    assert [item["key_id"] for item in listed] == ["hash-2", "hash-1"]
    assert all("key" not in item for item in listed)


def test_delete_key_requires_ownership(state):
    state.put_api_key(
        {
            "key_hash": "hash-a",
            "email": "owner@example.com",
            "name": "owner",
            "created_at": 1,
            "last_used_at": 1,
        }
    )

    assert keys.delete_key("hash-a", "other@example.com", state) is False
    assert state.get_api_key("hash-a") is not None

    assert keys.delete_key("hash-a", "owner@example.com", state) is True
    assert state.get_api_key("hash-a") is None
