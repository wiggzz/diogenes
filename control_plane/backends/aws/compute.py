"""EC2 compute backend — launches and terminates GPU instances."""

from __future__ import annotations

import boto3


class EC2ComputeBackend:
    def __init__(
        self,
        ami_id: str,
        security_group_id: str,
        subnet_id: str,
        instance_profile_arn: str,
        vllm_api_key: str = "",
        endpoint_url: str | None = None,
    ):
        kwargs = {}
        if endpoint_url:
            kwargs["endpoint_url"] = endpoint_url
        self._ec2 = boto3.client("ec2", **kwargs)
        self._ami_id = ami_id
        self._security_group_id = security_group_id
        self._subnet_id = subnet_id
        self._instance_profile_arn = instance_profile_arn
        self._vllm_api_key = vllm_api_key

    def launch(self, model_config: dict) -> tuple[str, str]:
        """Launch an EC2 GPU instance for the given model config.

        Returns (instance_id, private_ip).
        """
        user_data = self._build_user_data(model_config)

        resp = self._ec2.run_instances(
            ImageId=self._ami_id,
            InstanceType=model_config["instance_type"],
            MinCount=1,
            MaxCount=1,
            SecurityGroupIds=[self._security_group_id],
            SubnetId=self._subnet_id,
            IamInstanceProfile={"Arn": self._instance_profile_arn},
            UserData=user_data,
            TagSpecifications=[
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {"Key": "Name", "Value": f"diogenes-{model_config['name']}"},
                        {"Key": "diogenes:model", "Value": model_config["name"]},
                    ],
                }
            ],
        )

        instance = resp["Instances"][0]
        instance_id = instance["InstanceId"]

        # Public IP is used since Lambda runs outside the VPC.
        # It may not be present in the run_instances response yet, so poll
        # describe_instances until it appears (usually within a few seconds).
        public_ip = instance.get("PublicIpAddress", "")
        if not public_ip:
            import time
            for _ in range(20):
                time.sleep(3)
                desc = self._ec2.describe_instances(InstanceIds=[instance_id])
                public_ip = desc["Reservations"][0]["Instances"][0].get("PublicIpAddress", "")
                if public_ip:
                    break

        return instance_id, public_ip

    def terminate(self, instance_id: str) -> None:
        self._ec2.terminate_instances(InstanceIds=[instance_id])

    def _build_user_data(self, model_config: dict) -> str:
        """Build the cloud-init script that starts vLLM."""
        vllm_args = model_config.get("vllm_args", "")
        if self._vllm_api_key:
            vllm_args = f"{vllm_args} --api-key {self._vllm_api_key}".strip()
        return f"""#!/bin/bash
set -euo pipefail

# Write model config
cat > /etc/diogenes-model.env << 'MODELEOF'
MODEL_NAME={model_config['name']}
VLLM_ARGS="{vllm_args}"
MODELEOF

# Ensure LD_LIBRARY_PATH is set in start_vllm.sh for CUDA compat lib fix
# (idempotent — no-op on v1.0.5+ AMIs that already have it)
sed -i 's|-e HF_HOME=/opt/models|-e LD_LIBRARY_PATH=/lib/x86_64-linux-gnu -e HF_HOME=/opt/models|' \
  /opt/diogenes/start_vllm.sh 2>/dev/null || true

# Start vLLM (assumes AMI has vllm installed and systemd service configured)
systemctl start vllm
"""
