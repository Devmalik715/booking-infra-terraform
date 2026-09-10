project    = "tripare-booking"
owner      = "platform"
aws_region = "ap-south-1"
azs        = ["ap-south-1a", "ap-south-1b"]
vpc_cidr   = "10.10.0.0/16"

container_image    = "public.ecr.aws/nginx/nginx:1.27-alpine"
container_port     = 80
task_cpu           = 1024
task_memory        = 2048
desired_count      = 3
log_retention_days = 90

db_engine_version          = "16.3"
db_instance_class          = "db.m7g.large"
db_allocated_storage       = 100
db_max_allocated_storage   = 500
db_name                    = "bookings"
db_backup_retention_period = 30
