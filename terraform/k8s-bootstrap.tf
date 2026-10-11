### INI: Código para Configurar el clúster automáticamente (CNI, Certificados, Cloudflare, Almacenamiento)

# Configuramos el Provider de Helm usando los datos en memoria
# Como usamos talos_cluster_kubeconfig.this, este provider se configurará después
# de generarse el archivo kubeconfig (por eso no necesitamos 'depends_on' aquí)
provider "helm" {
  kubernetes = {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    # https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/cluster_kubeconfig#nested-schema-for-client_configuration
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  }
}

# Configuramos el Provider de Helm usando los datos en memoria
provider "kubernetes" {
  # config_path = "./kubeconfig"
  # config_path = "~/.kube/config"
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  # https://registry.terraform.io/providers/siderolabs/talos/0.11.0/docs/resources/cluster_kubeconfig#nested-schema-for-client_configuration
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
}

# Configuramos el Provider de kubectl usando los datos en memoria
provider "kubectl" {
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
}





# YA NO NECESITAMOS APROBAR "MANUALMENTE" LOS CERTIFICADOS PORQUE VAMOS A INSTALAR kubelet-csr-approver
# resource "terraform_data" "approve_csrs_1" {
#   count = var.auto_config_cluster ? 1 : 0
#   # Con el 'always_run', se fuerza la recreación destructiva, es decir, Terraform destruirá y volverá a crear
#   # el recurso terraform_data en cada único apply, sin importar si el clúster cambió o no, esto con el objetivo
#   # de capturar nodos nuevos en cada apply.
#   # Sin embargo, como posteriormente vamos a instalar el chart de 'kubelet-csr-approver',
#   # este comportamiento ya no sería necesario.
#   # triggers_replace = {
#   #   always_run = timestamp()
#   # }

#   provisioner "local-exec" {
#     # Filtra CSRs pendientes y las aprueba sin romper el flujo si no hay ninguna
#     #command     = "kubectl get csr -o jsonpath='{range .items[?(@.status.conditions==null)]}{.metadata.name}{\"\\n\"}{end}' | xargs -r kubectl certificate approve"
#     command     = "kubectl get csr -o name | xargs -r kubectl certificate approve"
#     interpreter = ["/bin/bash", "-c"]

#     environment = {
#       KUBECONFIG = local.KUBECONFIG
#     }
#   }

#   depends_on = [time_sleep.wait_after_kubeconfig]
# }


# Esperamos un par de minutos después de hacer el bootstrap
resource "time_sleep" "wait_after_kubeconfig" {
  count = var.auto_config_cluster ? 1 : 0

  depends_on = [talos_cluster_kubeconfig.this]
  create_duration = "120s"
}




# Instalación de los CRDs de Gateway API
resource "terraform_data" "install_gateway_api_crds" {
  count = var.auto_config_cluster ? 1 : 0

  # Se ejecuta siempre o cuando cambie la versión de las URLs locales
  triggers_replace = {
    urls = join(",", values(local.gateway_api_urls))
  }

  provisioner "local-exec" {
    # Ejecuta un bucle apply directo sobre las URLs remotas secuencialmente
    command = <<EOT
      for url in ${join(" ", values(local.gateway_api_urls))}; do
        kubectl apply -f "$url"
      done
    EOT
    
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = local.KUBECONFIG
    }
  }

  depends_on = [time_sleep.wait_after_kubeconfig]
}



# Instalación del auto aprobador de certificados
resource "helm_release" "kubelet_csr_approver" {
  # Si la variable es true crea 1 instancia, si es false crea 0 (no se instala)
  count            = var.auto_config_cluster ? 1 : 0

  name             = "kubelet-csr-approver"
  repository       = "oci://ghcr.io/postfinance/charts"
  chart            = "kubelet-csr-approver"
  version          = "1.2.14"
  namespace        = "kube-system"
  create_namespace = false

  # Como aún no se ha instalado Cilium, este pod quedará en estado Pending
  # Por tanto, desactivamos la espera obligatoria del estado Running/Ready
  wait          = false
  wait_for_jobs = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/kubelet-csr-approver-values.yaml")
  ]

  # depends_on = [terraform_data.approve_csrs_1]
  depends_on = [time_sleep.wait_after_kubeconfig]
}


