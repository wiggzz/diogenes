.PHONY: test test-unit test-e2e build deploy validate clean seed-api-key

test: test-unit

test-unit:
	python -m pytest tests/unit/ -v

test-e2e:
	python -m pytest tests/e2e/ -v

build:
	sam build

deploy: build
	sam deploy

validate:
	sam validate

clean:
	rm -rf .aws-sam/


seed-api-key:
	@if [ -z "$$EMAIL" ]; then echo "Usage: make seed-api-key EMAIL=user@example.com [NAME=laptop]"; exit 2; fi
	python scripts/create_api_key.py --email "$$EMAIL" --name "$${NAME:-default}"

