locals {
  environment = "prod"

  tags = {
    Project     = var.project
    Environment = local.environment
    ManagedBy   = "terraform"
    Owner       = var.owner
  }
}

module "network" {
  source = "../../modules/network"

  project     = var.project
  environment = local.environment
  vpc_cidr    = var.vpc_cidr
  azs         = var.azs

  single_nat_gateway = false

  tags = local.tags
}

module "ecs" {
  source = "../../modules/ecs"

  project     = var.project
  environment = local.environment
  aws_region  = var.aws_region

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids

  container_image = var.container_image
  container_port  = var.container_port
  task_cpu        = var.task_cpu
  task_memory     = var.task_memory
  desired_count   = var.desired_count

  log_retention_days         = var.log_retention_days
  enable_deletion_protection = true
  enable_container_insights  = true

  container_environment = {
    APP_ENV = local.environment
    DB_HOST = module.rds.address
    DB_PORT = tostring(module.rds.port)
    DB_NAME = module.rds.db_name
  }

  container_secrets = {
    DB_USER     = "${module.rds.master_user_secret_arn}:username::"
    DB_PASSWORD = "${module.rds.master_user_secret_arn}:password::"
  }

  tags = local.tags
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = local.environment

  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids

  allowed_security_group_ids = [module.ecs.tasks_security_group_id]

  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  db_name               = var.db_name

  multi_az                = true
  backup_retention_period = var.db_backup_retention_period
  deletion_protection     = true
  skip_final_snapshot     = false

  apply_immediately = false

  performance_insights_enabled = true
  monitoring_interval          = 30

  tags = local.tags
}
