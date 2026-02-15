#!/usr/bin/env python3
"""Create a Diogenes API key directly in the configured state store."""

from __future__ import annotations

import argparse
import json

from control_plane.backends.aws.state import DynamoDBStateStore
from control_plane.core.keys import create_key
from control_plane.shared.config import API_KEYS_TABLE, INSTANCES_TABLE, MODELS_TABLE


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a Diogenes API key")
    parser.add_argument("--email", required=True, help="Owner email")
    parser.add_argument("--name", default="default", help="Human-friendly key name")
    args = parser.parse_args()

    state = DynamoDBStateStore(
        instances_table=INSTANCES_TABLE(),
        models_table=MODELS_TABLE(),
        api_keys_table=API_KEYS_TABLE(),
    )
    created = create_key(email=args.email, name=args.name, state=state)
    print(json.dumps(created, indent=2))


if __name__ == "__main__":
    main()
