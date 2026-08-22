output "alb_dns_name" {
  description = "アプリの公開エンドポイント（http://<this>/health 等）"
  value       = aws_lb.main.dns_name
}

output "ecr_repository_url" {
  description = "docker push先。deploy-05-containers-image.ymlが自動でpushする"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "RDSエンドポイント（ECSタスクSGからのみ到達可能）"
  value       = aws_db_instance.main.address
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = aws_ecs_service.app.name
}
