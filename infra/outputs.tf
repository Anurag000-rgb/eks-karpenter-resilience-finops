output "cluster_name" {
  value = module.eks.cluster_name
}

output "karpenter_interruption_queue" {
  value = module.karpenter.queue_name
}

output "karpenter_controller_role_arn" {
  value = module.karpenter.iam_role_arn
}

output "database_endpoints" {
  value = var.enable_databases ? {
    prod_writer = aws_rds_cluster.prod[0].endpoint
    prod_reader = aws_rds_cluster.prod[0].reader_endpoint
    dev         = aws_db_instance.dev[0].address
  } : null
}
