variable "project" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "aws_region" {
  description = "Region, used by the awslogs driver."
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
  description = "Private subnets for the Fargate tasks."
  type        = list(string)
}

variable "container_image" {
  description = "Container image the service runs."
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
  description = "Number of tasks to run."
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
  description = "Protect the ALB from deletion."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable ECS Container Insights."
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
  description = "Env var name to Secrets Manager ARN."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
