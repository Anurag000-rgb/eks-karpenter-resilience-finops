locals {
  cluster_name   = "ca2-resilience"
  zones          = ["us-east-1a", "us-east-1b"]
  database_zones = concat(local.zones, ["us-east-1c"])
  discovery      = { "karpenter.sh/discovery" = local.cluster_name }
}
