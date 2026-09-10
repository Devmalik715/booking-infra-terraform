locals {
  name = "${var.project}-${var.environment}"

  major_version   = split(".", var.engine_version)[0]
  parameter_group = "postgres${local.major_version}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name}-db"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${local.name}-db" })
}

resource "aws_security_group" "this" {
  name        = "${local.name}-rds"
  description = "Postgres access for the application tasks only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, { Name = "${local.name}-rds" })
}

resource "aws_vpc_security_group_ingress_rule" "from_clients" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "Postgres from an approved client security group"
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.name}-pg"
  family      = local.parameter_group
  description = "Logging and connection defaults for ${local.name}"

  parameter {
    name  = "log_min_duration_statement"
    value = tostring(var.log_min_duration_statement)
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.master_username
  port     = var.port

  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az                   = var.multi_az
  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  performance_insights_enabled = var.performance_insights_enabled
  monitoring_interval          = var.monitoring_interval
  monitoring_role_arn          = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]

  tags = merge(var.tags, { Name = "${local.name}-postgres" })

  lifecycle {
    # the snapshot name embeds a timestamp; it must not force a replacement
    ignore_changes = [final_snapshot_identifier, performance_insights_kms_key_id]
  }
}

data "aws_iam_policy_document" "monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
