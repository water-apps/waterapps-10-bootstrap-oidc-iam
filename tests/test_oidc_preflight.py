import importlib.util
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = REPO_ROOT / "scripts" / "oidc_preflight.py"


def load_module():
    spec = importlib.util.spec_from_file_location("oidc_preflight", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


class OidcPreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module()

    def test_build_subjects_deduplicates_and_preserves_order(self):
        subjects = self.mod.build_subjects(
            ["water-apps", "water-apps", "vkaushik13"],
            ["repo-a", "repo-b"],
        )
        self.assertEqual(
            subjects,
            [
                "repo:water-apps/repo-a:*",
                "repo:water-apps/repo-b:*",
                "repo:vkaushik13/repo-a:*",
                "repo:vkaushik13/repo-b:*",
            ],
        )

    def test_parse_defaults_from_variables_tf(self):
        content = textwrap.dedent(
            """
            variable "github_org" {
              type = string
              default = "water-apps"
            }

            variable "github_repos" {
              type = list(string)
              default = [
                "waterapps-10-bootstrap-oidc-iam",
                "waterapps-20-infra-enterprise",
                "waterapps-contact-form",
              ]
            }
            """
        )
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "variables.tf"
            path.write_text(content, encoding="utf-8")
            org, repos = self.mod.parse_defaults_from_variables_tf(path)
        self.assertEqual(org, "water-apps")
        self.assertEqual(
            repos,
            [
                "waterapps-10-bootstrap-oidc-iam",
                "waterapps-20-infra-enterprise",
                "waterapps-contact-form",
            ],
        )

    def test_validate_name(self):
        self.assertTrue(self.mod.validate_name("water-apps"))
        self.assertTrue(self.mod.validate_name("repo_name.test-1"))
        self.assertFalse(self.mod.validate_name("bad name"))
        self.assertFalse(self.mod.validate_name("repo/name"))


if __name__ == "__main__":
    unittest.main()

