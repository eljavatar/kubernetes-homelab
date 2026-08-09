### INI: Código para Levantar VMs con Talos configuradas desde el arranque y Bootstrap automático

# Generar los secretos del cluster (CA, tokens, etc.) (solo se hace una vez para todo el cluster)
resource "talos_machine_secrets" "this" {}


# -------------------------------------------------------------------
# MINI PC 1 (pmx-01) - Control Planes 1 y 2, Workers: Data y Apps
# -------------------------------------------------------------------
module "talos_pmx01" {
  source = "./modules/talos-node"
  providers = {
    proxmox = proxmox.pmx01
  }
  node_name            = "pmx-01"
  node_ip              = "192.168.0.10"
  vms                  = local.vms_pmx01
  use_local_iso        = var.use_local_iso
  is_development       = var.is_development
  cluster_name         = local.cluster_name
  cluster_vip          = local.cluster_vip
  cluster_endpoint     = local.cluster_endpoint
  iso_url              = local.talos_iso_url
  iso_name             = local.talos_iso_name
  install_image        = local.talos_install_image
  local_iso            = local.talos_local_iso
  network_cidr         = local.network_cidr
  network_gateway      = local.network_gateway
  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
}

# -------------------------------------------------------------------
# MINI PC 2 (pmx-02) - Control Plane 3, Workers: Heavy y Ops
# -------------------------------------------------------------------
module "talos_pmx02" {
  source = "./modules/talos-node"
  providers = {
    proxmox = proxmox.pmx02
  }
  node_name            = "pmx-02"
  node_ip              = "192.168.0.11"
  vms                  = local.vms_pmx02
  use_local_iso        = var.use_local_iso
  is_development       = var.is_development
  cluster_name         = local.cluster_name
  cluster_vip          = local.cluster_vip
  cluster_endpoint     = local.cluster_endpoint
  iso_url              = local.talos_iso_url
  iso_name             = local.talos_iso_name
  install_image        = local.talos_install_image
  local_iso            = local.talos_local_iso
  network_cidr         = local.network_cidr
  network_gateway      = local.network_gateway
  machine_secrets      = talos_machine_secrets.this.machine_secrets
  client_configuration = talos_machine_secrets.this.client_configuration
}


# --- BOOTSTRAP Y ARCHIVOS DE ACCESO ---

resource "time_sleep" "wait_for_cp_talos" {
  # Depende directamente de que la VM del Control Plane principal esté creada y encendida
  #depends_on = [proxmox_virtual_environment_vm.talos_pmx01]
  depends_on = [module.talos_pmx01, module.talos_pmx02]
  create_duration = "150s" # En caso de ser necesario, aumentar este valor a 180 ó más segundos
}

# Indica a Terraform que ejecute el 'bootstrap' en el CP principal
resource "talos_machine_bootstrap" "this" {
  # Asegura que primero se haya encendido la VM del Control Plane principal
  # depends_on           = [talos_machine_configuration_apply.this]
  depends_on           = [time_sleep.wait_for_cp_talos]
  client_configuration = talos_machine_secrets.this.client_configuration
  # En el bootstrap no usamos la vip del cluster, ya que en este punto, los servicios internos de Talos no han
  # inicializado la IP Virtual, y por tanto debemos apuntar obligatoriamente a la IP física real del nodo que
  # elegimos como primer Control Plane
  node                 = local.primary_cp_ip # La IP del Control Plane inicial
}

# No usamos vamos a usar el talos_cluster_health ya que al desactivar el CNI por defecto (puesto que después
# configuraremos Cilium), el health no pasará y se quedará esperando indefinidamente hasta que venza el timeout.
# En caso de usar el CNI por defecto (Flannel), si podríamos habilitar la ejecución del health.
# # Equivalente al comando manual 'talosctl health', bloqueando la ejecución de Terraform hasta que todos
# # los componentes críticos del clúster (etcd, apiserver, kubelet, etc.) reporten un estado saludable
# # Al ver los logs en la Consola de la VM del control plane principal, es posible que se vean errores,
# # sin embargo, al finalizar aparecerá un mensaje que dice: '[talos] machine is running and ready'
# data "talos_cluster_health" "boostrap_health" {
#   # Forzamos a que espere a que termine el bootstrap obligatoriamente
#   depends_on = [talos_machine_bootstrap.this]
#   client_configuration = talos_machine_secrets.this.client_configuration
  
