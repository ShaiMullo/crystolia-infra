#!/bin/bash
set -euo pipefail

# =============================================================================
# Crystolia Staging — Startup
#
# RECREATES (via terraform apply):
#   EKS cluster, managed node group, NAT gateway, VPC + subnets,
#   Helm releases (argocd, aws-load-balancer-controller),
#   IRSA roles (LBC, external-secrets, EBS CSI),
#   EBS CSI addon, ArgoCD root app, StorageClass, ArgoCD Ingress
#
# DOES NOT TOUCH (preserved in state):
#   ECR repositories + all images
#   ACM certificate (*.crystolia.com)
#   Route53 DNS records  ← STALE after restart; update dns.tf manually
#   GitHub OIDC provider + IAM roles
#   Terraform state (S3: crystolia-tf-state-main + DynamoDB)
#   MongoDB S3 backups (s3://crystolia-backups)
#
# REQUIRED AFTER THIS SCRIPT COMPLETES:
#   1. Update ALB hostnames in terraform/dns.tf (see Phase 5 output)
#   2. Run: terraform apply -auto-approve (applies dns.tf changes)
#   3. Restore MongoDB from S3 backup if needed
#
# Usage:
#   bash scripts/startup-all.sh              # full bring-up (default)
#   bash scripts/startup-all.sh up           # same as above
#   bash scripts/startup-all.sh status       # read-only cluster health check
#   bash scripts/startup-all.sh dry-run      # pre-flight + terraform plan only
#
# Secret injection (for 'up' mode):
#   The script will create K8s secret crystolia-backend-secret if it does not
#   exist. Provide JWT_SECRET as an env var to avoid interactive prompt:
#     JWT_SECRET="$(openssl rand -base64 64)" bash scripts/startup-all.sh up
#   MONGO_URI defaults to the internal cluster DNS — override with env var if needed.
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
REGION="us-east-1"
CLUSTER_NAME="crystolia-cluster-demo"
TF_WORKSPACE="demo"
BACKUP_BUCKET="crystolia-backups"
DEFAULT_MONGO_URI="mongodb://crystolia-mongodb:27017/crystolia"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

# =============================================================================
# MODE PARSING
# =============================================================================
MODE="${1:-up}"
case "${MODE}" in
  up|status|dry-run) ;;
  *)
    log_error "Unknown mode: '${MODE}'. Valid modes: up | status | dry-run"
    echo ""
    echo "  bash scripts/startup-all.sh             # full bring-up"
    echo "  bash scripts/startup-all.sh up          # same"
    echo "  bash scripts/startup-all.sh status      # read-only health check"
    echo "  bash scripts/startup-all.sh dry-run     # pre-flight + terraform plan"
    exit 1
    ;;
esac

log_step "Mode: ${MODE}"

