variable "project" {
  description = "Project name, used as a prefix on every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "aws_region" {
  description = "Region the service runs in. Used for the awslogs driver configuration."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and load balancer are deployed into."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the internet-facing ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks. Tasks get no public IP."
  type        = list(string)
}

variable "container_image" {
  description = "Image the service runs. A placeholder web image is enough for this exercise."
  type        = string
  default     = "public.ecr.aws/nginx/nginx:1.27-alpine"
}

variable "container_port" {
  description = "Port the container listens on."
  type        = number
  default     = 80
}

variable "task_cpu" {
  description = "Fargate task CPU units (256 = 0.25 vCPU)."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Fargate task memory in MiB. Must be a valid pairing with task_cpu."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks to keep running."
  type        = number
  default     = 1
}

variable "health_check_path" {
  description = "Path the ALB target group polls."
  type        = string
  default     = "/"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the service log group."
  type        = number
  default     = 14
}

variable "enable_deletion_protection" {
  description = "Protect the ALB from accidental deletion. Should be true in prod."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Turn on ECS Container Insights (extra CloudWatch cost)."
  type        = bool
  default     = false
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB on port 80."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "container_environment" {
  description = "Plain environment variables passed to the container."
  type        = map(string)
  default     = {}
}

variable "container_secrets" {
  description = "Secrets injected into the container as env vars. Map of ENV_VAR_NAME to a Secrets Manager ARN."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
