"""Credential-free regression tests; all file mutations use temporary fixtures."""
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SECRETS = {
    "DIGITALOCEAN_TOKEN": "DIGITALOCEAN_TOKEN",
    "AWS_ACCESS_KEY_ID": "SPACES_ACCESS_KEY_ID",
    "AWS_SECRET_ACCESS_KEY": "SPACES_SECRET_ACCESS_KEY",
}


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        # Copy source fixtures only, never provider caches, state or local config.
        sources = list((ROOT / "scripts").glob("*.sh"))
        sources += [ROOT / ".buildkite/deploy.yml", ROOT / "infra/bootstrap.sh.tftpl"]
        sources += [ROOT / "infra/backend.hcl.example", ROOT / "infra/deploy.tfvars.example"]
        for source in sources:
            target = self.root / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)

    def run_infra(self, **env):
        # Fake Terraform so a test can never reach a real provider.
        bin_dir = self.root / "bin"
        bin_dir.mkdir(exist_ok=True)
        fake = bin_dir / "terraform"
        fake.write_text(
            "#!/bin/bash\n"
            "[[ $1 == version ]] && { echo '{\"terraform_version\": \"1.16.6\"}'; exit 0; }\n"
            "echo terraform-called >&2\nexit 99\n"
        )
        fake.chmod(0o755)
        jq_dir = os.path.dirname(shutil.which("jq"))
        base = {"PATH": f"{bin_dir}:{jq_dir}:/usr/bin:/bin", "BUILDKITE_BRANCH": "main"}
        return subprocess.run(
            ["bash", "scripts/infra.sh", "plan"],
            cwd=self.root, env={**base, **env}, text=True, capture_output=True, check=False,
        )

    def all_secrets(self):
        return {name: "test-value" for name in SECRETS}

    def write_config(self, placeholder=False):
        for name in ("backend.hcl", "deploy.tfvars"):
            text = (self.root / f"infra/{name}.example").read_text()
            if not placeholder:
                text = text.replace("REPLACE", "filled")
            (self.root / f"infra/{name}").write_text(text)

    def test_deploy_steps_map_exactly_the_buildkite_secrets(self):
        content = (ROOT / ".buildkite/deploy.yml").read_text()
        blocks = re.findall(r"(?m)^    secrets:\n((?:      .+\n)+)", content)
        self.assertEqual(len(blocks), 2)
        for block in blocks:
            pairs = dict(re.findall(r'(?m)^      (\w+): "(\w+)"$', block))
            self.assertEqual(pairs, SECRETS)
        self.assertNotIn("SOPS", content)

    def test_missing_secret_stops_before_terraform(self):
        self.write_config()
        for missing in SECRETS:
            with self.subTest(missing=missing):
                env = self.all_secrets()
                del env[missing]
                result = self.run_infra(**env)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(missing, result.stdout)
                self.assertNotIn("terraform-called", result.stderr)

    def test_missing_or_placeholder_config_stops_before_terraform(self):
        result = self.run_infra(**self.all_secrets())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Missing infra/backend.hcl", result.stdout)
        self.write_config(placeholder=True)
        result = self.run_infra(**self.all_secrets())
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Replace the placeholders", result.stdout)
        self.assertNotIn("terraform-called", result.stderr)

    def test_non_main_branch_is_refused(self):
        self.write_config()
        result = self.run_infra(**self.all_secrets(), BUILDKITE_BRANCH="feature")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires main", result.stdout)

    def test_secret_values_are_not_printed(self):
        self.write_config()
        env = {name: f"sentinel-{name}" for name in SECRETS}
        result = self.run_infra(**env)
        for value in env.values():
            self.assertNotIn(value, result.stdout + result.stderr)

    def check_shell(self):
        return subprocess.run(
            ["bash", "scripts/validate.sh", "--shell-only"],
            cwd=self.root, text=True, capture_output=True, check=False,
        )

    def test_all_shell_files_pass(self):
        result = self.check_shell()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_later_script_is_detected(self):
        for relative in ("scripts/validate.sh", "infra/bootstrap.sh.tftpl"):
            with self.subTest(path=relative):
                path = self.root / relative
                original = path.read_text()
                try:
                    path.write_text(original + "\nif then\n")
                    result = self.check_shell()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(relative, result.stderr)
                finally:
                    path.write_text(original)


if __name__ == "__main__":
    unittest.main()
