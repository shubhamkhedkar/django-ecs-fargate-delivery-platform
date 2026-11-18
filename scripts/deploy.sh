#!/usr/bin/env bash
# Build -> push to ECR -> gate on scan findings -> run migrations -> roll the ECS service.
#
# Dry-run by default: prints every command and touches nothing. Pass --apply to
# execute against the AWS account in your current credentials; EXPECTED_ACCOUNT_ID
# must match that account as a guard against deploying to the wrong place.
#
#   scripts/deploy.sh                       # dry-run with placeholder config
#   EXPECTED_ACCOUNT_ID=111122223333 scripts/deploy.sh --apply
#
# Requires (only for --apply): aws CLI v2, docker, jq, terraform, git.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPLY=0
TF_DIR="${ROOT}/terraform/stack"
PLATFORM="linux/amd64"
TAG=""
MAX_CRITICAL="${MAX_CRITICAL:-0}"

usage() {
  cat <<USAGE
Usage: $(basename "$0") [--apply] [--tag <git-sha>] [--tf-dir <dir>] [--platform linux/amd64|linux/arm64]

  --apply      Execute for real (default is a dry-run that only prints commands).
  --tag        Image tag; defaults to the short git SHA of HEAD. Must be hex.
  --tf-dir     Terraform root that exposes the deploy_config output.
  --platform   Image platform; match the task definition cpu_architecture.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --tag) TAG="${2:?--tag needs a value}"; shift ;;
    --tf-dir) TF_DIR="${2:?--tf-dir needs a value}"; shift ;;
    --platform) PLATFORM="${2:?--platform needs a value}"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# run <cmd...>: print in dry-run, execute with --apply.
run() {
  if [ "$APPLY" = "1" ]; then
    "$@"
  else
    printf '[dry-run] %s\n' "$*"
  fi
}

if [ -z "$TAG" ]; then
  TAG="$(git -C "$ROOT" rev-parse --short=12 HEAD 2>/dev/null || echo 0000000)"
fi
[[ "$TAG" =~ ^[0-9a-f]{7,40}$ ]] || die "tag '$TAG' must be a git SHA (immutable ECR tags)"
case "$PLATFORM" in linux/amd64 | linux/arm64) ;; *) die "unsupported platform $PLATFORM" ;; esac

# --- configuration -----------------------------------------------------------------
if [ "$APPLY" = "1" ]; then
  for bin in aws docker jq terraform; do
    command -v "$bin" >/dev/null || die "$bin is required for --apply"
  done
  [ -n "${EXPECTED_ACCOUNT_ID:-}" ] || die "set EXPECTED_ACCOUNT_ID to the AWS account you intend to deploy to"
  actual="$(aws sts get-caller-identity --query Account --output text)"
  [ "$actual" = "$EXPECTED_ACCOUNT_ID" ] || die "credentials are for account $actual, expected $EXPECTED_ACCOUNT_ID"
  cfg="$(terraform -chdir="$TF_DIR" output -json deploy_config)"
  REGION="$(jq -r .region <<<"$cfg")"
  REPO="$(jq -r .ecr_repository <<<"$cfg")"
  CLUSTER="$(jq -r .cluster <<<"$cfg")"
  SERVICE="$(jq -r .service <<<"$cfg")"
  WEB_FAMILY="$(jq -r .web_family <<<"$cfg")"
  MIGRATE_FAMILY="$(jq -r .migrate_family <<<"$cfg")"
  SUBNETS="$(jq -r '.subnets | join(",")' <<<"$cfg")"
  SGS="$(jq -r '.security_groups | join(",")' <<<"$cfg")"
else
  REGION="${AWS_REGION:-ap-south-1}"
  REPO="<account>.dkr.ecr.${REGION}.amazonaws.com/release-ledger"
  CLUSTER="release-ledger-prod"
  SERVICE="web"
  WEB_FAMILY="release-ledger-prod-web"
  MIGRATE_FAMILY="release-ledger-prod-migrate"
  SUBNETS="<app-subnet-a>,<app-subnet-b>"
  SGS="<app-sg>"
fi
REGISTRY="${REPO%%/*}"
REPO_NAME="${REPO#*/}"
IMAGE="${REPO}:${TAG}"

log "deploying ${IMAGE} to ${CLUSTER}/${SERVICE} (${REGION}) mode=$([ "$APPLY" = 1 ] && echo APPLY || echo dry-run)"

# --- 1. build ------------------------------------------------------------------------
log "1/6 build image"
run docker build --platform "$PLATFORM" \
  --build-arg GIT_SHA="$TAG" --build-arg APP_VERSION="$TAG" \
  -t "$IMAGE" "$ROOT"

