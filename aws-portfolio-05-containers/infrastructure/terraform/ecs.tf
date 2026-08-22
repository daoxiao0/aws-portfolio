# ============================================================
# ECS Fargate — クラスタ・タスク定義・サービス
# 0.25 vCPU / 0.5GB・desired_count 1・オートスケーリングなし
# （デモ用途であり負荷対策は不要）
# ============================================================

resource "aws_ecs_cluster" "main" {
  name = var.project_name

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14 # Phase 4と同じ方針——無期限保持にしない

  tags = {
    Project = var.project_name
  }
}

# ----------------------------------------------------------
# タスク実行ロール（ECSがイメージをpull・ログを書く際に使う。
# タスク自体のロールとは別物）
# ----------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ----------------------------------------------------------
# タスクロール（アプリコード自身が引き受ける権限。
# 現状DB接続情報はTerraformが環境変数として注入しており、実行時に
# AWS APIを呼ぶ必要がない——Phase 3のper-function最小権限方針と同じで、
# 「本当に必要な権限だけ」を空のロールとして用意する）
# ----------------------------------------------------------
resource "aws_iam_role" "task" {
  name = "${var.project_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.project_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [
        { name = "DB_HOST", value = aws_db_instance.main.address },
        { name = "DB_PORT", value = tostring(aws_db_instance.main.port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "DB_USER", value = var.db_username },
        { name = "DB_PASSWORD", value = random_password.db.result },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecs_service" "app" {
  name            = var.project_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.ecs_task.id]
    assign_public_ip = true # NAT Gatewayを使わないため、タスク自身がpublic IPを持つ
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # ALBのlistener/target group作成完了前にサービスを起動しようとして
  # 失敗しないよう明示的に依存させる
  depends_on = [aws_lb_listener.http]

  tags = {
    Project = var.project_name
  }
}
