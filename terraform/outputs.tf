
output "alb_dns_name" {
  description = "Public DNS of the Application Load Balancer"
  value       = module.ecs.alb_dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for pushing images"
  value       = module.ecr.repository_url
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group for the application"
  value       = module.monitoring.log_group_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}
