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
# Usage: bash scripts/startup-all.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
REGION="us-east-1"
CLUSTER_NAME="crystolia-cluster-demo"
BACKUP_BUCKET="crystolia-backups"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()  { echo -e "\n${CYAN}══════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════${NC}"; }

# =============================================================================
# PRE-FLIGHT
# =============================================================================
log_step "Pre-flight checks"

for cmd in aws kubectl terraform helm; do
  if ! command -v "${cmd}" &>/dev/null; then
    log_error "${cmd} not found in PATH. Install it and retry."
    exit 1
  fi
done

if ! aws sts get-caller-identity &>/dev/null; then
  log_error "AWS credentials not configured or session expired. Run 'aws sso login' or refresh credentials."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
log_info "AWS account: ${ACCOUNT_ID} | Region: ${REGION}"

cd "${TERRAFORM_DIR}"
if ! terraform state list &>/dev/null; then
  log_error "Terraform state not accessible. Run 'terraform init' first."
  exit 1
fi
log_info "Terraform state accessible (s3://crystolia-tf-state-main)."

# Verify the cluster does NOT already exist (idempotency guard)
if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" &>/dev/null; then
  CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query "cluster.status" --output text 2>/dev/null || echo "UNKNOWN")
  if [[ "${CLUSTER_STATUS}" == "ACTIVE" ]]; then
    log_warn "EKS cluster '${CLUSTER_NAME}' already exists and is ACTIVE."
    log_warn "If startup already completed, check the cluster state before proceeding."
    read -rp "Type CONTINUE to proceed anyway (terraform apply is idempotent): " GUARD
    if [[ "${GUARD}" != "CONTINUE" ]]; then
      log_info "Aborted — no changes made."
      exit 0
    fi
  fi
fi

# =============================================================================
# STARTUP SUMMARY
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
# PHASE 1: Terraform init + apply
# Full apply — recreates everything destroyed by shutdown-all.sh.
# The dependency graph (VPC → EKS → IRSA → Helm → K8s manifests) is resolved
# automatically by Terraform.
# =============================================================================
log_step "Phase 1: Terraform apply (full)"

log_info "Running terraform init to refresh provider cache..."
terraform init -reconfigure

log_info "Applying all resources. This will take 15–25 minutes..."
terraform apply -auto-approve

log_info "Terraform apply complete."

# =============================================================================
# PHASE 2: Update kubeconfig + verify cluster
# =============================================================================
log_step "Phase 2: Update kubeconfig and verify nodes"

log_info "Updating kubeconfig for cluster '${CLUSTER_NAME}'..."
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}"

log_info "Waiting for node group nodes to be Ready..."
TIMEOUT=600; ELAPSED=0; DESIRED_NODES=2
while true; do
  READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null \
    | grep -c " Ready " || echo "0")
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
# ArgoCD is deployed by helm_release.argocd in Terraform.
# The root Application (kubernetes_manifest.root_app) is also created by
# Terraform and will trigger ArgoCD to sync all apps from crystolia-gitops.
# =============================================================================
log_step "Phase 3: Wait for ArgoCD to be healthy"

log_info "Waiting for ArgoCD server deployment to be available (up to 5 min)..."
kubectl wait deployment argocd-server \
  -n argocd \
  --for=condition=available \
  --timeout=300s

log_info "ArgoCD server is available."

# Wait for the root-app to appear and start syncing
log_info "Waiting for root-app Application to appear in ArgoCD..."
TIMEOUT=120; ELAPSED=0
while true; do
  if kubectl get application root-app -n argocd &>/dev/null; then
    log_info "root-app Application found."
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "root-app not found after ${TIMEOUT}s. Terraform may still be applying or ArgoCD is not yet ready."
    log_warn "Check: kubectl get application -n argocd"
    break
  fi
  log_info "  root-app not yet present — ${ELAPSED}s elapsed..."
  sleep 10; ELAPSED=$((ELAPSED + 10))
done

# Wait for ArgoCD apps to sync
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
# PHASE 4: Wait for ALBs to be provisioned
# AWS LBC creates ALBs when it sees Ingress resources synced by ArgoCD.
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
log_warn "  staging.crystolia.com       → update alias.name to crystolia namespace ALB DNS"
log_warn "  admin-staging.crystolia.com → same as staging ALB"
log_warn "  monitoring-staging.crystolia.com → update alias.name to monitoring namespace ALB DNS"
echo ""
log_warn "After updating dns.tf, run: terraform apply -auto-approve"
echo ""

# =============================================================================
# PHASE 6: Post-startup verification
# =============================================================================
log_step "Phase 6: Verification"

log_info "Cluster nodes:"
kubectl get nodes --no-headers | awk '{print "  "$1,$2,$5}'

echo ""
log_info "Namespace workload status:"
for NS in argocd crystolia monitoring; do
  PODS=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  RUNNING=$(kubectl get pods -n "${NS}" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
  log_info "  ${NS}: ${RUNNING}/${PODS} pods Running"
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
