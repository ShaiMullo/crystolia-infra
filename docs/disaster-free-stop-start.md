# Crystolia Staging — Disaster-Free Stop/Start Guide

This document covers how to safely shut down and restart the entire Crystolia staging environment to stop AWS costs, then bring it back up without losing data or configuration.

---

## Overview

The staging environment uses targeted Terraform destroy/apply to minimize downtime and avoid re-provisioning long-lived resources (ECR, ACM, Route53, IAM). The EKS cluster, nodes, and networking are the expensive parts — these are the only things destroyed on shutdown.

**Shutdown time:** ~10–20 minutes
**Startup time:** ~15–25 minutes (EKS control plane is the bottleneck)

---

## What Gets Destroyed vs. Preserved

### Destroyed on shutdown (cost-generating)

| Resource | Why destroyed |
|---|---|
| EKS cluster `crystolia-cluster-demo` | ~$0.10/hr control plane |
| Managed node group `general-demo` (t3.medium × 2) | ~$0.07/hr per node |
| NAT Gateway | ~$0.045/hr + data transfer |
| VPC, subnets, route tables, internet gateway | Free, but tied to above |
| Helm release: `argocd` | Runs on nodes |
| Helm release: `aws-load-balancer-controller` | Runs on nodes |
| EKS addon: `aws-ebs-csi-driver` | Runs on nodes |
| IRSA roles: LBC, external-secrets, EBS CSI | Recreated in ~seconds |
| ALBs (staging, monitoring) | ~$0.008/hr per ALB |
| PVCs + EBS volumes (MongoDB 8Gi, Prometheus 5Gi, Grafana 2Gi, Loki 5Gi) | Tied to PVCs |

### Preserved (free or cheap, painful to recreate)

| Resource | Notes |
|---|---|
| ECR repos: `crystolia-backend`, `crystolia-frontend`, `crystolia-frontend-admin` | All images intact |
| ACM certificate `*.crystolia.com` / `crystolia.com` | DNS-validated; reissuing takes hours |
| Route53 DNS records | **Hostnames will be stale** — see Manual Steps |
| GitHub OIDC provider + IAM roles (`github_actions_ecr`, `github_actions_terraform`) | CI/CD continuity |
| Terraform state (S3: `crystolia-tf-state-main`, DynamoDB: `crystolia-tf-locks`) | Source of truth |
| MongoDB S3 backups (`s3://crystolia-backups`) | Scheduled daily at 02:00 UTC |

---

## Prerequisites

Before running either script, ensure:

1. **AWS credentials active:** `aws sts get-caller-identity` returns your account ID.
   If using SSO: `aws sso login --profile <profile>`

2. **Tools installed:** `aws`, `kubectl`, `terraform`, `helm` all in PATH.

3. **Terraform state accessible:** `cd terraform && terraform state list` works.

4. **For shutdown only:** The EKS cluster must be reachable (`kubectl get nodes`).
   If the cluster is already gone, shutdown is a no-op — there is nothing to tear down.

---

## Shutdown Procedure

```bash
bash scripts/shutdown-all.sh
```

The script walks through four phases:

**Phase 0 — Pre-flight:** Verifies AWS credentials, tools, cluster connectivity, and Terraform state access.

**Phase 0.5 — MongoDB backup check:** Queries `s3://crystolia-backups/` for the latest backup timestamp. You are warned if no backup exists. The shutdown does NOT trigger a new backup automatically — if you need fresh data, trigger the MongoDB backup CronJob manually before proceeding:

```bash
kubectl create job --from=cronjob/mongodb-backup manual-backup-$(date +%s) -n crystolia
kubectl wait job -n crystolia -l job-name --for=condition=complete --timeout=300s
```

**Phase 1 — Kubernetes cleanup:** Suspends ArgoCD auto-sync (prevents re-creation during teardown), deletes all Ingress resources (triggers ALB deletion by AWS LBC), deletes all PVCs (triggers EBS volume release by EBS CSI driver). Polls until ALBs are confirmed deleted from AWS.

> **Why this order matters:** ALBs and EBS volumes are created by Kubernetes controllers, not by Terraform. If EKS is destroyed without deleting them first, these AWS resources become orphaned — they continue to accrue charges and must be deleted manually.

