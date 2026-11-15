# The game's own Hetzner VM (docs/DEPLOY.md). OpenTofu or Terraform:
#   cd infra/hetzner && tofu init && tofu apply
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
  # The state stays on this PC by default (terraform.tfstate, git-ignored).
  # To keep it in a Hetzner Object Storage bucket instead, copy
  # backend.tf.example to backend.tf and run `tofu init -migrate-state`.
}

provider "hcloud" {
  token = var.hcloud_token
}
