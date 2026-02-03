#!/bin/bash
set -e

echo "🔒 Bootstrapping Cert-Manager..."

# 1. Add Jetstack Helm Repo
helm repo add jetstack https://charts.jetstack.io
helm repo update

# 2. Install Cert-Manager
echo "Installing Cert-Manager via Helm..."
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.3 \
  --set installCRDs=true \
  --wait

echo "✅ Cert-Manager Installed!"
