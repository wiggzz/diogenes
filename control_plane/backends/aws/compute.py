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
        # Public IP used since Lambda runs outside the VPC
        public_ip = instance.get("PublicIpAddress", "")
        return instance_id, public_ip

    def terminate(self, instance_id: str) -> None:
        self._ec2.terminate_instances(InstanceIds=[instance_id])

    def _build_user_data(self, model_config: dict) -> str:
        """Build the cloud-init script that starts vLLM."""
        vllm_args = model_config.get("vllm_args", "")
        return f"""#!/bin/bash
set -euo pipefail

# Write model config
cat > /etc/diogenes-model.env << 'MODELEOF'
MODEL_NAME={model_config['name']}
VLLM_ARGS="{vllm_args}"
MODELEOF

# Start vLLM (assumes AMI has vllm installed and systemd service configured)
systemctl start vllm
"""
