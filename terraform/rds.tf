# ─────────────────────────────────────────────
# RDS Subnet Group
# ─────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
  }
}

# ─────────────────────────────────────────────
# RDS Parameter Group
# ─────────────────────────────────────────────
resource "aws_db_parameter_group" "mysql" {
  name   = "${var.project_name}-${var.environment}-mysql8-params"
  family = "mysql8.0"

  parameter {
    name  = "general_log"
    value = "0"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  parameter {
    name  = "log_output"
    value = "FILE"
  }

  parameter {
    name         = "require_secure_transport"
    value        = "ON"
    apply_method = "immediate"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-mysql-params"
  }
}

# ─────────────────────────────────────────────
# RDS MySQL Instance
# ─────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-mysql"

  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = var.db_instance_class
  allocated_storage    = var.db_allocated_storage
  max_allocated_storage = 100 # Auto-scaling up to 100 GB
  storage_type         = "gp3"
  storage_encrypted    = true
  kms_key_id           = aws_kms_key.main.arn

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  parameter_group_name   = aws_db_parameter_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = var.db_multi_az
  publicly_accessible    = false
  deletion_protection    = var.db_deletion_protection

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  # Send logs to CloudWatch
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # Performance Insights
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  performance_insights_kms_key_id       = aws_kms_key.main.arn

  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project_name}-${var.environment}-mysql-final"

  tags = {
    Name = "${var.project_name}-${var.environment}-rds"
  }
}

# ─────────────────────────────────────────────
# Random password for RDS
# ─────────────────────────────────────────────
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# ─────────────────────────────────────────────
# AWS Secrets Manager – DB credentials
# ─────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "MySQL credentials for ${var.project_name} ${var.environment}"
  kms_key_id              = aws_kms_key.main.arn
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-${var.environment}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = var.db_name
    engine   = "mysql"
  })
}
