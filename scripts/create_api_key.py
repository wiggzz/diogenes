#!/usr/bin/env python3
"""Create a Diogenes API key directly in the configured state store."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

# Ensure repository root is importable when running via uv project context.
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

def _env_name_for_option(option: str) -> str:
    return option.lstrip("-").replace("-", "_").upper()


def _resolve_opt(action: argparse.Action, cli_value: str | None, required: bool = True) -> str | None:
    if cli_value:
        return cli_value
    long_opts = [opt for opt in action.option_strings if opt.startswith("--")]
    canonical_opt = long_opts[0] if long_opts else action.option_strings[0]
    env_name = _env_name_for_option(canonical_opt)
    env_value = os.environ.get(env_name)
    if env_value:
        return env_value
    if required:
        raise RuntimeError(f"Missing {canonical_opt}. Provide {canonical_opt} or set {env_name}.")
    return None


def main() -> None:
    parser = argparse.ArgumentParser(description="Create a Diogenes API key")
    parser.add_argument("--email", required=True, help="Owner email")
    parser.add_argument("--name", default="default", help="Human-friendly key name")
    instances_action = parser.add_argument(
        "--instances-table", help="Instances table name (or use INSTANCES_TABLE)"
    )
    models_action = parser.add_argument(
        "--models-table", help="Models table name (or use MODELS_TABLE)"
    )
    api_keys_action = parser.add_argument(
        "--api-keys-table", help="API keys table name (or use API_KEYS_TABLE)"
    )
    region_action = parser.add_argument(
        "--aws-region",
        "--region",
        dest="aws_region",
        help="AWS region (or use AWS_REGION)",
    )
    args = parser.parse_args()

    instances_table = _resolve_opt(instances_action, args.instances_table)
    models_table = _resolve_opt(models_action, args.models_table)
    api_keys_table = _resolve_opt(api_keys_action, args.api_keys_table)
    region = _resolve_opt(region_action, args.aws_region, required=False)

    from control_plane.backends.aws.state import DynamoDBStateStore
    from control_plane.core.keys import create_key

    state = DynamoDBStateStore(
        instances_table=instances_table,
        models_table=models_table,
        api_keys_table=api_keys_table,
        region_name=region,
    )
    created = create_key(email=args.email, name=args.name, state=state)
    print(json.dumps(created, indent=2))


if __name__ == "__main__":
    main()
