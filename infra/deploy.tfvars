# Non-secret deployment settings.
queue  = "linux-docker"
region = "syd1"
size   = "s-1vcpu-2gb"
# Set false after the agent is registered to close port 22 again.
droplet_console = true
apt_versions = {
  agent      = "4.6.0-15028"
  docker     = "5:29.9.1-1~ubuntu.24.04~noble"
  containerd = "2.4.2-2~ubuntu.24.04~noble"
  buildx     = "0.38.0-1~ubuntu.24.04~noble"
  compose    = "5.6.0-1~ubuntu.24.04~noble"
}
