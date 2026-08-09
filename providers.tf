terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.110.0" # https://registry.terraform.io/providers/bpg/proxmox/0.110.0/docs
    }
    talos = {
      source  = "siderolabs/talos"
      version = "0.11.0" # https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs
    }
    time = {
      source = "hashicorp/time"
      version = "0.14.0"
    }
    null = {
      source = "hashicorp/null"
      version = "3.3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "3.2.0" # https://registry.terraform.io/providers/hashicorp/helm/3.2.0/docs
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.0" # https://registry.terraform.io/providers/hashicorp/kubernetes/3.2.0/docs
    }

    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.19.0" # ">= 1.19.0" # https://registry.terraform.io/providers/gavinbunney/kubectl/1.19.0/docs
    }
  }
}

# Proveedor para la Mini PC 1
provider "proxmox" {
  alias    = "pmx01"
  endpoint = "https://192.168.0.10:8006/"
  api_token = var.pmx01_token
  insecure  = true # Ya que usamos certificados autofirmados

  ssh {
    agent       = false    # No usamos el ssh-agent local ya que especificaremos la ruta de la llave privada
    username    = "root"   # Usuario de Proxmox con acceso SSH
    private_key = file("~/.ssh/id_proxmox_terraform")
    # node {
    #   name    = "pmx01"
    #   address = "192.168.0.10"  # Opcional si el proveedor no logra resolver la IP del nodo
    # }
  }
}

# Proveedor para la Mini PC 2
provider "proxmox" {
  alias    = "pmx02"
  endpoint = "https://192.168.0.11:8006/"
  api_token = var.pmx02_token
  insecure  = true
  ssh {
    agent       = false    # No usamos el ssh-agent local ya que especificaremos la ruta de la llave privada
    username    = "root"   # Usuario de Proxmox con acceso SSH
    private_key = file("~/.ssh/id_proxmox_terraform")
    # node {
    #   name    = "pmx02"
    #   address = "192.168.0.11"  # Opcional si el proveedor no logra resolver la IP del nodo
    # }
  }
}
