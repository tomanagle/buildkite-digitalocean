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
variable "ssh_key_ids" {
  type = list(string)
  validation {
    condition     = length(var.ssh_key_ids) > 0
    error_message = "Provide existing DigitalOcean SSH key IDs."
  }
}
variable "ssh_cidrs" {
  type = list(string)
  validation {
    condition = length(var.ssh_cidrs) > 0 && alltrue([
      for cidr in var.ssh_cidrs : can(cidrhost(cidr, 0)) && !endswith(cidr, "/0")
    ])
    error_message = "Provide restricted administrator CIDRs; /0 is forbidden."
  }
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
  ssh_keys   = var.ssh_key_ids
  monitoring = true
  ipv6       = false
  user_data = templatefile("${path.module}/bootstrap.sh.tftpl", {
    queue = var.queue
    versions = var.apt_versions
  })
}
resource "digitalocean_firewall" "agent" {
  name        = "${var.name}-ssh-only"
  droplet_ids = [digitalocean_droplet.agent.id]
  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_cidrs
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
