terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  # State lives in S3 with a DynamoDB lock table, one key per environment.
  # The block is left commented so this repo can be reviewed offline with a
  # plain `terraform init`. The real settings are in backend.hcl:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # backend "s3" {}
}
