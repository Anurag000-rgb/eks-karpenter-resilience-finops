data "aws_iam_policy_document" "karpenter_irsa" {
  statement {
    # Match the module's trust statement SID so this override replaces it.
    sid     = "PodIdentity"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.eks.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.29.0"

  cluster_name                    = module.eks.cluster_name
  namespace                       = "kube-system"
  service_account                 = "karpenter"
  create_pod_identity_association = false
  enable_spot_termination         = true

  iam_role_override_assume_policy_documents = [data.aws_iam_policy_document.karpenter_irsa.json]

  node_iam_role_name            = "${local.cluster_name}-karpenter-node"
  node_iam_role_use_name_prefix = false
}