#   # Especificamos qué nodos queremos auditar (Típicamente los Control Planes)
#   endpoints           = [local.primary_cp_ip]
#   control_plane_nodes = [for k, v in local.vms : v.ip if v.is_cp]
#   worker_nodes        = [for k, v in local.vms : v.ip if !v.is_cp]

#   # Configuración de tiempos de espera para que Terraform no tire un timeout prematuro
#   timeouts = {
#     read = "10m" # Le da hasta 5 minutos al clúster para consolidarse y pasar los checks
#   }
# }

# Esperamos unos segundos después del boostrap para generar el kubeconfig
resource "time_sleep" "wait_after_boostrap" {
  depends_on = [talos_machine_bootstrap.this]
  create_duration = "10s"
}

# Recupera el kubeconfig de manera segura
resource "talos_cluster_kubeconfig" "this" {
  # Dependemos del boostrap, no del Health Check, ya que al desactivar el CNI por defecto (cni: name: none),
  # los nodos del clúster entrarán en estado NotReady.
  # Kubernetes necesita un CNI para asignar IPs a los pods y levantar componentes críticos como coredns.
  # Como coredns se quedará en estado Pending, el plano de control nunca se considerará completamente
  # "saludable" y talos_cluster_health se quedará esperando eternamente hasta lanzar un error por timeout.
  # Es por esa razón que no dependemos del Health aquí, ya que necesitamos el kubeconfig para instalar
  # el CNI vía Helm
  depends_on           = [time_sleep.wait_after_boostrap]
  client_configuration = talos_machine_secrets.this.client_configuration
  # node                 = local.primary_cp_ip
  node                 = local.cluster_vip
}

# Guarda el archivo kubeconfig en el entorno local para usarlo con kubectl
resource "local_file" "kubeconfig" {
  content  = resource.talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${path.module}/talos/kubeconfig"
}


# Extraer el archivo talosconfig generado por el provider
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  #endpoints            = [local.primary_cp_ip] # La IP del Control Plane principal
  # El endpoint es la dirección a la que el cliente talosctl envía las peticiones de la API. Si configuramos
  # aquí la IP Virtual (192.168.0.25), garantizamos que siempre podremos administrar la API de Talos (revisar
  # logs, reiniciar servicios del OS, etc.) incluso si el nodo cp-01 se apaga físicamente en Proxmox.
  endpoints            = [local.cluster_vip] # La IP del Virtual del clúster
  # El parámetro node le indica a talosctl la máquina física/virtual específica a la que le queremos mandar
  # un comando de bajo nivel (como un reboot o un desensamblado de discos). Si ponemos la VIP ahí, estaríamos
  # apuntando a un nodo flotante impredecible. Para operaciones de mantenimiento con talosctl, debemos
  # especificar la IP física real del nodo en cuestión o pasarla directamente en el comando usando el
  # flag -n 192.168.0.31 (o la IP de cualquier otro nodo).
  nodes                = [local.primary_cp_ip] # NO debe usar la VIP
}

# Escribir físicamente el archivo talosconfig en la carpeta './talos/'
resource "local_file" "talosconfig" {
  content  = data.talos_client_configuration.this.talos_config
  filename = "${path.module}/talos/talosconfig"
}


