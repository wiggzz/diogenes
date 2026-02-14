"""Orchestrator — manages GPU instance lifecycle.

Cloud-agnostic: depends on StateStore and ComputeBackend protocols.
"""

from __future__ import annotations

import logging
import time

import requests

from control_plane.core.interfaces import ComputeBackend, StateStore

logger = logging.getLogger(__name__)

VLLM_PORT = 8000


def scale_up(
    model_name: str,
    state: StateStore,
    compute: ComputeBackend,
) -> dict:
    """Launch a GPU instance for the given model (idempotent).

    Returns the instance record.
    """
    # Idempotency: skip if already starting or ready
    existing = state.list_instances(model=model_name, status="starting")
    existing += state.list_instances(model=model_name, status="ready")
    if existing:
        logger.info("Instance already exists for %s: %s", model_name, existing[0]["instance_id"])
        return existing[0]

    # Look up model config
    model_config = state.get_model_config(model_name)
    if model_config is None:
        raise ValueError(f"Unknown model: {model_name}")

    # Launch instance
    logger.info("Launching instance for model %s", model_name)
    instance_id, ip = compute.launch(model_config)

    instance = {
        "instance_id": instance_id,
        "model": model_name,
        "status": "starting",
        "ip": ip,
        "instance_type": model_config["instance_type"],
        "launched_at": int(time.time()),
        "last_request_at": int(time.time()),
    }
    state.put_instance(instance)

    # Poll for health
    healthy = poll_health(ip, VLLM_PORT)
    if healthy:
        state.update_instance(instance_id, status="ready")
        instance["status"] = "ready"
        logger.info("Instance %s is ready", instance_id)
    else:
        logger.error("Instance %s failed health check, terminating", instance_id)
        compute.terminate(instance_id)
        state.update_instance(instance_id, status="terminated")
        instance["status"] = "terminated"

    return instance


def scale_down(
    state: StateStore,
    compute: ComputeBackend,
) -> list[str]:
    """Terminate idle instances past their idle timeout.

    Returns list of terminated instance IDs.
    """
    terminated = []
    now = int(time.time())

    ready_instances = state.list_instances(status="ready")
    for inst in ready_instances:
        model_config = state.get_model_config(inst["model"])
        idle_timeout = 300  # default
        if model_config:
            idle_timeout = int(model_config.get("idle_timeout", 300))

        last_request = int(inst.get("last_request_at", inst.get("launched_at", 0)))
        if now - last_request > idle_timeout:
            logger.info(
                "Terminating idle instance %s (model=%s, idle=%ds)",
                inst["instance_id"],
                inst["model"],
                now - last_request,
            )
            state.update_instance(inst["instance_id"], status="draining")
            compute.terminate(inst["instance_id"])
            state.update_instance(inst["instance_id"], status="terminated")
            terminated.append(inst["instance_id"])

    return terminated


def poll_health(
    ip: str,
    port: int = VLLM_PORT,
    timeout: int = 600,
    interval: int = 10,
) -> bool:
    """Poll an instance's health endpoint until it responds 200 or times out."""
    url = f"http://{ip}:{port}/health"
    deadline = time.time() + timeout

    while time.time() < deadline:
        try:
            resp = requests.get(url, timeout=5)
            if resp.status_code == 200:
                return True
        except requests.RequestException:
            pass
        time.sleep(interval)

    return False
