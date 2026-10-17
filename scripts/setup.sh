#!/bin/bash
# Configure the Buildkite secret NAME only. Never paste a secret value here.
set -euo pipefail
cd "$(dirname "$0")/.."
default=DIGITALOCEAN_BUILDKITE_SOPS_AGE_KEY
read -r -p "Buildkite secret name for the SOPS age identity [$default]: " name
name=${name:-$default}
[[ "$name" =~ ^[A-Za-z0-9_]{1,255}$ ]] || { echo "Use 1-255 letters, digits or underscores."; exit 1; }
case "${name,,}" in
  buildkite*|bk*) echo "Buildkite reserves names beginning buildkite or bk."; exit 1 ;;
esac
python3 - "$name" <<'PY'
import json, pathlib, re, sys
p = pathlib.Path(".buildkite/deploy.yml")
text = p.read_text()
# JSON string encoding is also valid YAML double-quoted scalar syntax.
# Match only our restricted unquoted or quoted secret-name values.
pattern = r"""(?m)^(      SOPS_AGE_KEY: )(?:[A-Za-z0-9_]+|"[A-Za-z0-9_]+"|'[A-Za-z0-9_]+')$"""
text, count = re.subn(pattern, lambda m: m[1] + json.dumps(sys.argv[1]), text)
if count != 2:
    raise SystemExit("Expected two secret mappings; no changes written.")
p.write_text(text)
PY
echo "Saved the secret name in .buildkite/deploy.yml. Review the diff."
echo "Create its value separately in Buildkite Secrets. No credentials were requested or saved."
