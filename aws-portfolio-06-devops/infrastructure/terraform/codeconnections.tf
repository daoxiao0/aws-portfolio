# ============================================================
# CodeConnections（旧CodeStar Connections）— GitHubへの接続
# terraform applyだけではPENDING状態のまま——AWSコンソールで
# GitHub Appの認可を人間が完了させる必要がある（OAuthハンドシェイクの
# ため、これだけはプログラムから代行できない）
# ============================================================
resource "aws_codestarconnections_connection" "github" {
  name          = "${var.project_name}-github"
  provider_type = "GitHub"

  tags = {
    Project = var.project_name
  }
}
