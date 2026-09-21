variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_id" { type = string }
variable "public_subnet_ids" { type = list(string) }
variable "alb_sg_id" { type = string }
variable "container_port" { type = number }

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-${var.environment}-alb"
  }
}

resource "aws_lb_target_group" "ecs" {
  name        = "${var.project_name}-${var.environment}-ecs-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    path                = "/api/status"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-tg"
  }
}

resource "aws_lb_target_group" "ec2" {
  name        = "${var.project_name}-${var.environment}-ec2-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/api/status"
    matcher             = "200"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ec2-tg"
  }
}

# ECS — porta 80
resource "aws_lb_listener" "ecs_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

# EC2 — porta 8080 no ALB (mesmo path /api/status por baixo)
resource "aws_lb_listener" "ec2_http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }
}

output "dns_name" {
  value = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_arn_suffix" {
  value = aws_lb.main.arn_suffix
}

output "ecs_target_group_arn" {
  value = aws_lb_target_group.ecs.arn
}

output "ec2_target_group_arn" {
  value = aws_lb_target_group.ec2.arn
}

output "ecs_listener_arn" {
  value = aws_lb_listener.ecs_http.arn
}

output "ec2_listener_arn" {
  value = aws_lb_listener.ec2_http.arn
}
