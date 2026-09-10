output "cluster_name" {
  description = "Name of the ECS cluster."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "Name of the ECS service."
  value       = aws_ecs_service.this.name
}

output "alb_dns_name" {
  description = "Public DNS name of the load balancer."
  value       = aws_lb.this.dns_name
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB."
  value       = aws_security_group.alb.id
}

output "tasks_security_group_id" {
  description = "Security group attached to the Fargate tasks. RDS grants ingress to this SG."
  value       = aws_security_group.tasks.id
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role."
  value       = aws_iam_role.task_execution.arn
}
