output "droplet_id" {
  description = "DigitalOcean Droplet ID."
  value       = digitalocean_droplet.gateway.id
}

output "public_ipv4" {
  description = "Public egress address. New inbound connections are denied by the cloud and host firewalls."
  value       = digitalocean_droplet.gateway.ipv4_address
}

output "tailscale_hostname" {
  description = "MagicDNS hostname requested during Tailscale enrollment."
  value       = var.name
}

output "admin_ssh_command" {
  description = "Run from a device already connected to the same tailnet."
  value       = "ssh ${var.admin_username}@${var.name}"
}

output "agent_ssh_check" {
  description = "Run on the OpenClaw gateway once client/ssh_config is installed there."
  value       = "ssh ${var.name} box list"
}
