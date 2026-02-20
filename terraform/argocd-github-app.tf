variable "github_app_id" {
  type    = string
  default = "2878577"
}

variable "github_app_installation_id" {
  type    = string
  default = "110518599"
}

variable "github_repo_url" {
  type    = string
  default = "https://github.com/ShaiMullo/crystolia-gitops"
}

resource "kubernetes_secret" "argocd_github_repo" {
  metadata {
    name      = "repo-crystolia-gitops"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  data = {
    type                    = "git"
    url                     = var.github_repo_url
    githubAppID             = var.github_app_id
    githubAppInstallationID = var.github_app_installation_id
    # DO NOT hardcode private key here
    # Private key will be injected later via kubectl
  }

  depends_on = [helm_release.argocd]
}
