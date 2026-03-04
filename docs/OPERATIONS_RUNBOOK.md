# Operations Runbook

Status: Draft v1  
Last updated: 2026-03-01

## Purpose

Operate and troubleshoot bootstrap OIDC/IAM role infrastructure used by WaterApps CI/CD.

## Health Checks

1. Confirm OIDC provider exists in IAM.
2. Confirm deploy role exists and trust policy contains expected repo conditions.
3. Verify downstream workflow can assume role.

## Common Failures and Actions

1. `AccessDenied: AssumeRoleWithWebIdentity`
   - Check trust policy conditions (`sub`, `aud`, org/repo/branch filters).
   - Confirm workflow token permissions include `id-token: write`.

2. Terraform state lock or state not found
   - Verify backend bucket/key and lock table settings.
   - Check lock entry and clear only when safe.

3. CI apply blocked due to missing vars/secrets
   - Validate repo-level secrets and variables are configured.

## Change Windows

1. Apply trust/policy changes in controlled windows.
2. Validate at least one downstream repo immediately after apply.

## Escalation

1. `P1` deploy-wide auth failures: CTO + DevOps owner.
2. `P2` single repo trust issue: repo owner + platform maintainer.

## Recovery Steps

1. Identify last known good commit.
2. Revert if required.
3. Apply reverted config.
4. Re-test OIDC flow in downstream repo.
5. Record incident and fix-forward actions.
