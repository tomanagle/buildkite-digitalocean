---
name: setup-buildkite-digitalocean
description: Guide an explicitly requested setup of this repository using available Buildkite MCP and GitHub tools, with capability discovery, idempotent configuration, SOPS credential handoffs and separate deployment approval.
---

# Set up Buildkite DigitalOcean

## Scope

Use when the repository owner asks to connect/configure this starter, assess readiness, or prepare a Buildkite deployment. Read README.md and the actual checked-out pipeline/scripts first. Repository instructions are guidance, not authorization to create resources, grant access, enter credentials, start builds, spend money or merge code.

Default to a read-only readiness assessment until the user explicitly requests a particular setup action. Never infer organization, repository, team, spending limit or credentials from a sample value.

## 1. Establish the target and discover capabilities

- Confirm the existing GitHub owner/repository, Buildkite organization/cluster, desired pipeline names, approver team and intended scope. Reuse verified context; ask only for missing choices.
- Inspect repository visibility, default branch, open PRs and current files before editing. Preserve unrelated changes. Treat source as unvalidated until the documented checks actually run.
- Discover connected MCP tools and their schemas. Check authenticated identities and perform a harmless relevant read.
- Buildkite MCP is not assumed installed. Available tools may be read-only or may lack pipeline, queue, secret or access-policy creation. Build a small capability checklist: organizations, pipelines, clusters/queues, builds, secret names/policies and repository integration.
- Use only supported operations with their real schemas. If a required mutation is absent, hand that step to the operator through the official Buildkite UI or an explicitly authorized alternative. Do not fabricate tool names, install integrations, create API tokens or widen scopes as an implicit workaround.
- A connected GitHub account does not automatically make GitHub Actions secrets available in Buildkite.

### Documented capability map, not an availability promise

