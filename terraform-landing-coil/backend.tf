terraform {
  backend "s3" {
    bucket         = "crystolia-tf-state-main"
    key            = "landing-coil/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "crystolia-tf-locks"
    encrypt        = true
  }
}
