#!/usr/bin/env bash
set -euo pipefail

# Managed AMI build flow using AWS Image Builder.
#
# Usage:
#   ./ami/imagebuilder.sh deploy
#   ./ami/imagebuilder.sh start
#   ./ami/imagebuilder.sh latest
#   ./ami/imagebuilder.sh build   # deploy + start + wait + print AMI
#
# Required env vars:
#   AWS_REGION
#
# Optional env vars:
#   AMI_PIPELINE_STACK     (default: diogenes-ami-pipeline)
#   AMI_PIPELINE_ENV       (default: dev)
#   BASE_AMI_ID            (auto-selected by region if omitted)
#   BUILDER_SUBNET_ID      (auto-selected if omitted)
#   BUILDER_SECURITY_GROUP_ID (auto-selected if omitted)
#   BUILDER_INSTANCE_TYPE  (default: t3.small)
#   IMAGE_VERSION          (default: 1.0.0)
#   PIPELINE_STATUS        (default: DISABLED)

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Missing required env var: ${name}" >&2
    exit 1
  fi
}

require AWS_REGION

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found on PATH" >&2
  exit 1
fi

cmd="${1:-build}"
AMI_PIPELINE_STACK="${AMI_PIPELINE_STACK:-diogenes-ami-pipeline}"
AMI_PIPELINE_ENV="${AMI_PIPELINE_ENV:-dev}"
BUILDER_INSTANCE_TYPE="${BUILDER_INSTANCE_TYPE:-t3.small}"
IMAGE_VERSION="${IMAGE_VERSION:-1.0.0}"
PIPELINE_STATUS="${PIPELINE_STATUS:-DISABLED}"
TEMPLATE_FILE="${TEMPLATE_FILE:-ami/imagebuilder-template.yaml}"

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
    --subnet-ids "${BUILDER_SUBNET_ID}" \
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

resolve_defaults() {
  if [[ -z "${BASE_AMI_ID:-}" ]]; then
    BASE_AMI_ID="$(default_base_ami_for_region "${AWS_REGION}")"
  fi
  if [[ -z "${BASE_AMI_ID:-}" ]]; then
    echo "Missing BASE_AMI_ID and no regional default exists for AWS_REGION=${AWS_REGION}" >&2
    exit 1
  fi

  if [[ -z "${BUILDER_SUBNET_ID:-}" ]]; then
    if BUILDER_SUBNET_ID="$(resolve_subnet_id)"; then
      echo "Auto-selected BUILDER_SUBNET_ID=${BUILDER_SUBNET_ID}"
    else
      echo "Missing BUILDER_SUBNET_ID and no subnet could be auto-discovered in ${AWS_REGION}" >&2
      exit 1
    fi
  fi

  vpc_id="$(resolve_vpc_for_subnet)"
  if [[ -z "${vpc_id}" || "${vpc_id}" == "None" ]]; then
    echo "Unable to determine VPC for subnet ${BUILDER_SUBNET_ID}" >&2
    exit 1
  fi

  if [[ -z "${BUILDER_SECURITY_GROUP_ID:-}" ]]; then
    if BUILDER_SECURITY_GROUP_ID="$(resolve_security_group_id)"; then
      echo "Auto-selected BUILDER_SECURITY_GROUP_ID=${BUILDER_SECURITY_GROUP_ID} (vpc=${vpc_id})"
    else
      echo "Missing BUILDER_SECURITY_GROUP_ID and no security group could be auto-discovered for VPC ${vpc_id}" >&2
      exit 1
    fi
  fi
}

deploy_pipeline_stack() {
  resolve_defaults
  echo "Deploying Image Builder stack ${AMI_PIPELINE_STACK} in ${AWS_REGION}..."
  aws cloudformation deploy \
    --region "${AWS_REGION}" \
    --stack-name "${AMI_PIPELINE_STACK}" \
    --template-file "${TEMPLATE_FILE}" \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      Environment="${AMI_PIPELINE_ENV}" \
      BaseAmiId="${BASE_AMI_ID}" \
      BuilderSubnetId="${BUILDER_SUBNET_ID}" \
      BuilderSecurityGroupId="${BUILDER_SECURITY_GROUP_ID}" \
      BuilderInstanceType="${BUILDER_INSTANCE_TYPE}" \
      ImageVersion="${IMAGE_VERSION}" \
      PipelineStatus="${PIPELINE_STATUS}"
}

