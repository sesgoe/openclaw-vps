variable "name" {
  description = "Name used for the Droplet, its Tailscale hostname and its supporting resources."
  type        = string
  default     = "hey-gateway"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "name must be a lowercase DNS-style name between 2 and 63 characters."
  }
}

variable "region" {
  description = "DigitalOcean region slug."
  type        = string
  default     = "nyc3"
}

variable "size" {
  description = "DigitalOcean size slug. The smallest Droplet is plenty for one Go binary."
  type        = string
  default     = "s-1vcpu-512mb-10gb"
}

variable "image" {
  description = "Clean DigitalOcean base image; do not use an unreviewed Marketplace image."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "vpc_ip_range" {
  description = "Private CIDR for the dedicated VPC. Must not overlap the OpenClaw gateway's 10.42.0.0/20."
  type        = string
  default     = "10.42.16.0/24"
}

variable "admin_username" {
  description = "Non-root administrator account (you)."
  type        = string
  default     = "hey-admin"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.admin_username))
    error_message = "admin_username must be a valid Linux username of at most 31 characters."
  }
}

variable "service_username" {
  description = "System account that owns the HEY credentials and runs the restricted binary."
  type        = string
  default     = "hey"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.service_username))
    error_message = "service_username must be a valid Linux username of at most 31 characters."
  }
}

variable "agent_username" {
  description = "Account the OpenClaw agent logs in as. Every session runs the restricted binary."
  type        = string
  default     = "gordy"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,30}$", var.agent_username))
    error_message = "agent_username must be a valid Linux username of at most 31 characters."
  }
}

variable "ssh_public_key" {
  description = "Administrator SSH public key. Supply it with TF_VAR_ssh_public_key; it is not secret."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/=]+(?: .*)?$", trimspace(var.ssh_public_key)))
    error_message = "Use an Ed25519 or hardware-backed Ed25519 OpenSSH public key."
  }
}

variable "agent_ssh_public_key" {
  description = "The OpenClaw agent's SSH public key, generated on the OpenClaw gateway. Supply it with TF_VAR_agent_ssh_public_key."
  type        = string

  validation {
    condition     = can(regex("^ssh-ed25519 [A-Za-z0-9+/=]+(?: [^\"\\n]*)?$", trimspace(var.agent_ssh_public_key)))
    error_message = "Use an Ed25519 OpenSSH public key with no options and no double quotes in its comment."
  }
}

variable "tailscale_auth_key" {
  description = "One-off Tailscale auth key used to enroll the Droplet in your tailnet."
  type        = string
  sensitive   = true

  validation {
    condition     = startswith(var.tailscale_auth_key, "tskey-auth-")
    error_message = "tailscale_auth_key must be a Tailscale auth key beginning with tskey-auth-."
  }
}

variable "timezone" {
  description = "Server timezone."
  type        = string
  default     = "America/New_York"
}
