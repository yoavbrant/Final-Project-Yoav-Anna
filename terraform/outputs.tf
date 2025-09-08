output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}
output "configure_kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}
output "rds_endpoint" {
  value = aws_db_instance.main.endpoint
}
output "acm_certificate_arn" {
  value = aws_acm_certificate.main.arn
}
output "app_secrets_arn" {
  value = aws_secretsmanager_secret.app_secrets.arn
}
