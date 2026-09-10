provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }

  # ---------------------------------------------------------------------------
  # Plan-only review mode.
  # This assignment does not require a real deployment, so the provider is given
  # dummy static credentials and the pre-flight STS/IMDS lookups are turned off.
  # That lets `terraform validate` and `terraform plan` run on any machine with
  # no AWS account attached.
  #
  # Before an actual apply, delete the five lines below - the provider then
  # falls back to the normal credential chain (env vars, profile, or the OIDC
  # role assumed in CI).
  # ---------------------------------------------------------------------------
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}
