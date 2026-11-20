resource "aws_db_instance" "dev" {
  count = var.enable_databases ? 1 : 0

  identifier                  = "${local.cluster_name}-dev"
  engine                      = "postgres"
  engine_version              = "16.15"
  instance_class              = "db.t4g.medium"
  db_name                     = "devlab"
  username                    = "labadmin"
  manage_master_user_password = true

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  multi_az               = false
  availability_zone      = local.zones[0]
  db_subnet_group_name   = aws_db_subnet_group.lab[0].name
  vpc_security_group_ids = [aws_security_group.database[0].id]
  publicly_accessible    = false

  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false
}
