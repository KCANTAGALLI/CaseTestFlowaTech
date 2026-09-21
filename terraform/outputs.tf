output "alb_dns_name" {
  description = "DNS público do Application Load Balancer"
  value       = module.alb.dns_name
}

output "ecs_status_url" {
  description = "URL do endpoint /api/status via ALB (ECS, porta 80)"
  value       = "http://${module.alb.dns_name}/api/status"
}

output "ec2_status_url" {
  description = "URL do endpoint /api/status via ALB (EC2, porta 8080)"
  value       = "http://${module.alb.dns_name}:8080/api/status"
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "ecs_cluster_name" {
  value = module.ecs.cluster_name
}

output "ecs_service_name" {
  value = module.ecs.service_name
}

output "ec2_instance_id" {
  value = module.ec2.instance_id
}

output "ec2_private_ip" {
  value = module.ec2.private_ip
}

output "sns_topic_arn" {
  value = module.monitoring.sns_topic_arn
}

output "waf_web_acl_arn" {
  value = module.waf.web_acl_arn
}

output "deploy_bucket" {
  description = "Bucket S3 usado pelo pipeline para enviar o artefato Linux"
  value       = module.ec2.deploy_bucket
}
