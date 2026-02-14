.PHONY: test test-unit test-e2e build deploy validate clean

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
