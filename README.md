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

### 5b. One-Command Deploy (Auto Params)

```bash
AWS_REGION=ap-southeast-2 make deploy
```

This command automatically:
- builds/uses a GPU AMI from the Image Builder pipeline
- discovers `GpuSubnetId` and `GpuSecurityGroupId`
- runs `sam build` and `sam deploy` with parameter overrides

Optional deploy environment variables:
- `STACK_NAME` (default `diogenes`)
- `ENVIRONMENT` (default `dev`)
- `AMI_BUILD_MODE=auto` (default): use latest pipeline AMI, build if missing
- `AMI_BUILD_MODE=latest`: require latest pipeline AMI
- `AMI_BUILD_MODE=build`: always build a new AMI first
- `GPU_AMI_ID`, `GPU_SUBNET_ID`, `GPU_SECURITY_GROUP_ID` to override auto-discovery
- `ALLOWED_EMAILS`, `GOOGLE_CLIENT_ID` for auth configuration

### 6. Build a GPU AMI (Image Builder)

```bash
AWS_REGION=us-east-1 \
make ami-build
```

Optional environment variables:
- `BASE_AMI_ID` (if omitted, script uses regional defaults when available)
- `BUILDER_SUBNET_ID` (if omitted, script auto-selects a subnet)
- `BUILDER_SECURITY_GROUP_ID` (if omitted, script auto-selects a security group in the subnet VPC)
- `BUILDER_INSTANCE_TYPE` (default `t3.small`, used only for AMI build instances)
- `IMAGE_VERSION` (default `1.0.2`; bump when recipe changes)
- `AMI_PIPELINE_STACK` (default `diogenes-ami-pipeline`)
- `AMI_PIPELINE_ENV` (default `dev`)
- `PIPELINE_STATUS` (default `DISABLED`)

Useful subcommands:

```bash
AWS_REGION=us-east-1 make ami-build-deploy  # deploy/update pipeline stack only
AWS_REGION=us-east-1 make ami-build-start   # start a new image build
AWS_REGION=us-east-1 make ami-build-latest  # print latest AMI ID from pipeline
```

Regional defaults (community-maintained, PRs welcome):

| Region | Base GPU AMI (`BASE_AMI_ID`) | Notes |
|---|---|---|
| `ap-southeast-2` | `ami-021000ae4658b3c28` | Seed default; validate periodically |
| `us-west-2` | `ami-0a08f4510bfe41148` | Seed default; validate periodically |

## Common Commands

- `make setup` - install runtime deps
- `make setup-dev` - install runtime + dev deps
- `make sync-requirements` - regenerate `control_plane/requirements.txt` from `control_plane/pyproject.toml`
- `make ami-build` - deploy Image Builder stack and build a GPU AMI
- `make ami-build-deploy` - deploy/update Image Builder stack only
- `make ami-build-start` - start a new Image Builder pipeline execution
- `make ami-build-latest` - print latest AMI ID built by pipeline
- `make test` - run default test target (`test-unit`)
- `make test-unit` - run unit tests
- `make test-e2e` - run E2E tests
- `make validate` - validate SAM template
- `make build` - SAM build
- `make deploy` - one-command auto deploy (AMI + network param auto-resolution + SAM deploy)

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
