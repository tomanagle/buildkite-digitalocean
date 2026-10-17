#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
terraform version -json | jq -e '.terraform_version == "1.16.6"' >/dev/null
terraform -chdir=infra fmt -check
terraform -chdir=infra init -backend=false -input=false
terraform -chdir=infra validate
bash -n scripts/infra.sh scripts/validate.sh scripts/setup.sh
# Bootstrap template contains only Terraform substitutions, no shell ${...}.
bash -n infra/bootstrap.sh.tftpl
echo "Static checks passed; this does not verify real provisioning."
