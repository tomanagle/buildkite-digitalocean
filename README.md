# buildkite-digitalocean

A small Buildkite-only starter for one long-lived DigitalOcean Droplet running a single Buildkite worker with Git, Docker Engine and Docker Compose. Project language/toolchain dependencies run in containers; the host is generic.

> **Review draft:** source has been reviewed but not executed in a shell or deployed. Terraform formatting, provider initialization, cloud-init installation, secret policies, state locking, agent registration and reboot/drain behavior still need validation. Nothing in this repository has provisioned infrastructure. Do not treat it as production-ready.

## Architecture and trust

Use two pipelines: credential-free validation on an isolated queue, and a manual deployment pipeline on a **pre-existing trusted provisioning queue** (self-hosted or Buildkite hosted). The Droplet being created cannot bootstrap itself. Never run its own provisioning/teardown jobs on it.

Docker-group membership grants root-equivalent host access. Persistent build workspaces, containers and credentials are not isolated between hostile jobs. Only trusted repositories/builds belong on this agent. Never run untrusted PRs on the provisioning queue or a persistent agent holding secrets. A queue tag is routing, not a security boundary: configure cluster/queue access and Buildkite secret access policies outside repository YAML to restrict the deployment pipeline, trusted branch and permitted agents. Disable deployment push/PR triggers and restrict who can change/unblock it. An approval block does not protect a key already accessible to an attacker.

## Costs and prerequisites

