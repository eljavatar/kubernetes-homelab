terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.110.0" }
    talos   = { source = "siderolabs/talos", version = "0.11.0" }
    time    = { source = "hashicorp/time", version = "0.14.0" }
    local   = { source = "hashicorp/local", version = ">= 2.0.0" }
  }
}
