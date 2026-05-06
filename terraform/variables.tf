
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short slug used to name all resources"
  type        = string
  default     = "devops-challenge"
}

variable "environment" {
  description = "Deployment environment (prod | staging | dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "environment must be one of: prod, staging, dev."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of AZs to spread subnets across (minimum 2 for ALB)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "image_tag" {
  description = "Docker image tag to deploy (set by CI/CD to git SHA)"
  type        = string
  default     = "latest"
}

variable "app_port" {
  description = "Port the container listens on"
  type        = number
  default     = 3000
}

variable "desired_count" {
  description = "Number of ECS task replicas"
  type        = number
  default     = 2
}

variable "task_cpu" {
  description = "CPU units for the ECS task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memory (MiB) for the ECS task"
  type        = number
  default     = 512
}

variable "alarm_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = "ops@example.com"
}
