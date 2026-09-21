variable "aws_region" {
  description = "Região AWS do projeto"
  type        = string
  default     = "sa-east-1"
}

variable "project_name" {
  description = "Nome curto usado em recursos e tags"
  type        = string
  default     = "status-api"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.40.0.0/16"
}

variable "allowed_cidrs" {
  description = "CIDRs autorizados a acessar o ALB público (bloqueio de acesso)"
  type        = list(string)
  # Ajuste para o IP do avaliador / escritório. 0.0.0.0/0 só para testes iniciais.
  default     = ["0.0.0.0/0"]
}

variable "container_port" {
  description = "Porta da aplicação"
  type        = number
  default     = 5000
}

variable "ecs_desired_count" {
  description = "Quantidade inicial de tasks ECS (0 até o primeiro push no ECR)"
  type        = number
  default     = 0
}

variable "ecs_min_capacity" {
  description = "Mínimo do auto scaling (0 permite o stop das 18h zerar as tasks)"
  type        = number
  default     = 0
}

variable "ecs_max_capacity" {
  type    = number
  default = 4
}

variable "ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ec2_key_name" {
  description = "Key pair existente na conta (opcional; acesso SSH costuma ser via SSM)"
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "E-mail para inscrição no tópico SNS de alarmes"
  type        = string
  default     = ""
}

variable "schedule_timezone" {
  description = "Timezone dos agendamentos EventBridge"
  type        = string
  default     = "America/Sao_Paulo"
}

variable "ecr_image_tag" {
  description = "Tag da imagem usada no task definition (pipeline atualiza no deploy)"
  type        = string
  default     = "latest"
}
