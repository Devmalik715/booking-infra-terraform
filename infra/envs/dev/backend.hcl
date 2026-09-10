# terraform init -backend-config=backend.hcl
bucket and lock table are created once, out of band, so that bootstrapping
# state storage never depends on the state it is storing.
bucket         = "tripare-tfstate-ap-south-1"
key            = "booking-platform/dev/terraform.tfstate"
region         = "ap-south-1"
dynamodb_table = "tripare-tfstate-locks"
encrypt        = true