# --- EXTRACCIÓN DE CONFIGURACIONES BASE (CONTROLPLANE Y WORKER) ---
# El archivo controlplane.yaml generado aquí equivale exactamente al que se obtiene con 'talosctl gen config'.
# Sin embargo, los parches de red (IP fija, Gateway y Hostname) se aplican dinámicamente en vivo a través del
# recurso talos_machine_configuration_apply.
# Por lo tanto, los archivos extraídos en la carpeta ./talos/ serán las plantillas base del cluster listas para
# ser usadas con cualquier nodo de su tipo respectivo.

# Forzamos la generación de una config base limpia para Controlplane y Worker
data "talos_machine_configuration" "base_controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version
}

data "talos_machine_configuration" "base_worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version
}

# Guardamos el archivo controlplane.yaml base
resource "local_file" "controlplane_yaml" {
  #content  = values(data.talos_machine_configuration.this)[0].machine_configuration
  content  = data.talos_machine_configuration.base_controlplane.machine_configuration
  filename = "${path.module}/talos/controlplane.yaml"
}

# Guardamos el archivo worker.yaml base
resource "local_file" "worker_yaml" {
  content  = data.talos_machine_configuration.base_worker.machine_configuration
  filename = "${path.module}/talos/worker.yaml"
}

### END: Código para Levantar VMs con Talos configuradas desde el arranque y Bootstrap automático



### INI: Código para Configurar el clúster automáticamente (CNI, Certificados, Cloudflare, Almacenamiento)

# Configuramos el Provider de Helm usando los datos en memoria
# Como usamos talos_cluster_kubeconfig.this, este provider se configurará después
# de generarse el archivo kubeconfig
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
    file("${path.module}/k8s/deployments/kubelet-csr-approver-values.yaml")
  ]

  # depends_on = [terraform_data.approve_csrs_1]
  depends_on = [time_sleep.wait_after_kubeconfig]
}


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
    file("${path.module}/k8s/deployments/cilium-values.yaml")
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
    file("${path.module}/k8s/deployments/coredns-values.yaml")
  ]

  # Obligamos a que Cilium se aplique primero
  depends_on = [helm_release.cilium]
}


# Validación final de Hubble Relay.
# Como todos los pods de CoreDNS ya están Running (gracias al paso anterior), Hubble Relay se recuperará solo.
# Este bloque garantiza que todo esté al 100% antes de los siguientes pasos de Terraform.
# Esto reinicio lo hacemos debido a que el hubble-relay de Cilium necesita que CoreDNS esté corriendo y con
# las configuraciones correctas. Por tanto, al reiniciar hubble-relay después de que CoreDNS ya esté Running
# garantizamos que este pod también quede en estado Running.
resource "terraform_data" "wait_for_hubble" {
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
  yaml_body  = file("${path.module}/k8s/cilium-ip-pool.yaml")
  depends_on = [terraform_data.wait_for_hubble]
}

# Configuración del L2 Advertisement (Cilium)
resource "kubectl_manifest" "cilium_l2_policy" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${path.module}/k8s/cilium-l2-policy.yaml")
  depends_on = [terraform_data.wait_for_hubble]
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
    file("${path.module}/k8s/deployments/cert-manager-values.yaml")
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
    file("${path.module}/k8s/deployments/trust-manager-values.yaml")
  ]

  depends_on = [helm_release.cert_manager]
}



# Creación del CA interno y su respectivo Issuer
# Como este yaml es multidocumento, usamos kubectl_file_documents
# Debemos cargarlo desde el principio (sin condicionales ni depender de ningún otro bloque), ya que de
# lo contrario, el for_each de kubectl_manifest.internal_ca no podrá planificarse
data "kubectl_file_documents" "docs_internal_ca" {
  #count      = var.auto_config_cluster ? 1 : 0
  content    = file("${path.module}/k8s/internal-ca.yaml")
  #depends_on = [helm_release.cert_manager]
}

