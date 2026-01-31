variable "repositories" {
  type = list(string)
  default = ["crystolia-backend", "crystolia-frontend"]
}

resource "aws_ecr_repository" "repos" {
  count = length(var.repositories)
  name  = var.repositories[count.index]
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "repos_policy" {
  count      = length(var.repositories)
  repository = aws_ecr_repository.repos[count.index].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 30 images"
      selection = {
        tagStatus     = "any"
        countType     = "imageCountMoreThan"
        countNumber   = 30
      }
      action = {
        type = "expire"
      }
    }]
  })
}

output "repository_urls" {
  value = aws_ecr_repository.repos[*].repository_url
}