# YA NO NECESITAMOS RE-APROBAR "MANUALMENTE" LOS CERTIFICADOS PORQUE YA INSTALAMOS kubelet-csr-approver
# resource "time_sleep" "wait_after_install_kubelet_csr_approver" {
#   count = var.auto_config_cluster ? 1 : 0

#   depends_on = [helm_release.kubelet_csr_approver]
#   create_duration = "90s"
# }

# # Cuando se crea el clúster, a veces suelen crearsen nuevos certificados en medio, así que esperamos
# # un minuto después de instalar kubelet-csr-approver y volvemos a approbar los certificados
# resource "terraform_data" "approve_csrs_2" {
#   count = var.auto_config_cluster ? 1 : 0

#   provisioner "local-exec" {
#     # Filtra CSRs pendientes y las aprueba sin romper el flujo si no hay ninguna
#     #command     = "kubectl get csr -o jsonpath='{range .items[?(@.status.conditions==null)]}{.metadata.name}{\"\\n\"}{end}' | xargs -r kubectl certificate approve"
#     command     = "kubectl get csr -o name | xargs -r kubectl certificate approve"
#     interpreter = ["/bin/bash", "-c"]

#     environment = {
#       KUBECONFIG = local.KUBECONFIG
#     }
#   }

#   depends_on = [time_sleep.wait_after_install_kubelet_csr_approver]
# }



# Instalación de Cilium CNI
resource "helm_release" "cilium" {
  # Si la variable es true crea 1 instancia, si es false crea 0 (no se instala)
  count            = var.auto_config_cluster ? 1 : 0

  name             = "cilium"
  repository       = "https://helm.cilium.io"
  chart            = "cilium"
  version          = "1.18.0"
  namespace        = "kube-system"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/cilium-values.yaml")
  ]

  # depends_on = [terraform_data.approve_csrs_2]
  # depends_on = [time_sleep.wait_after_install_kubelet_csr_approver]
  depends_on = [helm_release.kubelet_csr_approver]
}


# Instalación de CoreDNS
resource "helm_release" "coredns" {
  # Si la variable es true crea 1 instancia, si es false crea 0 (no se instala)
  count            = var.auto_config_cluster ? 1 : 0

  name             = "coredns"
  repository       = "https://coredns.github.io/helm"
  chart            = "coredns"
  version          = "1.46.0"
  namespace        = "kube-system"
  create_namespace = false

  # CoreDNS necesita que la red de Cilium exista en el clúster para arrancar.
  wait             = true 
  wait_for_jobs    = true
  timeout          = 300

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/coredns-values.yaml")
  ]

  # Obligamos a que Cilium se aplique primero
  depends_on = [helm_release.cilium]
}


# Validación final de Hubble Relay.
# Como todos los pods de CoreDNS ya están Running (gracias al paso anterior), Hubble Relay se recuperará solo.
# Este bloque garantiza que todo esté al 100% antes de los siguientes pasos de Terraform.
# Este reinicio lo hacemos debido a que el hubble-relay de Cilium necesita que CoreDNS esté corriendo y con
# las configuraciones correctas. Por tanto, al reiniciar hubble-relay después de que CoreDNS ya esté Running
# garantizamos que este pod también quede en estado Running.
resource "terraform_data" "wait_for_cilium_hubble" {
  count = var.auto_config_cluster ? 1 : 0

  provisioner "local-exec" {
    command = "kubectl rollout status deployment/hubble-relay -n kube-system --timeout=5m"
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = local.KUBECONFIG
    }
  }

  depends_on = [helm_release.coredns]
}



# Configuración del Pool de IPs (Cilium)
resource "kubectl_manifest" "cilium_ip_pool" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/cilium-ip-pool.yaml")
  depends_on = [terraform_data.wait_for_cilium_hubble]
}

# Configuración del L2 Advertisement (Cilium)
resource "kubectl_manifest" "cilium_l2_policy" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/cilium-l2-policy.yaml")
  depends_on = [terraform_data.wait_for_cilium_hubble]
}