# =============================================================================
# STATUS MODE — read-only cluster health check, exits after printing
# =============================================================================
if [[ "${MODE}" == "status" ]]; then
  log_step "Cluster status check (read-only)"

  # AWS identity
  if ! aws sts get-caller-identity &>/dev/null; then
    log_error "AWS credentials not configured or session expired."
    exit 1
  fi
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  log_info "AWS account: ${ACCOUNT_ID} | Region: ${REGION}"

  # EKS cluster
  CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
  if [[ "${CLUSTER_STATUS}" == "NOT_FOUND" ]]; then
    log_warn "EKS cluster '${CLUSTER_NAME}': NOT FOUND — cluster is down or does not exist."
    log_warn "Run: bash scripts/startup-all.sh up"
    exit 0
  fi
  log_info "EKS cluster '${CLUSTER_NAME}': ${CLUSTER_STATUS}"

  # kubeconfig + nodes (update-kubeconfig writes ~/.kube/config but is non-destructive)
  if ! aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" &>/dev/null; then
    log_warn "Could not update kubeconfig — cluster may not be reachable yet."
    exit 0
  fi
  echo ""
  log_info "Nodes:"
  kubectl get nodes -o wide 2>/dev/null || log_warn "kubectl get nodes failed"

  # Namespaces
  echo ""
  log_info "Namespaces:"
  kubectl get ns 2>/dev/null || log_warn "kubectl get ns failed"

  # Pod summary by namespace
  echo ""
  log_info "Pod status by namespace:"
  for NS in argocd crystolia monitoring; do
    if kubectl get ns "${NS}" &>/dev/null; then
      PODS=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      RUNNING=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
      NOT_READY=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -vc "Running" || echo "0")
      log_info "  ${NS}: ${RUNNING}/${PODS} Running  (${NOT_READY} not Running)"
    else
      log_warn "  ${NS}: namespace not found"
    fi
  done

  # ArgoCD apps
  echo ""
  log_info "ArgoCD application status:"
  kubectl get application -n argocd 2>/dev/null || log_warn "Could not query ArgoCD applications"

  # crystolia-backend-secret
  echo ""
  log_info "K8s secret 'crystolia-backend-secret' in namespace 'crystolia':"
  if kubectl get ns crystolia &>/dev/null; then
    if kubectl get secret crystolia-backend-secret -n crystolia &>/dev/null; then
      KEYS=$(kubectl get secret crystolia-backend-secret -n crystolia \
        -o jsonpath='{.data}' 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(d.keys()))" 2>/dev/null || echo "could not parse keys")
      log_info "  EXISTS — keys: ${KEYS}"
    else
      log_warn "  MISSING — backend pod will CrashLoopBackOff without it."
      log_warn "  Run: bash scripts/startup-all.sh up  (will create it)"
    fi
  else
    log_warn "  crystolia namespace not found — ArgoCD may not have synced yet."
  fi

  # ECR
  echo ""
  log_info "ECR repositories:"
  aws ecr describe-repositories --region "${REGION}" \
    --query "repositories[].[repositoryName]" \
    --output table 2>/dev/null || log_warn "Could not query ECR."

  exit 0
fi

# =============================================================================
# PRE-FLIGHT (shared between 'up' and 'dry-run')
# =============================================================================
log_step "Pre-flight checks"

REQUIRED_CMDS=(aws kubectl terraform)
if [[ "${MODE}" == "up" ]]; then
  REQUIRED_CMDS+=(helm)
fi

for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "'${cmd}' not found in PATH. Install it and retry."
    exit 1
  fi
  log_info "  ${cmd}: $(command -v "${cmd}")"
done

if ! aws sts get-caller-identity &>/dev/null; then
  log_error "AWS credentials not configured or session expired. Run 'aws sso login' or refresh credentials."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
log_info "AWS account: ${ACCOUNT_ID} | Region: ${REGION}"
log_info "Caller: ${CALLER_ARN}"

ACTIVE_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo "")}"
if [[ "${ACTIVE_REGION}" != "us-east-1" ]]; then
  log_error "Active AWS region is '${ACTIVE_REGION}', expected 'us-east-1'. Refusing to proceed."
  log_error "Set: export AWS_DEFAULT_REGION=us-east-1  (or configure your AWS profile)"
  exit 1
fi

# Terraform state
cd "${TERRAFORM_DIR}"
log_info "Running terraform init..."
terraform init -reconfigure -input=false

if ! terraform state list &>/dev/null; then
  log_error "Terraform state not accessible after init. Check S3 bucket 'crystolia-tf-state-main' and DynamoDB lock table."
  exit 1
fi
log_info "Terraform state accessible (s3://crystolia-tf-state-main)."

# Terraform workspace
CURRENT_WORKSPACE=$(terraform workspace show 2>/dev/null || echo "default")
if [[ "${CURRENT_WORKSPACE}" != "${TF_WORKSPACE}" ]]; then
  log_warn "Current Terraform workspace: '${CURRENT_WORKSPACE}'. Expected: '${TF_WORKSPACE}'."
  if terraform workspace list 2>/dev/null | grep -qE "(^|\*)[[:space:]]*${TF_WORKSPACE}[[:space:]]*$"; then
    log_info "Selecting workspace '${TF_WORKSPACE}'..."
    terraform workspace select "${TF_WORKSPACE}"
  else
    log_info "Workspace '${TF_WORKSPACE}' not found — creating it..."
    terraform workspace new "${TF_WORKSPACE}"
  fi
fi
log_info "Terraform workspace: $(terraform workspace show)"

# Cluster existence check
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query "cluster.status" --output text 2>/dev/null || echo "NOT_FOUND")
log_info "EKS cluster '${CLUSTER_NAME}': ${CLUSTER_STATUS}"

