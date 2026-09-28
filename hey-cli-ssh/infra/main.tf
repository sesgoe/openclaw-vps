locals {
  resource_tag = "${var.name}-managed"

  # The restricted binary, installed by scripts/deploy.sh. The agent's SSH session can
  # run it, as the service user that owns the HEY credentials, and nothing else.
  gordy_binary  = "/usr/local/libexec/hey-gordy"
  force_command = "sudo -n -H -u ${var.service_username} ${local.gordy_binary}"

  tailscale_up = [
    "tailscale",
    "up",
    "--auth-key=${var.tailscale_auth_key}",
    "--hostname=${var.name}",
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
        gecos               = "HEY gateway administrator"
        groups              = ["adm", "sudo"]
        shell               = "/bin/bash"
        lock_passwd         = true
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = [trimspace(var.ssh_public_key)]
      },
      # Owns the HEY credentials. Nobody logs in as it; it is only reached through sudo.
      {
        name        = var.service_username
        gecos       = "HEY CLI credentials owner"
        system      = true
        homedir     = "/var/lib/${var.service_username}"
        shell       = "/usr/sbin/nologin"
        lock_passwd = true
      },
      # The agent's login. Its key lives in a root-owned file outside its home, and every
      # session it opens runs the forced command.
      {
        name        = var.agent_username
        gecos       = "OpenClaw agent (restricted HEY CLI only)"
        shell       = "/bin/sh"
        lock_passwd = true
      },
    ]

    packages = [
      "ca-certificates",
      "curl",
      "ufw",
      "unattended-upgrades",
    ]

    write_files = [
      {
        path        = "/etc/ssh/sshd_config.d/60-hey-gateway-hardening.conf"
        owner       = "root:root"
        permissions = "0644"
        content = join("\n", [
          "PasswordAuthentication no",
          "KbdInteractiveAuthentication no",
          "PermitRootLogin no",
          "PubkeyAuthentication yes",
          "PermitUserEnvironment no",
          "MaxAuthTries 3",
          "X11Forwarding no",
          "AllowAgentForwarding no",
          "AllowTcpForwarding no",
          "AllowStreamLocalForwarding no",
          "GatewayPorts no",
          "PermitTunnel no",
          "AllowUsers ${var.admin_username} ${var.agent_username}",
          "",
          "Match User ${var.agent_username}",
          "    AuthorizedKeysFile /etc/ssh/agent_authorized_keys/%u",
          "    ForceCommand ${local.force_command}",
          "    PermitTTY no",
          "    DisableForwarding yes",
          "",
        ])
      },
      {
        # Belt and braces with ForceCommand: the key itself is restricted to the command.
        path        = "/etc/ssh/agent_authorized_keys/${var.agent_username}"
        owner       = "root:root"
        permissions = "0644"
        content     = "restrict,command=\"${local.force_command}\" ${trimspace(var.agent_ssh_public_key)}\n"
      },
      {
        # The agent may run exactly the restricted binary, with no arguments, as the
        # service user. The command it asked for travels in SSH_ORIGINAL_COMMAND, which
        # the binary splits itself without a shell.
        path        = "/etc/sudoers.d/60-hey-gordy"
        owner       = "root:root"
        permissions = "0440"
        content = join("\n", [
          "Defaults!${local.gordy_binary} env_keep += \"SSH_ORIGINAL_COMMAND\"",
          "${var.agent_username} ALL=(${var.service_username}) NOPASSWD: ${local.gordy_binary} \"\"",
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
        path        = "/etc/sysctl.d/99-hey-gateway-hardening.conf"
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
        path        = "/etc/update-motd.d/99-hey-gateway"
        owner       = "root:root"
        permissions = "0755"
        content     = "#!/bin/sh\necho 'HEY gateway: public ingress is denied; administer through Tailscale.'\n"
      },
    ]

    runcmd = [
      ["visudo", "-cf", "/etc/sudoers.d/60-hey-gordy"],
      ["install", "-d", "-m", "0700", "-o", var.service_username, "-g", var.service_username, "/var/lib/${var.service_username}"],
      # The agent owns nothing, not even its home directory.
      ["chown", "root:root", "/home/${var.agent_username}"],
      ["chmod", "0755", "/home/${var.agent_username}"],
      ["sshd", "-t"],
      ["systemctl", "restart", "ssh.service"],
      ["sysctl", "--system"],
      ["ufw", "default", "deny", "incoming"],
      ["ufw", "default", "allow", "outgoing"],
      ["ufw", "allow", "in", "on", "tailscale0", "to", "any", "port", "22", "proto", "tcp", "comment", "SSH over Tailscale"],
      ["ufw", "--force", "enable"],
      ["sh", "-c", "curl -fsSL https://tailscale.com/install.sh | sh"],
      local.tailscale_up,
      ["systemctl", "enable", "--now", "unattended-upgrades.service"],
      ["touch", "/var/lib/hey-gateway-bootstrap-complete"],
    ]

    final_message = "HEY gateway bootstrap finished. Connect to ${var.name} through Tailscale as ${var.admin_username}, then run make deploy and make login."
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

# Attached by tag before the Droplet exists, with no inbound rules. DigitalOcean
# firewalls are stateful, so replies to outbound connections (Tailscale, HEY) still pass.
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

# DigitalOcean registers a public key once per account, and the OpenClaw gateway's
# Terraform has already registered the administrator key both gateways share. Look it up
# rather than register it again. (Creating it only when missing would flip-flop: the next
# plan would find the key this config created and destroy it.)
data "digitalocean_ssh_keys" "operator" {
  filter {
    key    = "public_key"
    values = [trimspace(var.ssh_public_key)]
  }
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
  backups           = false # stateless: a rebuild is a new sign-in, not a restore
  droplet_agent     = true
  graceful_shutdown = true
  ssh_keys          = [for key in data.digitalocean_ssh_keys.operator.ssh_keys : key.fingerprint]
  tags              = [digitalocean_tag.gateway.name]
  user_data         = "#cloud-config\n${yamlencode(local.cloud_config)}"

  # Ensure there is no momentary public SSH exposure while the Droplet boots.
  depends_on = [digitalocean_firewall.gateway]

  lifecycle {
    precondition {
      condition     = length(data.digitalocean_ssh_keys.operator.ssh_keys) == 1
      error_message = "The administrator public key (TF_VAR_ssh_public_key) must be registered in DigitalOcean exactly once. The OpenClaw gateway's Terraform registers it; otherwise add it under Settings → Security → SSH Keys."
    }
  }
}

resource "digitalocean_project" "gateway" {
  name        = var.name
  description = "Tailnet-only host for the restricted HEY CLI the OpenClaw agent uses"
  purpose     = "Service or API"
  environment = "Production"
  resources   = [digitalocean_droplet.gateway.urn]
}