# Instalación de cert-manager
resource "helm_release" "cert_manager" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.21.0"
  namespace        = "cert-manager"
  create_namespace = true

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/cert-manager-values.yaml")
  ]

  # set {
  #   name  = "crds.enabled"
  #   value = "true"
  # }

  depends_on = [kubectl_manifest.cilium_ip_pool, kubectl_manifest.cilium_l2_policy]
}

# Instalación de trust-manager
resource "helm_release" "trust_manager" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "trust-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "trust-manager"
  version          = "0.24.0"
  namespace        = "cert-manager"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/trust-manager-values.yaml")
  ]

  depends_on = [helm_release.cert_manager]
}



# Creación del CA interno y su respectivo Issuer
# Como este yaml es multidocumento, usamos kubectl_file_documents
# Debemos cargarlo desde el principio (sin condicionales ni depender de ningún otro bloque), ya que de
# lo contrario, el for_each de kubectl_manifest.internal_ca no podrá planificarse
data "kubectl_file_documents" "docs_internal_ca" {
  #count      = var.auto_config_cluster ? 1 : 0
  content    = file("${local.k8s_path}/internal-ca.yaml")
  #depends_on = [helm_release.cert_manager]
}

# # Alternativa a kubectl_file_documents: Usar la función manifest_decode_multi
# output "example_output" {
#   value = provider::kubernetes::manifest_decode_multi(file("${local.k8s_path}/internal-ca.yaml"))
# }

resource "kubectl_manifest" "internal_ca" {
  # ¿Por qué no podemos usar 'count = var.auto_config_cluster ? 1 : 0' en este bloque?
  #
  # Veamos primero qué pasa cuando usamos 'for_each' y 'count' en un mismo bloque:
  # - Al usar por ejemplo 'for_each = data.kubectl_file_documents.docs_internal_ca.manifests', estamos
  #   indicando que vamos a recorrer un array de elementos, a los que vamos a acceder a través de 'each'.
  # - Si usamos 'count = var.auto_config_cluster ? 1 : 0', estamos indicando las veces que vamos a
  #   ejecutar este bloque, que por lo general, es una sola vez si se cumple cierta condición, o cero
  #   veces si no se cumple; es decir, estamos creando un array donde cada elemento es una ejecución.
  # - Esto quiere decir, que un 'for_each' en un bloque que usa un 'count' tiene que saber a qué elemento
  #   de esa lista de ejecuciones (determinadas por el count) corresponde un determinado recurso, que en
  #   caso de count=1 es la ejecución con índice 0, y por tanto, es al recurso de ese elemento que debemos
  #   acceder: 'data.kubectl_file_documents.docs_internal_ca[0].manifests', que sería similar a tener algo
  #   como 'data.kubectl_file_documents.docs_internal_ca[count - 1].manifests'.
  #
  # Por otro lado, el valor que se utiliza en el metaargumento for_each de Terraform debe conocerse por
  # completo durante la fase de planificación (terraform plan) antes de ejecutar los cambios. No puede
  # depender de atributos calculados o generados durante la aplicación (known after apply).
  #
  # Entonces, cuando count=1, significa que hay un bloque a ejecutar, y por tanto podemos obtener el valor
  # de 'data.kubectl_file_documents.docs_internal_ca[0].manifests', pero si count=0, no hay ningún bloque
  # a ejecutar (es como si tuviéramos 'data.kubectl_file_documents.docs_internal_ca[null].manifests)', y
  # por ende no se podría planificar el contenido que ejecutaría el for_each.
  #
  # Por esa razón, la validación de si debemos ejecutar o no este bloque, no la hacemos con un count
  # sino que la hacemos con el operadore ternario (?:); incluso, al tener este operador tenrnario, si
  # intentamos agregar el 'count', terraform nos responderá con este mensaje de error: 'The "count"
  # and "for_each" meta-arguments are mutually-exclusive, only one should be used to be explicit about
  # the number of resources to be created'
  for_each  = var.auto_config_cluster ? data.kubectl_file_documents.docs_internal_ca.manifests : {}
  yaml_body = each.value
  depends_on = [helm_release.cert_manager, data.kubectl_file_documents.docs_internal_ca]
}

# No usamos kubernetes_manifest para esto, porque no admite multidocumento
# resource "kubernetes_manifest" "internal_ca" {
#   manifest = yamldecode(
#     templatefile("${local.k8s_path}/internal-ca.yaml", {
#       domain_name = var.domain_name
#     })
#   )

