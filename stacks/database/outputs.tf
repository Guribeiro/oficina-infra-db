# Consumidos via terraform_remote_state pelo repositório oficina-lambda-auth.
output "db_address" {
  description = "Endpoint (host) do PostgreSQL"
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "Porta do PostgreSQL"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Nome do banco"
  value       = aws_db_instance.this.db_name
}

output "db_secret_arn" {
  description = "ARN do segredo de conexão (oficina/<env>/db)"
  value       = aws_secretsmanager_secret.db.arn
}

output "jwt_secret_arn" {
  description = "ARN do segredo JWT (oficina/<env>/jwt)"
  value       = aws_secretsmanager_secret.jwt.arn
}

output "db_security_group_id" {
  description = "Security group do RDS"
  value       = aws_security_group.db.id
}

output "db_client_security_group_id" {
  description = "Security group a anexar nas Lambdas que acessam o banco"
  value       = aws_security_group.clients.id
}
