resource "aws_db_subnet_group" "lab" {
  count = var.enable_databases ? 1 : 0

  name       = local.cluster_name
  subnet_ids = module.vpc.database_subnets
}

resource "aws_security_group" "database" {
  count = var.enable_databases ? 1 : 0

  name_prefix = "${local.cluster_name}-db-"
  description = "PostgreSQL access from the EKS worker security group"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "database_from_workers" {
  count = var.enable_databases ? 1 : 0

  security_group_id            = aws_security_group.database[0].id
  referenced_security_group_id = module.eks.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
