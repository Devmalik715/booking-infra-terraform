variable "project" {
  description = "Project name, used as a prefix on every resource name."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, prod, ...)."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Subnets are carved out of this automatically."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }
}

variable "azs" {
  description = "Availability zones to spread subnets across. One public and one private subnet is created per AZ."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two AZs are required - both the ALB and the RDS subnet group need them."
  }
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ. Cheaper, but the NAT becomes a single point of failure - fine for dev, not for prod."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource in this module."
  type        = map(string)
  default     = {}
}
