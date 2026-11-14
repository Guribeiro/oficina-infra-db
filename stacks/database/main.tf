# Banco de dados gerenciado de um ambiente (hml ou prd): Amazon RDS PostgreSQL em
# subnets privadas, acessível apenas pelos nodes do EKS e pelas Lambdas de
# autenticação, com credenciais publicadas no AWS Secrets Manager.
locals {
  name = "${var.project}-db-${var.environment}"

  tags = {
    Project     = "oficina-mecanica"
    Repository  = "oficina-infra-db"
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  platform = data.terraform_remote_state.platform.outputs
  db_name  = "${var.project}_${var.environment}"
}

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "oficina-infra-k8s/platform/terraform.tfstate"
    region = var.aws_region
  }
}

# ---------------------------------------------------------------------------
# Rede e acesso
# ---------------------------------------------------------------------------
resource "aws_db_subnet_group" "this" {
  name        = local.name
  description = "Subnets privadas do RDS (${var.environment})"
  subnet_ids  = local.platform.private_subnet_ids
}

# SG anexado pelos clientes do banco fora do cluster (Lambdas de autenticação).
resource "aws_security_group" "clients" {
  name        = "${local.name}-clients"
  description = "Clientes autorizados a acessar o RDS ${var.environment} (Lambdas)"
  vpc_id      = local.platform.vpc_id

  egress {
    description = "Saida liberada (RDS e Secrets Manager via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name        = local.name
  description = "PostgreSQL ${var.environment}: acesso somente do EKS e das Lambdas"
  vpc_id      = local.platform.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "from_eks" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL a partir dos nodes do EKS (API e Jobs de migration)"
  referenced_security_group_id = local.platform.cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "from_clients" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL a partir das Lambdas de autenticacao"
  referenced_security_group_id = aws_security_group.clients.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# ---------------------------------------------------------------------------
# PostgreSQL
# ---------------------------------------------------------------------------
resource "aws_db_parameter_group" "this" {
  name        = local.name
  family      = "postgres${var.engine_version}"
  description = "Parametros do PostgreSQL ${var.environment}"

  # Conexões somente com TLS. Parâmetro estático: a AWS o registra como pending-reboot;
  # declarar o mesmo apply_method evita um diff a cada apply.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  # Registra queries lentas (análise de performance da modelagem/índices).
  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.slow_query_ms)
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }
}

# Sem caracteres que exigem escape em URLs de conexão.
resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "-_"
}

resource "aws_db_instance" "this" {
  identifier     = local.name
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = local.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period         = var.backup_retention_days
  backup_window                   = "06:00-06:30"
  maintenance_window              = "sun:07:00-sun:08:00"
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true

  # Ambiente acadêmico (Learner Lab): permite destruir entre sessões sem snapshot final.
  # Enhanced Monitoring e Performance Insights exigem role IAM/KMS indisponíveis no laboratório.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}

# ---------------------------------------------------------------------------
# Segredos consumidos pela aplicação (scripts/deploy.sh) e pelas Lambdas
# ---------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project}/${var.environment}/db"
  description             = "Conexao do PostgreSQL ${var.environment} (host, port, username, password, dbname)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    username = aws_db_instance.this.username
    password = random_password.master.result
    dbname   = aws_db_instance.this.db_name
  })
}

# Segredo de assinatura dos JWT (HS256), compartilhado entre a Lambda de
# autenticação por CPF (emite) e a API/authorizer (validam).
resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "${var.project}/${var.environment}/jwt"
  description             = "Segredo de assinatura dos tokens JWT (${var.environment})"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({ secret = random_password.jwt.result })
}