**Phase 2 — Terraform state cleanup:** Removes three Kubernetes-provider-managed resources from Terraform state (`kubernetes_ingress_v1.argocd`, `kubernetes_manifest.root_app`, `kubernetes_storage_class.gp3_csi`). These were already deleted by kubectl in Phase 1. Removing them from state prevents Terraform from attempting to delete them again during destroy — which would fail once the EKS API is unreachable.

**Phase 3 — Terraform targeted destroy:** Destroys expensive resources in dependency order. Preserves ECR, ACM, Route53, GitHub IAM, and Terraform state. Takes 10–20 minutes.

**Phase 4 — Verification:** Confirms EKS cluster is gone, no orphaned NAT gateways or ALBs remain, ECR repos are intact, preserved resources remain in state.

---

## Startup Procedure

```bash
bash scripts/startup-all.sh
```

**Phase 1 — Terraform apply:** Recreates all destroyed resources. Terraform resolves the dependency graph automatically (VPC → EKS → IRSA → Helm releases → Kubernetes manifests). The `kubernetes_manifest.root_app` resource is recreated here, which bootstraps all ArgoCD applications.

**Phase 2 — Nodes ready:** Updates kubeconfig and waits for node group nodes to enter `Ready` state.

**Phase 3 — ArgoCD healthy:** Waits for the ArgoCD server deployment, then for the root `Application` resource to appear, then for all ArgoCD apps to reach `Synced + Healthy`.

**Phase 4 — ALBs provisioned:** Waits for AWS LBC to create new ALBs from the Ingress resources synced by ArgoCD.

**Phase 5 — ALB hostname output:** Prints the new ALB DNS names from both `kubectl get ingress -A` and `aws elbv2 describe-load-balancers`. **You must update `dns.tf` with these values** — see Post-Startup Manual Steps.

**Phase 6 — Verification:** Shows node status, pod counts per namespace, ECR repo list, latest S3 backup.

---

## Post-Startup Manual Steps

### Step 1 — Update Route53 ALB hostnames in dns.tf (REQUIRED)

Every time the staging environment is restarted, new ALBs are created with different DNS names. The `dns.tf` file contains hardcoded ALB hostnames that are now stale.

1. From the Phase 5 output of `startup-all.sh`, note the new ALB DNS names.

2. Edit `terraform/dns.tf`. Update the three stale `alias.name` values:

   ```hcl
   # staging.crystolia.com and admin-staging.crystolia.com
   # both point to the crystolia-namespace ALB:
   resource "aws_route53_record" "staging" {
     alias {
       name = "<NEW-CRYSTOLIA-ALB-HOSTNAME>.us-east-1.elb.amazonaws.com"
       ...
     }
   }

   resource "aws_route53_record" "admin_staging" {
     alias {
       name = "<NEW-CRYSTOLIA-ALB-HOSTNAME>.us-east-1.elb.amazonaws.com"
       ...
     }
   }

   # monitoring-staging.crystolia.com points to the monitoring-namespace ALB:
   resource "aws_route53_record" "monitoring_staging" {
     alias {
       name = "<NEW-MONITORING-ALB-HOSTNAME>.us-east-1.elb.amazonaws.com"
       ...
     }
   }
   ```

3. Apply the change:

   ```bash
   cd terraform && terraform apply -auto-approve
   ```

4. Verify DNS propagation (may take 30–60 seconds):

   ```bash
   dig staging.crystolia.com
   dig admin-staging.crystolia.com
   dig monitoring-staging.crystolia.com
   ```

> **Note:** The `aws_route53_record.www` record has `lifecycle { ignore_changes = all }` — it does not need updating.

### Step 2 — Restore MongoDB from S3 backup (if needed)

MongoDB starts **completely empty** after every startup. The PVC is deleted during shutdown. If the application needs its data, restore it manually.

**Check available backups:**

```bash
aws s3 ls s3://crystolia-backups/ --recursive | sort
```

**Restore procedure:**

