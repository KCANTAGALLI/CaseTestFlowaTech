variable "project_name" { type = string }
variable "environment" { type = string }
variable "ecs_cluster_name" { type = string }
variable "ecs_service_name" { type = string }
variable "ec2_instance_id" { type = string }
variable "schedule_timezone" { type = string }

data "archive_file" "ecs_scheduler" {
  type        = "zip"
  source_file = "${path.root}/../lambda/ecs_scheduler/handler.py"
  output_path = "${path.module}/ecs_scheduler.zip"
}

data "archive_file" "ec2_scheduler" {
  type        = "zip"
  source_file = "${path.root}/../lambda/ec2_scheduler/handler.py"
  output_path = "${path.module}/ec2_scheduler.zip"
}

# --- ECS start/stop ---------------------------------------------------------

resource "aws_iam_role" "ecs_lambda" {
  name = "${var.project_name}-${var.environment}-ecs-sched-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_lambda_basic" {
  role       = aws_iam_role.ecs_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ecs_lambda" {
  name = "${var.project_name}-${var.environment}-ecs-sched"
  role = aws_iam_role.ecs_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ecs:UpdateService", "ecs:DescribeServices"]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "ecs_scheduler" {
  function_name = "${var.project_name}-${var.environment}-ecs-scheduler"
  role          = aws_iam_role.ecs_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.ecs_scheduler.output_path
  source_code_hash = data.archive_file.ecs_scheduler.output_base64sha256

  environment {
    variables = {
      ECS_CLUSTER = var.ecs_cluster_name
      ECS_SERVICE = var.ecs_service_name
    }
  }
}

# EventBridge Scheduler com timezone explícito (America/Sao_Paulo)
resource "aws_scheduler_schedule_group" "main" {
  name = "${var.project_name}-${var.environment}"
}

resource "aws_iam_role" "scheduler" {
  name = "${var.project_name}-${var.environment}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "${var.project_name}-${var.environment}-scheduler"
  role = aws_iam_role.scheduler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = [
        aws_lambda_function.ecs_scheduler.arn,
        aws_lambda_function.ec2_scheduler.arn,
      ]
    }]
  })
}

resource "aws_scheduler_schedule" "ecs_start" {
  name       = "${var.project_name}-${var.environment}-ecs-start"
  group_name = aws_scheduler_schedule_group.main.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 9 ? * MON-FRI *)"
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.ecs_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "start" })
  }
}

resource "aws_scheduler_schedule" "ecs_stop" {
  name       = "${var.project_name}-${var.environment}-ecs-stop"
  group_name = aws_scheduler_schedule_group.main.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 18 ? * MON-FRI *)"
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.ecs_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "stop" })
  }
}

# --- EC2 start/stop ---------------------------------------------------------

resource "aws_iam_role" "ec2_lambda" {
  name = "${var.project_name}-${var.environment}-ec2-sched-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_lambda_basic" {
  role       = aws_iam_role.ec2_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ec2_lambda" {
  name = "${var.project_name}-${var.environment}-ec2-sched"
  role = aws_iam_role.ec2_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:StartInstances",
        "ec2:StopInstances",
        "ec2:DescribeInstances"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_lambda_function" "ec2_scheduler" {
  function_name = "${var.project_name}-${var.environment}-ec2-scheduler"
  role          = aws_iam_role.ec2_lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.ec2_scheduler.output_path
  source_code_hash = data.archive_file.ec2_scheduler.output_base64sha256

  environment {
    variables = {
      INSTANCE_ID = var.ec2_instance_id
    }
  }
}

resource "aws_scheduler_schedule" "ec2_start" {
  name       = "${var.project_name}-${var.environment}-ec2-start"
  group_name = aws_scheduler_schedule_group.main.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 9 ? * MON-FRI *)"
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.ec2_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "start" })
  }
}

resource "aws_scheduler_schedule" "ec2_stop" {
  name       = "${var.project_name}-${var.environment}-ec2-stop"
  group_name = aws_scheduler_schedule_group.main.name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0 18 ? * MON-FRI *)"
  schedule_expression_timezone = var.schedule_timezone

  target {
    arn      = aws_lambda_function.ec2_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn
    input    = jsonencode({ action = "stop" })
  }
}

# Permissão explícita (além do role do Scheduler) — útil se alguém invocar via EventBridge clássico
resource "aws_lambda_permission" "ecs_scheduler_events" {
  statement_id  = "AllowSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_scheduler.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:*:*:schedule/${aws_scheduler_schedule_group.main.name}/*"
}

resource "aws_lambda_permission" "ec2_scheduler_events" {
  statement_id  = "AllowSchedulerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = "arn:aws:scheduler:*:*:schedule/${aws_scheduler_schedule_group.main.name}/*"
}

output "ecs_scheduler_arn" {
  value = aws_lambda_function.ecs_scheduler.arn
}

output "ec2_scheduler_arn" {
  value = aws_lambda_function.ec2_scheduler.arn
}
