# Demo Checklist

## Pre-Demo Verification

### 1. Infrastructure Status

```bash
# Check EKS cluster
aws eks describe-cluster --name crystolia-cluster-demo --region us-east-1 --query 'cluster.status'

# Check nodes
kubectl get nodes

# Expected: 2 nodes, STATUS=Ready
```

### 2. ArgoCD Status

```bash
kubectl get applications -n argocd

# Expected:
# NAME       SYNC STATUS   HEALTH STATUS
# demo-app   Synced        Healthy
# root-app   Synced        Healthy
```

### 3. CI/CD Verification

**Trigger GitHub Actions:**
1. Go to: `GitHub → Actions → Terraform CI → Run workflow`
2. Select branch: `main`
3. Click: `Run workflow`

**Expected Output:**
- ✅ OIDC authentication succeeds
- ✅ `terraform init` succeeds
- ✅ `terraform validate` succeeds
- ✅ `terraform plan` shows current state

---

## Demo Flow

### Step 1: Repository Structure
Show Git structure:
```
crystolia-infra/
├── terraform/      # Infrastructure as Code
├── argocd/         # GitOps Applications
└── docs/           # Documentation
```

### Step 2: Infrastructure Creation
Explain Terraform creates:
- VPC (2 AZs, single NAT)
- EKS cluster (Spot nodes)
- OIDC for IRSA

### Step 3: GitOps Deployment
Show ArgoCD:
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open: https://localhost:8080
```

### Step 4: CI/CD Pipeline
Show GitHub Actions workflow with OIDC authentication.

---

## Local Apply (Infrastructure Changes)

```bash
cd /Users/shaimullo/Desktop/crystolia-infra/terraform

# Verify AWS credentials
aws sts get-caller-identity

# Plan changes
terraform plan

# Apply (manual approval required)
terraform apply
```

---

## Destroy Checklist

### Step 1: Remove ArgoCD Applications
```bash
kubectl delete application root-app -n argocd
kubectl delete application demo-app -n argocd
```

### Step 2: Uninstall ArgoCD
```bash
kubectl delete namespace argocd
```

### Step 3: Destroy Infrastructure
```bash
cd terraform
terraform destroy
```

### Step 4: Verify Cleanup
```bash
aws eks list-clusters --region us-east-1
# Expected: No crystolia clusters

aws ec2 describe-vpcs --region us-east-1 --filters "Name=tag:Project,Values=crystolia"
# Expected: No results
```

---

## Cost Notes

| Resource | Cost | Notes |
|----------|------|-------|
| EKS Control Plane | ~$72/month | Fixed while cluster exists |
| NAT Gateway | ~$32/month | Single NAT |
| Spot Nodes | ~$7-15/month | Variable |
| **Total** | **~$80-100/month** | Destroy when not in use |
