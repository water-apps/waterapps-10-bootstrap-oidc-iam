# WaterApps AWS Bootstrap — OIDC + IAM Deploy Role + Terraform State
#
# Provisions:
#   - S3 bucket + DynamoDB table for shared Terraform remote state
#   - GitHub Actions OIDC identity provider
#   - Scoped IAM deploy role used by all WaterApps CI/CD pipelines
#
# First-run workflow (one-time local bootstrap):
#   1. terraform apply  — creates bucket, DynamoDB, OIDC provider, IAM role
#   2. Uncomment the S3 backend block below
#   3. terraform init   — migrates local state into the new S3 bucket
#   4. git push         — all future applies run via GitHub Actions pipeline
#
# Cost estimate: ~$0/month (S3 + DynamoDB at this scale are effectively free)

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Step 2: uncomment after first local apply, then run: terraform init
  # backend "s3" {
  #   bucket         = "waterapps-terraform-state"
  #   key            = "bootstrap/terraform.tfstate"
  #   region         = "ap-southeast-2"
  #   dynamodb_table = "waterapps-terraform-lock"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = var.common_tags
  }
}

locals {
  # During repo migration, allow both the legacy owner and the GitHub org.
  # Keep var.github_org as the primary source, but include water-apps for moved repos.
  github_oidc_orgs = distinct([var.github_org, "water-apps"])
}

# ─────────────────────────────────────────────
# DATA
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# TERRAFORM STATE — S3 bucket + DynamoDB lock
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project}-terraform-state"

  # Prevent accidental destroy — must empty bucket manually before removing
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "${var.project}-terraform-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ─────────────────────────────────────────────
# OIDC — GitHub Actions identity provider
# ─────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # sts.amazonaws.com is the audience GitHub Actions uses when assuming roles
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's TLS certificate thumbprints — multiple listed for resilience across cert rotations.
  # Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1", # DigiCert (legacy)
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd", # DigiCert (2023)
    "7560d6f40fa55195f740ee2b1b7c0b4836cbe103", # current
  ]
}

# ─────────────────────────────────────────────
# IAM — GitHub deploy role (one role, many repos)
# ─────────────────────────────────────────────

resource "aws_iam_role" "github_deploy" {
  name        = "${var.project}-${var.environment}-github-deploy"
  description = "Assumed by GitHub Actions via OIDC for WaterApps deployments"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          # Allow any branch/tag in authorised repos — branch restrictions
          # are enforced by GitHub environment protection rules instead.
          "token.actions.githubusercontent.com:sub" = [
            for pair in flatten([
              for org in local.github_oidc_orgs : [
                for repo in var.github_repos : "repo:${org}/${repo}:*"
              ]
            ]) : pair
          ]
        }
      }
    }]
  })
}

