# Crystolia Infrastructure

This repository contains the Terraform configuration for the Crystolia platform.

## Structure
- `terraform/bootstrap`: S3 Backend setup (One-time setup)
- `terraform/modules`: Reusable components (VPC, EKS, etc.)
- `terraform/`: Main configuration files

## CI/CD
Infrastructure changes are applied automatically via GitHub Actions on push to `main`.
