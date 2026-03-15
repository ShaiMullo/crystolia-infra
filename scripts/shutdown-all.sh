#!/bin/bash
set -euo pipefail

# =============================================================================
# Crystolia Staging — Shutdown
#
# DESTROYS (cost-generating):
#   EKS cluster, managed node group, NAT gateway, VPC + subnets,
#   Helm releases (argocd, aws-load-balancer-controller),
#   IRSA roles (LBC, external-secrets, EBS CSI),
#   EBS CSI addon, ALBs (via Kubernetes cleanup before destroy)
#
# PRESERVES (cheap/free, painful to recreate):
#   ECR repositories + all images
#   ACM certificate (*.crystolia.com)
#   Route53 DNS records
#   GitHub OIDC provider + IAM roles
#   Terraform state (S3: crystolia-tf-state-main + DynamoDB)
#   MongoDB S3 backups (s3://crystolia-backups)
#
# Usage: bash scripts/shutdown-all.sh
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

for cmd in aws kubectl terraform; do
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

if ! aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER_NAME}" &>/dev/null; then
  log_error "Cannot update kubeconfig for cluster '${CLUSTER_NAME}'."
  log_error "If the cluster is already gone, there is nothing to shut down."
  exit 1
fi
if ! kubectl get nodes &>/dev/null; then
  log_error "kubectl cannot reach the cluster API. Verify the cluster is running."
  exit 1
fi
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
log_info "Cluster reachable. Nodes online: ${NODE_COUNT}"

# =============================================================================
# MONGODB BACKUP CHECK
# =============================================================================
log_step "MongoDB data safety check"

LATEST_BACKUP=$(aws s3 ls "s3://${BACKUP_BUCKET}/" 2>/dev/null | sort | tail -1 || true)
if [[ -z "${LATEST_BACKUP}" ]]; then
  log_warn "No backups found in s3://${BACKUP_BUCKET}/."
  log_warn "MongoDB data WILL BE LOST on shutdown. The PVC is deleted."
else
  log_info "Latest S3 backup: ${LATEST_BACKUP}"
fi
log_warn "MongoDB starts EMPTY after a startup. Restore from S3 backup is a manual step."
log_warn "Scheduled backup runs daily at 02:00 UTC. If you need a fresh backup, trigger it now."

# =============================================================================
# CONFIRMATION GUARD
# =============================================================================
log_step "Destruction summary — read carefully"

echo ""
log_warn "WILL BE DESTROYED:"
log_warn "  • EKS cluster: ${CLUSTER_NAME} (control plane)"
log_warn "  • EKS managed node group: general-demo (all EC2 t3.medium instances)"
log_warn "  • NAT Gateway + Elastic IP (us-east-1)"
log_warn "  • VPC 10.0.0.0/16 + all subnets, route tables, internet gateway"
log_warn "  • Helm release: argocd"
log_warn "  • Helm release: aws-load-balancer-controller"
log_warn "  • EKS addon: aws-ebs-csi-driver"
log_warn "  • IRSA roles: LBC, external-secrets, EBS CSI"
log_warn "  • ALBs (staging + monitoring — deleted via K8s before TF destroy)"
log_warn "  • All PVCs + EBS volumes: MongoDB 8Gi, Prometheus 5Gi, Grafana 2Gi, Loki 5Gi"
echo ""
log_info "WILL BE PRESERVED:"
log_info "  • ECR repos: crystolia-backend, crystolia-frontend, crystolia-frontend-admin"
log_info "  • ACM certificate: *.crystolia.com / crystolia.com"
log_info "  • Route53 records (NOTE: ALB hostnames will be stale after restart)"
log_info "  • GitHub OIDC provider + IAM roles (github_actions_ecr, github_actions_terraform)"
log_info "  • Terraform state bucket (S3 + DynamoDB lock table)"
log_info "  • MongoDB S3 backups in s3://${BACKUP_BUCKET}/"
echo ""
read -rp "Type SHUTDOWN to confirm and proceed: " CONFIRM
if [[ "${CONFIRM}" != "SHUTDOWN" ]]; then
  log_info "Aborted — no changes made."
  exit 0
fi

# =============================================================================
# PHASE 1: Kubernetes cleanup
# Delete Ingresses first (AWS LBC will delete ALBs).
# Delete PVCs next (EBS CSI will release EBS volumes).
# This MUST happen before destroying EKS or the ALBs and EBS volumes
# become orphaned AWS resources that continue to accrue charges.
# =============================================================================
log_step "Phase 1: Kubernetes cleanup (ALBs + EBS volumes)"

log_info "Suspending all ArgoCD app auto-sync to prevent re-creation during cleanup..."
for APP in $(kubectl get application -n argocd -o name 2>/dev/null || true); do
  kubectl patch "${APP}" -n argocd \
    --type merge \
    -p '{"spec":{"syncPolicy":null}}' 2>/dev/null || true
done
log_info "ArgoCD auto-sync suspended."

log_info "Deleting all Ingress resources across all namespaces (triggers ALB deletion)..."
kubectl delete ingress --all -n crystolia  --timeout=90s 2>/dev/null || true
kubectl delete ingress --all -n monitoring --timeout=90s 2>/dev/null || true
kubectl delete ingress --all -n argocd     --timeout=90s 2>/dev/null || true

log_info "Deleting all PVCs (triggers EBS volume deletion via EBS CSI driver)..."
kubectl delete pvc --all -n crystolia  --timeout=90s 2>/dev/null || true
kubectl delete pvc --all -n monitoring --timeout=90s 2>/dev/null || true

