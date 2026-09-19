# -------------------------------------------------------------------
# CONFIGURACIÓN LOCAL DE VARIABLES (El Mapa de Datos)
# -------------------------------------------------------------------
locals {
    # --- Configuración del Cluster ---
    cluster_name        = "eljavatar-k8s-talos-cluster"
    cluster_vip         = "192.168.0.30"
    cluster_endpoint    = "https://192.168.0.30:6443"
    primary_cp_ip       = "192.168.0.31" # IP usada para bootstrap y conexiones de talosctl
    talos_version       = "v1.13.4"
    talos_disk_image    = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.4/nocloud-amd64.raw.xz"
    talos_iso_url       = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.13.4/nocloud-amd64.iso"
    talos_iso_name      = "talos-v1.13.4-nocloud-amd64-with-qemu.iso"
    talos_install_image = "factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.4"
    talos_local_iso     = "local:iso/talos-nocloud-amd64-with-qemu.iso"

    # --- Red ---
    network_gateway  = "192.168.0.1"
    network_cidr     = "/24"

    # En Terraform, la interpolación ${path.module} hace referencia al directorio donde reside el archivo .tf que la invoca.
    # Por tanto, sería útil si necesitamos acceder a archivos dentro de la carpeta 'terraform/'
    # Sin embargo, 'k8s/' y 'talos/' no están dentro de 'terraform/', por lo tanto, usamos path.root combinado con una salida
    # al directorio superior (../)
    # ${path.root} apunta al directorio del módulo raíz (la carpeta terraform/ donde se ejecuta el comando).
    # Usar ../ nos permite "subir" un nivel al directorio principal del repositorio (kubernetes-homelab/) y
    # de ahí acceder de forma segura a cualquier otro folder.
    k8s_path = "${path.root}/../k8s"
    talos_path = "${path.root}/../talos"

    KUBECONFIG = "${local.talos_path}/kubeconfig"

    vms = {
        # -------------------------------------------------------------------
        # MINI PC 1 (pmx-01) - Control Planes 1 y 2, Workers: Data y Apps
        # -------------------------------------------------------------------

        # Talos Control Plane 01
        "cp-01" = { 
            vm_id       = 101
            node        = "pmx-01"
            tags        = ["k8s", "control-plane"]
            cores       = 2
            memory      = 3072 # 3 GB RAM
            disk_size   = 20 # 20 GB
            is_cp       = true
            node_type   = "controlplane"
            zone        = "pmx-01"
            role        = "cp"
            ip          = "192.168.0.31"
            mac_address = "52:54:01:aa:aa:01"
            run_on_ssd  = true
        }
        # Talos Control Plane 02
        "cp-03" = {
            vm_id       = 103
            node        = "pmx-01"
            tags        = ["k8s", "control-plane"]
            cores       = 2
            memory      = 3072 # 3 GB RAM
            disk_size   = 20 # 20 GB
            is_cp       = true
            node_type   = "controlplane"
            zone        = "pmx-01"
            role        = "cp"
            ip          = "192.168.0.33"
            mac_address = "52:54:01:aa:aa:03"
            run_on_ssd  = true
        }
        # Talos Worker Data 01 (Postgres, Mongo, SeaweedFS Master, Redis)
        "worker-data-01" = {
            vm_id       = 201
            node        = "pmx-01"
            tags        = ["k8s", "worker", "data"]
            cores       = 4
            memory      = 10240 # 10 GB RAM
            disk_size   = 400 # 400 GB
            is_cp       = false
            node_type   = "worker"
            zone        = "pmx-01"
            role        = "data"
            ip          = "192.168.0.40"
            mac_address = "52:54:01:cc:bb:01"
            run_on_ssd  = true
        }
        # Talos Worker Apps 01 (Java, Go, Keycloak, Knative)
        "worker-apps-01" = {
            vm_id       = 202
            node        = "pmx-01"
            tags        = ["k8s", "worker", "apps"]
            cores       = 6
            memory      = 10240 # 10 GB RAM
            disk_size   = 100 # 100 GB
            is_cp       = false
            node_type   = "worker"
            zone        = "pmx-01"
            role        = "apps"
            ip          = "192.168.0.41"
            mac_address = "52:54:01:cc:bb:02"
            run_on_ssd  = true
        }

        # -------------------------------------------------------------------
        # MINI PC 2 (pmx-02) - Control Plane 3, Workers: Heavy y Ops
        # -------------------------------------------------------------------

        # Talos Control Plane 03
        "cp-02" = {
            vm_id       = 102
            node        = "pmx-02"
            tags        = ["k8s", "control-plane"]
            cores       = 2
            memory      = 3072 # 3 GB RAM
            disk_size   = 20 # 20 GB
            is_cp       = true
            node_type   = "controlplane"
            zone        = "pmx-02"
            role        = "cp"
            ip          = "192.168.0.32"
            mac_address = "52:54:02:aa:aa:02"
            run_on_ssd  = true
        }
        # Talos Worker Heavy 02 (Apache Pulsar, ScyllaDB)
        "worker-heavy-02" = {
            vm_id       = 203
            node        = "pmx-02"
            tags        = ["k8s", "worker", "heavy"]
            cores       = 6
            memory      = 12288 # 12 GB RAM
            disk_size   = 200 # 200 GB
            is_cp       = false
            node_type   = "worker"
            zone        = "pmx-02"
            role        = "heavy"
            ip          = "192.168.0.42"
            mac_address = "52:54:02:cc:bb:01"
            run_on_ssd  = true
        }
        # Talos Worker Ops 02 (VictoriaMetrics, OpenObserve, Grafana, SeaweedFS Vol)
        "worker-ops-02" = {
            vm_id       = 204
            node        = "pmx-02"
            tags        = ["k8s", "worker", "ops"]
            cores       = 6
            memory      = 11264 # 11 GB RAM
            disk_size   = 400 # 400 GB
            is_cp       = false
            node_type   = "worker"
            zone        = "pmx-02"
            role        = "ops"
            ip          = "192.168.0.43"
            mac_address = "52:54:02:cc:bb:02"
            run_on_ssd  = true
        }
    }

    # Filtramos el mapa general por cada uno de los nodos físicos
    vms_pmx01 = { for k, v in local.vms : k => v if v.node == "pmx-01" }
    vms_pmx02 = { for k, v in local.vms : k => v if v.node == "pmx-02" }

    gateway_api_urls = {
        standard     = var.use_local_iso ? "${local.k8s_path}/gateway-api-crds/v1.4.1/standard-install.yaml" : "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
        experimental = var.use_local_iso ? "${local.k8s_path}/gateway-api-crds/v1.4.1/experimental/io_tlsroutes.yaml" : "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.4.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml"
    }
}
