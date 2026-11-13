variable "environment" {
  description = "Ambiente (hml ou prd)"
  type        = string

  validation {
    condition     = contains(["hml", "prd"], var.environment)
    error_message = "environment deve ser hml ou prd."
  }
}

variable "aws_region" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket" {
  description = "Bucket S3 do Terraform state (TF_VAR_state_bucket)"
  type        = string
}

variable "project" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "oficina"
}

variable "engine_version" {
  description = "Versão do PostgreSQL (major; a AWS escolhe o minor padrão)"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "Classe da instância RDS"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Armazenamento inicial (GB)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Limite do autoscaling de armazenamento (GB)"
  type        = number
  default     = 50
}

variable "backup_retention_days" {
  description = "Retenção dos backups automáticos (dias)"
  type        = number
  default     = 1
}

variable "slow_query_ms" {
  description = "Queries acima deste tempo (ms) são registradas no log"
  type        = number
  default     = 500
}

variable "master_username" {
  description = "Usuário administrador do banco"
  type        = string
  default     = "oficina_admin"
}