# =============================================================================
# DRY-RUN MODE — plan only, no apply, no kubectl changes
# =============================================================================
if [[ "${MODE}" == "dry-run" ]]; then
  log_step "Dry-run: terraform plan (no changes will be made)"

  # Note: kubernetes_manifest.root_app has been removed from Terraform.
  # It is applied via kubectl in Phase 3 of 'up' mode.
  # All remaining kubernetes/helm resources (helm_release, kubernetes_ingress_v1,
  # kubernetes_storage_class) plan correctly with (known after apply) provider config.
  log_info "Running terraform plan..."
  terraform plan -input=false

  echo ""
  log_info "Dry-run complete. No resources were created or modified."
  log_info "Note: ArgoCD root-app is applied via kubectl in 'up' mode — it does not appear in this plan."
  log_info "To apply: bash scripts/startup-all.sh up"
  exit 0
fi

# =============================================================================
# UP MODE — everything below only runs in 'up'
# =============================================================================

# Idempotency guard if cluster is already active
if [[ "${CLUSTER_STATUS}" == "ACTIVE" ]]; then
  log_warn "EKS cluster '${CLUSTER_NAME}' already exists and is ACTIVE."
  log_warn "Terraform apply is idempotent — it will reconcile state but create nothing new."
  read -rp "Type CONTINUE to proceed anyway, or press Enter to abort: " GUARD
  if [[ "${GUARD}" != "CONTINUE" ]]; then
    log_info "Aborted — no changes made."
    exit 0
  fi
fi

# =============================================================================
# STARTUP SUMMARY + CONFIRMATION
# =============================================================================
log_step "Startup summary — read carefully"

echo ""
log_info "WILL BE CREATED:"
log_info "  • VPC 10.0.0.0/16 + subnets, route tables, internet gateway"
log_info "  • NAT Gateway + Elastic IP (us-east-1)"
log_info "  • EKS cluster: ${CLUSTER_NAME} (control plane, ~10 min)"
log_info "  • EKS managed node group: general-demo (t3.medium on-demand)"
log_info "  • IRSA roles: LBC, external-secrets, EBS CSI"
log_info "  • EKS addon: aws-ebs-csi-driver"
log_info "  • Helm release: argocd"
log_info "  • Helm release: aws-load-balancer-controller"
log_info "  • ArgoCD root Application → crystolia-gitops/argocd/apps"
log_info "  • StorageClass: gp3-csi"
log_info "  • ArgoCD Ingress (new ALB hostname — update dns.tf after)"
echo ""
log_warn "ESTIMATED TIME: 15–25 minutes (EKS control plane is the bottleneck)"
echo ""
log_warn "COST IMPACT: NAT Gateway + EC2 nodes will immediately start accruing charges."
echo ""
read -rp "Type STARTUP to confirm and proceed: " CONFIRM
if [[ "${CONFIRM}" != "STARTUP" ]]; then
  log_info "Aborted — no changes made."
  exit 0
fi

# =============================================================================
# PHASE 1: Terraform apply
# =============================================================================
log_step "Phase 1: Terraform apply (full)"

# If kubernetes_manifest.root_app is still in state from a prior run (before
# it was removed from .tf files), remove it now — otherwise terraform apply
# would try to destroy a resource it no longer manages in code.
if terraform state list 2>/dev/null | grep -q "^kubernetes_manifest\.root_app$"; then
  log_warn "Removing kubernetes_manifest.root_app from Terraform state (resource moved to kubectl in Phase 3)..."
  terraform state rm kubernetes_manifest.root_app
fi

log_info "Applying all resources. This will take 15–25 minutes..."
terraform apply -auto-approve -input=false

log_info "Terraform apply complete."

# Read cluster name from terraform outputs if available (tolerates missing output)
TF_CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")
if [[ -n "${TF_CLUSTER_NAME}" && "${TF_CLUSTER_NAME}" != "${CLUSTER_NAME}" ]]; then
  log_warn "Terraform output 'cluster_name' = '${TF_CLUSTER_NAME}' differs from hardcoded '${CLUSTER_NAME}'."
  log_warn "Using terraform output value: '${TF_CLUSTER_NAME}'."
  CLUSTER_NAME="${TF_CLUSTER_NAME}"
