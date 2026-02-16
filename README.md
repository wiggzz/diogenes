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

### 6. Build a GPU AMI (Automated)

```bash
AWS_REGION=us-east-1 \
make ami-build
```

Optional environment variables:
- `BASE_AMI_ID` (if omitted, script uses regional defaults when available)
- `GPU_SUBNET_ID` (if omitted, script auto-selects a subnet)
- `GPU_SECURITY_GROUP_ID` (if omitted, script auto-selects a security group in the subnet VPC)
- `INSTANCE_TYPE` (default `t3.small`, used only for AMI build instance)
- `AMI_NAME_PREFIX` (default `diogenes-gpu`)
- `USE_SSM_WAIT` (default `1`, uses SSM to detect bootstrap completion)
- `SSM_ONLINE_TIMEOUT` (default `600`)
- `SSM_POLL_INTERVAL` (default `10`)
- `BOOTSTRAP_WAIT_SECONDS` (default `900`)
- `TEMP_INSTANCE_PROFILE` (recommended for SSM wait; instance profile name with `AmazonSSMManagedInstanceCore`)
- `TEMP_KEY_NAME` (optional)
- `KEEP_TEMP_INSTANCE=1` (skip terminate for debugging)

Regional defaults (community-maintained, PRs welcome):

| Region | Base GPU AMI (`BASE_AMI_ID`) | Notes |
|---|---|---|
| `ap-southeast-2` | `ami-021000ae4658b3c28` | Seed default; validate periodically |
| `us-west-2` | `ami-0a08f4510bfe41148` | Seed default; validate periodically |

## Common Commands

- `make setup` - install runtime deps
- `make setup-dev` - install runtime + dev deps
- `make sync-requirements` - regenerate `control_plane/requirements.txt` from `control_plane/pyproject.toml`
- `make ami-build` - build a GPU AMI from `ami/setup.sh` via AWS CLI
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
