# Agent guidance

For requests to set up this repository with Buildkite, read
[the repository setup skill](.agents/skills/setup-buildkite-digitalocean/SKILL.md)
and README.md before acting.

This repository is a source-only, unexecuted deployment draft. Keep setup,
credential configuration and paid deployment as separate approval stages.
Do not create infrastructure, start builds, mint credentials or merge the draft
merely because these instructions exist. Discover actual connected capabilities
rather than assuming a Buildkite MCP tool is installed.

Never put credentials in source, cloud-init, Terraform variables/state, logs,
chat or issue/PR text. The supported initial agent bootstrap is an operator
handoff through the authenticated DigitalOcean Droplet Console.
