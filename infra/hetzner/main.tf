resource "hcloud_ssh_key" "admin" {
  name       = "${var.name}-admin"
  public_key = file(pathexpand(var.ssh_public_key_file))
}

# Open to everyone: HTTP (Let's Encrypt's check and the redirect) and HTTPS.
# SSH and the Kubernetes API only from your own addresses.
resource "hcloud_firewall" "game" {
  name = "${var.name}-firewall"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.admin_cidrs
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "6443"
    source_ips = var.admin_cidrs
  }
  rule {
    direction  = "in"
    protocol   = "icmp"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

# Postgres lives here (k3s local-path storage on /mnt/data), apart from the VM's
# own disk, so a rebuilt VM can take the same data back.
resource "hcloud_volume" "data" {
  name     = "${var.name}-data"
  size     = var.volume_size_gb
  location = var.location
  format   = "ext4"
}

resource "hcloud_server" "game" {
  name         = var.name
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [hcloud_ssh_key.admin.id]
  firewall_ids = [hcloud_firewall.game.id]
  user_data = templatefile("${path.module}/cloud-init.yaml", {
    volume_id   = hcloud_volume.data.id
    k3s_version = var.k3s_version
    api_host    = var.api_host
    swap_gb     = var.swap_gb
  })
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
  labels = {
    app = "flapjaw"
  }
  lifecycle {
    # cloud-init only runs on the first boot. A change to it never replaces the
    # VM by itself; rebuild on purpose: tofu apply -replace=hcloud_server.game
    ignore_changes = [user_data, ssh_keys]
  }
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.game.id
  automount = false
}
