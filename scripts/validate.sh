#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  ""|--shell-only) ;;
  *) echo "Usage: validate.sh [--shell-only]"; exit 1 ;;
esac
# bash -n accepts one script; additional filenames would only be its arguments.
for script in scripts/*.sh infra/bootstrap.sh.tftpl; do
  bash -n "$script"
done
if [[ "${1:-}" == --shell-only ]]; then
  echo "All shell files passed syntax checks."
  exit 0
fi
python3 -B -m unittest discover -s tests -v
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
source scripts/tools.sh
ensure_tools "$tmp/bin"
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
echo "Static checks passed; this does not verify real provisioning."
