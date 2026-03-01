# Learnings - 2026-03-01

## Context

Bootstrap `workflow_dispatch` apply was failing while reconciling existing AWS resources into Terraform remote state. Failures surfaced in sequence as missing read/metadata IAM permissions required by provider import/refresh behavior.

## What Happened

1. Bootstrap apply failed on missing `s3:GetBucketPolicy`.
2. After fix, apply failed on missing `s3:GetBucketAcl`.
3. After S3 expansion, apply failed on missing `dynamodb:DescribeContinuousBackups`.
4. After policy updates and one controlled rerun, apply completed successfully and state reconciliation finished.

## Root Cause

- IAM policy for bootstrap role was least-privilege for planned writes, but not broad enough for provider read-side metadata calls during `terraform import` and refresh against pre-existing resources.
- Existing state resources (S3 bucket, DynamoDB lock table, OIDC provider, role, inline policy) required import before first managed apply.

## Fixes Applied

- Updated S3 state bucket management actions to include:
  - `s3:GetBucket*`
  - `s3:PutBucket*`
  - `s3:DeleteBucketPolicy`
- Updated DynamoDB lock table actions to include:
  - `dynamodb:Describe*`
- Kept resource scope restricted to state bucket and lock table.
- Completed successful bootstrap apply run and validated live trust/permissions.

## Security Outcomes

- OIDC trust policy is restricted to explicit repo subjects for:
  - `refs/heads/main`
  - `refs/tags/*`
  - `environment:production`
- PR paths are blocked from direct deploy-role credential flow.
- Temporary break-glass policies used during remediation were removed after successful apply.

## Process Learnings

1. First reconciliation against existing infra should be treated as a migration event, not a routine apply.
2. Import/reconcile runbooks should include expected metadata permissions up front.
3. Keep fixes small and merge quickly to preserve clean RCA.
4. Always remove temporary elevation immediately after permanent policy converge.

## Permanent Improvements

- Keep a reusable bootstrap reconciliation runbook in this repo.
- Run OIDC preflight and policy checks on every PR.
- Require environment approval for all applies.
- Keep apply restricted to `main` only.
