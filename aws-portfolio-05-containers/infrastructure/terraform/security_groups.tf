# ============================================================
# セキュリティグループ — 3層（ALB → ECSタスク → RDS）
# サブネットはすべて公開サブネットだが、実際のアクセス制御はここで行う。
# RDSはpublicサブネットに置くが、インバウンドはECSタスクSGからの
# 5432番のみに絞っているため、インターネットから直接到達はできない
# ============================================================

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb"
  description = "ALB - allow HTTP 80 from the internet only"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "ecs_task" {
  name        = "${var.project_name}-ecs-task"
  description = "ECS task - allow the container port from the ALB SG only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    # RDS（5432）とECR/CloudWatch Logs等へのHTTPS両方が必要なので全開放
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds"
  description = "RDS - allow port 5432 from the ECS task SG only (public subnet, unreachable from the internet)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Postgres from ECS tasks only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_task.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Project = var.project_name
  }
}