fi

# =============================================================================
# PHASE 2: Update kubeconfig + verify cluster
# =============================================================================
log_step "Phase 2: Update kubeconfig and verify nodes"

log_info "Updating kubeconfig for cluster '${CLUSTER_NAME}'..."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

log_info "Verifying kubectl can reach the API server (up to 3 min)..."
KUBE_OK=false
for attempt in 1 2 3 4 5 6; do
  if kubectl get nodes &>/dev/null; then
    KUBE_OK=true
    break
  fi
  log_info "  kubectl not yet reachable (attempt ${attempt}/6) — waiting 30s..."
  sleep 30
done

if [[ "${KUBE_OK}" == "false" ]]; then
  # Diagnostic: check publicAccessCidrs vs current IP
  MY_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "unknown")
  ALLOWED_CIDRS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text 2>/dev/null || echo "unknown")
  log_error "kubectl cannot reach the API server after 3 minutes."
  log_error "Your current IP : ${MY_IP}"
  log_error "Allowed CIDRs   : ${ALLOWED_CIDRS}"
  if [[ "${ALLOWED_CIDRS}" != "0.0.0.0/0" && "${ALLOWED_CIDRS}" != *"${MY_IP}"* ]]; then
    log_error ""
    log_error "Your IP is not in the cluster's publicAccessCidrs. Fix with:"
    log_error "  aws eks update-cluster-config \\"
    log_error "    --name ${CLUSTER_NAME} --region ${REGION} \\"
    log_error "    --resources-vpc-config endpointPublicAccess=true,endpointPrivateAccess=true,publicAccessCidrs=\"0.0.0.0/0\""
    log_error ""
    log_error "Wait ~2 min for the update to propagate, then rerun: bash scripts/startup-all.sh up"
  else
    log_error "CIDR looks correct. The cluster API may still be initializing."
    log_error "Check cluster status: aws eks describe-cluster --name ${CLUSTER_NAME} --region ${REGION} --query cluster.status"
  fi
  exit 1
fi

log_info "Waiting for node group nodes to be Ready..."
TIMEOUT=600; ELAPSED=0; DESIRED_NODES=2
while true; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null \
    | awk '$2=="Ready"{c++} END{print c+0}')
  if [[ "${READY_NODES}" -ge "${DESIRED_NODES}" ]]; then
    log_info "Nodes ready: ${READY_NODES}/${DESIRED_NODES}"
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "Only ${READY_NODES}/${DESIRED_NODES} nodes ready after ${TIMEOUT}s."
    log_warn "The cluster may still be initializing. Check: kubectl get nodes"
    break
  fi
  log_info "  Nodes ready: ${READY_NODES}/${DESIRED_NODES} — ${ELAPSED}s elapsed..."
  sleep 20; ELAPSED=$((ELAPSED + 20))
done

kubectl get nodes -o wide

# =============================================================================
# PHASE 3: Wait for ArgoCD
# =============================================================================
log_step "Phase 3: Wait for ArgoCD to be healthy"

log_info "Waiting for ArgoCD server deployment to be available (up to 5 min)..."
kubectl wait deployment argocd-server \
  -n argocd \
  --for=condition=available \
  --timeout=300s

log_info "ArgoCD server is available."

# Apply the ArgoCD root-app manifest (bootstraps all child Applications).
# This is done via kubectl rather than terraform kubernetes_manifest because
# kubernetes_manifest requires a live API server at terraform plan time,
# which breaks fresh-cluster bootstrapping.
log_info "Applying ArgoCD root-app manifest..."
kubectl apply -f - <<'ROOTAPP'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ShaiMullo/crystolia-gitops.git
    targetRevision: main
    path: argocd/apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
ROOTAPP

log_info "Waiting for root-app Application to appear in ArgoCD..."
TIMEOUT=120; ELAPSED=0
while true; do
  if kubectl get application root-app -n argocd &>/dev/null; then
    log_info "root-app Application found."
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "root-app not found after ${TIMEOUT}s. Check: kubectl get application -n argocd"
    break
  fi
  log_info "  root-app not yet present — ${ELAPSED}s elapsed..."
  sleep 10; ELAPSED=$((ELAPSED + 10))
done

