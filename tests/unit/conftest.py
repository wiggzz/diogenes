"""Shared fixtures for unit tests — uses mock backends, no Docker needed."""

import pytest
import sys
import os

# Add project root to path so control_plane is importable
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from control_plane.backends.mock.state import InMemoryStateStore
from control_plane.backends.mock.compute import MockComputeBackend


SAMPLE_MODEL_CONFIG = {
    "name": "Qwen/Qwen3-32B",
    "instance_type": "g5.xlarge",
    "idle_timeout": 300,
    "vllm_args": "--max-model-len 32768",
}


@pytest.fixture
def state():
    store = InMemoryStateStore()
    store.put_model_config(SAMPLE_MODEL_CONFIG)
    return store


@pytest.fixture
def compute():
    return MockComputeBackend()
