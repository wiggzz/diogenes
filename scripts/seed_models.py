#!/usr/bin/env python3
"""Seed default model configurations into the Diogenes DynamoDB models table."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

DEFAULT_MODELS = [
    {
        "name": "Qwen/Qwen3.5-27B",
        # Path to the pre-downloaded GGUF file in the AMI (must match PrimaryModelGgufFile).
        "model_id": "/opt/models/Qwen_Qwen3.5-27B-Q4_K_M.gguf",
        "instance_type": "g5.2xlarge",
        # llama-server flags: full GPU offload, 64k context, Jinja template for tool calling.
        # --no-mmap is set globally in start_vllm.sh (sequential EBS read vs page-fault random I/O).
        "vllm_args": "-ngl 99 --ctx-size 65536 --jinja",
        "idle_timeout": 300,
    },
    {
        "name": "Qwen/Qwen3.5-4B",
        # Path to the pre-downloaded GGUF file in the AMI (must match SmallModelGgufFile).
        "model_id": "/opt/models/Qwen_Qwen3.5-4B-Q4_K_M.gguf",
        "instance_type": "g5.xlarge",
        # llama-server flags: full GPU offload, 128k context, single slot (parallel 1 so full
        # 22GB VRAM is available for KV cache; n_parallel=4 default would OOM at 128k).
        "vllm_args": "-ngl 99 --ctx-size 131072 --parallel 1 --jinja",
        "idle_timeout": 300,
    },
]


_VLLM_ONLY_FLAGS = {
    "--max-model-len",
    "--reasoning-parser",
    "--enable-auto-tool-choice",
    "--tool-call-parser",
    "--enforce-eager",
    "--tensor-parallel-size",
    "--dtype",
    "--quantization",
}


def validate_model(model: dict) -> None:
    """Raise ValueError if a model config looks wrong for llama-server."""
    name = model.get("name", "?")

    model_id = model.get("model_id") or model.get("name", "")
    if not model_id.startswith("/"):
        raise ValueError(
            f"Model '{name}': model_id must be an absolute path to a GGUF file "
            f"(e.g. /opt/models/foo.gguf), got: {model_id!r}"
        )
    if not model_id.endswith(".gguf"):
        raise ValueError(
            f"Model '{name}': model_id must point to a .gguf file, got: {model_id!r}"
        )

    server_args = model.get("vllm_args", "")
    bad = [flag for flag in _VLLM_ONLY_FLAGS if flag in server_args]
    if bad:
        raise ValueError(
            f"Model '{name}': vllm_args contains vLLM-only flag(s) not supported by "
            f"llama-server: {bad}. Use llama-server flags like -ngl, --ctx-size, --jinja."
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed Diogenes model configurations into DynamoDB")
    parser.add_argument(
        "--environment",
        default=os.environ.get("ENVIRONMENT", "dev"),
        help="Stack environment suffix (default: dev)",
    )
    parser.add_argument(
        "--region",
        default=os.environ.get("AWS_REGION"),
        help="AWS region (or set AWS_REGION)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print models that would be seeded without writing to DynamoDB",
    )
    args = parser.parse_args()

    table_name = f"diogenes-models-{args.environment}"

    for model in DEFAULT_MODELS:
        validate_model(model)

    if args.dry_run:
        print(f"Would seed {len(DEFAULT_MODELS)} model(s) into {table_name}:")
        for model in DEFAULT_MODELS:
            print(json.dumps(model, indent=2))
        return

    import boto3
    dynamodb = boto3.resource("dynamodb", region_name=args.region)
    table = dynamodb.Table(table_name)

    for model in DEFAULT_MODELS:
        table.put_item(Item=model)
        print(f"Seeded: {model['name']} ({model['instance_type']})")

    print(f"\nDone — {len(DEFAULT_MODELS)} model(s) written to {table_name}")


if __name__ == "__main__":
    main()
