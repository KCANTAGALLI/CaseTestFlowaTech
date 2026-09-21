variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "allowed_cidrs" { type = list(string) }
variable "container_port" { type = number }

# ALB — único ponto com acesso público (restrito por CIDR)
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-alb-sg"
  description = "ALB publico - acesso controlado por CIDR"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP ECS (ALB:80) — só CIDRs autorizados"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  ingress {
    description = "HTTP EC2 (ALB:8080) — só CIDRs autorizados"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# Tasks ECS — só recebem tráfego do ALB, sem IP público
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-sg"
  description = "Tasks ECS - apenas trafego do ALB na porta da app"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-sg"
  }
}

# EC2 — privado; app só pelo ALB; SSM/egress via NAT
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-sg"
  description = "EC2 privado - app apenas via ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # SSH opcional só de dentro da VPC (bastion / Session Manager é o caminho preferido)
  ingress {
    description = "SSH interno VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-sg"
  }
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "ecs_sg_id" {
  value = aws_security_group.ecs.id
}

output "ec2_sg_id" {
  value = aws_security_group.ec2.id
}
