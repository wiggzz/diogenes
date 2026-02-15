#!/usr/bin/env python3
"""Create a Diogenes API key in DynamoDB.

This script is intentionally manual: it is not auto-run by Lambda or AMI boot.
Use it during environment bootstrapping (e.g., right after `sam deploy`) to seed
an initial API key for programmatic clients before UI-based key creation exists.

Usage:
  python scripts/create_api_key.py --email user@example.com --name laptop
  make seed-api-key EMAIL=user@example.com NAME=laptop
"""

from __future__ import annotations

import argparse
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from control_plane.backends.aws.state import DynamoDBStateStore
from control_plane.core.keys import create_key


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create a Diogenes API key")
    parser.add_argument("--email", required=True, help="Owner email")
    parser.add_argument("--name", default="default", help="Key label")
    parser.add_argument("--instances-table", default=os.environ.get("INSTANCES_TABLE", ""))
    parser.add_argument("--models-table", default=os.environ.get("MODELS_TABLE", ""))
    parser.add_argument("--api-keys-table", default=os.environ.get("API_KEYS_TABLE", ""))
    parser.add_argument("--endpoint-url", default=os.environ.get("AWS_ENDPOINT_URL"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.instances_table or not args.models_table or not args.api_keys_table:
        print("instances/models/api-keys table names are required", file=sys.stderr)
        return 2

    state = DynamoDBStateStore(
        instances_table=args.instances_table,
        models_table=args.models_table,
        api_keys_table=args.api_keys_table,
        endpoint_url=args.endpoint_url,
    )

    payload = create_key(args.email, args.name, state)
    print("Created API key:")
    print(payload["key"])
    print(f"key_id={payload['key_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