get_pipeline_arn() {
  aws cloudformation describe-stacks \
    --region "${AWS_REGION}" \
    --stack-name "${AMI_PIPELINE_STACK}" \
    --query "Stacks[0].Outputs[?OutputKey=='ImagePipelineArn'].OutputValue | [0]" \
    --output text
}

wait_for_build() {
  local image_build_arn="$1"
  echo "Waiting for image build: ${image_build_arn}"

  while true; do
    local status
    status="$(
      aws imagebuilder get-image \
        --region "${AWS_REGION}" \
        --image-build-version-arn "${image_build_arn}" \
        --query "image.state.status" \
        --output text
    )"
    case "${status}" in
      AVAILABLE)
        local ami_id
        ami_id="$(
          aws imagebuilder get-image \
            --region "${AWS_REGION}" \
            --image-build-version-arn "${image_build_arn}" \
            --query "image.outputResources.amis[0].image" \
            --output text
        )"
        if [[ -z "${ami_id}" || "${ami_id}" == "None" ]]; then
          ami_id="$(
            aws imagebuilder get-image \
              --region "${AWS_REGION}" \
              --image-build-version-arn "${image_build_arn}" \
              --query "image.outputResources.amis[0].imageId" \
              --output text
          )"
        fi
        echo "AMI is ready: ${ami_id}"
        echo "Use this value for GpuAmiId."
        break
        ;;
      FAILED | CANCELLED)
        echo "Image build failed with status=${status}" >&2
        aws imagebuilder get-image \
          --region "${AWS_REGION}" \
          --image-build-version-arn "${image_build_arn}" \
          --query "image.state" \
          --output json >&2 || true
        exit 1
        ;;
      *)
        echo "Current status: ${status}. Waiting 30s..."
        sleep 30
        ;;
    esac
  done
}

start_pipeline_build() {
  local pipeline_arn
  pipeline_arn="$(get_pipeline_arn)"
  if [[ -z "${pipeline_arn}" || "${pipeline_arn}" == "None" ]]; then
    echo "ImagePipelineArn not found. Run deploy first." >&2
    exit 1
  fi

  local image_build_arn
  image_build_arn="$(
    aws imagebuilder start-image-pipeline-execution \
      --region "${AWS_REGION}" \
      --image-pipeline-arn "${pipeline_arn}" \
      --query "imageBuildVersionArn" \
      --output text
  )"
  echo "Started image build: ${image_build_arn}"
  wait_for_build "${image_build_arn}"
}

print_latest_ami() {
  local pipeline_arn
  pipeline_arn="$(get_pipeline_arn)"
  if [[ -z "${pipeline_arn}" || "${pipeline_arn}" == "None" ]]; then
    echo "ImagePipelineArn not found. Run deploy first." >&2
    exit 1
  fi

  local latest_image_arn
  latest_image_arn="$(
    aws imagebuilder list-image-pipeline-images \
      --region "${AWS_REGION}" \
      --image-pipeline-arn "${pipeline_arn}" \
      --query "sort_by(imageSummaryList,&dateCreated)[-1].arn" \
      --output text
  )"
  if [[ -z "${latest_image_arn}" || "${latest_image_arn}" == "None" ]]; then
    echo "No images found for pipeline ${pipeline_arn}" >&2
    exit 1
  fi

  local ami_id
  ami_id="$(
    aws imagebuilder get-image \
      --region "${AWS_REGION}" \
      --image-build-version-arn "${latest_image_arn}" \
      --query "image.outputResources.amis[0].image" \
      --output text
  )"
  if [[ -z "${ami_id}" || "${ami_id}" == "None" ]]; then
    ami_id="$(
      aws imagebuilder get-image \
        --region "${AWS_REGION}" \
        --image-build-version-arn "${latest_image_arn}" \
        --query "image.outputResources.amis[0].imageId" \
        --output text
    )"
  fi
  echo "${ami_id}"
}

case "${cmd}" in
  deploy)
    deploy_pipeline_stack
    ;;
  start)
    start_pipeline_build
    ;;
  latest)
    print_latest_ami
    ;;
  build)
    deploy_pipeline_stack
    start_pipeline_build
    ;;
  *)
    echo "Unknown command: ${cmd}" >&2
    echo "Usage: $0 [deploy|start|latest|build]" >&2
    exit 1
    ;;
esac
