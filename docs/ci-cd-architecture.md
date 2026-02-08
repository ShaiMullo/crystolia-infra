# CI/CD Architecture

## Overview

This document explains the CI/CD pipeline for Terraform infrastructure management.

```
┌─────────────────┐     OIDC Token     ┌─────────────────┐
│  GitHub Actions │ ─────────────────► │   AWS IAM       │
│  (main branch)  │                    │   OIDC Provider │
└────────┬────────┘                    └────────┬────────┘
         │                                      │
         │ Workflow runs:                       │ AssumeRoleWithWebIdentity
         │ - terraform init                     ▼
         │ - terraform validate        ┌─────────────────┐
         │ - terraform plan            │   IAM Role      │
         │                             │   (state-only)  │
         │                             └────────┬────────┘
         │                                      │
         ▼                                      ▼
┌─────────────────┐                    ┌─────────────────┐
│   PR Comment    │                    │   S3 + DynamoDB │
│   with Plan     │                    │   (state only)  │
└─────────────────┘                    └─────────────────┘
```

---

## Why GitHub OIDC?

| Static Credentials | GitHub OIDC |
|-------------------|-------------|
| Long-lived secrets in GitHub | Short-lived tokens (15 min) |
| Can be leaked/stolen | Generated per workflow run |
| Manual rotation required | Automatic rotation |
| Hard to audit | CloudTrail shows repo/branch |

**GitHub OIDC is AWS-recommended best practice for CI/CD.**

---

## Trust Policy Restrictions

The IAM role can ONLY be assumed when:

1. **Repository:** `ShaiMullo/crystolia-infra`
2. **Branch:** `refs/heads/main`
3. **Audience:** `sts.amazonaws.com`

```json
{
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:ShaiMullo/crystolia-infra:ref:refs/heads/main"
    }
  }
}
```

---

## Why Terraform Apply is Local-Only

| Reason | Explanation |
|--------|-------------|
| **Cost Control** | Prevents accidental resource creation |
| **Safety** | Infrastructure changes require human review |
| **Audit Trail** | Local apply = explicit decision point |
| **Academic** | Demonstrates CI validation vs CD deployment |

**Pattern:**
- CI validates and plans (automated, fast feedback)
- Apply is gated (manual, human approval)

---

## S3 Backend + DynamoDB Locking

**State Storage:**
- Bucket: `crystolia-tf-state-main`
- Key: `infra/terraform.tfstate`
- Encryption: Enabled (AES-256)

**Locking:**
- Table: `crystolia-tf-locks`
- Prevents concurrent applies

**OIDC Access:**
- CI role has read/write to state bucket
- CI role has access to lock table
- CI role has NO permissions to create/modify AWS resources

---

## How to Apply Locally

```bash
cd terraform
terraform init
terraform plan
terraform apply  # Requires local AWS credentials with full permissions
```

---

## Verification

Check OIDC authentication in AWS CloudTrail:
- Event: `AssumeRoleWithWebIdentity`
- Principal: `arn:aws:iam::268456953512:oidc-provider/token.actions.githubusercontent.com`
