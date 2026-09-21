variable "project_name" { type = string }
variable "environment" { type = string }
variable "aws_region" { type = string }
variable "private_subnet_id" { type = string }
variable "ec2_sg_id" { type = string }
variable "instance_type" { type = string }
variable "key_name" { type = string }
variable "container_port" { type = number }
variable "target_group_arn" { type = string }

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_s3_bucket" "deploy" {
  bucket_prefix = "${var.project_name}-${var.environment}-deploy-"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-deploy"
  }
}

resource "aws_s3_bucket_public_access_block" "deploy" {
  bucket = aws_s3_bucket.deploy.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "deploy" {
  bucket = aws_s3_bucket.deploy.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ec2_s3" {
  name = "${var.project_name}-${var.environment}-ec2-s3"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.deploy.arn,
          "${aws_s3_bucket.deploy.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    dnf update -y
    dnf install -y cronie amazon-cloudwatch-agent

    # Runtime .NET 8 (ASP.NET Core)
    if ! command -v dotnet >/dev/null 2>&1; then
      curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
      bash /tmp/dotnet-install.sh --channel 8.0 --runtime aspnetcore --install-dir /usr/share/dotnet
      ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    fi
    dotnet --list-runtimes || true

    systemctl enable --now crond

    # Usuário de transferência de artefatos (sem shell de login interativo)
    id deployxfer &>/dev/null || useradd -m -s /usr/sbin/nologin deployxfer
    mkdir -p /opt/status-api/releases /opt/status-api/current
    chown -R deployxfer:deployxfer /opt/status-api
    chmod 755 /opt/status-api

    # Usuário que executa a aplicação
    id apprunner &>/dev/null || useradd -m -s /bin/bash apprunner
    usermod -aG deployxfer apprunner || true

    # Permite que apprunner leia o release atual
    setfacl -R -m u:apprunner:rx /opt/status-api 2>/dev/null || \
      chmod -R o+rx /opt/status-api

    # Placeholder do unit — o pipeline sobrescreve no deploy
    cat >/etc/systemd/system/status-api.service <<'UNIT'
    [Unit]
    Description=Status API (.NET)
    After=network.target

    [Service]
    Type=simple
    User=apprunner
    WorkingDirectory=/opt/status-api/current
    ExecStart=/usr/bin/dotnet /opt/status-api/current/StatusApi.dll
    Restart=on-failure
    RestartSec=5
    Environment=ASPNETCORE_URLS=http://0.0.0.0:5000
    Environment=ASPNETCORE_ENVIRONMENT=Production
    Environment=DOTNET_PRINT_TELEMETRY_MESSAGE=false

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    # Serviço só sobe de verdade depois do primeiro deploy via pipeline

    # CloudWatch Agent — métricas de CPU, memória e rede
    cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CW'
    {
      "metrics": {
        "namespace": "StatusApi/EC2",
        "append_dimensions": {
          "InstanceId": "$${aws:InstanceId}"
        },
        "metrics_collected": {
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
            "totalcpu": true,
            "metrics_collection_interval": 60
          },
          "mem": {
            "measurement": ["mem_used_percent"],
            "metrics_collection_interval": 60
          },
          "net": {
            "measurement": ["bytes_sent", "bytes_recv"],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": ["used_percent"],
            "resources": ["/"],
            "metrics_collection_interval": 60
          }
        }
      }
    }
    CW

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true

    echo "bootstrap ok" > /var/log/status-api-bootstrap.log
  EOF
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_id
  vpc_security_group_ids = [var.ec2_sg_id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = var.key_name != "" ? var.key_name : null

  associate_public_ip_address = false

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = {
    Name    = "${var.project_name}-${var.environment}-ec2"
    Role    = "app-server"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.app.id
  port             = var.container_port
}

output "instance_id" {
  value = aws_instance.app.id
}

output "private_ip" {
  value = aws_instance.app.private_ip
}

output "deploy_bucket" {
  value = aws_s3_bucket.deploy.id
}

output "deploy_bucket_arn" {
  value = aws_s3_bucket.deploy.arn
}

output "instance_role_name" {
  value = aws_iam_role.ec2.name
}
