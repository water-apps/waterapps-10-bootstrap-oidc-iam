# Deployment Guide

Status: Draft v1  
Last updated: 2026-03-01

## Prerequisites

1. AWS credentials with IAM/OIDC role creation rights.
2. Terraform installed.
3. Access to target AWS account and GitHub org.

## First-Time Bootstrap (local apply)

Use local credentials for first bootstrap because OIDC trust does not exist yet:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

## Post-Bootstrap GitOps Flow

1. Configure remote state (S3 + DynamoDB lock table).
2. Set required GitHub secret/vars:
   - `AWS_DEPLOY_ROLE_ARN`
   - remote state bucket/key/lock variables
3. Use workflow dispatch path with environment approval for apply.

## Change Process

1. Open PR for policy/trust changes.
2. Validate in CI.
3. Merge after review.
4. Run approved apply.

## Rollback

1. Revert offending commit.
2. Re-run plan to confirm expected rollback.
3. Apply with approval.
4. Validate role assumption in one downstream repo.

## Evidence Checklist

1. PR URL.
2. Plan output (artifact/log).
3. Apply run URL.
4. Downstream repo OIDC assume-role success proof.
