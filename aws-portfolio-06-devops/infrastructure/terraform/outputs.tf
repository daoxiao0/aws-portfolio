output "connection_arn" {
  description = "PENDING状態。AWSコンソールでGitHub Appの認可を完了させること"
  value       = aws_codestarconnections_connection.github.arn
}

output "connection_status" {
  value = aws_codestarconnections_connection.github.connection_status
}

output "pipeline_name" {
  value = aws_codepipeline.app.name
}

output "codebuild_project_name" {
  value = aws_codebuild_project.app.name
}
