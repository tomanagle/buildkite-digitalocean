#!/bin/bash
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
mode=${1:-}
[[ "$mode" == plan || "$mode" == apply ]] || { echo "Usage: infra.sh plan|apply"; exit 1; }
[[ "${BUILDKITE_BRANCH:-}" == main && "${BUILDKITE_PULL_REQUEST:-false}" == false ]] || {
  echo "Deployment requires main and no pull request"; exit 1;
}
# Credentials come only from Buildkite Secrets, mapped in .buildkite/deploy.yml.
for name in DIGITALOCEAN_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY; do
  [[ -n "${!name:-}" ]] || { echo "Missing $name. Check the Buildkite Secrets mapped in .buildkite/deploy.yml."; exit 1; }
done
for config in infra/backend.hcl infra/deploy.tfvars; do
  [[ -f "$config" ]] || { echo "Missing $config. Copy it from $config.example and commit it."; exit 1; }
  ! grep -q REPLACE "$config" || { echo "Replace the placeholders in $config."; exit 1; }
done
umask 077
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
source scripts/tools.sh
ensure_tools "$tmp/bin"
export TF_IN_AUTOMATION=1 TF_INPUT=0
[[ -f infra/.terraform.lock.hcl ]] || { echo "Generate and commit the provider lockfile before deployment."; exit 1; }
terraform -chdir=infra init -lockfile=readonly -reconfigure -backend-config=backend.hcl
terraform -chdir=infra validate
terraform -chdir=infra plan -lock-timeout=5m -var-file=deploy.tfvars -out="$tmp/change.tfplan"
# Compare all machine-readable plan content except its creation timestamp.
# Any drift or nondeterminism fails closed: start a new reviewed build.
digest=$(terraform -chdir=infra show -json "$tmp/change.tfplan" | jq -Sc 'del(.timestamp)' | sha256sum | cut -d' ' -f1)
if [[ "$mode" == plan ]]; then
  existing=$(buildkite-agent meta-data get terraform-reviewed-plan-sha256 --default not-recorded)
  [[ "$existing" == not-recorded ]] || { echo "A preview already exists in this build. Start a new build for fresh approval."; exit 1; }
  buildkite-agent meta-data set terraform-reviewed-plan-sha256 "$digest"
else
  reviewed=$(buildkite-agent meta-data get terraform-reviewed-plan-sha256)
  [[ "$digest" == "$reviewed" ]] || { echo "Plan changed since review. Cancel and start a new plan/approval build."; exit 1; }
  # Refuse delete/replacement during the routine deployment flow.
  terraform -chdir=infra show -json "$tmp/change.tfplan" |
    jq -e '[.resource_changes[]? | .change.actions[] | select(. == "delete")] | length == 0' >/dev/null || {
      echo "Deletion/replacement refused. Use the documented explicit maintenance process."; exit 1;
    }
  terraform -chdir=infra apply -lock-timeout=5m "$tmp/change.tfplan"
fi
