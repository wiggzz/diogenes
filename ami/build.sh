#!/usr/bin/env bash
set -euo pipefail

# Build a Diogenes GPU AMI from a base AMI using ami/setup.sh.
#
# Required env vars:
#   AWS_REGION
#
# Optional env vars:
#   BASE_AMI_ID             (if omitted, script uses regional defaults when available)
#   GPU_SUBNET_ID           (if omitted, script auto-selects a subnet)
#   GPU_SECURITY_GROUP_ID   (if omitted, script auto-selects a security group in subnet VPC)
#   INSTANCE_TYPE            (default: t3.small, used only for AMI build instance)
#   AMI_NAME_PREFIX          (default: diogenes-gpu)
#   USE_SSM_WAIT             (default: 1; set 0 to disable)
#   SSM_ONLINE_TIMEOUT       (default: 600)
#   SSM_POLL_INTERVAL        (default: 10)
#   BOOTSTRAP_WAIT_SECONDS   (default: 900)
#   TEMP_INSTANCE_PROFILE    (optional instance profile name)
#   TEMP_KEY_NAME            (optional EC2 key pair name)
#   KEEP_TEMP_INSTANCE       (set to 1 to skip terminate)

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: ${name}" >&2
    exit 1
  fi
}

require AWS_REGION

INSTANCE_TYPE="${INSTANCE_TYPE:-t3.small}"
AMI_NAME_PREFIX="${AMI_NAME_PREFIX:-diogenes-gpu}"
USE_SSM_WAIT="${USE_SSM_WAIT:-1}"
SSM_ONLINE_TIMEOUT="${SSM_ONLINE_TIMEOUT:-600}"
SSM_POLL_INTERVAL="${SSM_POLL_INTERVAL:-10}"
BOOTSTRAP_WAIT_SECONDS="${BOOTSTRAP_WAIT_SECONDS:-900}"
KEEP_TEMP_INSTANCE="${KEEP_TEMP_INSTANCE:-0}"

default_base_ami_for_region() {
  case "$1" in
    ap-southeast-2) echo "ami-021000ae4658b3c28" ;;
    us-west-2) echo "ami-0a08f4510bfe41148" ;;
    *) echo "" ;;
  esac
}

resolve_subnet_id() {
  local subnet_id
  subnet_id="$(
    aws ec2 describe-subnets \
      --region "${AWS_REGION}" \
      --filters "Name=default-for-az,Values=true" "Name=state,Values=available" \
      --query "sort_by(Subnets,&AvailabilityZone)[0].SubnetId" \
      --output text 2>/dev/null || true
  )"
  if [[ -n "${subnet_id}" && "${subnet_id}" != "None" ]]; then
    echo "${subnet_id}"
    return 0
  fi

  subnet_id="$(
    aws ec2 describe-subnets \
      --region "${AWS_REGION}" \
      --filters "Name=state,Values=available" \
      --query "sort_by(Subnets,&AvailabilityZone)[0].SubnetId" \
      --output text 2>/dev/null || true
  )"
  if [[ -n "${subnet_id}" && "${subnet_id}" != "None" ]]; then
    echo "${subnet_id}"
    return 0
  fi

  return 1
}

resolve_vpc_for_subnet() {
  aws ec2 describe-subnets \
    --region "${AWS_REGION}" \
    --subnet-ids "${GPU_SUBNET_ID}" \
    --query "Subnets[0].VpcId" \
    --output text
}

resolve_security_group_id() {
  local sg_id
  sg_id="$(
    aws ec2 describe-security-groups \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" "Name=group-name,Values=default" \
      --query "SecurityGroups[0].GroupId" \
      --output text 2>/dev/null || true
  )"
  if [[ -n "${sg_id}" && "${sg_id}" != "None" ]]; then
    echo "${sg_id}"
    return 0
  fi

  sg_id="$(
    aws ec2 describe-security-groups \
      --region "${AWS_REGION}" \
      --filters "Name=vpc-id,Values=${vpc_id}" \
      --query "SecurityGroups[0].GroupId" \
      --output text 2>/dev/null || true
  )"
  if [[ -n "${sg_id}" && "${sg_id}" != "None" ]]; then
    echo "${sg_id}"
    return 0
  fi

  return 1
}

