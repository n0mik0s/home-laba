resource "libvirt_pool" "pool" {
  name = "${var.project_name}-libvirt_pool"
  type = "dir"
  target = {
    path = "${var.pool_path}/${var.project_name}"
  }
}
