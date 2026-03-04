# Architecture

Status: Draft v1  
Last updated: 2026-03-01

## Purpose

`waterapps-10-bootstrap-oidc-iam` bootstraps AWS OIDC trust for GitHub Actions and creates a scoped deploy IAM role for downstream WaterApps repos.

## System Context

1. GitHub Actions workflows request OIDC tokens.
2. AWS IAM OIDC provider validates token issuer/audience.
3. IAM deploy role trust policy limits allowed GitHub org/repo/branch contexts.
4. STS issues temporary credentials to workflow jobs.

## Core Components

1. `aws_iam_openid_connect_provider` for GitHub Actions.
2. Deploy role (`waterapps-prod-github-deploy` pattern).
3. Inline or attached deploy policy (least-privilege service actions).
4. GitHub workflow (`.github/workflows/apply.yml`) for validate/plan/apply path.

## Data/Control Flow

1. Workflow starts in GitHub.
2. OIDC token exchanged with AWS STS.
3. Assume role produces temporary credentials.
4. Terraform applies or validates bootstrap resources.
5. Role ARN is consumed by downstream repos.

## Dependencies

1. AWS account permissions for bootstrap apply.
2. Terraform CLI + provider configuration.
3. GitHub repo/environment configuration for secrets/vars.

## Key Risks

1. Overly broad trust policy could allow unauthorized repo assumption.
2. Overly broad deploy policy could create privilege escalation risk.
3. Local-state drift if remote state is not used.

## Mitigations

1. Restrict trust conditions to approved repo/branch patterns.
2. Review deploy policy scope via PR.
3. Use remote state with locking for team workflows.
