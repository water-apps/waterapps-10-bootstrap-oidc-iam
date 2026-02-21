# Changelog

All notable changes to this project will be documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] — 2026-02-21

### Added
- GitHub Actions OIDC identity provider (`aws_iam_openid_connect_provider`)
- Scoped IAM deploy role for GitHub Actions OIDC federation
- Least-privilege inline policy covering Lambda, API Gateway v2, CloudWatch Logs, IAM, SES
- Variables for `github_org` and `github_repos` list (add repos without a new role)
- GitHub Actions workflow: validate on PR, manual plan/apply on dispatch
- Outputs `deploy_role_arn` for pasting into GitHub environment secrets
