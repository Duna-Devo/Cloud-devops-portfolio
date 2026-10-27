resource "aws_eks_fargate_profile" "gitops" {
  cluster_name           = aws_eks_cluster.main.name
  fargate_profile_name   = "${var.name}-gitops"
  pod_execution_role_arn = aws_iam_role.fargate.arn
  subnet_ids             = aws_subnet.private[*].id

  selector { namespace = "argocd" }
  selector { namespace = "flux-system" }

  depends_on = [aws_eks_fargate_profile.main]
}