log_info "Waiting for ArgoCD applications to sync (up to 10 min)..."
TIMEOUT=600; ELAPSED=0
while true; do
  TOTAL=$(kubectl get application -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  SYNCED=$(kubectl get application -n argocd --no-headers 2>/dev/null \
    | grep -c "Synced.*Healthy" || echo "0")
  DEGRADED=$(kubectl get application -n argocd --no-headers 2>/dev/null \
    | grep -c "Degraded\|Unknown" || echo "0")

  if [[ "${TOTAL}" -gt 0 && "${SYNCED}" -eq "${TOTAL}" ]]; then
    log_info "All ${TOTAL} ArgoCD apps: Synced + Healthy."
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "ArgoCD sync not fully complete after ${TIMEOUT}s."
    log_warn "Synced+Healthy: ${SYNCED}/${TOTAL} | Degraded/Unknown: ${DEGRADED}"
    log_warn "Check: kubectl get application -n argocd"
    break
  fi
  log_info "  ArgoCD apps — Synced+Healthy: ${SYNCED}/${TOTAL}, Degraded: ${DEGRADED} — ${ELAPSED}s elapsed..."
  sleep 20; ELAPSED=$((ELAPSED + 20))
done

kubectl get application -n argocd

# =============================================================================
# PHASE 4: Wait for ALBs
# =============================================================================
log_step "Phase 4: Wait for ALBs to be provisioned"

log_info "Waiting for ALBs to be provisioned by AWS Load Balancer Controller (up to 5 min)..."
TIMEOUT=300; ELAPSED=0
while true; do
  ALB_COUNT=$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "length(LoadBalancers[?contains(LoadBalancerName,'k8s-crystoli') || contains(LoadBalancerName,'k8s-monitori') || contains(LoadBalancerName,'k8s-argocd')])" \
    --output text 2>/dev/null || echo "0")
  if [[ "${ALB_COUNT}" -ge 2 ]]; then
    log_info "ALBs provisioned: ${ALB_COUNT}"
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "Expected >=2 ALBs but found ${ALB_COUNT} after ${TIMEOUT}s."
    log_warn "AWS LBC may still be creating them. Check: kubectl get ingress -A"
    break
  fi
  log_info "  ALBs provisioned: ${ALB_COUNT} — ${ELAPSED}s elapsed..."
  sleep 15; ELAPSED=$((ELAPSED + 15))
done

# =============================================================================
# PHASE 5: Show new ALB hostnames for dns.tf update
# =============================================================================
log_step "Phase 5: New ALB hostnames — UPDATE dns.tf"

echo ""
log_warn "The following ALB hostnames were assigned. You MUST update dns.tf with these values."
echo ""

log_info "Ingress hostnames (from kubectl):"
kubectl get ingress -A -o wide 2>/dev/null || log_warn "Could not query ingresses."

echo ""
log_info "ALB DNS names (from AWS):"
aws elbv2 describe-load-balancers --region "${REGION}" \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,DNSName]" \
  --output table 2>/dev/null || log_warn "Could not query ALBs."

echo ""
log_warn "dns.tf records that need updating:"
log_warn "  staging.crystolia.com            → update alias.name to crystolia namespace ALB DNS"
log_warn "  admin-staging.crystolia.com      → same as staging ALB"
log_warn "  monitoring-staging.crystolia.com → update alias.name to monitoring namespace ALB DNS"
echo ""
log_warn "After updating dns.tf, run: terraform apply -auto-approve"
echo ""

# =============================================================================
# PHASE 6: Wait for crystolia namespace + create crystolia-backend-secret
#
# The namespace is created by ArgoCD syncing the crystolia-app Helm chart.
# By Phase 3 it should already exist, but we wait explicitly to eliminate
# any race — secret creation against a non-existent namespace will fail.
#
# crystolia-backend-secret is NOT managed by Helm or ArgoCD.
# It must be created manually before the backend pod can start.
# This phase creates it if absent, and skips it if already present.
# =============================================================================
log_step "Phase 6: Create crystolia-backend-secret (if absent)"

