#!/usr/bin/env bash
# Show vLLM startup logs and cluster status for active GPU instances.
#
# Usage:
#   ./scripts/instance-logs.sh            # logs for all active instances
#   MODEL=Qwen3.5-4B ./scripts/instance-logs.sh   # filter by model
#   LINES=100 ./scripts/instance-logs.sh  # more lines (default: 60)
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || true)}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
INSTANCES_TABLE="diogenes-instances-${ENVIRONMENT}"
LINES="${LINES:-60}"
MODEL_FILTER="${MODEL:-}"

if [[ -z "${AWS_REGION}" ]]; then
  echo "AWS_REGION is required" >&2
  exit 1
fi

# Fetch all non-terminated instances
items="$(
  aws dynamodb scan \
    --region "${AWS_REGION}" \
    --table-name "${INSTANCES_TABLE}" \
    --filter-expression "#s <> :t" \
    --expression-attribute-names '{"#s":"status"}' \
    --expression-attribute-values '{":t":{"S":"terminated"}}' \
    --output json
)"

count="$(echo "${items}" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('Items',[])))")"
if [[ "${count}" == "0" ]]; then
  echo "No active instances found in ${INSTANCES_TABLE}."
  exit 0
fi

echo "${items}" | python3 - <<'PYEOF'
import json, subprocess, sys, os, time

data = json.loads(sys.stdin.read())
region = os.environ["AWS_REGION"]
lines = os.environ.get("LINES", "60")
model_filter = os.environ.get("MODEL_FILTER", "")

def g(item, key):
    return list(item.get(key, {}).values())[0] if key in item else ""

for item in data.get("Items", []):
    ec2_id = g(item, "provider_instance_id")
    model  = g(item, "model")
    status = g(item, "status")
    ip     = g(item, "ip")

    if model_filter and model_filter not in model:
        continue

    launched = g(item, "launched_at")
    if launched:
        import datetime
        age_s = int(time.time()) - int(launched)
        age   = f"{age_s//60}m{age_s%60}s"
    else:
        age = "?"

    print(f"\n{'='*70}")
    print(f"  model   : {model}")
    print(f"  status  : {status}  (age: {age})")
    print(f"  ip      : {ip}")
    print(f"  ec2     : {ec2_id}")
    print(f"{'='*70}")

    if not ec2_id or not ec2_id.startswith("i-"):
        print("  (no EC2 instance ID recorded)")
        continue

    # Check EC2 state
    try:
        r = subprocess.run(
            ["aws", "ec2", "describe-instances", "--region", region,
             "--instance-ids", ec2_id,
             "--query", "Reservations[0].Instances[0].State.Name",
             "--output", "text"],
            capture_output=True, text=True, timeout=10
        )
        ec2_state = r.stdout.strip()
        print(f"  ec2 state: {ec2_state}")
    except Exception as e:
        print(f"  ec2 state: error ({e})")

    # Check health endpoint
    try:
        r = subprocess.run(
            ["curl", "-sf", "--connect-timeout", "3", "--max-time", "5",
             f"http://{ip}:8000/health"],
            capture_output=True, text=True, timeout=8
        )
        health = "UP" if r.returncode == 0 else "DOWN"
    except Exception:
        health = "DOWN"
    print(f"  health  : {health}")

    print(f"\n--- vLLM journal (last {lines} lines via SSM) ---")

    # Send SSM command
    try:
        cmd_result = subprocess.run(
            ["aws", "ssm", "send-command",
             "--region", region,
             "--instance-ids", ec2_id,
             "--document-name", "AWS-RunShellScript",
             "--parameters",
             f'commands=["journalctl -u vllm -n {lines} --no-pager 2>&1 || echo \\"vllm service not found\\""]',
             "--output", "json"],
            capture_output=True, text=True, timeout=15
        )
        if cmd_result.returncode != 0:
            print(f"SSM send-command failed: {cmd_result.stderr[:300]}")
            continue

        cmd_data = json.loads(cmd_result.stdout)
        cmd_id = cmd_data["Command"]["CommandId"]

        # Poll for result
        for attempt in range(10):
            time.sleep(3)
            out = subprocess.run(
                ["aws", "ssm", "get-command-invocation",
                 "--region", region,
                 "--command-id", cmd_id,
                 "--instance-id", ec2_id,
                 "--output", "json"],
                capture_output=True, text=True, timeout=10
            )
            if out.returncode != 0:
                continue
            inv = json.loads(out.stdout)
            invocation_status = inv.get("Status", "")
            if invocation_status in ("InProgress", "Pending", "Delayed"):
                print(f"  (waiting for SSM... {invocation_status})", end="\r", flush=True)
                continue
            content = inv.get("StandardOutputContent", "").strip()
            err_content = inv.get("StandardErrorContent", "").strip()
            print(content or "(no output)")
            if err_content:
                print(f"[stderr] {err_content[:500]}")
            break
        else:
            print("  (SSM command timed out)")

    except Exception as e:
        print(f"  SSM error: {e}")

print()
PYEOF
