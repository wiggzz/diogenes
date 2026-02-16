.PHONY: setup setup-dev sync-requirements ami-build test test-unit test-e2e build deploy validate clean

setup:
	uv sync --project control_plane

setup-dev:
	uv sync --project control_plane --extra dev

sync-requirements:
	uv export --project control_plane --no-dev --no-hashes --no-header --output-file control_plane/requirements.txt

ami-build:
	./ami/build.sh

test: test-unit

test-unit:
	uv run --project control_plane --no-sync pytest tests/unit/ -v

test-e2e:
	uv run --project control_plane --no-sync pytest tests/e2e/ -v

build: sync-requirements
	sam build

deploy: build
	sam deploy

validate:
	sam validate

clean:
	rm -rf .aws-sam/
