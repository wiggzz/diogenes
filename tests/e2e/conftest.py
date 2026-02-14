"""E2E test fixtures — testcontainers for LocalStack, mock vLLM server."""

import pytest
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))

from tests.e2e.mock_vllm import MockVLLMServer


@pytest.fixture(scope="session")
def mock_vllm():
    """Start a mock vLLM server on a random port."""
    server = MockVLLMServer()
    server.start()
    yield server
    server.stop()


# LocalStack fixtures will be added in Phase 4 when we have the full
# stack to deploy. For now, E2E tests can use mock backends + mock vLLM.
