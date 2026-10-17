"""Credential-free regression tests; all file mutations use temporary fixtures."""
import json
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = pathlib.Path(self.tmp.name)
        for directory in ("scripts", ".buildkite", "infra"):
            shutil.copytree(ROOT / directory, self.root / directory)

    def setup_name(self, name):
        return subprocess.run(
            ["bash", "scripts/setup.sh"],
            cwd=self.root,
            input=name + "\n",
            text=True,
            capture_output=True,
            check=False,
        )

    def mappings(self):
        content = (self.root / ".buildkite/deploy.yml").read_text()
        scalars = re.findall(r"(?m)^      SOPS_AGE_KEY: (.+)$", content)
        self.assertEqual(len(scalars), 2)
        # Require JSON-encoded strings, which are valid YAML quoted scalars.
        values = [json.loads(scalar) for scalar in scalars]
        self.assertTrue(all(type(value) is str for value in values))
        return values

    def test_yaml_ambiguous_names_and_repeated_setup(self):
        for name in ("123", "true", "null", "false", "001", "CUSTOM_KEY"):
            with self.subTest(name=name):
                result = self.setup_name(name)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.mappings(), [name, name])

    def test_default_and_single_quoted_existing_mappings(self):
        path = self.root / ".buildkite/deploy.yml"
        path.write_text(re.sub(
            r'(?m)^(      SOPS_AGE_KEY: ).+$',
            lambda match: match[1] + "'OLD_KEY'",
            path.read_text(),
        ))
        result = self.setup_name("")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.mappings(), ["DIGITALOCEAN_BUILDKITE_SOPS_AGE_KEY"] * 2)

    def test_invalid_names_leave_file_unchanged(self):
        path = self.root / ".buildkite/deploy.yml"
        for name in ("buildkite_key", "BK_token", "bad-name", "x" * 256):
            with self.subTest(name=name):
                before = path.read_bytes()
                self.assertNotEqual(self.setup_name(name).returncode, 0)
                self.assertEqual(path.read_bytes(), before)

    def test_wrong_mapping_count_leaves_file_unchanged(self):
        path = self.root / ".buildkite/deploy.yml"
        path.write_text(path.read_text().replace("SOPS_AGE_KEY:", "OTHER_KEY:", 1))
        before = path.read_bytes()
        self.assertNotEqual(self.setup_name("VALID").returncode, 0)
        self.assertEqual(path.read_bytes(), before)

    def check_shell(self):
        return subprocess.run(
            ["bash", "scripts/validate.sh", "--shell-only"],
            cwd=self.root, text=True, capture_output=True, check=False,
        )

    def test_all_shell_files_pass(self):
        result = self.check_shell()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_later_script_is_detected(self):
        for relative in ("scripts/setup.sh", "infra/bootstrap.sh.tftpl"):
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
