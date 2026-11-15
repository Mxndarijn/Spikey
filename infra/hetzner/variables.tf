variable "hcloud_token" {
  description = "A Hetzner Cloud API token (Read & Write) for the project the game runs in."
  type        = string
  sensitive   = true
}

variable "name" {
  description = "Name of the server and everything made with it."
  type        = string
  default     = "flapjaw"
}

variable "server_type" {
  description = "cpx11: 2 vCPU, 2 GB (the plan's default). cx22 or cpx21: 4 GB, the comfortable option. x86 only."
  type        = string
  default     = "cpx11"
}

variable "location" {
  description = "Hetzner location: nbg1 (Nuremberg), fsn1 (Falkenstein) or hel1 (Helsinki)."
  type        = string
  default     = "nbg1"
}

variable "image" {
  type    = string
  default = "ubuntu-24.04"
}

variable "ssh_public_key_file" {
  description = "Your SSH public key, for logging in to the VM."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "admin_cidrs" {
  description = "Addresses that may use SSH (22) and the Kubernetes API (6443), e.g. [\"203.0.113.7/32\"]."
  type        = list(string)
}

variable "api_host" {
  description = "The game API's host name (API_HOST), also put in the Kubernetes API certificate."
  type        = string
}

variable "volume_size_gb" {
  description = "The Postgres data volume."
  type        = number
  default     = 20
}

variable "k3s_version" {
  description = "The k3s release cloud-init installs (pinned, so a rebuild gets the same one)."
  type        = string
  default     = "v1.31.4+k3s1"
}

variable "swap_gb" {
  description = "Swap file size: a safety net on the 2 GB VM (docs/SERVER_MIGRATION.md, VM size)."
  type        = number
  default     = 2
}
