terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.99"
    }
  }
}

provider "digitalocean" {
  # The provider reads DIGITALOCEAN_TOKEN from the process environment.
}

