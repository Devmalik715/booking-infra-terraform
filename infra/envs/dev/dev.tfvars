# Dev: smallest thing that still exercises the same code path as prod.
project    = "tripare-booking"
owner      = "platform"
aws_region = "ap-south-1"
azs        = ["ap-south-1a", "ap-south-1b"]
vpc_cidr   = "10.20.0.0/16"

# Application
container_image    = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port     = 80
task_cpu           = 256
task_memory        = 512
desired_count      = 1
log_retention_days = 7

# Database - single AZ, one day of backups, no deletion protection because this
# environment gets rebuilt regularly.
db_engine_version          = "16.3"
db_instance_class          = "db.t4g.micro"
db_allocated_storage       = 20
db_max_allocated_storage   = 50
db_name                    = "bookings"
db_backup_retention_period = 1
