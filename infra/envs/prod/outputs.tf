output "vpc_id" {
  description = "ID of the prod VPC."
  value       = module.network.vpc_id
}

output "alb_dns_name" {
  description = "Public hostname of the load balancer."
  value       = module.ecs.alb_dns_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster."
  value       = module.ecs.cluster_name
}

output "rds_endpoint" {
  description = "Private endpoint of the database. Only resolvable from inside the VPC."
  value       = module.rds.endpoint
}

output "rds_master_user_secret_arn" {
  description = "Secrets Manager ARN holding the master credentials."
  value       = module.rds.master_user_secret_arn
}
