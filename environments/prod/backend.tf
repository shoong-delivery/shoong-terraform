terraform {
  backend "s3" {
    bucket         = "shoong-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "shoong-terraform-state-lock"
    encrypt        = true
  }
}
