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
  talos_path           = local.talos_path
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
  talos_path           = local.talos_path
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

# No vamos a usar el talos_cluster_health ya que al desactivar el CNI por defecto (puesto que después
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
  filename = "${local.talos_path}/kubeconfig"
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
  filename = "${local.talos_path}/talosconfig"
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
  filename = "${local.talos_path}/controlplane.yaml"
}

# Guardamos el archivo worker.yaml base
resource "local_file" "worker_yaml" {
  content  = data.talos_machine_configuration.base_worker.machine_configuration
  filename = "${local.talos_path}/worker.yaml"
}

### END: Código para Levantar VMs con Talos configuradas desde el arranque y Bootstrap automático
