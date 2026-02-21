# WaterApps AWS Bootstrap — OIDC + IAM Deploy Role
#
# Provisions the GitHub Actions OIDC identity provider and the scoped
# IAM role used by all WaterApps CI/CD pipelines to deploy to AWS.
#
# First-run: apply locally with AWS credentials (aws sso login / env vars).
# Subsequent runs: use the output role ARN via GitHub OIDC — no long-lived keys.
#
# Cost estimate: $0/month — IAM and OIDC resources are free.

terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment for remote state (recommended after first apply)
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

# ─────────────────────────────────────────────
# DATA
# ─────────────────────────────────────────────

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# OIDC — GitHub Actions identity provider
# ─────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  # sts.amazonaws.com is the audience GitHub Actions uses when assuming roles
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's TLS certificate thumbprint — stable across GitHub's CDN
  # Source: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
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
            for repo in var.github_repos :
            "repo:${var.github_org}/${repo}:*"
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
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:ListTagsLogGroup",
          "logs:TagLogGroup",
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-*",
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.project}-*",
        ]
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
        Sid    = "IamPassRoleLambdaOnly"
        Effect = "Allow"
        Action = ["iam:PassRole"]
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
    ]
  })
}
