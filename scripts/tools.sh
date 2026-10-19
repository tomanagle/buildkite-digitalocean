#!/bin/bash
# Sourced by infra.sh. Installs pinned, checksum-verified jq and Terraform into a
# job-local directory when they're missing, so deploy jobs can run on Buildkite
# hosted agents. Agents that already have the right versions skip the downloads.
terraform_version=1.16.6
terraform_sha256=38034b38d03096399a7a1264a14561a8029b2b496fd1f169452656e53968f1b7
jq_version=1.8.2
jq_sha256=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f

linux_amd64_only() {
  [[ "$(uname -sm)" == "Linux x86_64" ]] || { echo "Install $1 yourself on this platform."; return 1; }
}

ensure_tools() {
  local bin=$1
  mkdir -p "$bin"
  export PATH="$bin:$PATH"
  if ! command -v jq >/dev/null; then
    linux_amd64_only "jq $jq_version" || return 1
    curl -fsSL -o "$bin/jq" "https://github.com/jqlang/jq/releases/download/jq-$jq_version/jq-linux-amd64" || return 1
    echo "$jq_sha256  $bin/jq" | sha256sum -c --quiet - || { echo "Checksum mismatch for a downloaded tool."; return 1; }
    chmod 0755 "$bin/jq"
  fi
  if ! terraform version -json 2>/dev/null | jq -e --arg v "$terraform_version" '.terraform_version == $v' >/dev/null; then
    linux_amd64_only "Terraform $terraform_version" || return 1
    curl -fsSL -o "$bin/terraform.zip" \
      "https://releases.hashicorp.com/terraform/$terraform_version/terraform_${terraform_version}_linux_amd64.zip" || return 1
    echo "$terraform_sha256  $bin/terraform.zip" | sha256sum -c --quiet - || { echo "Checksum mismatch for a downloaded tool."; return 1; }
    if command -v unzip >/dev/null; then
      unzip -q -o "$bin/terraform.zip" terraform -d "$bin"
    elif command -v python3 >/dev/null; then
      python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extract("terraform", sys.argv[2])' "$bin/terraform.zip" "$bin"
    else
      echo "Need unzip or python3 to unpack Terraform."; return 1
    fi
    chmod 0755 "$bin/terraform"
    rm -f -- "$bin/terraform.zip"
  fi
  terraform version -json | jq -e --arg v "$terraform_version" '.terraform_version == $v' >/dev/null
}