#   depends_on = [helm_release.cert_manager]
# }


# Creamos el Trust Bundle
resource "kubectl_manifest" "trust_bundle" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/trust-bundle.yaml")
  depends_on = [helm_release.trust_manager]
}



# Creamos el Secret para el API Token de Cloudflare (Solo si se usa producción)
resource "kubernetes_secret_v1" "cloudflare_api_token_secret" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0
  metadata {
    name      = "cloudflare-api-token-secret"
    namespace = "cert-manager"
  }

  type = "Opaque"

  data = {
    "api-token" = var.cloudflare_api_token
  }

  depends_on = [helm_release.trust_manager]
}



# Creamos los ClusterIssuer para Let's Encript
# De Stage
resource "kubectl_manifest" "letsencrypt_stage_cluster_issuer" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0

  yaml_body = templatefile(
    "${local.k8s_path}/letsencrypt-stage-cluster-issuer.yaml",
    {
      PERSONAL_EMAIL           = var.personal_email
      CLOUDFLARE_ACCOUNT_EMAIL = var.cloudflare_account_email
    }
  )

  depends_on = [kubernetes_secret_v1.cloudflare_api_token_secret]
}

# De Producción
resource "kubectl_manifest" "letsencrypt_prod_cluster_issuer" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0

  yaml_body = templatefile(
    "${local.k8s_path}/letsencrypt-stage-cluster-issuer.yaml",
    {
      PERSONAL_EMAIL           = var.personal_email
      CLOUDFLARE_ACCOUNT_EMAIL = var.cloudflare_account_email
    }
  )

  depends_on = [kubernetes_secret_v1.cloudflare_api_token_secret]
}



# Creamos el Namespace gateway-api-system
resource "kubectl_manifest" "namespace_gateway_api_system" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/gateway-api-namespace.yaml")
  depends_on = [kubectl_manifest.letsencrypt_stage_cluster_issuer, kubectl_manifest.letsencrypt_prod_cluster_issuer]
}




# Creamos los Certificados internos y públicos que usará el Gateway para sus listeners HTTPS
# Local
resource "kubectl_manifest" "cert_gateway_local" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/cert-gateway-local.yaml")
  depends_on = [kubectl_manifest.namespace_gateway_api_system]
}

# Let's Encrypt
resource "kubectl_manifest" "cert_letsencrypt_public" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0

  # Lee el archivo y reemplaza la cadena según el valor de var.use_letsencrypt_prod
  yaml_body = replace(
    file("${local.k8s_path}/cert-letsencrypt-public.yaml"),
    "name: letsencrypt-stage-issuer",
    "name: ${var.use_letsencrypt_prod ? "letsencrypt-prod-issuer" : "letsencrypt-stage-issuer"}"
  )

  depends_on = [kubectl_manifest.namespace_gateway_api_system]
}



# Levantamos el Gateway
resource "kubectl_manifest" "external_gateway" {
  count = var.auto_config_cluster ? 1 : 0
  
  yaml_body = templatefile(
    "${local.k8s_path}/templates/gateway-api-external.yaml.tpl",
    {
      USE_PROD_DOMAIN = var.use_prod_domain
    }
  )
  
  depends_on = [kubectl_manifest.cert_gateway_local]
}



# Creamos el redireccionador http global para que redireccione a https
resource "kubectl_manifest" "global_http_redirect" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/global-http-redirect.yaml")
  depends_on = [kubectl_manifest.external_gateway]
}



# Configuración del agente clouflared para el túnel de Cloudflare
# 1. Creamos el namespace cloudflare-tunnel-system
resource "kubectl_manifest" "namespace_cloudflare_tunnel_system" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0
  yaml_body  = file("${local.k8s_path}/deployments/cloudflare-tunnel/namespace.yaml")
  depends_on = [kubectl_manifest.global_http_redirect]
}

# 2. Creamos el Secret para el Token del túnel de Cloudflare
resource "kubernetes_secret_v1" "cloudflare_tunnel_token_secret" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0
  metadata {
    name      = "cloudflare-tunnel-token-secret"
    namespace = "cloudflare-tunnel-system"
  }

  type = "Opaque"

  data = {
    "TUNNEL_TOKEN" = var.cloudflare_tunnel_token
  }

  depends_on = [kubectl_manifest.namespace_cloudflare_tunnel_system]
}

