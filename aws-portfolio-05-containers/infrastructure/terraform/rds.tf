# ============================================================
# RDS PostgreSQL
# コスト・destroyのしやすさを優先した設定：
# - db.t4g.micro・単一AZ（Multi-AZ・大きいインスタンスクラスは使わない）
# - backup_retention_period = 0（自動バックアップなし。ポートフォリオの
#   デモデータであり、本番の重要データではないため）
# - deletion_protection = false・skip_final_snapshot = true
#   →この2つがないと terraform destroy がスナップショット作成待ちで
#     止まる、または削除保護でエラーになる。「削除用に別のterraformを
#     作る」のではなく、最初から destroy が1コマンドで完走するように
#     設計する、という本Phaseの方針そのもの
# ============================================================

resource "random_password" "db" {
  length  = 24
  special = false # 一部の特殊文字が接続文字列で問題を起こすことがあるため英数字のみ
}

resource "aws_db_subnet_group" "main" {
  name       = var.project_name
  subnet_ids = var.public_subnet_ids

  tags = {
    Project = var.project_name
  }
}

resource "aws_db_instance" "main" {
  identifier     = var.project_name
  engine         = "postgres"
  engine_version = "16.15"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 20 # オートスケーリング無効化（コスト予測を単純にする）
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # SGで既に閉じているが、多層防御として明示

  multi_az                = false
  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = {
    Project = var.project_name
  }
}
