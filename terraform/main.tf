module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

module "security" {
  source = "./modules/security"

  project_name   = var.project_name
  environment    = var.environment
  vpc_id         = module.network.vpc_id
  vpc_cidr       = module.network.vpc_cidr
  allowed_cidrs  = var.allowed_cidrs
  container_port = var.container_port
}

module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id
  container_port    = var.container_port
}

module "ecs" {
  source = "./modules/ecs"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  private_subnet_ids = module.network.private_subnet_ids
  ecs_sg_id          = module.security.ecs_sg_id
  container_port     = var.container_port
  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.ecr_image_tag
  desired_count      = var.ecs_desired_count
  min_capacity       = var.ecs_min_capacity
  max_capacity       = var.ecs_max_capacity
  target_group_arn   = module.alb.ecs_target_group_arn
}

module "ec2" {
  source = "./modules/ec2"

  project_name      = var.project_name
  environment       = var.environment
  aws_region        = var.aws_region
  private_subnet_id = module.network.private_subnet_ids[0]
  ec2_sg_id         = module.security.ec2_sg_id
  instance_type     = var.ec2_instance_type
  key_name          = var.ec2_key_name
  container_port    = var.container_port
  target_group_arn  = module.alb.ec2_target_group_arn
}

module "waf" {
  source = "./modules/waf"

  project_name = var.project_name
  environment  = var.environment
  alb_arn      = module.alb.alb_arn
}

module "lambda" {
  source = "./modules/lambda"

  project_name       = var.project_name
  environment        = var.environment
  ecs_cluster_name   = module.ecs.cluster_name
  ecs_service_name   = module.ecs.service_name
  ec2_instance_id    = module.ec2.instance_id
  schedule_timezone  = var.schedule_timezone
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name     = var.project_name
  environment      = var.environment
  aws_region       = var.aws_region
  alarm_email      = var.alarm_email
  ecs_cluster_name = module.ecs.cluster_name
  ecs_service_name = module.ecs.service_name
  ec2_instance_id  = module.ec2.instance_id
  alb_arn_suffix   = module.alb.alb_arn_suffix
}
