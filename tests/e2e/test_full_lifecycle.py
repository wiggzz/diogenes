"""E2E lifecycle test using mock backends + mock vLLM server."""

from __future__ import annotations

from control_plane.backends.mock.compute import MockComputeBackend
from control_plane.backends.mock.state import InMemoryStateStore
from control_plane.core import orchestrator, router


def test_full_cold_start_inference_and_scale_down_cycle(mock_vllm, monkeypatch):
    state = InMemoryStateStore()
    state.put_model_config(
        {
            "name": "Qwen/Qwen3-32B",
            "instance_type": "g5.xlarge",
            "idle_timeout": 1,
        }
    )
    compute = MockComputeBackend(mock_ip=mock_vllm.host)

    triggered = []
    cold = router.handle_inference(
        model="Qwen/Qwen3-32B",
        body={"model": "Qwen/Qwen3-32B", "messages": [{"role": "user", "content": "hi"}]},
        state=state,
        trigger_scale_up=triggered.append,
    )
    assert cold["status_code"] == 503
    assert triggered == ["Qwen/Qwen3-32B"]

    monkeypatch.setattr(orchestrator, "VLLM_PORT", mock_vllm.port)
    up = orchestrator.scale_up("Qwen/Qwen3-32B", state, compute)
    assert up["status"] == "ready"

    monkeypatch.setattr(router, "VLLM_PORT", mock_vllm.port)
    warm = router.handle_inference(
        model="Qwen/Qwen3-32B",
        body={"model": "Qwen/Qwen3-32B", "messages": [{"role": "user", "content": "hello"}]},
        state=state,
        trigger_scale_up=lambda *_: None,
    )
    assert warm["status_code"] == 200
    assert warm["body"]["id"] == "chatcmpl-mock"

    instance = state.get_instance("model#Qwen/Qwen3-32B")
    state.update_instance(instance["instance_id"], last_request_at=0)
    monkeypatch.setattr(orchestrator.time, "time", lambda: 10)

    terminated = orchestrator.scale_down(state, compute)
    assert terminated == ["model#Qwen/Qwen3-32B"]
    assert state.get_instance("model#Qwen/Qwen3-32B")["status"] == "terminated"
