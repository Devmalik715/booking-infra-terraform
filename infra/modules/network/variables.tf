variable "project" {
  description = "Prefix for resource names."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "Must be a valid IPv4 CIDR block."
  }
}

variable "azs" {
  description = "Availability zones. One public and one private subnet per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required."
  }
}

variable "single_nat_gateway" {
  description = "Share one NAT gateway across all AZs instead of one per AZ."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
