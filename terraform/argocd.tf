# ArgoCD Installation via Helm
# ----------------------------
# GitOps controller for application deployments.
# Exposed via ingress-nginx for external access.

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.6"
  namespace        = "argocd"
  create_namespace = true

  wait    = true
  timeout = 600

  # Server configuration
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  # Disable TLS on server (handled by ingress)
  set {
    name  = "server.insecure"
    value = "true"
  }

  # Resource limits for server
  set {
    name  = "server.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "server.resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "server.resources.limits.memory"
    value = "256Mi"
  }

  # Repo server resources
  set {
    name  = "repoServer.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "repoServer.resources.requests.memory"
    value = "128Mi"
  }

  # Controller resources
  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "128Mi"
  }

  depends_on = [module.eks, helm_release.ingress_nginx]
}

# -----------------------------------------------------------------------------
# Ingress for ArgoCD Server
# -----------------------------------------------------------------------------

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server-ingress"
    namespace = "argocd"
    annotations = {
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "argocd_url" {
  description = "ArgoCD external URL (via ingress-nginx NLB)"
  value       = "http://${data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].hostname}"
}

output "argocd_admin_password_command" {
  description = "Command to get ArgoCD admin password"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

# Data source to get ingress-nginx LoadBalancer hostname
data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}
