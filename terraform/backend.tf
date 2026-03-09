terraform {
  backend "s3" {
    bucket         = "stock-movers-tf-state"
    key            = "prod/terraform.tfstate"
    region         = "us-west-1"
    dynamodb_table = "stock-movers-tf-lock"
    encrypt        = true
  }
}
