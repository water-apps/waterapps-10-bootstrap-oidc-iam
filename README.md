# waterapps-aws-bootstrap

Terraform that provisions the GitHub Actions OIDC identity provider and the scoped IAM deploy role used by all WaterApps CI/CD pipelines.

## Repository Metadata

- Standard name: `waterapps-10-bootstrap-oidc-iam`
- Depends on: none
- Provides: GitHub OIDC provider and AWS IAM deploy role for downstream repo CI/CD
- Deploy order: `10`

## What it creates

| Resource | Name | Purpose |
|---|---|---|
| `aws_iam_openid_connect_provider` | GitHub OIDC | Lets GitHub Actions assume AWS roles without long-lived keys |
| `aws_iam_role` | `waterapps-prod-github-deploy` | Assumed by GitHub Actions workflows |
| `aws_iam_role_policy` | `waterapps-prod-deploy-permissions` | Least-privilege access for Lambda, API GW, IAM, SES, CloudWatch |

## First-time setup (chicken-and-egg)

The workflow uses OIDC to authenticate, but the OIDC role doesn't exist yet on first run. Apply locally:

```bash
aws sso login --profile your-profile   # or export AWS_* env vars
cd terraform
terraform init
terraform plan
terraform apply
```

Copy the `deploy_role_arn` output, then:

1. Go to `github.com/water-apps/waterapps-contact-form` → **Settings → Environments → production**
2. Add secret `AWS_DEPLOY_ROLE_ARN` = the ARN from above
3. Repeat for any other repos listed in `var.github_repos`

Subsequent changes to this repo can then run via GitHub Actions.

## Adding a new repo

In `terraform/variables.tf`, add the repo name to `github_repos`:

```hcl
variable "github_repos" {
  default = ["waterapps-contact-form", "waterapps-new-service"]
}
```

Then `terraform apply`. No new role needed — the trust policy updates to include the new repo.

## Structure

```
terraform/
  main.tf        # OIDC provider + IAM role + inline policy
  variables.tf   # github_org, github_repos, common_tags, etc.
  outputs.tf     # deploy_role_arn
.github/workflows/
  apply.yml      # validate on PR; plan/apply on manual dispatch
```
