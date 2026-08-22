# ============================================================
# ECR — Dockerイメージリポジトリ
# force_delete = true にしておかないと、イメージが1枚でも残っている状態で
# terraform destroy が失敗する（ECRは非空リポジトリの削除を拒否するため）。
# これが「削除用のterraformを別に作る」のではなく「destroyが1コマンドで
# 完走するように最初から設計する」という方針の具体例
# ============================================================
resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "直近10枚だけ保持（ポートフォリオ規模で十分・ストレージ費用を抑える）"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