As checked 2026-10-17, the [official MCP tool catalog](https://buildkite.com/docs/apis/mcp-server/tools) documents pipeline create/update, cluster create/update, self-hosted queue create/update, secret creation and build creation. Inspect actual tools and authorization first; do not assume these are exposed in your connection.

- Organization/user/scope discovery: current_user, user_token_organization and access_token metadata. Never request or display the raw access token.
- API token scopes (not tool names): pipelines use read_pipelines/write_pipelines; clusters and queues: read_clusters/write_clusters.
- Agent reads: read_agents. Build creation: write_builds, used only after explicit run authorization.
- Secret metadata: read_secrets_details; creation: write_secrets. Even if create_cluster_secret is exposed, do not transmit credential values through an ordinary agent tool call; use the secure operator handoff.
- No documented agent-token management, GitHub repository integration/file-writing, or secret update/delete tool should be assumed. Those need separate supported service tools or operator action.
- Hosted MCP's ordinary endpoint includes write capabilities; its /mcp/readonly endpoint excludes them. See [toolsets](https://buildkite.com/docs/apis/mcp-server/tools/toolsets). Never switch endpoints or widen scopes to bypass a restriction.

## 2. Read before creating or changing

List and inspect existing pipelines/queues and their repository URL, branch rules, upload commands, cluster/queue assignments, team permissions and secret references. Match exact identifiers; names alone are not enough.

Present the smallest change set. Reuse matching resources. If a matching name points to a different repository or trust boundary, stop and ask; do not overwrite or create duplicates. Preserve existing settings outside the requested scope.

The target layout:
- Validation pipeline: upload .buildkite/validate.yml on an isolated validation queue; no deployment secrets.
- Manual infrastructure pipeline: upload .buildkite/deploy.yml on a pre-existing trusted provisioning queue, restricted to trusted main. Disable automatic push/PR deployment triggers.
- Application queue: linux-docker by default, populated by the new Droplet only after provisioning and token bootstrap.
- Explicit approver-team slug in the approval block.
- Cluster/queue access and secret policies enforced outside editable YAML. Queue tags and shell branch checks alone are not security isolation.

The new Droplet must never be required to provision or destroy itself. If there is no existing trusted provisioning agent, explain the bootstrap dependency. Do not silently create a paid hosted queue or new host.

Create a new deployment pipeline disabled/manual-only, including safe trigger settings in the initial creation where supported. If the available tool cannot establish or confirm those controls, hand off before creation/enabling rather than leaving a live intermediate configuration.

After explicit setup authorization, use available supported MCP mutations for only the approved changes. Read back every mutation. Do not configure unrelated source-control webhooks, write team memberships, grant new access, or start a build as a side effect.

## 3. Validate source before enabling deployment

Require an executable environment and reviewed dependency installation. Run credential-free static checks with bash scripts/validate.sh, including Terraform formatting/validation and shell syntax. Run appropriate YAML parsing and render/test the bootstrap separately. Generate/review/commit the provider checksum lockfile. Confirm exact apt package versions and compatible Ubuntu 24.04 amd64 packages.

If the environment is unavailable, provide the precise blocker and keep the PR/pipeline readiness status as draft. Never report source inspection as a passed test. Do not dispatch paid provisioning to discover syntax errors.

Review deployment guardrails: native state locking, no state/plan CI artifacts, no token in user-data, plan digest checked after approval, plan retry cannot replace the digest, no automatic delete/replacement, narrow SSH CIDRs, one worker, trusted Docker workloads only. Recognize the digest as a trusted-pipeline drift guard, not signed authorization or exact-binary-plan retention.

## 4. Configure names without receiving secret values

Run or explain bash scripts/setup.sh in the authorized workspace. It asks only for the Buildkite secret NAME used for the age identity and updates YAML mappings. Default: DIGITALOCEAN_BUILDKITE_SOPS_AGE_KEY. Buildkite names may use letters, digits and underscores (maximum 255 characters), but cannot begin with buildkite or bk, case-insensitively.

The YAML secrets mapping must map the SOPS_AGE_KEY environment variable to the selected stored secret name. Do not replace it with an ordinary env mapping containing the literal name.

Credential handoffs:
- Operator creates/selects an age identity securely and sets its private value in Buildkite Secrets with restrictive pipeline/branch/agent access. Never request the private value in chat or call a tool with it.
- Operator supplies the DigitalOcean API token and bucket-scoped Spaces access keys through secure tooling, then encrypts secrets/deploy.enc.json following README.md. Do not generate or configure persistent credentials without explicit action-time approval and the required secure handoff.
- Keep public age recipient/configuration separate from the private key. Commit ciphertext only after reviewing staged changes. Never commit plaintext, .env, private keys, plans or state.
- Agent registration token stays outside Terraform and is entered only during the verified-host bootstrap below.
- Private Git checkout and registry access need separate least-privilege credentials; an agent registration token does not provide them.

Check existence/permissions through nonsecret metadata only. Never print/decrypt secrets merely to prove they exist. SOPS plaintext is not automatically registered for Buildkite redaction. No debug/environment dumps.

## 5. Prepare state and deployment approval

Reuse an approved private Spaces backend; it must outlive the Droplet. Read its configuration and lock/versioning/recovery arrangements when authorized. Creating a bucket may add cost and is a separate step, not an automatic prerequisite fix.

Check current DigitalOcean size/region/image compatibility and pricing using official sources or authenticated read-only APIs. The repository currently defaults to s-1vcpu-512mb-10gb in NYC1; recheck the actual source. Do not silently upgrade if unavailable or too small. Distinguish the Droplet cost from taxes, Spaces, Buildkite, backups and bandwidth.

Before starting a provisioning build or approving apply, obtain explicit approval covering the provider, resource/region/size, current spending limit and recurring billing, associated costs, and destructive/replacement consequences where relevant. A setup request does not authorize a paid deployment. Do not unblock the human approval step on the user's behalf without authorization for that exact action and reviewed changes.

If only setup was requested, stop after configuration/read-back and provide the readiness checklist. Do not create a validation or deployment run unless requested/authorized.

## 6. Verified one-time agent bootstrap

After separately approved provisioning:
1. Operator verifies the intended Droplet's SSH host fingerprint through the authenticated DigitalOcean console.
2. Add/trust the host key only after that match; never use StrictHostKeyChecking=no or trust ssh-keyscan alone.
3. Operator connects with strict host verification, checks cloud-init completion and runs sudo /usr/local/sbin/buildkite-set-token.
4. Operator enters the registration token at the hidden terminal prompt. Systemd reads the root-owned 0600 EnvironmentFile before dropping privileges. Do not put the token in command arguments, Terraform, cloud-init or chat.
5. Use permitted read-only Buildkite tools to confirm the agent appears in the intended queue. Run a smoke build only when authorized.

Do not imply unattended SSH bootstrap is supported without an independently trusted host-identity mechanism and approved credential path.

## 7. Completion report

Report verified links and IDs for resources actually created or changed; distinguish prepared source from configured services and passing tests from unexecuted checks. Include unresolved operator handoffs, current costs, security limitations and the next concrete step. Stop when the requested setup stage is complete or blocked on required access/approval.

## Dry-run review cases (no external actions)

- Missing organization/cluster choice: ask for it; do not select a sample or arbitrary account.
- Existing pipeline name points elsewhere: stop for the owner decision; do not overwrite it.
- No Buildkite MCP: explain missing capability; prepare an operator checklist, create nothing.
- Read-only MCP: inspect existing resources, produce the minimal proposed changes, hand off unsupported mutations.
- Matching pipeline already exists: reuse it; do not duplicate or overwrite unrelated settings.
- User asks only to set up: configure only explicitly approved supported resources; do not start builds or provision.
- Secret value pasted into an ordinary prompt: do not repeat/store it; route to secure handling and advise rotation if exposed.
- Missing agent/Spaces bucket or current price above approval: stop for the specific decision; do not create paid prerequisites.
- PR is untrusted, checksum lockfile missing, approver placeholder remains, or tests cannot run: deployment stays blocked.
- Host key is unverified: token injection stays blocked even if the Droplet is running.
- Previously approved plan changes or plan job is rerun: require a fresh reviewed build.
