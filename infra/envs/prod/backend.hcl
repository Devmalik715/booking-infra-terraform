# terraform init -backend-config=backend.hcl
bucket         = "tripare-tfstate-ap-south-1"
key            = "booking-platform/prod/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "tripare-tfstate-locks"
encrypt        = true