resolve_temp_instance_profile() {
  local profiles
  profiles="$(
    aws iam list-instance-profiles \
      --query "InstanceProfiles[].InstanceProfileName" \
      --output text 2>/dev/null || true
  )"
  if [[ -z "${profiles}" || "${profiles}" == "None" ]]; then
    return 1
  fi

  local profile role has_ssm
  for profile in ${profiles}; do
    role="$(
      aws iam get-instance-profile \
        --instance-profile-name "${profile}" \
        --query "InstanceProfile.Roles[0].RoleName" \
        --output text 2>/dev/null || true
    )"
    if [[ -z "${role}" || "${role}" == "None" ]]; then
      continue
    fi
    has_ssm="$(
      aws iam list-attached-role-policies \
        --role-name "${role}" \
        --query "contains(AttachedPolicies[].PolicyArn, 'arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore')" \
        --output text 2>/dev/null || true
    )"
    if [[ "${has_ssm}" == "True" ]]; then
      echo "${profile}"
      return 0
    fi
  done

  return 1
}

if [[ -z "${BASE_AMI_ID:-}" ]]; then
  BASE_AMI_ID="$(default_base_ami_for_region "${AWS_REGION}")"
fi

if [[ -z "${BASE_AMI_ID:-}" ]]; then
  echo "Missing BASE_AMI_ID and no regional default exists for AWS_REGION=${AWS_REGION}" >&2
  echo "Set BASE_AMI_ID explicitly or add a default in ami/build.sh." >&2
  exit 1
fi

if [[ -z "${GPU_SUBNET_ID:-}" ]]; then
  if GPU_SUBNET_ID="$(resolve_subnet_id)"; then
    echo "Auto-selected GPU_SUBNET_ID=${GPU_SUBNET_ID}"
  else
    echo "Missing GPU_SUBNET_ID and no subnet could be auto-discovered in ${AWS_REGION}" >&2
    exit 1
  fi
fi

vpc_id="$(resolve_vpc_for_subnet)"
if [[ -z "${vpc_id}" || "${vpc_id}" == "None" ]]; then
  echo "Unable to determine VPC for subnet ${GPU_SUBNET_ID}" >&2
  exit 1
fi

if [[ -z "${GPU_SECURITY_GROUP_ID:-}" ]]; then
  if GPU_SECURITY_GROUP_ID="$(resolve_security_group_id)"; then
    echo "Auto-selected GPU_SECURITY_GROUP_ID=${GPU_SECURITY_GROUP_ID} (vpc=${vpc_id})"
  else
    echo "Missing GPU_SECURITY_GROUP_ID and no security group could be auto-discovered for VPC ${vpc_id}" >&2
    exit 1
  fi
fi

if [[ "${USE_SSM_WAIT}" == "1" && -z "${TEMP_INSTANCE_PROFILE:-}" ]]; then
  if TEMP_INSTANCE_PROFILE="$(resolve_temp_instance_profile)"; then
    echo "Auto-selected TEMP_INSTANCE_PROFILE=${TEMP_INSTANCE_PROFILE} for SSM checks"
  else
    echo "No SSM-capable TEMP_INSTANCE_PROFILE found; disabling SSM wait and using fixed wait fallback." >&2
    USE_SSM_WAIT="0"
  fi
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found on PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="${SCRIPT_DIR}/setup.sh"
if [[ ! -f "${SETUP_SCRIPT}" ]]; then
  echo "Setup script not found: ${SETUP_SCRIPT}" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%d-%H%M%S)"
ami_name="${AMI_NAME_PREFIX}-${timestamp}"
instance_id=""
image_id=""

cleanup() {
  if [[ "${KEEP_TEMP_INSTANCE}" == "1" ]]; then
    return
  fi
  if [[ -n "${instance_id}" ]]; then
    aws ec2 terminate-instances \
      --region "${AWS_REGION}" \
      --instance-ids "${instance_id}" >/dev/null || true
  fi
}
trap cleanup EXIT

wait_for_ssm_online() {
  local deadline=$((SECONDS + SSM_ONLINE_TIMEOUT))
  while (( SECONDS < deadline )); do
    local count
    count="$(
      aws ssm describe-instance-information \
        --region "${AWS_REGION}" \
        --filters "Key=InstanceIds,Values=${instance_id}" \
        --query "length(InstanceInformationList[?PingStatus=='Online'])" \
        --output text 2>/dev/null || echo "0"
    )"
    if [[ "${count}" == "1" ]]; then
      return 0
    fi
    sleep "${SSM_POLL_INTERVAL}"
  done
  return 1
}

