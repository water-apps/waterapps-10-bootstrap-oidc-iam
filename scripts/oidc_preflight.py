#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path
from typing import List, Tuple


ORG_DEFAULT_RE = re.compile(
    r'variable\s+"github_org"\s*{.*?default\s*=\s*"([^"]+)"',
    re.DOTALL,
)
REPOS_DEFAULT_RE = re.compile(
    r'variable\s+"github_repos"\s*{.*?default\s*=\s*\[(.*?)\]',
    re.DOTALL,
)
QUOTED_STRING_RE = re.compile(r'"([^"]+)"')


def parse_defaults_from_variables_tf(path: Path) -> Tuple[str, List[str]]:
    text = path.read_text(encoding="utf-8")

    org_match = ORG_DEFAULT_RE.search(text)
    if not org_match:
        raise ValueError("Could not parse github_org default from variables.tf")
    github_org = org_match.group(1).strip()

    repos_match = REPOS_DEFAULT_RE.search(text)
    if not repos_match:
        raise ValueError("Could not parse github_repos default list from variables.tf")
    repos_block = repos_match.group(1)
    github_repos = [m.group(1).strip() for m in QUOTED_STRING_RE.finditer(repos_block)]
    if not github_repos:
        raise ValueError("Parsed github_repos list is empty")

    return github_org, github_repos


def build_subjects(orgs: List[str], repos: List[str]) -> List[str]:
    out: List[str] = []
    seen = set()
    for org in orgs:
        for repo in repos:
            subj = f"repo:{org}/{repo}:*"
            if subj not in seen:
                seen.add(subj)
                out.append(subj)
    return out


def validate_name(name: str) -> bool:
    return bool(re.fullmatch(r"[A-Za-z0-9_.-]+", name))


def cmd_check(args: argparse.Namespace) -> int:
    variables_file = Path(args.variables_file)
    github_org, github_repos = parse_defaults_from_variables_tf(variables_file)

    orgs = [github_org] + list(args.extra_org or [])

    errors: List[str] = []
    if not validate_name(github_org):
        errors.append(f"invalid github_org default: {github_org}")
    for org in orgs:
        if not validate_name(org):
            errors.append(f"invalid org name: {org}")
    for repo in github_repos:
        if not validate_name(repo):
            errors.append(f"invalid repo name in github_repos: {repo}")

    for req in args.require_repo or []:
        if req not in github_repos:
            errors.append(f"missing required repo in github_repos default: {req}")

    if args.require_org and github_org != args.require_org:
        errors.append(f"github_org default must be '{args.require_org}' (found '{github_org}')")

    subjects = build_subjects(orgs, github_repos)

    result = {
        "github_org": github_org,
        "github_repos": github_repos,
        "effective_orgs": orgs,
        "oidc_subjects": subjects,
    }
    print(json.dumps(result, indent=2))

    if errors:
        for err in errors:
            print(f"[ERROR] {err}", file=sys.stderr)
        return 1

    print("\n[INFO] OIDC preflight checks passed.", file=sys.stderr)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="OIDC preflight checks for WaterApps bootstrap Terraform config")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_check = sub.add_parser("check", help="Validate github_org/github_repos defaults and print OIDC subject patterns")
    p_check.add_argument("--variables-file", default="terraform/variables.tf")
    p_check.add_argument("--require-org", default="water-apps")
    p_check.add_argument("--extra-org", action="append", help="Additional allowed org(s) to include in preflight subject generation")
    p_check.add_argument("--require-repo", action="append", help="Repo that must exist in github_repos default (repeatable)")
    p_check.set_defaults(func=cmd_check)

    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

