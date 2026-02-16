# Diogenes

Diogenes is a personal LLM backend control plane designed to scale GPU inference to zero when idle.

Current status: phases 1-4 are implemented (orchestration, routing, API key auth, and cluster state).

## What Is Included

- AWS SAM template and Lambda handlers (`template.yaml`, `control_plane/backends/aws/handlers.py`)
- Cloud-agnostic core logic (`control_plane/core/`)
- AWS and mock backends (`control_plane/backends/aws/`, `control_plane/backends/mock/`)
- Unit and E2E tests (`tests/unit/`, `tests/e2e/`)

## Quickstart

### 1. Prerequisites

- Python 3.12+
- `uv`
- Docker (required for LocalStack E2E tests)
- Optional: AWS SAM CLI (for build/deploy)

### 2. Install Dependencies

```bash
make setup-dev
```

### 3. Run Unit Tests (Fast Feedback)

```bash
make test-unit
```

### 4. Run E2E Tests (LocalStack + Mock vLLM)

```bash
make test-e2e
```

### 5. Optional: Build/Validate SAM Template

```bash
make validate
make build
```

## Common Commands

- `make setup` - install runtime deps
- `make setup-dev` - install runtime + dev deps
- `make sync-requirements` - regenerate `control_plane/requirements.txt` from `control_plane/pyproject.toml`
- `make test` - run default test target (`test-unit`)
- `make test-unit` - run unit tests
- `make test-e2e` - run E2E tests
- `make validate` - validate SAM template
- `make build` - SAM build
- `make deploy` - SAM deploy

Dependency note:
- `control_plane/pyproject.toml` is the source of truth.
- `make build` runs `make sync-requirements` first so SAM packaging stays in sync.

## Repository Layout

- `control_plane/core/` - cloud-agnostic domain logic
- `control_plane/backends/aws/` - AWS implementations + Lambda handlers
- `control_plane/backends/mock/` - in-memory/mock implementations for testing
- `tests/unit/` - unit tests with mock backends
- `tests/e2e/` - E2E tests (mock vLLM + optional LocalStack)
- `scripts/create_api_key.py` - API key creation helper
