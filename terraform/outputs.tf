output "deploy_role_arn" {
  description = "Set this as AWS_DEPLOY_ROLE_ARN in each repo's GitHub environment secrets"
  value       = aws_iam_role.github_deploy.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN — reuse this if adding more roles later"
  value       = aws_iam_openid_connect_provider.github.arn
}