# Wait for ALBs to be deregistered
log_info "Waiting up to 4 minutes for staging ALBs to be deleted from AWS..."
TIMEOUT=240; ELAPSED=0
while true; do
  ALB_COUNT=$(aws elbv2 describe-load-balancers --region "${REGION}" \
    --query "length(LoadBalancers[?contains(LoadBalancerName,'k8s-crystoli') || contains(LoadBalancerName,'k8s-monitori') || contains(LoadBalancerName,'k8s-argocd')])" \
    --output text 2>/dev/null || echo "0")
  if [[ "${ALB_COUNT}" -eq 0 ]]; then
    log_info "ALBs confirmed deleted."
    break
  fi
  if [[ "${ELAPSED}" -ge "${TIMEOUT}" ]]; then
    log_warn "ALBs still present after ${TIMEOUT}s. Proceeding — they may clean up on their own."
    log_warn "If not, delete them manually in the AWS console before the next startup."
    aws elbv2 describe-load-balancers --region "${REGION}" \
      --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,LoadBalancerArn]" \
      --output table 2>/dev/null || true
    break
  fi
  log_info "  ALBs still deleting (count: ${ALB_COUNT}) — ${ELAPSED}s elapsed..."
  sleep 15; ELAPSED=$((ELAPSED + 15))
done

# =============================================================================
# PHASE 2: Remove Kubernetes Terraform-managed resources from state
# We deleted these with kubectl above. Removing them from state prevents
# Terraform from trying to DELETE them via the Kubernetes provider during
# destroy (which would fail once the EKS cluster itself is torn down).
# =============================================================================
log_step "Phase 2: Detach Kubernetes provider resources from Terraform state"

for RESOURCE in \
  "kubernetes_ingress_v1.argocd" \
  "kubernetes_manifest.root_app" \
  "kubernetes_storage_class.gp3_csi"; do
  if terraform state list 2>/dev/null | grep -qx "${RESOURCE}"; then
    log_info "Removing from state: ${RESOURCE}"
    terraform state rm "${RESOURCE}"
  else
    log_info "Already absent from state: ${RESOURCE}"
  fi
done

# =============================================================================
# PHASE 3: Targeted Terraform destroy
#
# Order matters — Terraform resolves the dependency graph within the targets,
# but we list Helm releases before module.eks to give Terraform the clearest
# signal. The EBS CSI addon must be destroyed before the EKS cluster.
#
# NOT targeted (preserved in state):
#   module.acm, aws_ecr_*, aws_route53_record.*, aws_iam_openid_connect_provider.github,
#   aws_iam_role.github_actions_*, aws_iam_policy.ecr_push,
#   aws_iam_policy.terraform_state_access
# =============================================================================
log_step "Phase 3: Terraform targeted destroy"

log_info "Destroying expensive resources. This will take 10–20 minutes..."

terraform destroy \
  -target=helm_release.aws_load_balancer_controller \
  -target=helm_release.argocd \
  -target=aws_eks_addon.ebs_csi_driver \
  -target=aws_iam_role_policy_attachment.ebs_csi_driver \
  -target=aws_iam_role.ebs_csi_driver \
  -target=module.load_balancer_controller_irsa_role \
  -target=module.external_secrets_irsa_role \
  -target=aws_iam_policy.external_secrets \
  -target=aws_security_group_rule.node_ingress_self \
  -target=module.eks \
  -target=module.vpc \
  -auto-approve

# =============================================================================
# PHASE 4: Post-destroy verification
# =============================================================================
log_step "Phase 4: Verification"

log_info "Checking EKS cluster..."
if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" &>/dev/null; then
  log_warn "EKS cluster still visible in AWS — may still be terminating. Check console."
else
  log_info "EKS cluster: confirmed gone."
fi

log_info "Checking NAT gateways..."
NAT_ACTIVE=$(aws ec2 describe-nat-gateways --region "${REGION}" \
  --filter "Name=state,Values=available" \
  --query "length(NatGateways)" \
  --output text 2>/dev/null || echo "0")
if [[ "${NAT_ACTIVE}" -gt 0 ]]; then
  log_warn "${NAT_ACTIVE} NAT gateway(s) still in 'available' state — check if they belong to this project."
else
  log_info "NAT gateways: none active."
fi

log_info "Checking ALBs..."
ALB_REMAINING=$(aws elbv2 describe-load-balancers --region "${REGION}" \
  --query "length(LoadBalancers[?contains(LoadBalancerName,'k8s-')])" \
  --output text 2>/dev/null || echo "0")
if [[ "${ALB_REMAINING}" -gt 0 ]]; then
  log_warn "${ALB_REMAINING} k8s-prefixed ALB(s) still present — delete manually if they belong to crystolia."
else
  log_info "ALBs: none remaining."
fi

log_info "Verifying ECR repos are intact..."
aws ecr describe-repositories --region "${REGION}" \
  --query "repositories[].[repositoryName,repositoryUri]" \
  --output table 2>/dev/null || log_warn "Could not query ECR."

log_info "Verifying Terraform state preserved resources..."
PRESERVED_COUNT=$(terraform state list 2>/dev/null | grep -cE "^(module\.acm|aws_ecr_|aws_route53_record|aws_iam_openid_connect_provider\.github|aws_iam_role\.github_actions)" || echo "0")
log_info "Preserved resources in state: ${PRESERVED_COUNT}"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Shutdown complete.${NC}"
echo -e "${GREEN}════════════════════════════════════════════════${NC}"
echo ""
log_warn "REQUIRED before next startup — update Route53 ALB hostnames in dns.tf:"
log_warn "  The current hostnames in dns.tf are now stale (ALBs were deleted)."
log_warn "  After startup, find the new ALB hostnames and update dns.tf accordingly."
log_warn "  See: docs/disaster-free-stop-start.md — Post-Startup Manual Steps"
echo ""
log_warn "MongoDB data status: PVC deleted. Restore from s3://${BACKUP_BUCKET}/ after startup."
echo ""