# # Alternativa: Usar la función manifest_decode_multi
# output "example_output" {
#   value = provider::kubernetes::manifest_decode_multi(file("${path.module}/k8s/internal-ca.yaml"))
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
  #   acceder data.kubectl_file_documents.docs_internal_ca[0].manifests que sería similar a tener algo como
  #   data.kubectl_file_documents.docs_internal_ca[count - 1].manifests.
  #
  # Por otro lado, el valor que se utiliza en el metaargumento for_each de Terraform debe conocerse por
  # completo durante la fase de planificación (terraform plan) antes de ejecutar los cambios. No puede
  # depender de atributos calculados o generados durante la aplicación (known after apply).
  #
  # Entonces, cuando count=1, significa que hay un bloque a ejecutar, y por tanto podemos obtener el valor
  # de data.kubectl_file_documents.docs_internal_ca[0].manifests, pero si count=0, no hay ningún bloque
  # a ejecutar (es como si tuviéramos data.kubectl_file_documents.docs_internal_ca[null].manifests), y por
  # ende no se podría planificar el contenido que ejecutaría el for_each.
  for_each  = var.auto_config_cluster ? data.kubectl_file_documents.docs_internal_ca.manifests : {}
  yaml_body = each.value
  depends_on = [helm_release.cert_manager, data.kubectl_file_documents.docs_internal_ca]
}

# No usamos kubernetes_manifest poruq eno admite multidocumento
# resource "kubernetes_manifest" "internal_ca" {
#   manifest = yamldecode(
#     templatefile("${path.module}/k8s/internal-ca.yaml", {
#       domain_name = var.domain_name
#     })
#   )

#   depends_on = [helm_release.cert_manager]
# }


# Creamos el Trust Bundle
resource "kubectl_manifest" "trust_bundle" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${path.module}/k8s/trust-bundle.yaml")
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
    "${path.module}/k8s/letsencrypt-stage-cluster-issuer.yaml",
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
    "${path.module}/k8s/letsencrypt-stage-cluster-issuer.yaml",
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
  yaml_body  = file("${path.module}/k8s/gateway-api-namespace.yaml")
  depends_on = [kubectl_manifest.letsencrypt_stage_cluster_issuer, kubectl_manifest.letsencrypt_prod_cluster_issuer]
}




# Creamos los Certificados internos y públicos que usará el Gateway para sus listeners HTTPS
# Local
resource "kubectl_manifest" "cert_gateway_local" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${path.module}/k8s/cert-gateway-local.yaml")
  depends_on = [kubectl_manifest.namespace_gateway_api_system]
}

# Let's Encrypt
resource "kubectl_manifest" "cert_letsencrypt_public" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0

  # Lee el archivo y reemplaza la cadena según el valor de var.use_letsencrypt_prod
  yaml_body = replace(
    file("${path.module}/k8s/cert-letsencrypt-public.yaml"),
    "name: letsencrypt-stage-issuer",
    "name: ${var.use_letsencrypt_prod ? "letsencrypt-prod-issuer" : "letsencrypt-stage-issuer"}"
  )

  depends_on = [kubectl_manifest.namespace_gateway_api_system]
}



# Levantamos el Gateway
resource "kubectl_manifest" "external_gateway" {
  count = var.auto_config_cluster ? 1 : 0
  
  yaml_body = templatefile(
    "${path.module}/k8s/templates/gateway-api-external.yaml.tpl",
    {
      USE_PROD_DOMAIN = var.use_prod_domain
    }
  )
  
  depends_on = [kubectl_manifest.cert_gateway_local]
}



# Creamos el redireccionador http global para que redireccione a https
resource "kubectl_manifest" "global_http_redirect" {
  count      = var.auto_config_cluster ? 1 : 0
  yaml_body  = file("${path.module}/k8s/global-http-redirect.yaml")
  depends_on = [kubectl_manifest.external_gateway]
}



# Configuración del agente clouflared para el túnel de Cloudflare
# 1. Creamos el namespace cloudflare-tunnel-system
resource "kubectl_manifest" "namespace_cloudflare_tunnel_system" {
  count = var.auto_config_cluster && var.use_prod_domain ? 1 : 0
  yaml_body  = file("${path.module}/k8s/deployments/cloudflare-tunnel/namespace.yaml")
  depends_on = [kubectl_manifest.global_http_redirect]
}

