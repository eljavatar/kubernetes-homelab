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
    vault = {
      source  = "hashicorp/vault"
      version = "5.11.0" # https://registry.terraform.io/providers/hashicorp/vault/5.11.0/docs
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

# Proveedor para Vault
# https://registry.terraform.io/providers/hashicorp/vault/latest/docs
provider "vault" {
  # Dirección y token de Vault (generalmente se pasan por variables de entorno VAULT_ADDR y VAULT_TOKEN)
  # En este caso las definimos desde aquí mismo
  address = "https://192.168.0.20:8200"
  # Lo ideal en entornos productivos, es que el token suministrado no sea un token de administrador,
  # o incluso tener habilitados otros métodos de autenticación (como por ejemplo usuario y contraseña)
  # con permisos restringidos a únicamente lo que puede hacer el usuario que quiera acceder a Vault.
  token = var.vault_token
  token_name = "terraform_token" # Nombre del token intermedio que crea Terraform
  max_lease_ttl_seconds = 1800   # Tiempo de vida del token intermedio (por defecto son 20 minutos)
  # Si usamos un token de administrador, lo ideal es asegurarnos de que skip_child_token esté en true,
  # ya que de este modo Terraform emitirá un nuevo token que será hijo del proporcionado, y con un TTL
  # corto para limitar la exposición de cualquier secreto solicitado.
  # Al usar 'skip_child_token=true', debemos asegurarnos que el token que usemos tenga una política
  # asignada por permisos de "read" sobre el path "auth/token/lookup-self" y permisos de "update"
  # sobre el path "auth/token/create"
  skip_child_token = false
  # Por el momento, omitimos la verificación TLS, pero en entornos productivos se debería
  # usar el certificado TLS emitido por el servidor de Vault (en nuestro caso, el del LXC
  # que exponemos en la ruta hhtp://192.168.0.20/certs/vault.crt)
  skip_tls_verify = true
  # ca_cert_file = "path/vault.crt"
}
