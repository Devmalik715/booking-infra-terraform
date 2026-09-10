variable "project" {
  description = "Project name, used as a prefix on every resource name."
  type        = string
  default     = "tripare-booking"
}

variable "owner" {
  description = "Team that owns the stack. Ends up on every resource as a tag."
  type        = string
  default     = "platform"
}

variable "aws_region" {
  description = "Region the stack is deployed into."
  type        = string
  default     = "ap-south-1"
}

variable "azs" {
  description = "Availability zones to spread the subnets across."
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC. Kept distinct from prod so the two can be peered later."
  type        = string
  default     = "10.20.0.0/16"
}

########################################
# Application sizing
########################################

variable "container_image" {
  description = "Image the service runs. Placeholder until the real backend image is published."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to keep running."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the service."
  type        = number
  default     = 7
}

########################################
# Database sizing
########################################

variable "db_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 50
}

variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "bookings"
}

variable "db_backup_retention_period" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 1
}
