# ingress-nginx Controller for EKS
# ---------------------------------
# Provides Ingress capabilities for the cluster.
# Creates an AWS Network Load Balancer (NLB) for external access.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.9.0"
  namespace        = "ingress-nginx"
  create_namespace = true

  # Wait for the LoadBalancer to be provisioned
  wait    = true
  timeout = 300

  # AWS-specific configuration for NLB
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "nlb"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-cross-zone-load-balancing-enabled"
    value = "true"
  }

  # Resource limits
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "controller.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "controller.resources.limits.memory"
    value = "256Mi"
  }

  # Admission webhook (required for ingress validation)
  set {
    name  = "controller.admissionWebhooks.enabled"
    value = "true"
  }

  depends_on = [module.eks]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "ingress_nginx_service" {
  description = "ingress-nginx controller service name"
  value       = "ingress-nginx-controller"
}

output "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is installed"
  value       = helm_release.ingress_nginx.namespace
}