# --- 2. push (tags are immutable, so an existing tag is reused, never overwritten) ---
log "2/6 push to ECR"
if [ "$APPLY" = "1" ]; then
  aws ecr get-login-password --region "$REGION" |
    docker login --username AWS --password-stdin "$REGISTRY"
  if aws ecr describe-images --region "$REGION" --repository-name "$REPO_NAME" \
    --image-ids imageTag="$TAG" >/dev/null 2>&1; then
    log "tag ${TAG} already in ECR; reusing it"
  else
    docker push "$IMAGE"
  fi
else
  run aws ecr get-login-password --region "$REGION" '|' docker login --username AWS --password-stdin "$REGISTRY"
  run docker push "$IMAGE"
fi

# --- 3. scan gate --------------------------------------------------------------------
log "3/6 wait for ECR scan and gate on CRITICAL findings (max ${MAX_CRITICAL})"
run aws ecr wait image-scan-complete --region "$REGION" --repository-name "$REPO_NAME" --image-id imageTag="$TAG"
if [ "$APPLY" = "1" ]; then
  critical="$(aws ecr describe-image-scan-findings --region "$REGION" --repository-name "$REPO_NAME" \
    --image-id imageTag="$TAG" --query 'imageScanFindings.findingSeverityCounts.CRITICAL' --output text)"
  [ "$critical" = "None" ] && critical=0
  [ "$critical" -le "$MAX_CRITICAL" ] || die "image has ${critical} CRITICAL findings; refusing to deploy"
fi

# --- 4. new task definition revisions --------------------------------------------------
# Copy the current revision, swap only the image, drop read-only fields, register.
register_revision() {
  local family="$1"
  if [ "$APPLY" = "1" ]; then
    aws ecs describe-task-definition --region "$REGION" --task-definition "$family" \
      --query taskDefinition --output json |
      jq --arg img "$IMAGE" '.containerDefinitions[0].image = $img
        | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities,
              .registeredAt, .registeredBy, .deregisteredAt)' >"${TMPDIR:-/tmp}/td-${family}.json"
    aws ecs register-task-definition --region "$REGION" \
      --cli-input-json "file://${TMPDIR:-/tmp}/td-${family}.json" \
      --query taskDefinition.taskDefinitionArn --output text
  else
    printf '[dry-run] aws ecs describe-task-definition --task-definition %s | jq (image=%s) | aws ecs register-task-definition\n' \
      "$family" "$IMAGE" >&2
    echo "arn:aws:ecs:${REGION}:<account>:task-definition/${family}:<next>"
  fi
}
log "4/6 register task definition revisions"
MIGRATE_TD="$(register_revision "$MIGRATE_FAMILY")"
WEB_TD="$(register_revision "$WEB_FAMILY")"

# --- 5. migrations as a one-off task -------------------------------------------------
log "5/6 run database migrations (${MIGRATE_TD})"
NETCFG="awsvpcConfiguration={subnets=[${SUBNETS}],securityGroups=[${SGS}],assignPublicIp=DISABLED}"
if [ "$APPLY" = "1" ]; then
  task_arn="$(aws ecs run-task --region "$REGION" --cluster "$CLUSTER" --launch-type FARGATE \
    --task-definition "$MIGRATE_TD" --network-configuration "$NETCFG" \
    --started-by "deploy-${TAG}" --query 'tasks[0].taskArn' --output text)"
  aws ecs wait tasks-stopped --region "$REGION" --cluster "$CLUSTER" --tasks "$task_arn"
  exit_code="$(aws ecs describe-tasks --region "$REGION" --cluster "$CLUSTER" --tasks "$task_arn" \
    --query 'tasks[0].containers[0].exitCode' --output text)"
  [ "$exit_code" = "0" ] || die "migration task exited with ${exit_code}; service left unchanged"
else
  run aws ecs run-task --cluster "$CLUSTER" --launch-type FARGATE --task-definition "$MIGRATE_TD" \
    --network-configuration "$NETCFG"
  run aws ecs wait tasks-stopped --cluster "$CLUSTER" --tasks "<migrate-task-arn>"
fi

# --- 6. rolling update (circuit breaker rolls back automatically on failure) ---------
log "6/6 update service and wait for steady state"
if [ "$APPLY" = "1" ]; then
  previous="$(aws ecs describe-services --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE" \
    --query 'services[0].taskDefinition' --output text)"
  log "previous task definition: ${previous} (manual rollback: update-service --task-definition it)"
fi
run aws ecs update-service --region "$REGION" --cluster "$CLUSTER" --service "$SERVICE" \
  --task-definition "$WEB_TD"
run aws ecs wait services-stable --region "$REGION" --cluster "$CLUSTER" --services "$SERVICE"

log "done: ${IMAGE}"
