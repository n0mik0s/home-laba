resource "libvirt_network" "network" {
  name      = var.project_name
  autostart = true

  forward = {
    mode = "bridge"
  }

  bridge = {
    name = var.bridge_name
  }
}
