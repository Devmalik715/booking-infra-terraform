variable "project" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security groups allowed to connect to the database."
  type        = list(string)

  validation {
    condition     = length(var.allowed_security_group_ids) > 0
    error_message = "Pass at least one client security group."
  }
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.3"
}

variable "instance_class" {
  description = "RDS instance class. Sized per environment."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB."
  type        = number
  default     = 100
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "bookings"
}

variable "master_username" {
  description = "Master username. The password is managed by RDS in Secrets Manager."
  type        = string
  default     = "app_admin"
}

variable "port" {
  description = "Port the database listens on."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Run a synchronous standby in a second AZ."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days of automated backups to keep."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Must be between 1 and 35."
  }
}

variable "backup_window" {
  description = "Daily backup window, UTC."
  type        = string
  default     = "18:30-19:30"
}

variable "maintenance_window" {
  description = "Weekly maintenance window, UTC."
  type        = string
  default     = "sun:19:45-sun:20:45"
}

variable "deletion_protection" {
  description = "Block deletion of the instance."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on delete."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds (0 disables it)."
  type        = number
  default     = 0
}

variable "apply_immediately" {
  description = "Apply changes immediately instead of at the maintenance window."
  type        = bool
  default     = false
}

variable "log_min_duration_statement" {
  description = "Log statements slower than this many milliseconds."
  type        = number
  default     = 1000
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
