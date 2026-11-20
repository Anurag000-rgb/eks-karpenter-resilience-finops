resource "aws_rds_cluster" "prod" {
  count = var.enable_databases ? 1 : 0

  cluster_identifier          = "${local.cluster_name}-prod"
  engine                      = "aurora-postgresql"
  engine_version              = "16.15"
  database_name               = "checkout"
  master_username             = "labadmin"
  manage_master_user_password = true
  storage_encrypted           = true

  db_subnet_group_name   = aws_db_subnet_group.lab[0].name
  vpc_security_group_ids = [aws_security_group.database[0].id]
  availability_zones     = local.database_zones

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
}

resource "aws_rds_cluster_instance" "prod_writer" {
  count = var.enable_databases ? 1 : 0

  identifier           = "${local.cluster_name}-prod-a"
  cluster_identifier   = aws_rds_cluster.prod[0].id
  engine               = aws_rds_cluster.prod[0].engine
  engine_version       = aws_rds_cluster.prod[0].engine_version
  instance_class       = "db.t4g.medium"
  availability_zone    = local.zones[0]
  db_subnet_group_name = aws_db_subnet_group.lab[0].name
  publicly_accessible  = false
}

resource "aws_rds_cluster_instance" "prod_reader" {
  count = var.enable_databases ? 1 : 0

  identifier           = "${local.cluster_name}-prod-b"
  cluster_identifier   = aws_rds_cluster.prod[0].id
  engine               = aws_rds_cluster.prod[0].engine
  engine_version       = aws_rds_cluster.prod[0].engine_version
  instance_class       = "db.t4g.medium"
  availability_zone    = local.zones[1]
  db_subnet_group_name = aws_db_subnet_group.lab[0].name
  publicly_accessible  = false
  promotion_tier       = 0

  # Aurora makes the first instance the initial writer.
  depends_on = [aws_rds_cluster_instance.prod_writer]
}
