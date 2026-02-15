"""E2E auth flows through Lambda handlers."""

from __future__ import annotations

import json

from control_plane.backends.aws import handlers
from control_plane.backends.mock.state import InMemoryStateStore


def test_requests_rejected_without_key(monkeypatch):
    state = InMemoryStateStore()
    monkeypatch.setattr(handlers, "_get_state_store", lambda: state)

    result = handlers.authorizer_handler({"headers": {}}, None)

    assert result == {"isAuthorized": False}


def test_key_creation_then_authorizer_accepts_key(monkeypatch):
    state = InMemoryStateStore()
    monkeypatch.setattr(handlers, "_get_state_store", lambda: state)

    create_event = {
        "requestContext": {"http": {"method": "POST"}, "authorizer": {"lambda": {"email": "owner@example.com"}}},
        "rawPath": "/api/keys",
        "body": json.dumps({"name": "laptop"}),
    }
    created = handlers.keys_handler(create_event, None)
    body = json.loads(created["body"])
    raw_key = body["key"]

    auth_event = {"headers": {"authorization": f"Bearer {raw_key}"}}
    auth_result = handlers.authorizer_handler(auth_event, None)

    assert auth_result["isAuthorized"] is True
    assert auth_result["context"]["email"] == "owner@example.com"
