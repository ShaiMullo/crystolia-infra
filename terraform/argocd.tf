resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "5.51.6"
  namespace        = "argocd"
  create_namespace = true

  wait         = true
  timeout      = 600
  force_update = true

  values = [
    yamlencode({
      configs = {
        params = {
          # "server.insecure" removed to rely on extraArgs
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }

        ingress = {
          enabled = false
        }

        extraArgs = ["--insecure"]
      }

      controller = {
        resources = { requests = { cpu = "100m", memory = "128Mi" } }
      }
      repoServer = {
        resources = { requests = { cpu = "100m", memory = "128Mi" } }
      }
    })
  ]

  depends_on = [
    module.eks,
    helm_release.ingress_nginx
  ]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server-ingress"
    namespace = "argocd"

    annotations = {
      "kubernetes.io/ingress.class"                    = "nginx"
      "nginx.ingress.kubernetes.io/backend-protocol"   = "HTTP"
      "nginx.ingress.kubernetes.io/ssl-redirect"       = "false"
      "nginx.ingress.kubernetes.io/force-ssl-redirect" = "false"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = "argocd.crystolia.com"

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

  depends_on = [
    module.eks,
    helm_release.argocd
  ]
}

output "argocd_admin_password_command" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
