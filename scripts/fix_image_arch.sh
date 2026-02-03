#!/bin/bash
set -e

echo "🏗️  Fixing Architecture Mismatch (ARM64 -> AMD64)..."

# Define variables
ECR_REGISTRY="268456953512.dkr.ecr.us-east-1.amazonaws.com"
APP_DIR="../crystolia-app"

# Check if app dir exists
if [ ! -d "$APP_DIR" ]; then
  echo "❌ Error: Cannot find $APP_DIR"
  echo "Please make sure 'crystolia-app' and 'crystolia-infra' are side-by-side."
  exit 1
fi

# 1. Login to ECR
echo "🔑 Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_REGISTRY

# 2. Build & Push Backend
echo "📦 Building Backend (linux/amd64)..."
docker build --platform linux/amd64 -t $ECR_REGISTRY/crystolia-backend:latest $APP_DIR/backend
echo "⬆️  Pushing Backend..."
docker push $ECR_REGISTRY/crystolia-backend:latest

# 3. Build & Push Frontend
echo "📦 Building Frontend (linux/amd64)..."
docker build --platform linux/amd64 --build-arg NEXT_PUBLIC_API_URL=https://crystolia.com/api -t $ECR_REGISTRY/crystolia-frontend:latest $APP_DIR/frontend-client
echo "⬆️  Pushing Frontend..."
docker push $ECR_REGISTRY/crystolia-frontend:latest

# 4. Restart Pods
echo "🔄 Restarting Pods to pull new images..."
kubectl delete pods -n default --all

echo "✅ Done! Images rebuilt for Server Architecture."
