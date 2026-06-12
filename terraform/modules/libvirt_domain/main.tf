resource "libvirt_domain" "domain" {
  name        = "${var.project_name}-${var.vm_name}"
  type        = "kvm"
  running     = true
  autostart   = true
  memory      = var.memory
  memory_unit = "MiB"
  vcpu        = var.vcpu

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  features = {
    acpi = true
    apic = {}
  }

  devices = {
    disks = concat([
      {
        source = {
          volume = {
            pool   = var.pool_name
            volume = var.volume_name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        boot = {
          order = 1
        }
      },
      {
        device    = "cdrom"
        read_only = true
        source = {
          file = {
            file = var.cloudinit_disk_path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        boot = {
          order = 2
        }
      }
      ],
      [
        for idx, volume_name in var.data_volume_names : {
          source = {
            volume = {
              pool   = var.pool_name
              volume = volume_name
            }
          }
          target = {
            dev = "vd${substr("bcdefghijklmnopqrstuvwxyz", idx, 1)}"
            bus = "virtio"
          }
          driver = {
            name = "qemu"
            type = "qcow2"
          }
        }
      ]
    )
    interfaces = [
      {
        source = {
          network = {
            network = var.network_name
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]
    serials = [
      {
        source = { vc = true }
        target = {
          port = 0
        }
        log = {
          file   = "/var/log/libvirt/qemu/${var.project_name}-${var.vm_name}-console.log"
          append = "on"
        }
      }
    ]
    consoles = [
      {
        source = { vc = true }
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]
  }
}
