#!/bin/bash
set -e

echo "🐙 Bootstrapping ArgoCD..."

# 1. Add ArgoCD Helm Repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# 2. Install ArgoCD
echo "Installing ArgoCD via Helm..."
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --set server.service.type=LoadBalancer \
  --wait

echo "✅ ArgoCD Installed!"

# 3. Retrieve Initial Password
echo "🔑 Retrieving Initial Admin Password..."
PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "---------------------------------------------------"
echo "🌐 ArgoCD URL: (Wait for LoadBalancer IP below)"
kubectl -n argocd get svc argocd-server
echo ""
echo "👤 Username: admin"
echo "🔑 Password: $PASSWORD"
echo "---------------------------------------------------"
