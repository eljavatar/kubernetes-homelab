variable "pmx01_token" {
  type      = string
  sensitive = true # Evita que el token se imprima en los logs de la consola
}

variable "pmx02_token" {
  type      = string
  sensitive = true
}

variable "vault_token" {
  type      = string
  sensitive = true
}

variable "personal_email" {
  type        = string
  description = "Correo electrónico personal para alertas de vencimiento de Let's Encrypt"
}

variable "cloudflare_account_email" {
  type        = string
  description = "Correo electrónico asociado a la cuenta de Cloudflare"
}

variable "cloudflare_api_token" {
  type        = string
  description = "API Token con permisos Zone.DNS:Edit para el desafío DNS-01"
  sensitive   = true
  ephemeral   = true # Evita que la variable se guarde en otros lugares del estado
}

variable "cloudflare_tunnel_token" {
  type        = string
  description = "Token del túnel de Cloudflare"
  sensitive   = true
  ephemeral   = true # Evita que la variable se guarde en otros lugares del estado
}

variable "use_local_iso" {
  type        = bool
  default     = false
  description = "Fuerza el uso de la ISO local si no hay internet o el sitio de Talos Factory está caído"
}

variable "is_development" {
  type        = bool
  default     = false
  description = "Si es true, el clúster arranca en modo permisivo (Desarrollo). Si es false, activa el perfil estricto 'baseline' por defecto (Producción)."
}

variable "auto_config_cluster" {
  type        = bool
  default     = true
  description = "Define si se auto-configura el clúster después de hacer el bootstrap o no"
}

variable "sync_with_tf" {
  type        = bool
  default     = false
  description = "Define si un componente se debe gestionar con Terraform o no; en caso de que no, debería ser instalado manualmente, ó gestionado con GitOps"
}

variable "gitops_branch" {
  type        = string
  default     = "main"
  description = "Rama del repositorio GitOps que sincroniza la Application raíz (main en producción, test/<tema> en pruebas)"
}

variable "use_prod_domain" {
  type        = bool
  default     = true
  description = "Si es true, usa el dominio real con Cloudflare DNS-01. Si es false, usa los certificados locales self-signed"
}

variable "use_letsencrypt_prod" {
  type        = bool
  default     = false
  description = "Si es true, crea el Certificando usando el ambiente productivo de Let's Encrypt. Si es false, usa el ambiente de Stage"
}

# variable "domain_name" {
#   type        = string
#   description = "The domain name to use (e.g., eljavatar.org)"
#   default     = "eljavatar.home"
# }
