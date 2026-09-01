locals {
  resource_tag = "${var.name}-managed"

  tailscale_up = [
    "tailscale",
    "up",
    "--auth-key=${var.tailscale_auth_key}",
    "--hostname=${var.name}",
    "--operator=${var.admin_username}",
    "--accept-dns=true",
    "--accept-routes=false",
  ]

  cloud_config = {
    package_update  = true
    package_upgrade = true
    timezone        = var.timezone
    ssh_pwauth      = false
    disable_root    = true

    users = [
      "default",
      {
        name                = var.admin_username
        gecos               = "OpenClaw administrator"
        groups              = ["adm", "sudo"]
        shell               = "/bin/bash"
        lock_passwd         = true
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = [trimspace(var.ssh_public_key)]
      }
    ]

    packages = [
      "ca-certificates",
      "curl",
      "gnupg",
      "jq",
      "ufw",
      "unattended-upgrades",
    ]

    write_files = [
      {
        path        = "/etc/ssh/sshd_config.d/60-openclaw-hardening.conf"
        owner       = "root:root"
        permissions = "0644"
        content = join("\n", [
          "PasswordAuthentication no",
          "KbdInteractiveAuthentication no",
          "PermitRootLogin no",
          "PubkeyAuthentication yes",
          "MaxAuthTries 3",
          "X11Forwarding no",
          "AllowAgentForwarding no",
          "AllowTcpForwarding local",
          "GatewayPorts no",
          "PermitTunnel no",
          "AllowUsers ${var.admin_username}",
          "",
        ])
      },
      {
        path        = "/etc/apt/apt.conf.d/20auto-upgrades"
        owner       = "root:root"
        permissions = "0644"
        content = join("\n", [
          "APT::Periodic::Update-Package-Lists \"1\";",
          "APT::Periodic::Unattended-Upgrade \"1\";",
          "",
        ])
      },
      {
        path        = "/etc/sysctl.d/99-openclaw-hardening.conf"
        owner       = "root:root"
        permissions = "0644"
        content = join("\n", [
          "kernel.kptr_restrict = 2",
          "kernel.dmesg_restrict = 1",
          "kernel.unprivileged_bpf_disabled = 1",
          "fs.protected_fifos = 2",
          "fs.protected_regular = 2",
          "net.ipv4.conf.all.accept_redirects = 0",
          "net.ipv4.conf.default.accept_redirects = 0",
          "net.ipv6.conf.all.accept_redirects = 0",
          "net.ipv6.conf.default.accept_redirects = 0",
          "",
        ])
      },
      {
        path        = "/etc/update-motd.d/99-openclaw"
        owner       = "root:root"
        permissions = "0755"
        content     = "#!/bin/sh\necho 'OpenClaw host: public ingress is denied; administer through Tailscale.'\n"
      },
    ]

    runcmd = [
      ["systemctl", "restart", "ssh.service"],
      ["sysctl", "--system"],
      ["ufw", "default", "deny", "incoming"],
      ["ufw", "default", "allow", "outgoing"],
      ["ufw", "allow", "in", "on", "tailscale0", "to", "any", "port", "22", "proto", "tcp", "comment", "SSH over Tailscale"],
      ["ufw", "--force", "enable"],
      ["sh", "-c", "curl -fsSL https://tailscale.com/install.sh | sh"],
      local.tailscale_up,
      ["install", "-d", "-m", "0750", "-o", var.admin_username, "-g", var.admin_username, "/srv/openclaw"],
      ["loginctl", "enable-linger", var.admin_username],
      ["systemctl", "enable", "--now", "unattended-upgrades.service"],
      ["touch", "/var/lib/openclaw-bootstrap-complete"],
    ]

    final_message = "OpenClaw host bootstrap finished. Connect to ${var.name} through Tailscale as ${var.admin_username}."
  }
}

resource "digitalocean_vpc" "gateway" {
  name     = "${var.name}-vpc"
  region   = var.region
  ip_range = var.vpc_ip_range
}

resource "digitalocean_tag" "gateway" {
  name = local.resource_tag
}

# This firewall is attached by tag before the Droplet exists. It intentionally
# has no inbound rules. Because DigitalOcean firewalls are stateful, response
# traffic for outbound connections (including Tailscale) is still allowed.
resource "digitalocean_firewall" "gateway" {
  name = "${var.name}-deny-inbound"
  tags = [digitalocean_tag.gateway.name]

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

resource "digitalocean_ssh_key" "operator" {
  name       = "${var.name}-operator"
  public_key = trimspace(var.ssh_public_key)
}

resource "digitalocean_droplet" "gateway" {
  name              = var.name
  region            = var.region
  size              = var.size
  image             = var.image
  vpc_uuid          = digitalocean_vpc.gateway.id
  public_networking = true
  ipv6              = false
  monitoring        = true
  backups           = var.enable_backups
  droplet_agent     = true
  graceful_shutdown = true
  ssh_keys          = [digitalocean_ssh_key.operator.fingerprint]
  tags              = [digitalocean_tag.gateway.name]
  user_data         = "#cloud-config\n${yamlencode(local.cloud_config)}"

  dynamic "backup_policy" {
    for_each = var.enable_backups ? [1] : []
    content {
      plan    = "weekly"
      weekday = "SUN"
      hour    = 8
    }
  }

  # Ensure there is no momentary public SSH exposure while the Droplet boots.
  depends_on = [digitalocean_firewall.gateway]
}

resource "digitalocean_project" "gateway" {
  name        = var.name
  description = "Tailnet-only OpenClaw gateway infrastructure"
  purpose     = "Web Application"
  environment = "Production"
  resources   = [digitalocean_droplet.gateway.urn]
}
