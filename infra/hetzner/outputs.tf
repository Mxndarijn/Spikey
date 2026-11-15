output "ipv4" {
  description = "Point the DNS record for api_host (an A record) here."
  value       = hcloud_server.game.ipv4_address
}

output "ipv6" {
  description = "And an AAAA record here."
  value       = hcloud_server.game.ipv6_address
}

output "ssh" {
  value = "ssh root@${hcloud_server.game.ipv4_address}"
}

output "kubeconfig" {
  description = "Copies the cluster's kubeconfig to this PC (docs/DEPLOY.md, step 4)."
  value       = "scp root@${hcloud_server.game.ipv4_address}:/etc/rancher/k3s/k3s.yaml ./flapjaw.kubeconfig"
}