# 3. Levantamos el agente de cloudflared
resource "kubectl_manifest" "cloudflared_agent" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0
  yaml_body  = file("${local.k8s_path}/deployments/cloudflare-tunnel/deployment.yaml")
  depends_on = [kubernetes_secret_v1.cloudflare_tunnel_token_secret]
}



# Configuración del almacenamiento con OpenEBS
# Instalamos OpenEBS
resource "helm_release" "openebs" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "openebs"
  repository       = "https://openebs.github.io/openebs"
  chart            = "openebs"
  version          = "4.5.1"
  namespace        = "openebs"
  create_namespace = true

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/openebs-values.yaml")
  ]

  depends_on = [kubectl_manifest.cloudflared_agent]
}




# Configuración del TokenReviewer para Vault
# 1. Creamos el namespace external_auth
resource "kubectl_manifest" "namespace_external_auth" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/external-auth-namespace.yaml")
  depends_on = [helm_release.openebs]
}

# El resource kubernetes_manifest está diseñado no solo para manejar YAMLs genéricos, sino también CRDS,
# por lo tanto fuerza al proveedor a iniciar un cliente REST para consultar al clúster durante el plan.
# Por esa razón, no puede usarse en el mismo plan donde se hace el bootstrap del clúster (con Talos), ya
# que en esta instancia aún no hay un clúster de kubernetes existente.
# resource "kubernetes_manifest" "vault_token_reviewer" {
#   for_each = { for manifest in provider::kubernetes::manifest_decode_multi(file("${local.k8s_path}/vault-token-reviewer-setup.yaml")) : "${lower(manifest.kind)}-${manifest.metadata.name}" => manifest }
#   manifest = each.value
#   depends_on = [kubectl_manifest.namespace_external_auth]
# }

# Esta es otra alternativa
# variable "empty_string_set" {
#   type    = set(string)
#   default = []
# }
# resource "kubectl_manifest" "vault_token_reviewer" {
#   for_each   = var.auto_config_cluster ? toset(split("---", file("${local.k8s_path}/vault-token-reviewer-setup.yaml"))) : var.empty_string_set
#   yaml_body  = each.value
#   depends_on = [kubectl_manifest.namespace_external_auth]
# }

# 2. Aplicamos el manifiesto de configuración del TokenReviewer
data "kubectl_file_documents" "files_vault_token_reviewer_setup" {
  content    = file("${local.k8s_path}/tf-vault-token-reviewer-setup-without-secret.yaml")
}

resource "kubectl_manifest" "vault_token_reviewer_setup" {
  for_each   = var.auto_config_cluster ? data.kubectl_file_documents.files_vault_token_reviewer_setup.manifests : {}
  yaml_body  = each.value
  depends_on = [kubectl_manifest.namespace_external_auth, data.kubectl_file_documents.files_vault_token_reviewer_setup]
}

# Debemos crear el Secreto por separado, ya que cuando se aplica un secreto con la anotación kubernetes.io/service-account.name,
# como es el caso del TokenReviewer, la API de Kubernetes o un controlador interno modifica, vacía o muta el objeto de inmediato,
# o en ocasiones lo rechaza/elimina si la ServiceAccount asociada no está completamente lista en el microsegundo en que se crea
# el secreto. Al cambiar drásticamente el estado del recurso justo después de crearse, el proveedor de Terraform se confunde,
# piensa que el objeto desapareció o mutó ilegalmente, y lanza un error.
# Por eso gestionamos el Secret directamente con el proveedor oficial de Kubernetes de Terraform (hashicorp/kubernetes).
# Este proveedor maneja mucho mejor el ciclo de vida y los reintentos de los tokens.
# Este bloque creará el secreto de forma segura y esperará a que 
# Kubernetes inyecte el token sin romper el estado de Terraform.
resource "kubernetes_secret_v1" "vault_token_reviewer_secret" {
  count = var.auto_config_cluster ? 1 : 0

  metadata {
    name      = "vault-token-reviewer-secret"
    namespace = "external-auth"
    annotations = {
      "kubernetes.io/service-account.name" = "vault-token-reviewer-sa"
    }
  }

  type = "kubernetes.io/service-account-token"

  # Espera a que el ServiceAccount sea creado por el loop de kubectl_manifest
  depends_on = [kubectl_manifest.vault_token_reviewer_setup]
}




