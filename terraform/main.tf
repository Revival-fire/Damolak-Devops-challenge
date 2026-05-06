###############################################################################
# Root Terraform Configuration — DevOps Challenge
# Orchestrates all child modules.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state — bucket and table created by bootstrap.sh
  backend "s3" {
    bucket         = "devops-challenge-tfstate"          # set via -backend-config or env
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "devops-challenge-tflock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "github.com/your-org/devops-challenge"
    }
  }
}

###############################################################################
# Modules
###############################################################################

module "networking" {
  source = "./modules/networking"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "ecs" {
  source = "./modules/ecs"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  vpc_id              = module.networking.vpc_id
  public_subnet_ids   = module.networking.public_subnet_ids
  private_subnet_ids  = module.networking.private_subnet_ids
  ecr_repository_url  = module.ecr.repository_url
  image_tag           = var.image_tag
  app_port            = var.app_port
  desired_count       = var.desired_count
  cpu                 = var.task_cpu
  memory              = var.task_memory
  log_group_name      = module.monitoring.log_group_name
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name     = var.project_name
  environment      = var.environment
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  alb_arn_suffix   = module.ecs.alb_arn_suffix
  alarm_email      = var.alarm_email
}
