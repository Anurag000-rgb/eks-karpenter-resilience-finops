module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = local.cluster_name
  cidr = "10.42.0.0/16"
  azs  = local.database_zones

  # Short-lived lab workers use public IPv4 egress without a NAT gateway.
  public_subnets          = ["10.42.0.0/24", "10.42.1.0/24"]
  map_public_ip_on_launch = true
  public_subnet_tags      = local.discovery
  public_subnet_tags_per_az = {
    (local.zones[0]) = { ca2-zone = local.zones[0] }
  }

  # Reserve isolated subnets for the EKS control plane network interfaces.
  intra_subnets = ["10.42.10.0/24", "10.42.11.0/24"]

  database_subnets             = var.enable_databases ? ["10.42.20.0/24", "10.42.21.0/24", "10.42.22.0/24"] : []
  create_database_subnet_group = false
}
