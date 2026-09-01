variable "name" {
  description = "Name used for the Droplet and its supporting resources."
  type        = string
  default     = "openclaw-gateway"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "name must be a lowercase DNS-style name between 2 and 63 characters."
  }
}

variable "region" {
  description = "DigitalOcean region slug. NYC3 is a reasonable East Coast default."
  type        = string
  default     = "nyc3"
}

variable "size" {
  description = "DigitalOcean size slug. Four GiB provides headroom for Chromium-heavy OpenClaw workloads."
  type        = string
  default     = "s-2vcpu-4gb"
}

variable "image" {
  description = "Clean DigitalOcean base image; do not use an unreviewed Marketplace image."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "vpc_ip_range" {
  description = "Private CIDR for the dedicated VPC."
  type        = string
  default     = "10.42.0.0/20"
}

variable "admin_username" {
  description = "Non-root operating-system administrator account."
  type        = string
  default     = "openclaw-admin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.admin_username))
    error_message = "admin_username must be a valid Linux username of at most 31 characters."
  }
}

variable "ssh_public_key" {
  description = "Operator SSH public key. Supply it with TF_VAR_ssh_public_key; it is not secret."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/=]+(?: .*)?$", trimspace(var.ssh_public_key)))
    error_message = "Use an Ed25519 or hardware-backed Ed25519 OpenSSH public key."
  }
}

variable "tailscale_auth_key" {
  description = "One-off Tailscale auth key carrying tag:openclaw, used to enroll the Droplet in your tailnet."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.tailscale_auth_key, "tskey-auth-")
    error_message = "tailscale_auth_key must be a Tailscale auth key beginning with tskey-auth-."
  }
}

variable "enable_backups" {
  description = "Enable weekly DigitalOcean backups. Recommended because the gateway is stateful."
  type        = bool
  default     = true
}

variable "timezone" {
  description = "Server timezone."
  type        = string
  default     = "America/New_York"
}