# Configuración del TokenReviewer en Vault
# 1. Buscamos el método de autenticación ya existente
data "vault_auth_backend" "eljavatar_k8s_kubernetes" {
  count      = var.auto_config_cluster ? 1 : 0
  path       = "eljavatar_k8s/kubernetes"
  depends_on = [kubernetes_secret_v1.vault_token_reviewer_secret]
}

# Si queremos leer un Secreto ya existente.
# En este caso no lo hacemos ya que creamos el recurso desde este mismo Script
# data "kubernetes_secret_v1" "vault_token_reviewer" {
#   count = var.auto_config_cluster ? 1 : 0
#   metadata {
#     name      = "vault-token-reviewer-secret"
#     namespace = "external-auth"
#   }
#   depends_on = [kubectl_manifest.vault_token_reviewer_setup]
# }

# 2. Escribimos la configuración en Vault (Equivalente al 'vault write auth/eljavatar_k8s/kubernetes/config')
resource "vault_kubernetes_auth_backend_config" "eljavatar_k8s_config" {
  count                = var.auto_config_cluster ? 1 : 0
  backend              = data.vault_auth_backend.eljavatar_k8s_kubernetes[0].path # count.index
  # backend              = "eljavatar_k8s/kubernetes"
  kubernetes_host      = local.cluster_endpoint
  
  # El proveedor de Kubernetes en Terraform ya decodifica el base64 automáticamente
  kubernetes_ca_cert   = kubernetes_secret_v1.vault_token_reviewer_secret[0].data["ca.crt"]
  token_reviewer_jwt   = kubernetes_secret_v1.vault_token_reviewer_secret[0].data["token"]
  disable_local_ca_jwt = false # Opcional: por defecto según el caso de uso

  # Habilitar los metadatos de las anotaciones
  use_annotations_as_alias_metadata = true

  depends_on = [data.vault_auth_backend.eljavatar_k8s_kubernetes, kubernetes_secret_v1.vault_token_reviewer_secret]
}




# Configuración el CronJob que actualiza automáticamente en el clúster el certificado TLS del servidor de Vault
# 1. Creamos los namespaces
resource "kubectl_manifest" "namespace_ops_shared" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/shared-ops-namespace.yaml")
  depends_on = [vault_kubernetes_auth_backend_config.eljavatar_k8s_config]
}

resource "kubectl_manifest" "namespace_eso" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/eso-namespace.yaml")
  depends_on = [vault_kubernetes_auth_backend_config.eljavatar_k8s_config]
}

resource "kubectl_manifest" "namespace_vso" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/vso-namespace.yaml")
  depends_on = [vault_kubernetes_auth_backend_config.eljavatar_k8s_config]
}

# 2. Creamos los permisos mediante RBAC
data "kubectl_file_documents" "files_vault_cert_syncer_rbac" {
  content    = file("${local.k8s_path}/vault-cert-syncer-rbac.yaml")
}

resource "kubectl_manifest" "vault_cert_syncer_rbac" {
  for_each   = var.auto_config_cluster ? data.kubectl_file_documents.files_vault_cert_syncer_rbac.manifests : {}
  yaml_body  = each.value
  depends_on = [
    kubectl_manifest.namespace_ops_shared,
    kubectl_manifest.namespace_eso,
    kubectl_manifest.namespace_vso,
    data.kubectl_file_documents.files_vault_cert_syncer_rbac
  ]
}

# 3. Creamos el CronJob
resource "kubectl_manifest" "vault_cert_syncer_cronjob" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/deployments/vault-cert-syncer-cronjob.yaml")
  depends_on = [kubectl_manifest.vault_cert_syncer_rbac]
}

