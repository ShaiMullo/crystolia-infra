terraform {
  backend "s3" {
    bucket         = "crystolia-tf-state-main"
    key            = "infra/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "crystolia-tf-locks"
    encrypt        = true
  }
}