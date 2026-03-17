# ArgoCD root-app is NOT managed by Terraform.
#
# The root-app Application manifest lives in:
#   crystolia-gitops/argocd/bootstrap/root-app.yaml
#
# It is applied via kubectl in startup-all.sh (Phase 3) after ArgoCD is healthy.
# Reason: kubernetes_manifest fetches CRD schemas during `terraform plan`,
# which fails on a fresh cluster that does not exist yet.
# ArgoCD manages its own resources after bootstrapping — Terraform state
# tracking of an ArgoCD Application creates a circular management problem.