# Wait for crystolia namespace to exist and be Active
log_info "Waiting for 'crystolia' namespace to be Active (up to 2 min)..."
TIMEOUT=120; ELAPSED=0
NS_READY=false
while true; do
  NS_PHASE=$(kubectl get namespace crystolia -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "${NS_PHASE}" == "Active" ]]; then
    NS_READY=true
    log_info "'crystolia' namespace: Active."
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "'crystolia' namespace not Active after ${TIMEOUT}s (phase='${NS_PHASE}')."
    log_warn "ArgoCD may not have synced the crystolia-app yet."
    log_warn "Check: kubectl get ns crystolia && kubectl get application -n argocd"
    break
  fi
  log_info "  Waiting for crystolia namespace — ${ELAPSED}s elapsed..."
  sleep 10; ELAPSED=$((ELAPSED + 10))
done

if [[ "${NS_READY}" == "false" ]]; then
  log_warn "Skipping secret creation — namespace not ready."
  log_warn "Create the secret manually once the namespace exists:"
  log_warn "  kubectl create secret generic crystolia-backend-secret \\"
  log_warn "    --namespace crystolia \\"
  log_warn "    --from-literal=MONGO_URI='mongodb://crystolia-mongodb:27017/crystolia' \\"
  log_warn "    --from-literal=JWT_SECRET='<generate: openssl rand -base64 64>'"