wait_for_bootstrap_via_ssm() {
  echo "Waiting for instance to register with SSM..."
  if ! wait_for_ssm_online; then
    echo "SSM online check timed out after ${SSM_ONLINE_TIMEOUT}s." >&2
    return 1
  fi

  echo "Running bootstrap completion checks via SSM..."
  local cmd_id
  cmd_id="$(
    aws ssm send-command \
      --region "${AWS_REGION}" \
      --instance-ids "${instance_id}" \
      --document-name "AWS-RunShellScript" \
      --comment "Wait for Diogenes bootstrap completion" \
      --parameters '{"commands":["cloud-init status --wait","test -f /var/log/diogenes-bootstrap.done","systemctl is-enabled vllm.service","systemctl is-active docker"]}' \
      --query "Command.CommandId" \
      --output text
  )"

  aws ssm wait command-executed \
    --region "${AWS_REGION}" \
    --command-id "${cmd_id}" \
    --instance-id "${instance_id}"

  local status
  status="$(
    aws ssm get-command-invocation \
      --region "${AWS_REGION}" \
      --command-id "${cmd_id}" \
      --instance-id "${instance_id}" \
      --query "Status" \
      --output text
  )"

  if [[ "${status}" != "Success" ]]; then
    echo "SSM bootstrap check failed with status: ${status}" >&2
    aws ssm get-command-invocation \
      --region "${AWS_REGION}" \
      --command-id "${cmd_id}" \
      --instance-id "${instance_id}" \
      --query "{StdOut:StandardOutputContent,StdErr:StandardErrorContent}" \
      --output json >&2 || true
    return 1
  fi

  echo "Bootstrap completed (verified by SSM)."
  return 0
}

echo "Launching temporary builder instance in ${AWS_REGION}..."
echo "Using base AMI: ${BASE_AMI_ID}"
echo "Using subnet: ${GPU_SUBNET_ID}"
echo "Using security group: ${GPU_SECURITY_GROUP_ID}"
run_args=(
  aws ec2 run-instances
  --region "${AWS_REGION}"
  --image-id "${BASE_AMI_ID}"
  --instance-type "${INSTANCE_TYPE}"
  --subnet-id "${GPU_SUBNET_ID}"
  --security-group-ids "${GPU_SECURITY_GROUP_ID}"
  --user-data "file://${SETUP_SCRIPT}"
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${ami_name}-builder},{Key=diogenes:purpose,Value=ami-build}]"
  --query "Instances[0].InstanceId"
  --output text
)

if [[ -n "${TEMP_INSTANCE_PROFILE:-}" ]]; then
  run_args+=(--iam-instance-profile "Name=${TEMP_INSTANCE_PROFILE}")
fi

if [[ -n "${TEMP_KEY_NAME:-}" ]]; then
  run_args+=(--key-name "${TEMP_KEY_NAME}")
fi

instance_id="$("${run_args[@]}")"
echo "Builder instance: ${instance_id}"

echo "Waiting for instance to enter running state..."
aws ec2 wait instance-running --region "${AWS_REGION}" --instance-ids "${instance_id}"

echo "Waiting for EC2 status checks..."
aws ec2 wait instance-status-ok --region "${AWS_REGION}" --instance-ids "${instance_id}"

if [[ "${USE_SSM_WAIT}" == "1" ]]; then
  if ! wait_for_bootstrap_via_ssm; then
    echo "Falling back to fixed wait: ${BOOTSTRAP_WAIT_SECONDS}s..."
    sleep "${BOOTSTRAP_WAIT_SECONDS}"
  fi
else
  echo "Waiting ${BOOTSTRAP_WAIT_SECONDS}s for bootstrap script completion..."
  sleep "${BOOTSTRAP_WAIT_SECONDS}"
fi

echo "Creating AMI ${ami_name}..."
image_id="$(
  aws ec2 create-image \
    --region "${AWS_REGION}" \
    --instance-id "${instance_id}" \
    --name "${ami_name}" \
    --description "Diogenes GPU AMI built from ${BASE_AMI_ID} at ${timestamp}" \
    --query "ImageId" \
    --output text
)"
echo "AMI creation started: ${image_id}"

echo "Waiting for AMI to become available..."
aws ec2 wait image-available --region "${AWS_REGION}" --image-ids "${image_id}"

echo
echo "AMI is ready: ${image_id}"
echo "Use this value for CloudFormation parameter GpuAmiId."
echo
echo "Suggested deploy args:"
echo "  --parameter-overrides GpuAmiId=${image_id} GpuSubnetId=${GPU_SUBNET_ID} GpuSecurityGroupId=${GPU_SECURITY_GROUP_ID}"
