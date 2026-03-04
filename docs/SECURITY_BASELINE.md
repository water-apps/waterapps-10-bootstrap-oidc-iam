# Security Baseline

Status: Draft v1  
Last updated: 2026-03-01

## Security Objectives

1. Eliminate long-lived AWS keys in CI/CD.
2. Restrict cloud deploy access to approved GitHub contexts.
3. Keep deploy permissions least-privilege.

## Baseline Controls

1. GitHub OIDC provider with constrained trust policy.
2. Dedicated deploy IAM role for CI/CD.
3. Policy-as-code changes via Terraform + PR review.
4. Environment approvals for apply paths.

## Trust Policy Rules

1. Restrict to `water-apps` organization repositories.
2. Restrict branch/ref patterns where possible.
3. Use expected audience (`sts.amazonaws.com`).

## Secrets and Credential Handling

1. No static AWS access keys for deployment.
2. Temporary credentials only via STS OIDC federation.
3. Repo secrets limited to role ARN and state config values.

## Logging and Audit

1. CloudTrail captures role assumption and IAM mutations.
2. GitHub Actions logs provide change execution trace.
3. PR history is authoritative change audit trail.

## Known Risks and Mitigations

1. Risk: overly broad IAM policy scope.
   - Mitigation: periodic policy review and narrowing.
2. Risk: trust policy drift.
   - Mitigation: Terraform as source of truth + drift checks.
3. Risk: misconfigured remote state.
   - Mitigation: enforce backend config and lock table usage.