else
  # Check if the secret already exists
  if kubectl get secret crystolia-backend-secret -n crystolia &>/dev/null; then
    EXISTING_KEYS=$(kubectl get secret crystolia-backend-secret -n crystolia \
      -o jsonpath='{.data}' 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(sorted(d.keys())))" 2>/dev/null \
      || echo "unknown")
    log_info "crystolia-backend-secret already exists (keys: ${EXISTING_KEYS}). Skipping creation."
    log_info "To rotate: kubectl delete secret crystolia-backend-secret -n crystolia && re-run this phase."
  else
    log_warn "crystolia-backend-secret not found. Creating it now."
    echo ""
    log_warn "Required values:"
    log_warn "  MONGO_URI    — internal cluster DNS (default: ${DEFAULT_MONGO_URI})"
    log_warn "  JWT_SECRET   — cryptographically random string, minimum 32 chars"
    log_warn "  GOOGLE_CLIENT_ID     — optional, Google OAuth (leave empty to skip)"
    log_warn "  GOOGLE_CLIENT_SECRET — optional, Google OAuth (leave empty to skip)"
    echo ""

    # ── MONGO_URI ────────────────────────────────────────────────────────────
    if [[ -z "${MONGO_URI:-}" ]]; then
      read -rp "MONGO_URI [${DEFAULT_MONGO_URI}]: " INPUT_MONGO_URI
      MONGO_URI="${INPUT_MONGO_URI:-${DEFAULT_MONGO_URI}}"
    fi
    log_info "MONGO_URI: ${MONGO_URI}"

    # ── JWT_SECRET ───────────────────────────────────────────────────────────
    if [[ -z "${JWT_SECRET:-}" ]]; then
      if [[ ! -t 0 ]]; then
        log_error "JWT_SECRET must be set as an env var in non-interactive sessions."
        log_error "  JWT_SECRET=\"\$(openssl rand -base64 64)\" bash scripts/startup-all.sh up"
        exit 1
      fi
      log_warn "JWT_SECRET not set in environment. Enter it now (input hidden)."
      log_warn "Tip: generate one with: openssl rand -base64 64"
      read -rsp "JWT_SECRET: " JWT_SECRET
      echo ""
    fi
    if [[ -z "${JWT_SECRET}" ]]; then
      log_error "JWT_SECRET cannot be empty."
      log_error "Generate one: openssl rand -base64 64"
      log_error "Then re-run: JWT_SECRET='...' bash scripts/startup-all.sh up"
      echo ""
      log_error "Or create the secret manually:"
      log_error "  kubectl create secret generic crystolia-backend-secret \\"
      log_error "    --namespace crystolia \\"
      log_error "    --from-literal=MONGO_URI='${MONGO_URI}' \\"
      log_error "    --from-literal=JWT_SECRET='<your-secret>'"
      exit 1
    fi
    if [[ "${#JWT_SECRET}" -lt 32 ]]; then
      log_error "JWT_SECRET is too short (${#JWT_SECRET} chars). Minimum: 32 chars."
      log_error "Generate a safe one: openssl rand -base64 64"
      exit 1
    fi

    # ── Google OAuth (optional) ───────────────────────────────────────────────
    if [[ -z "${GOOGLE_CLIENT_ID:-}" ]]; then
      read -rp "GOOGLE_CLIENT_ID (optional, press Enter to skip): " GOOGLE_CLIENT_ID
    fi
    if [[ -z "${GOOGLE_CLIENT_SECRET:-}" && -n "${GOOGLE_CLIENT_ID:-}" ]]; then
      read -rsp "GOOGLE_CLIENT_SECRET (input hidden): " GOOGLE_CLIENT_SECRET
      echo ""
    fi

    # ── Create secret ────────────────────────────────────────────────────────
    SECRET_ARGS=(
      --namespace crystolia
      --from-literal="MONGO_URI=${MONGO_URI}"
      --from-literal="JWT_SECRET=${JWT_SECRET}"
    )
    if [[ -n "${GOOGLE_CLIENT_ID:-}" ]]; then
      SECRET_ARGS+=(--from-literal="GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}")
    fi
    if [[ -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
      SECRET_ARGS+=(--from-literal="GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}")
    fi

    kubectl create secret generic crystolia-backend-secret "${SECRET_ARGS[@]}"

    # Unset sensitive variables from shell memory immediately after use
    unset JWT_SECRET GOOGLE_CLIENT_SECRET

    log_info "crystolia-backend-secret created."

    # Verify the secret is readable
    CREATED_KEYS=$(kubectl get secret crystolia-backend-secret -n crystolia \
      -o jsonpath='{.data}' 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(', '.join(sorted(d.keys())))" 2>/dev/null \
      || echo "could not parse")
    log_info "Secret keys confirmed: ${CREATED_KEYS}"

    # Restart backend deployment to pick up the new secret (if it already started in CrashLoop)
    if kubectl get deployment crystolia-backend -n crystolia &>/dev/null; then
      log_info "Restarting backend deployment to pick up new secret..."
      kubectl rollout restart deployment/crystolia-backend -n crystolia
      log_info "Waiting for backend rollout (up to 3 min)..."
      kubectl rollout status deployment/crystolia-backend -n crystolia --timeout=180s \
        || log_warn "Backend rollout did not complete within 180s. Check: kubectl get pods -n crystolia"
    fi
  fi
fi

# =============================================================================
# PHASE 7: Post-startup verification
# =============================================================================
log_step "Phase 7: Verification"

log_info "Cluster nodes:"
kubectl get nodes --no-headers | awk '{print "  "$1,$2,$5}'

echo ""
log_info "Namespace workload status:"
for NS in argocd crystolia monitoring; do
  if kubectl get ns "${NS}" &>/dev/null; then
    PODS=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    RUNNING=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    log_info "  ${NS}: ${RUNNING}/${PODS} pods Running"
  else
    log_warn "  ${NS}: namespace not found"
  fi
done

echo ""
log_info "Verifying ECR repos intact:"
aws ecr describe-repositories --region "${REGION}" \
  --query "repositories[].[repositoryName]" \
  --output table 2>/dev/null || log_warn "Could not query ECR."

echo ""
log_info "Checking latest MongoDB backup in S3:"
LATEST_BACKUP=$(aws s3 ls "s3://${BACKUP_BUCKET}/" 2>/dev/null | sort | tail -1 || true)
if [[ -n "${LATEST_BACKUP}" ]]; then
  log_info "Latest backup: ${LATEST_BACKUP}"
else
  log_warn "No backups found in s3://${BACKUP_BUCKET}/."
fi

echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Startup complete.${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
log_warn "REQUIRED MANUAL STEPS — do not skip:"
log_warn ""
log_warn "  1. UPDATE dns.tf with the new ALB hostnames shown above (Phase 5)"
log_warn "     Then run: terraform apply -auto-approve"
log_warn ""
log_warn "  2. RESTORE MongoDB from S3 backup if needed."
log_warn "     MongoDB started EMPTY. Data does not auto-restore."
log_warn "     Backup bucket: s3://${BACKUP_BUCKET}/"
log_warn "     Restore procedure: docs/disaster-free-stop-start.md — MongoDB Restore"
echo ""
log_info "Quick health check: bash scripts/startup-all.sh status"
echo ""