# 1. Creamos el secreto con el token del túnel de Cloudflare
# resource "kubectl_manifest" "cloudflare_tunnel_token_secret" {
#   count = var.auto_config_cluster ? 1 : 0
  
#   yaml_body = templatefile(
#     "${path.module}/k8s/templates/gateway-api-external.yaml.tpl",
#     {
#       USE_PROD_DOMAIN = var.use_prod_domain
#     }
#   )
  
#   depends_on = [kubectl_manifest.cert_gateway_local]
# }

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
  yaml_body  = file("${path.module}/k8s/deployments/cloudflare-tunnel/deployment.yaml")
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
    file("${path.module}/k8s/deployments/openebs-values.yaml")
  ]

  depends_on = [kubectl_manifest.cloudflared_agent]
}



# # Instalación de Descheduler
# resource "helm_release" "descheduler" {
#   count            = var.auto_config_cluster ? 1 : 0

#   name             = "descheduler"
#   repository       = "https://kubernetes-sigs.github.io/descheduler/"
#   chart            = "descheduler"
#   version          = "0.36.0"
#   namespace        = "kube-system"
#   create_namespace = false

#   # Carga el archivo de valores externo
#   values = [
#     file("${path.module}/k8s/deployments/descheduler-values.yaml")
#   ]

#   depends_on = [kubectl_manifest.openebs]
# }




# # Instalación de Metrics Server
# resource "helm_release" "metrics_server" {
#   count            = var.auto_config_cluster ? 1 : 0

#   name             = "metrics-server"
#   repository       = "https://kubernetes-sigs.github.io/metrics-server/"
#   chart            = "metrics-server"
#   version          = "3.13.1"
#   namespace        = "kube-system"
#   create_namespace = false

#   # Carga el archivo de valores externo
#   values = [
#     file("${path.module}/k8s/deployments/metrics-server-values.yaml")
#   ]

#   depends_on = [kubectl_manifest.descheduler]
# }
















# resource "null_resource" "restart_coredns" {
#   provisioner "local-exec" {
#     command     = "kubectl rollout restart deployment coredns -n kube-system"
#     interpreter = ["/bin/bash", "-c"]

#     environment = {
#       #KUBECONFIG = "./talos/kubeconfig"
#       KUBECONFIG = local.KUBECONFIG
#     }
#   }

#   depends_on = [kubernetes_config_map_v1_data.coredns_patch]
# }





# # Un namespace de aplicación normal en producción (No requiere privilegios de red ni root)
# resource "kubernetes_namespace" "apps" {
#   metadata {
#     name = "apps"
#     # No necesitas agregar labels manualmente porque el comportamiento global ya es 'baseline'
#   }
# }

# # Un namespace especial (Ej: Si despliegas herramientas de monitoreo o storages pesados en 'infra')
# resource "kubernetes_namespace" "infra" {
#   metadata {
#     name = "infra"
    
#     # Solo forzamos 'privileged' si el clúster dejó de estar en modo desarrollo.
#     # Si var.is_development es true, no hace falta ponerlo porque el clúster ya regala privilegios globalmente.
#     labels = var.is_development ? {} : {
#       "pod-security.kubernetes.io/enforce" = "privileged"
#     }
#   }
# }


# # ALternativa por defecto?
# # Este recurso modificará la configuración de admisión de Kubernetes EN CALIENTE
# # mediante la API de Kubernetes una vez el clúster esté arriba.
# resource "kubernetes_labels" "default_namespaces" {
#   # Solo aplicamos cambios si is_development es FALSE (Producción)
#   count       = var.is_development ? 0 : 1
#   api_version = "v1"
#   kind        = "Namespace"
  
#   metadata {
#     name = "default" # Protege el namespace default en producción
#   }

#   labels = {
#     "pod-security.kubernetes.io/enforce" = "baseline"
#   }
# }



