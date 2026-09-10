provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }

  # Plan-only, so fmt/validate/plan need no AWS account. Drop these five before an apply.
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
