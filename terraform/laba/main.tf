module "libvirt_network" {
  source       = "../modules/libvirt_network"
  project_name = var.project_name
  bridge_name  = var.bridge_name
}

module "libvirt_pool" {
  source       = "../modules/libvirt_pool"
  project_name = var.project_name
  pool_path    = var.pool_path
}

module "libvirt_volume_base" {
  source       = "../modules/libvirt_volume"
  project_name = var.project_name
  vm_name      = "ubuntu-noble-base"
  pool         = module.libvirt_pool.name
  source_url   = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

module "libvirt_volume" {
  for_each         = var.vms
  source           = "../modules/libvirt_volume"
  project_name     = var.project_name
  vm_name          = each.key
  pool             = module.libvirt_pool.name
  base_volume_path = module.libvirt_volume_base.path
  capacity         = each.value.disk_size_gb
}

locals {
  # Flatten {vm_name => [data_disks]} into a map keyed by "<vm_name>-data<index>"
  # so each extra disk gets its own libvirt_volume resource.
  vm_data_disks = merge([
    for vm_key, vm in var.vms : {
      for idx, disk in vm.data_disks :
      "${vm_key}-data${idx}" => { vm_key = vm_key, capacity = disk.size_gb }
    }
  ]...)
}

module "libvirt_volume_data" {
  for_each     = local.vm_data_disks
  source       = "../modules/libvirt_volume"
  project_name = var.project_name
  vm_name      = each.key
  pool         = module.libvirt_pool.name
  capacity     = each.value.capacity
}

module "libvirt_cloudinit_disk" {
  for_each     = var.vms
  source       = "../modules/libvirt_cloudinit_disk"
  project_name = var.project_name
  vm_name      = each.key

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    hostname       = each.key
    domain_name    = var.domain_name
    admin_user     = var.admin_user
    ssh_public_key = var.ssh_public_key
    data_disks     = local.vm_data_disk_mounts[each.key]
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    network_interface = each.value.network_interface
    ip_address        = each.value.ip_address
    gateway           = each.value.gateway
    dns               = each.value.dns
    domain_name       = var.domain_name
  })
}

locals {
  # Per-VM list of {device, mount_point, fs_type, label} for cloud-init fs_setup/mounts,
  # using the same vdb, vdc, ... ordering as libvirt_domain's data_volume_names.
  vm_data_disk_mounts = {
    for vm_key, vm in var.vms : vm_key => [
      for idx, disk in vm.data_disks : {
        device      = "/dev/vd${substr("bcdefghijklmnopqrstuvwxyz", idx, 1)}"
        format      = disk.format
        mount_point = disk.mount_point
        fs_type     = disk.fs_type
        label       = "data${idx}"
      }
    ]
  }
}

module "libvirt_domain" {
  for_each            = var.vms
  source              = "../modules/libvirt_domain"
  project_name        = var.project_name
  vm_name             = each.key
  vcpu                = each.value.vcpu
  memory              = each.value.memory
  pool_name           = module.libvirt_pool.name
  volume_name         = module.libvirt_volume[each.key].name
  network_name        = module.libvirt_network.network_name
  cloudinit_disk_path = module.libvirt_cloudinit_disk[each.key].path

  data_volume_names = [
    for idx in range(length(each.value.data_disks)) :
    module.libvirt_volume_data["${each.key}-data${idx}"].name
  ]
}
