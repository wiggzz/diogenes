#!/usr/bin/env bash
set -euo pipefail

# Phase 1 GPU AMI bootstrap script.
# This script installs NVIDIA container tooling and configures the vLLM service.

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  git \
  jq \
  python3 \
  python3-pip \
  python3-venv \
  docker.io

systemctl enable --now docker

# Install NVIDIA Container Toolkit (required for GPU access in Docker).
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y --no-install-recommends nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Create environment file consumed by systemd service.
cat > /etc/diogenes-model.env <<'EOF'
MODEL_NAME=
VLLM_ARGS=
EOF

# Install vLLM launcher script.
install -d -m 0755 /opt/diogenes
cat > /opt/diogenes/start_vllm.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source /etc/diogenes-model.env

if [[ -z "${MODEL_NAME:-}" ]]; then
  echo "MODEL_NAME is required in /etc/diogenes-model.env"
  exit 1
fi

exec docker run --rm --gpus all --network host \
  -e HUGGING_FACE_HUB_TOKEN="${HUGGING_FACE_HUB_TOKEN:-}" \
  vllm/vllm-openai:latest \
  --model "$MODEL_NAME" \
  --host 0.0.0.0 --port 8000 \
  ${VLLM_ARGS:-}
EOF
chmod +x /opt/diogenes/start_vllm.sh

# Register vLLM systemd service.
cat > /etc/systemd/system/vllm.service <<'EOF'
[Unit]
Description=Diogenes vLLM server
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
EnvironmentFile=/etc/diogenes-model.env
ExecStart=/opt/diogenes/start_vllm.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vllm.service

# Marker used by AMI build automation to detect bootstrap completion.
echo "DIOGENES_BOOTSTRAP_DONE" > /var/log/diogenes-bootstrap.done
