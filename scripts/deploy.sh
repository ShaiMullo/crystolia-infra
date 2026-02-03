#!/bin/bash
set -e
REGION="us-east-1"
CLUSTER_NAME="crystolia-cluster"

echo "🔄 Restarting Crystolia Backend..."

# Auth
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME > /dev/null 2>&1
if ! kubectl get svc > /dev/null 2>&1; then
    echo "⚠️  Default auth failed. Trying to assume 'prod-backend-role'..."
    aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME --role-arn arn:aws:iam::268456953512:role/prod-backend-role
fi

# Restart
kubectl rollout restart deployment/crystolia-backend
kubectl rollout status deployment/crystolia-backend

echo "✅ Backend restarted successfully!"