# Deploy permissions — least privilege for all current WaterApps Terraform repos.
# Scoped to waterapps-* resources to prevent lateral movement.
resource "aws_iam_role_policy" "deploy_permissions" {
  name = "${var.project}-${var.environment}-deploy-permissions"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── Lambda ────────────────────────────────────────────────────────────
      # Scoped to functions prefixed waterapps- to prevent touching other workloads.
      {
        Sid    = "LambdaManage"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:DeleteFunction",
          "lambda:GetFunction",
          "lambda:GetFunctionConfiguration",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:AddPermission",
          "lambda:RemovePermission",
          "lambda:ListVersionsByFunction",
          "lambda:PublishVersion",
          "lambda:TagResource",
          "lambda:UntagResource",
          "lambda:ListTags",
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project}-*"
      },

      # ── API Gateway v2 (HTTP API) ──────────────────────────────────────────
      # API Gateway v2 ARNs use /apis/* — scoped to this account and region.
      {
        Sid    = "ApiGatewayManage"
        Effect = "Allow"
        Action = [
          "apigatewayv2:CreateApi",
          "apigatewayv2:DeleteApi",
          "apigatewayv2:GetApi",
          "apigatewayv2:GetApis",
          "apigatewayv2:UpdateApi",
          "apigatewayv2:TagResource",
          "apigatewayv2:UntagResource",
          "apigatewayv2:CreateStage",
          "apigatewayv2:DeleteStage",
          "apigatewayv2:GetStage",
          "apigatewayv2:UpdateStage",
          "apigatewayv2:CreateIntegration",
          "apigatewayv2:DeleteIntegration",
          "apigatewayv2:GetIntegration",
          "apigatewayv2:UpdateIntegration",
          "apigatewayv2:CreateRoute",
          "apigatewayv2:DeleteRoute",
          "apigatewayv2:GetRoute",
          "apigatewayv2:UpdateRoute",
        ]
        Resource = "arn:aws:apigateway:${data.aws_region.current.name}::/apis/*"
      },
      # API Gateway tag operations for v2 APIs use the legacy apigateway action namespace
      # against /tags/... resources, which Terraform calls during create/update.
      {
        Sid    = "ApiGatewayTags"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:DELETE",
        ]
        Resource = "arn:aws:apigateway:${data.aws_region.current.name}::/tags/*"
      },
      # Some API Gateway v2 operations are authorized under the legacy apigateway action
      # namespace on /apis and /apis/* collection resources.
      {
        Sid    = "ApiGatewayLegacyCollection"
        Effect = "Allow"
        Action = [
          "apigateway:GET",
          "apigateway:POST",
          "apigateway:PATCH",
          "apigateway:DELETE",
        ]
        Resource = [
          "arn:aws:apigateway:${data.aws_region.current.name}::/apis",
          "arn:aws:apigateway:${data.aws_region.current.name}::/apis/*",
        ]
      },
      # GET /apis required for Terraform refresh (list operation, no resource scope)
      {
        Sid      = "ApiGatewayList"
        Effect   = "Allow"
        Action   = ["apigatewayv2:GetApis"]
        Resource = "*"
      },

      # ── CloudWatch Logs ────────────────────────────────────────────────────
      # Scoped to log groups created by WaterApps Lambda and API Gateway resources.
      {
        Sid    = "LogsLambda"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:ListTagsLogGroup",
          "logs:TagLogGroup",
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.project}-*",
        ]
      },
      # DescribeLogGroups is a list-style API and is commonly evaluated against "*".
      {
        Sid      = "LogsDescribeGroups"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = "*"
      },

      # ── IAM — Lambda execution roles ──────────────────────────────────────
      # Scoped to roles/policies prefixed waterapps-.
      # iam:PassRole restricted to Lambda service only.
      {
        Sid    = "IamRoleManage"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:TagRole",
          "iam:UntagRole",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"
      },
      {
        Sid      = "IamPassRoleLambdaOnly"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "lambda.amazonaws.com"
          }
        }
      },

      # ── SES — Email identity verification ─────────────────────────────────
      # SES identity actions do not support resource-level ARN scoping.
      # Restricted to read/verify/delete only — cannot send email.
      {
        Sid    = "SesIdentityManage"
        Effect = "Allow"
        Action = [
          "ses:VerifyEmailIdentity",
          "ses:DeleteIdentity",
          "ses:GetIdentityVerificationAttributes",
          "ses:ListIdentities",
        ]
        # SES does not support resource-level restrictions for these actions
        Resource = "*"
      },

      # ── STS — Terraform data source (aws_caller_identity) ─────────────────
      {
        Sid      = "StsCallerIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },

      # ── S3 — Terraform remote state ────────────────────────────────────────
      # Read/write state objects and manage the bucket itself (lifecycle).
      {
        Sid    = "S3StateObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.project}-terraform-state",
          "arn:aws:s3:::${var.project}-terraform-state/*",
        ]
      },
      {
        Sid    = "S3StateBucketManage"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetEncryptionConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
        ]
        Resource = "arn:aws:s3:::${var.project}-terraform-state"
      },

      # ── DynamoDB — Terraform state locking ─────────────────────────────────
      {
        Sid    = "DynamoDBStateLock"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${var.project}-terraform-lock"
      },

      # ── IAM OIDC — bootstrap manages its own OIDC provider ─────────────────
      {
        Sid    = "OidcProviderManage"
        Effect = "Allow"
        Action = [
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:GetOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
        ]
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
      },
    ]
  })
}
