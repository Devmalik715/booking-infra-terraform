# Remote state for prod. Deliberately a different key (and in a real account, a
# different AWS account entirely) so a mistake in dev can never touch prod state.
#   terraform init -backend-config=backend.hcl
bucket         = "tripare-tfstate-ap-south-1"
key            = "booking-platform/prod/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "tripare-tfstate-locks"
encrypt        = true
