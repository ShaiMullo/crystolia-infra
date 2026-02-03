#!/bin/bash
set -e

echo "🧹 Cleaning up conflicting AWS Resources..."

# 1. Fix Secrets Manager Conflict
# The secret 'prod-backend-secrets' is 'scheduled for deletion', which blocks creating a new one.
# We will force delete it permanently.
echo "Checking Secret: prod-backend-secrets..."
aws secretsmanager delete-secret --secret-id prod-backend-secrets --force-delete-without-recovery --region us-east-1 || echo "Secret not found or already deleted."

# 2. Fix CloudWatch Log Group Conflict
# The log group '/aws/eks/crystolia-cluster/cluster' exists from a previous run.
echo "Deleting Log Group: /aws/eks/crystolia-cluster/cluster..."
aws logs delete-log-group --log-group-name /aws/eks/crystolia-cluster/cluster --region us-east-1 || echo "Log group not found."

echo "✅ Specific conflicts cleaned."
echo "⚠️  IMPORTANT: logic for Subnets/IGW:"
echo "If Terraform still fails on Subnets, you manually need to delete the Load Balancer (ELB) in the AWS Console > EC2 > Load Balancers."
