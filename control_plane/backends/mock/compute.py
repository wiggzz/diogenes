"""Mock compute backend for testing."""

from __future__ import annotations

import uuid


class MockComputeBackend:
    """Simulates launching/terminating instances.

    In tests, the mock vLLM server runs on localhost. The 'ip' returned by
    launch() points there so the router can proxy to it.
    """

    def __init__(self, mock_ip: str = "127.0.0.1"):
        self.mock_ip = mock_ip
        self.launched: list[dict] = []
        self.terminated: list[str] = []

    def launch(self, model_config: dict) -> tuple[str, str]:
        instance_id = f"i-mock-{uuid.uuid4().hex[:8]}"
        self.launched.append(
            {"instance_id": instance_id, "model_config": model_config}
        )
        return instance_id, self.mock_ip

    def terminate(self, instance_id: str) -> None:
        self.terminated.append(instance_id)
