# buildkite-digitalocean

Runs **one self-hosted Buildkite agent on a DigitalOcean Droplet** (Ubuntu 24.04 with Git, Docker and Docker Compose). A manual Buildkite pipeline creates the Droplet with Terraform. You then open the Droplet Console in your browser once to give the agent its token.

> **Untested:** the static checks pass, but this has never provisioned real infrastructure.

The settings in `infra/deploy.tfvars` are `s-1vcpu-2gb` in `syd1`, about **US$12/month**. Spaces state storage adds about $5/month. The Droplet keeps billing while it's powered off.

## Setup

### 1. DigitalOcean

1. **Spaces Object Storage → Create Bucket:** region `syd1`, private. Put its name in `bucket` in `infra/backend.hcl`.
2. **Spaces Object Storage → Access Keys → Create Access Key:** **Limited access**, that bucket only, Read/Write/Delete. Keep both values for step 2.
3. **API → Tokens → Generate New Token:** **Custom scopes**, `droplet` create/read/update and `firewall` create/read/update.

### 2. Buildkite secrets

In Buildkite, go to **Agents → your cluster → Secrets → New secret** and create:

| Secret | Value |
| --- | --- |
| `DIGITALOCEAN_TOKEN` | The API token |
| `SPACES_ACCESS_KEY_ID` | The Spaces access key ID |
| `SPACES_SECRET_ACCESS_KEY` | The Spaces secret key |

Restrict each secret's access policy to the Deploy pipeline once it exists.

### 3. Buildkite pipeline and queue

1. In the same cluster, create a **self-hosted queue** called `linux-docker`, plus an **agent token** for it. The Droplet's agent will join this queue.
2. Create a pipeline called **Deploy** for this repository, in that cluster:
   - steps: `buildkite-agent pipeline upload .buildkite/deploy.yml`
   - branch: `main`
   - turn off builds on push and pull requests, so it only runs when you start it

The deploy jobs run on the cluster's hosted `linux-small` queue, and only people in the `everyone` team can approve. Change either in `.buildkite/deploy.yml` if needed.

### 4. Deploy

Commit and push `infra/backend.hcl` to `main`. Then click **New Build** on the Deploy pipeline, review the Terraform plan, and approve it. The apply step creates the Droplet and its firewall.

### 5. Register the agent

1. In DigitalOcean, open the Droplet and go to **Access → Launch Droplet Console**, as `root`.
2. Run:
   ```sh
   cloud-init status --wait
   /usr/local/sbin/buildkite-set-token   # paste the linux-docker agent token
   ```
3. The agent appears in the `linux-docker` queue.

To run a quick test, copy `examples/pipeline.yml` into a new pipeline and run it.

## Using the agent

In your project's `.buildkite/pipeline.yml`, target `queue: "linux-docker"`, and run your toolchains in pinned containers as the agent's user (`--user "$(id -u):$(id -g)"`). [Social Mockery's `.buildkite/`](https://github.com/tomanagle/Social-Mockery/tree/main/.buildkite) is a worked example. Only build repositories you trust, and turn off builds from forks: Docker access is root on the host.

## Changing settings

Edit `infra/deploy.tfvars`, push, and run Deploy again. The apply step refuses changes that would delete or replace the Droplet.

- `size` and `region`: see [Droplet pricing](https://www.digitalocean.com/pricing/droplets)
- `droplet_console`: set to `false` after setup to close port 22. While it's open, SSH accepts keys only, not passwords.
- `apt_versions`: exact package versions. List the available ones with `apt-cache madison buildkite-agent docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin` on Ubuntu 24.04.

## Operating

- **Reboot:** run `sudo systemctl stop buildkite-agent` first. It waits for the current job to finish.
- **Disk:** nothing cleans up Docker images automatically.
- **Problems:** check `/var/log/cloud-init-output.log` for install errors and `journalctl -u buildkite-agent` for agent errors. If the Droplet Console won't connect, use the **Recovery Console** with the root password DigitalOcean emailed you.
- **Teardown:** there's no pipeline step for this, on purpose. On a machine with Terraform 1.16.6, export `DIGITALOCEAN_TOKEN`, `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` (your Spaces keys), then run:
  ```sh
  terraform -chdir=infra init -backend-config=backend.hcl
  terraform -chdir=infra destroy -var-file=deploy.tfvars
  ```
  Then revoke the agent token. Delete the Spaces bucket separately if you no longer need it.

## Development

`bash scripts/validate.sh` runs shell syntax checks, the unit tests, `terraform fmt` and `terraform validate`. It needs Python 3 and jq, plus Terraform 1.16.6 on anything other than Linux amd64.
