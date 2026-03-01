output "deploy_role_arn" {
  description = "Set this as AWS_DEPLOY_ROLE_ARN in each repo's GitHub environment secrets"
  value       = aws_iam_role.github_deploy.arn
}

output "oidc_provider_arn" {
  description = "GitHub OIDC provider ARN — reuse this if adding more roles later"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "state_bucket" {
  description = "S3 bucket name for Terraform remote state — use in each repo's backend config"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_lock_table" {
  description = "DynamoDB table name for Terraform state locking"
  value       = aws_dynamodb_table.terraform_lock.name
}

output "github_oidc_trusted_subjects" {
  description = "OIDC subject patterns allowed to assume the GitHub deploy role (repo/org trust list)"
  value       = local.github_oidc_subjects
}
