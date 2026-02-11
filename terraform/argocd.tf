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

  # ---- ArgoCD server configuration ----
  values = [
    yamlencode({
      # Global configs including server params
      configs = {
        params = {
          # Run server in insecure mode (no TLS) - required for HTTP ingress
          "server.insecure" = true
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }

        # Extra args for proper HTTP handling
        extraArgs = [
          "--insecure"
        ]

        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      repoServer = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      controller = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    module.eks,
    helm_release.ingress_nginx
  ]
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
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
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