A Droplet accrues charges while retained, including while powered off; Spaces, snapshots, bandwidth and Buildkite hosted execution can add costs. Review current [Droplet pricing](https://www.digitalocean.com/pricing/droplets), [Spaces pricing](https://www.digitalocean.com/pricing/spaces-object-storage) and your Buildkite plan before approving deployment. The configurable default is **s-1vcpu-512mb-10gb in NYC1**: Basic Regular/shared CPU, 1 vCPU, 512 MiB RAM, 10 GiB SSD and 500 GiB transfer. DigitalOcean's official list price checked **2026-10-17** is **US$4/month maximum for the bundled Droplet plan** (listed hourly equivalent US$0.00595); taxes, Spaces/state storage, Buildkite charges, backups/snapshots and transfer overages are excluded. This is the cheapest listed Basic Regular plan, not a promise that your complete setup costs $4.

[DigitalOcean's documented size catalog](https://docs.digitalocean.com/reference/ansible/reference/modules/sizes_info/) lists this slug in NYC1. This was verified from official documentation, not a live authenticated account-capacity query. Before deployment, check current availability with the read-only DigitalOcean sizes/regions API or doctl compute size list. The Spaces endpoint example remains NYC3 because the state bucket's location is independent of the Droplet.

This default prioritizes low cost for light jobs. 512 MiB RAM and 10 GiB disk are tight even for installation and Docker image pulls; bootstrap and workloads have not been tested at this size. Bun/PostgreSQL/Chromium end-to-end jobs will likely need a larger size. Increase the configurable size only after observing requirements and approving the extra cost; the template never automatically selects a more expensive plan.

Prepare:
- A trusted provisioning agent with Bash, Terraform **1.16.6**, jq, and SOPS **3.10.2**. Install from official releases and verify signatures/checksums. Validation also needs Terraform and jq. The interactive setup helper needs Python 3.
- An existing DigitalOcean SSH public key and a narrow administrator CIDR; no world-open SSH default.
- A private Spaces bucket with versioning/backups appropriate to your recovery requirements, created separately from this stack. Never delete it with the Droplet. Limit its runtime access key to the bucket's required object read/write/delete operations (locking needs deletion). Keep bucket configuration/admin access separate.
- A DigitalOcean API token restricted to the operations actually needed for Droplets, firewalls, SSH-key reads and related reads. Do not grant credential-management privileges. Verify exact scopes against the current API and a reviewed plan; missing scopes should fail rather than expanding automatically.
- A Buildkite cluster/queue for application jobs, an agent registration token, and an operator-controlled age identity. The application agent must not receive infrastructure credentials.

Terraform 1.16.6 and DigitalOcean provider 2.100.0 are exact, verified release pins, not claims of newest releases. Generate/review and commit infra/.terraform.lock.hcl before deployment. Ubuntu's image slug and base OS/Git security packages track their distribution; this is not a bit-for-bit reproducible machine image.

## Configure names, then encrypted values

Run:

    bash scripts/setup.sh

It asks for the **name** of the Buildkite secret containing your SOPS age identity, defaulting to DIGITALOCEAN_BUILDKITE_SOPS_AGE_KEY. It updates two YAML mappings and never requests or stores a secret value. Review/commit that change. Buildkite reserves secret names beginning with buildkite or bk (any case), so BUILDKITE_DIGITALOCEAN_... cannot be used. Valid names contain letters, digits and underscores, up to 255 characters.

The pipeline maps your selected name to the standard SOPS_AGE_KEY environment variable. Store the private age identity in that Buildkite Secret through its secure UI, with restrictive access policies. GitHub Actions secrets are not automatically available to Buildkite.

Copy .sops.yaml.example to .sops.yaml and replace its public age recipient. That public recipient is safe to share; the private identity is not. Prepare secrets/deploy.plain.json from secrets/deploy.example.json using a secure local editor, setting:
- digitalocean_token
- spaces_access_key_id
- spaces_secret_access_key
- backend_hcl: completed contents of infra/backend.hcl.example
- terraform_tfvars: completed contents of infra/terraform.tfvars.example

Never add agent registration tokens or private SSH keys to Terraform variables. Backend configuration must contain no access keys; the script supplies them via environment variables.

Before encryption, fill exact signed apt repository versions for Buildkite agent, Docker Engine/CLI, containerd, Buildx and Compose. On a disposable Ubuntu 24.04 amd64 host using the official repositories, inspect:

    apt-cache madison buildkite-agent docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

Choose compatible versions (Buildkite 4.6.0 is a verified stable release; use its full apt version). Match Docker CE and CLI versions. This starter deliberately fails on placeholders instead of silently installing latest components. The package availability and compatibility checks have not yet run.

Encrypt the JSON (input name differs from output, so specify the intended filename for SOPS rule matching):

    sops --encrypt --filename-override secrets/deploy.enc.json secrets/deploy.plain.json > secrets/deploy.enc.json

Verify decryption privately without printing values. Review staged files and commit **only ciphertext**, public configuration and code. Remove the plaintext using your organization's secure-storage practices. Gitignore is a guardrail, not a secret scanner. Do not commit private age keys, .env files, plaintext secrets, plans or state. Ciphertext in a public repo remains public forever; rotate exposed keys and credentials if compromised. No real secrets or key pairs are included here.

Pins constrain initial package installation; establish an explicit security-update policy before production use. Abrupt process/host termination can prevent cleanup, so provisioning workers should be isolated and disposed of or sanitized between jobs.

The deploy script decrypts into a mode-0700 temporary directory, uses restrictive file permissions and removes its own temporary files at exit. It unsets SOPS_AGE_KEY before Terraform. SOPS-decrypted values are not automatically registered for Buildkite redaction: never enable shell tracing, Terraform debug logging, environment dumps or print the JSON. The provisioning agent remains a trusted secret-bearing host.

## Connect Buildkite and validate

After code review, create a validation pipeline whose upload step runs:

    buildkite-agent pipeline upload .buildkite/validate.yml

On a credential-free validation agent, run bash scripts/validate.sh. Generate provider lockfiles with terraform -chdir=infra providers lock -platform=linux_amd64 and review/commit them. Add your other development platforms if needed. A successful validation does not prove cloud provisioning.

Create a separate manual-only deployment pipeline pinned to trusted main, using:

    buildkite-agent pipeline upload .buildkite/deploy.yml

Its upload job must also run on an appropriate trusted agent. Replace REPLACE_WITH_INFRA_APPROVER_TEAM_SLUG with your real Buildkite approver team slug. Configure the provisioning queue and server-side secret policies before starting any build. No pipeline is created or run by this repository.

Flow: manual request -> plan -> restricted human approval -> apply. Apply recomputes the plan and compares a SHA-256 digest of its canonical machine-readable content (excluding its creation timestamp) against the preview. The preview digest cannot be replaced by rerunning the plan job in the same build. Differences fail closed and require a new reviewed build; harmless nondeterminism may also require replanning. The digest is nonsecret Buildkite metadata, not a stored plan. This is a drift guard in a trusted pipeline, not signed authorization against a compromised provisioning agent or metadata administrator. Routine apply also refuses deletions/replacements. For strict exact-binary-plan requirements, use a separately reviewed private saved-plan workflow. Review the actual configuration and costs; the guard is not a monetary budget. State is durable in Spaces with native S3 lockfiles; state and plans are never uploaded as CI artifacts.

## Agent token: deliberate one-time operator bootstrap

The Droplet installs software but leaves the agent stopped. Its registration token is not in cloud-init, Terraform state or the provisioning pipeline.

1. Through the authenticated DigitalOcean console, inspect the Droplet SSH host fingerprint with ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub. Verify the correct Droplet ID/IP.
2. Establish a known_hosts entry only after matching that fingerprint. ssh-keyscan alone is not trust; never disable StrictHostKeyChecking.
3. SSH using the verified host key and your existing SSH key. Check cloud-init status --wait and inspect logs for failures.
4. Run sudo /usr/local/sbin/buildkite-set-token. Paste the registration token at its hidden terminal prompt, not in a command argument or chat. This writes a root-owned mode-0600 EnvironmentFile and enables/starts the agent.
5. Confirm the agent appears in the intended Buildkite queue.

If you keep the registration token in SOPS, decrypt it separately in your trusted operator session and supply it at that prompt. The starter does not automatically SSH a token to an unverified new host. Future unattended bootstrap needs an independently trusted host-identity mechanism and a separately approved SSH credential path.

## Smoke checks and operation

On the Droplet:

    cloud-init status --wait
    systemctl status docker buildkite-agent --no-pager
    buildkite-agent --version
    git --version
    sudo -u buildkite-agent docker version
    sudo -u buildkite-agent docker compose version

Use examples/pipeline.yml for an explicit container smoke build; review/pin a trusted image digest for real projects. Private repository checkout and registry credentials require separate least-privilege setup; no deploy keys are generated automatically.

After an approved maintenance reboot, verify the agent reconnects and a smoke job runs. This has not been live-tested.

Graceful maintenance:

    sudo systemctl stop buildkite-agent
    sudo systemctl is-active buildkite-agent

SIGTERM lets the current job finish; systemd targets the main process first and waits indefinitely. Stop can therefore hang on a stuck job: investigate rather than assuming it drained. Do not reboot until the unit is inactive. Forced cancellation loses work and requires an explicit operator decision. Upgrade reviewed apt versions only after draining, then start the service and rerun checks. Editing user-data is not an in-place package upgrade and may propose replacement.

No automatic docker prune, workspace deletion or volume cleanup is included. Monitor disk usage, patches and credentials; assess what data can be removed first.

Troubleshooting: inspect cloud-init status and /var/log/cloud-init-output.log for missing apt versions; journalctl -u buildkite-agent for registration/queue problems; verify Docker-group membership; check CIDRs and cloud firewall for SSH failures. Never paste credentials into logs/issues. A pending job often means a queue mismatch or no provisioning agent.

## Explicit teardown

Disable new application jobs, drain and stop the agent, then use the separate trusted operator/provisioning environment and the same backend/configuration. Review terraform plan -destroy and run an interactive terraform destroy only after explicit approval. This is intentionally not a one-click pipeline step. Destruction removes the Droplet and its local data; preserve anything needed first. Verify removal in DigitalOcean, then revoke the now-unused agent token and unneeded credentials. Keep state/bucket backups until recovery is no longer needed; Spaces/snapshots may continue billing separately.

## Official references

- [Buildkite Secrets and naming rules](https://buildkite.com/docs/pipelines/security/secrets/buildkite-secrets)
- [Buildkite Ubuntu installation](https://buildkite.com/docs/agent/self-hosted/install/ubuntu)
- [Agent lifecycle](https://buildkite.com/docs/agent/lifecycle)
- [Approval blocks](https://buildkite.com/docs/pipelines/configure/step-types/block-step)
- [DigitalOcean Spaces Terraform backend](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/)
- [Docker Ubuntu installation](https://docs.docker.com/engine/install/ubuntu/)
- [SOPS documentation](https://getsops.io/docs/)
- [SOPS 3.10.2 verification instructions](https://github.com/getsops/sops/releases/tag/v3.10.2)
