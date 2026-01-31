#!/bin/bash
set -e

echo "📊 Bootstrapping Monitoring Stack (Prometheus & Grafana)..."

# 1. Add Prometheus Helm Repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 2. Install Kube-Prometheus-Stack
echo "Installing Prometheus & Grafana via Helm..."
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.service.type=LoadBalancer \
  --wait

echo "✅ Monitoring Stack Installed!"

# 3. Retrieve Grafana Admin Password
echo "🔑 Retrieving Grafana Admin Password..."
PASSWORD=$(kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 -d)

echo "---------------------------------------------------"
echo "📈 Grafana URL: (Wait for LoadBalancer IP below)"
kubectl -n monitoring get svc prometheus-grafana
echo ""
echo "👤 Username: admin"
echo "🔑 Password: $PASSWORD"
echo "---------------------------------------------------"
