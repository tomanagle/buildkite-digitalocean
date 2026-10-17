#!/bin/bash
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
mode=${1:-}
[[ "$mode" == plan || "$mode" == apply ]] || { echo "Usage: infra.sh plan|apply"; exit 1; }
[[ "${BUILDKITE_BRANCH:-}" == main && "${BUILDKITE_PULL_REQUEST:-false}" == false ]] || {
  echo "Deployment requires main and no pull request"; exit 1;
}
# The ciphertext is checked in; the age identity comes only from Buildkite Secrets.
: "${SOPS_AGE_KEY:?}"
umask 077
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
sops --decrypt --output-type json secrets/deploy.enc.json > "$tmp/secrets.json"
export DIGITALOCEAN_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
DIGITALOCEAN_TOKEN=$(jq -er '.digitalocean_token | select(type == "string" and length > 0)' "$tmp/secrets.json")
AWS_ACCESS_KEY_ID=$(jq -er '.spaces_access_key_id | select(type == "string" and length > 0)' "$tmp/secrets.json")
AWS_SECRET_ACCESS_KEY=$(jq -er '.spaces_secret_access_key | select(type == "string" and length > 0)' "$tmp/secrets.json")
TF_BACKEND_CONFIG=$(jq -er '.backend_hcl | select(type == "string" and length > 0)' "$tmp/secrets.json")
TF_DEPLOY_CONFIG=$(jq -er '.terraform_tfvars | select(type == "string" and length > 0)' "$tmp/secrets.json")
rm -f -- "$tmp/secrets.json"
unset SOPS_AGE_KEY
: "${DIGITALOCEAN_TOKEN:?}"
: "${AWS_ACCESS_KEY_ID:?}"
: "${AWS_SECRET_ACCESS_KEY:?}"
: "${TF_BACKEND_CONFIG:?}"
: "${TF_DEPLOY_CONFIG:?}"
terraform version -json | jq -e '.terraform_version == "1.16.6"' >/dev/null
printf '%s\n' "$TF_BACKEND_CONFIG" > "$tmp/backend.hcl"
printf '%s\n' "$TF_DEPLOY_CONFIG" > "$tmp/deploy.tfvars"
unset TF_BACKEND_CONFIG TF_DEPLOY_CONFIG
export TF_IN_AUTOMATION=1 TF_INPUT=0
[[ -f infra/.terraform.lock.hcl ]] || { echo "Generate and commit the provider lockfile before deployment."; exit 1; }
terraform -chdir=infra init -lockfile=readonly -reconfigure -backend-config="$tmp/backend.hcl"
terraform -chdir=infra validate
terraform -chdir=infra plan -lock-timeout=5m -var-file="$tmp/deploy.tfvars" -out="$tmp/change.tfplan"
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