# 4. Hacemos una primera ejecución del Job
# Las ejecuciones en terminal las usamos si no queremos que Terraform gestione el ciclo de
# vida de un recurso, como lo es el caso de este Job que solo nos interesa que se ejecute
# una vez cuando se hace el bootstrap del cluster
resource "terraform_data" "first_sync_vault_cert_manual" {
  count = var.auto_config_cluster ? 1 : 0

  # Re-ejecuta el comando si el CronJob cambia o se recrea
  triggers_replace = {
    cronjob_id = kubectl_manifest.vault_cert_syncer_cronjob[0].id
  }

  provisioner "local-exec" {
    # Añadimos validación '--ignore-not-found' para evitar que falle si el Job ya existe
    #command = "kubectl create job first-sync-vault-cert-manual --from=cronjob/sync-vault-cert -n shared-ops"
    command = "kubectl delete job first-sync-vault-cert-manual -n shared-ops --ignore-not-found && kubectl create job first-sync-vault-cert-manual --from=cronjob/sync-vault-cert -n shared-ops"
    interpreter = ["/bin/bash", "-c"]

    environment = {
      KUBECONFIG = local.KUBECONFIG
    }
  }

  depends_on = [kubectl_manifest.vault_cert_syncer_cronjob]
}




# Instalación de ESO
resource "helm_release" "eso" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = "2.9.0"
  namespace        = "external-secrets"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/eso-values.yaml")
  ]

  depends_on = [terraform_data.first_sync_vault_cert_manual]
}



# Instalación y Configuración de VSO
resource "helm_release" "vso" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "vault-secrets-operator"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault-secrets-operator"
  version          = "1.5.1"
  namespace        = "vault-secrets-operator"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/vso-values.yaml")
  ]

  depends_on = [terraform_data.first_sync_vault_cert_manual]
}

# Configuración del VaultConnection (de VSO)
resource "kubectl_manifest" "vso_vault_connection" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/vso-vault-connection.yaml")
  depends_on = [helm_release.vso]
}

# Configuración del VaultAuthGlobal (de VSO)
resource "kubectl_manifest" "vso_vault_auth_global" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${local.k8s_path}/vso-vault-auth-global.yaml")
  depends_on = [kubectl_manifest.vso_vault_connection]
}



# Instalación de Argo Rollouts
resource "helm_release" "argo_rollouts" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = "2.43.6"
  namespace        = "argo-rollouts"
  create_namespace = true

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/argo-rollouts-values.yaml")
  ]

  depends_on = [kubectl_manifest.vso_vault_auth_global]
}



# Instalación de Reloader
resource "helm_release" "reloader" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "reloader"
  repository       = "https://stakater.github.io/stakater-charts"
  chart            = "reloader"
  version          = "2.2.17"
  namespace        = "reloader"
  create_namespace = true

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/reloader-values.yaml")
  ]

  depends_on = [helm_release.argo_rollouts]
}



# Instalación de Descheduler
resource "helm_release" "descheduler" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "descheduler"
  repository       = "https://kubernetes-sigs.github.io/descheduler/"
  chart            = "descheduler"
  version          = "0.36.0"
  namespace        = "kube-system"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/descheduler-values.yaml")
  ]

  depends_on = [helm_release.reloader]
}



# Instalación de Metrics Server
resource "helm_release" "metrics_server" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "metrics-server"
  repository       = "https://kubernetes-sigs.github.io/metrics-server/"
  chart            = "metrics-server"
  version          = "3.13.1"
  namespace        = "kube-system"
  create_namespace = false

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/metrics-server-values.yaml")
  ]

  depends_on = [helm_release.descheduler]
}



# Instalación del OpenFeature Operator
# Requiere cert-manager (ya instalado) para los certificados del webhook de admisión
resource "helm_release" "open_feature_operator" {
  count            = var.auto_config_cluster ? 1 : 0

  name             = "open-feature-operator"
  repository       = "https://open-feature.github.io/open-feature-operator"
  chart            = "open-feature-operator"
  version          = "0.9.3"
  namespace        = "open-feature-operator-system"
  create_namespace = true

  wait          = true
  wait_for_jobs = false
  timeout       = 300

  # Carga el archivo de valores externo
  values = [
    file("${local.k8s_path}/deployments/open-feature-values.yaml")
  ]

  depends_on = [helm_release.cert_manager, helm_release.metrics_server]
}

### END: Código para Configurar el clúster automáticamente (CNI, Certificados, Cloudflare, Almacenamiento)
