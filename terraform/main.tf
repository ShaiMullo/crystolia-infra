terraform {
  backend "s3" {
    bucket         = "crystolia-terraform-state-prod"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "crystolia-terraform-locks"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# 1. Network
module "vpc" {
  source       = "./modules/vpc"
  environment  = "prod"
  cluster_name = "crystolia-cluster"
  vpc_cidr     = "10.0.0.0/16"
}

# 2. Compute
module "eks" {
  source       = "./modules/eks"
  cluster_name = "crystolia-cluster"
  environment  = "prod"
  vpc_id       = module.vpc.vpc_id
  subnet_ids   = module.vpc.private_subnets
}

# 3. Registry
module "ecr" {
  source = "./modules/ecr"
}

# 4. Security
module "security" {
  source            = "./modules/security"
  environment       = "prod"
  cluster_name      = module.eks.cluster_name

  oidc_provider_arn = module.eks.oidc_provider_arn
}

# 5. Certificates
module "acm" {
  source           = "./modules/acm"
  domain_name      = "crystolia.com"
  environment      = "prod"
  alternative_name = ["www.crystolia.com", "api.crystolia.com"]
  zone_id          = aws_route53_zone.main_zone.zone_id
}

output "vpc_id" { value = module.vpc.vpc_id }
output "nat_ip" { value = module.vpc.nat_public_ip } # Whitelist this in MongoDB Atlas
output "eks_cluster_endpoint" { value = module.eks.cluster_endpoint }
output "backend_role_arn" { value = module.security.backend_role_arn }
output "ecr_repos" { value = module.ecr.repository_urls }