```bash
# 1. Copy the latest backup archive from S3 into the MongoDB pod
BACKUP_FILE="<backup-filename>.gz"  # from 's3 ls' output above
MONGO_POD=$(kubectl get pod -n crystolia -l app=mongodb -o name | head -1)

aws s3 cp "s3://crystolia-backups/${BACKUP_FILE}" /tmp/mongodb-backup.gz

kubectl cp /tmp/mongodb-backup.gz crystolia/"${MONGO_POD#pod/}":/tmp/backup.gz

# 2. Restore inside the pod
kubectl exec -n crystolia "${MONGO_POD#pod/}" -- \
  bash -c "mongorestore --gzip --archive=/tmp/backup.gz --drop"
```

> Adjust the restore command to match the backup format used by your backup CronJob. Check `scripts/` or the CronJob spec for the exact `mongodump` flags used.

---

## Quick Verification Commands

After startup, verify end-to-end health:

```bash
# Cluster + nodes
kubectl get nodes -o wide

# ArgoCD apps
kubectl get application -n argocd

# Pods per namespace
kubectl get pods -n argocd
kubectl get pods -n crystolia
kubectl get pods -n monitoring

# Ingress + ALB hostnames
kubectl get ingress -A -o wide

# ALBs in AWS
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,DNSName,State.Code]" \
  --output table

# ECR repos
aws ecr describe-repositories --region us-east-1 \
  --query "repositories[].[repositoryName,repositoryUri]" --output table

# MongoDB S3 backups
aws s3 ls s3://crystolia-backups/ | sort | tail -5
```

---

## Troubleshooting

### ALBs not deleted after Phase 1

If `shutdown-all.sh` warns that ALBs are still present after 4 minutes:

1. Check which ALBs remain:
   ```bash
   aws elbv2 describe-load-balancers --region us-east-1 \
     --query "LoadBalancers[?contains(LoadBalancerName,'k8s-')].[LoadBalancerName,LoadBalancerArn,State.Code]" \
     --output table
   ```
2. If they belong to this project, delete them manually in the AWS Console or via CLI before proceeding with terraform destroy. Orphaned ALBs will block VPC deletion.

### Terraform destroy fails on `module.eks`

This typically means a dependency (security group, ENI) is still in use by an ALB or a dangling network interface. Resolution:

1. Check for orphaned network interfaces in the VPC.
2. Check for any remaining ALBs pointing into the VPC's subnets.
3. Delete the blocking resources manually, then re-run `shutdown-all.sh` from Phase 3.

### ArgoCD apps stuck in `OutOfSync` or `Degraded` after startup

Common causes:

- **external-secrets:** The `ExternalSecret` resources pull from AWS Secrets Manager. If the IRSA role for external-secrets was not recreated cleanly, the secrets controller cannot authenticate. Check: `kubectl get externalsecret -A` and `kubectl logs -n crystolia -l app.kubernetes.io/name=external-secrets`.
- **MongoDB:** The app may be healthy but the database is empty. Restore from S3 (see Step 2 above).
- **Image not found:** If a deployment references an image tag that was never pushed, the pod will fail with `ImagePullBackOff`. Check ECR for the expected tag.

### `terraform apply` fails on `kubernetes_manifest.root_app`

The Kubernetes provider requires the EKS cluster API to be reachable when applying. If `terraform apply` fails at this resource, the ArgoCD `helm_release` may not be fully ready yet:

```bash
# Manually wait for ArgoCD CRDs to be installed
kubectl wait --for condition=established --timeout=120s crd/applications.argoproj.io

# Then re-run apply
terraform apply -auto-approve
```

### Route53 DNS not resolving after `dns.tf` update

- Verify the new ALB hostname in `dns.tf` is correct (copy-paste from `kubectl get ingress` or `aws elbv2 describe-load-balancers`).
- The `zone_id` for ALBs in `us-east-1` is `Z35SXDOTRQ7X7K` — do not change this value.
- TTL for alias records is controlled by Route53 internally; propagation is typically under 60 seconds.

---

## Cost Estimate (while running)

| Resource | Approx. hourly cost |
|---|---|
| EKS control plane | $0.10 |
| 2× t3.medium nodes | $0.14 |
| NAT Gateway (idle) | $0.045 |
| 2× ALBs (idle) | $0.016 |
| EBS volumes (~20 GiB total) | ~$0.002 |
| **Total** | **~$0.30/hr (~$7.20/day)** |

Running only during working hours (8h/day, 5 days/week) saves ~75% vs. always-on.
