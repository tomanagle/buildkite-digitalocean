terraform {
  required_version = "= 1.16.6"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "= 2.100.0"
    }
  }
  backend "s3" {}
}
provider "digitalocean" {}

variable "name" {
  type    = string
  default = "buildkite-agent"
}
variable "region" {
  type    = string
  default = "nyc1"
}
variable "size" {
  type    = string
  default = "s-1vcpu-512mb-10gb"
}
variable "droplet_console" {
  description = "Open port 22 to all addresses so the DigitalOcean Droplet Console can connect. Password SSH logins are disabled."
  type        = bool
  default     = true
}
variable "queue" {
  type    = string
  default = "linux-docker"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9_-]*$", var.queue))
    error_message = "Queue must contain lowercase letters, numbers, underscores or dashes."
  }
}
variable "apt_versions" {
  description = "Exact signed-repository package versions. Resolve and review before deployment."
  type = object({
    agent      = string
    docker     = string
    containerd = string
    buildx     = string
    compose    = string
  })
  validation {
    condition     = alltrue([for v in values(var.apt_versions) : can(regex("^[0-9][A-Za-z0-9.+:~_-]*$", v))])
    error_message = "Every package needs an exact apt version, not a placeholder."
  }
}
resource "digitalocean_droplet" "agent" {
  name       = var.name
  region     = var.region
  size       = var.size
  image      = "ubuntu-24-04-x64"
  monitoring = true
  ipv6       = false
  user_data = templatefile("${path.module}/bootstrap.sh.tftpl", {
    queue    = var.queue
    versions = var.apt_versions
  })
}
resource "digitalocean_firewall" "agent" {
  name        = "${var.name}-console-only"
  droplet_ids = [digitalocean_droplet.agent.id]
  # The Droplet Console has no published source range, so it needs port 22 open to all.
  dynamic "inbound_rule" {
    for_each = var.droplet_console ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "22"
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
output "agent_ipv4" {
  value = digitalocean_droplet.agent.ipv4_address
}
