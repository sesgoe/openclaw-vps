output "droplet_id" {
  description = "DigitalOcean Droplet ID."
  value       = digitalocean_droplet.gateway.id
}

output "public_ipv4" {
  description = "Public egress address. New inbound connections are denied by the cloud and host firewalls."
  value       = digitalocean_droplet.gateway.ipv4_address
}

output "vpc_ipv4" {
  description = "Droplet address inside the dedicated DigitalOcean VPC."
  value       = digitalocean_droplet.gateway.ipv4_address_private
}

output "tailscale_hostname" {
  description = "MagicDNS hostname requested during Tailscale enrollment."
  value       = var.name
}

output "ssh_command" {
  description = "Run from a device already connected to the same tailnet."
  value       = "ssh ${var.admin_username}@${var.name}"
}

output "estimated_base_monthly_cost_note" {
  description = "Billing reminder; verify live Droplet pricing before applying."
  value       = "2 vCPU / 4 GiB Droplet + weekly backups; Cloud Firewall and VPC have no additional monthly charge."
}
