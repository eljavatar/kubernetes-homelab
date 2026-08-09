terraform {
  required_providers {
    proxmox = { source = "bpg/proxmox", version = "0.110.0" }
    talos   = { source = "siderolabs/talos", version = "0.11.0" }
    time    = { source = "hashicorp/time", version = "0.14.0" }
    local   = { source = "hashicorp/local", version = ">= 2.0.0" }
  }
}

variable "node_name" {}
variable "node_ip" {}
variable "vms" {
  type = map(object({
    vm_id        = number
    cores        = number
    memory       = number
    disk_size    = string
    ip           = string
    mac_address  = string
    is_cp        = bool
    node_type    = string
    zone         = string
    role         = string
    tags         = list(string)
  }))
}
variable "use_local_iso" {}
variable "is_development" {}
variable "cluster_name" {}
variable "cluster_vip" {}
variable "cluster_endpoint" {}
variable "iso_url" {}
variable "iso_name" {}
variable "install_image" {}
variable "local_iso" {}
variable "network_cidr" {}
variable "network_gateway" {}
variable "machine_secrets" {
  type = any
  sensitive = true
}
variable "client_configuration" {
  type = any
}



# Descargar ISO oficial Nocloud de Talos directamente en Proxmox (una por nodo Proxmox)
resource "proxmox_download_file" "talos_image" {
  count        = var.use_local_iso ? 0 : 1

  provider     = proxmox
  node_name    = var.node_name
  content_type = "iso"   # En Proxmox se almacena las imágenes RAW en el mismo directorio que ISOs
  datastore_id = "local"
  url          = var.iso_url
  file_name    = var.iso_name
}



# Configuración Talos base para cada VM
data "talos_machine_configuration" "this" {
  for_each         = var.vms

  cluster_name     = var.cluster_name
  cluster_endpoint = var.cluster_endpoint # IP del CP principal o Balanceador
  machine_type     = each.value.is_cp ? "controlplane" : "worker"
  machine_secrets  = var.machine_secrets

  config_patches = compact([
    # Parche 1: Configuración de red e instalación
    yamlencode({
      machine = {
        install = {
          image = var.install_image
        }
        nodeLabels = {
          "topology.kubernetes.io/zone" = each.value.zone
          "custom-role" = each.value.role
        }
        network = {
          # El provider 'siderolabs/talos' en versiones recientes genera configuraciones multi-document,
          # y uno de esos archivos es de tipo HostnameConfig. Por eso, si seteamos el hostname aquí,
          # obtendríamos el error "static hostname is already set in v1alpha1 config". EN lugar de
          # setear el hostname aquí, lo hacemos directamente en el patch 2.
          # https://github.com/ryyyyan-taylor/homelab/wiki/Talos-Cluster
          # https://docs.siderolabs.com/talos/v1.13/networking/configuration/hostname
          #hostname = each.key
          interfaces = [
            {
              #interface = "eth0"
              # En lugar de interface = "eth0", usamos selectores:
              # https://oneuptime.com/blog/post/2026-03-03-configure-static-ip-addresses-in-talos-linux/view#using-device-selectors-instead-of-interface-names
              deviceSelector = {
                # Si los nodos tienen múltiples interfaces (como en mi caso) y se necesita asegurar cuál de
                # ellas recibe la IP estática de forma dinámica según el hardware, usamos el selector por
                # dirección MAC o por el driver de la tarjeta (aunque esta forma también sirve para nodos
                # con una sola interface de red)
                hardwareAddr = each.value.mac_address  # Propiedad nativa oficial v1alpha1
              }
              dhcp      = false
              addresses = ["${each.value.ip}${var.network_cidr}"]
              routes    = [
                {
                  network = "0.0.0.0/0",
                  gateway = var.network_gateway
                }
              ]
              # Adición de VIP: Solo se inyecta en la interfaz si la máquina es Control Plane
              # Si dejamos el cluster_endpoint apuntando rígidamente a la IP de un solo nodo (como 192.168.0.31),
              # en el momento en que ese servidor Proxmox entre en mantenimiento o la VM se apague, se perderá el
              # acceso a la API de Kubernetes, rompiendo el propósito de tener 3 planos de control. Por eso, como
              # vamos a tener mínimo 3 Control Planes, es crítico que configuremos una IP Virtual (VIP) integrada
              # de Talos en este momento
              vip = each.value.is_cp ? {
                ip = var.cluster_vip
              } : null
            }
          ]
          nameservers = [
            "1.1.1.1",
            "8.8.8.8"
          ]
        }
        # https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config#kubelet
        # https://oneuptime.com/blog/post/2026-03-03-override-default-machine-configuration-values-in-talos/view
        kubelet = {
          extraArgs = {
            rotate-server-certificates = "true" # Permite que el nodo pida renovar sus certificados automáticamente
          }
          extraConfig = {
            # Le indica al kubelet que envíe una solicitud de firma de certificado (CSR) para su certificado
            # de servicio al iniciarse, y que la renueve antes de que caduque enviando otra
            serverTLSBootstrap = true
          }
          # Asegura que Kubelet apunte al IP del servicio DNS
          # https://oneuptime.com/blog/post/2026-03-03-configure-coredns-custom-settings-on-talos-linux/view#applying-changes-through-talos-machine-config
          # https://oneuptime.com/blog/post/2026-03-03-troubleshoot-coredns-issues-on-talos-linux/view
          # https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config#kubelet
          clusterDNS = ["10.96.0.10"]
          # OpenEBS Local PV necesita acceso a rutas de host específicas
          # Si no aplicamos este parche en la configuración de Talos (MachineConfig), los Pods fallarán de forma
          # intermitente al intentar escribir datos, o el clúster sufrirá de fugas de montajes (Mount Leaks) al
          # reiniciar nodos.
          # La Razón Técnica: Talos Linux gestiona el binario de kubelet dentro de un contenedor aislado con su
          # propio espacio de nombres de montaje (Mount Namespace). Cuando el agente de OpenEBS aprovisiona una
          # carpeta en el host (/var/openebs/local/...), el Kubelet de Talos no puede verla de forma nativa.
          # La Directiva rshared: Al añadir este bind-mount con la opción rshared (Recursive Shared), le indicamos
          # al kernel que cualquier subcarpeta o volumen que OpenEBS monte o cree dentro de /var/openebs/local se
          # propague de forma bidireccional e inmediata hacia el contenedor de Kubelet. Sin esto, las bases de datos
          # arrojarán errores de Read-only file system o Directory not found.
          # https://oneuptime.com/blog/post/2026-03-03-set-up-openebs-local-pv-on-talos-linux/view
          extraMounts = !each.value.is_cp ? [
            {
              destination = "/var/openebs/local"
              type        = "bind"
              source      = "/var/openebs/local"
              options     = ["bind", "rshared", "rw"]
            }
          ] : []
        }
        # Desactiva el resolvedor de caché DNS del host y utiliza directamente los resolvedores DNS configurados
        # En resumen esto hace que el archivo 'talosctl read /etc/resolv.conf' en vez de contener el nameserver
        # '127.0.0.53', contenga los nameservers '1.1.1.1' y '8.8.8.8'
        # https://docs.siderolabs.com/talos/v1.13/networking/host-dns
        # https://docs.siderolabs.com/talos/v1.13/reference/configuration/v1alpha1/config#hostdns
        features = {
          hostDNS = {
            enabled = false
            forwardKubeDNSToHost = false
          }
        }
      }
    }),
    # Parche 2: Configuración del hostname (documento separado)
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "HostnameConfig"
      hostname   = each.key
      auto       = "off"
    }),
    # Parche 3: Cofiguración a nivel de clúster (Solo para Control Planes)
    # Los componentes a nivel de clúster (como CoreDNS, CNI y kube-proxy) solo deberían aplicarse
    # en los nodos Control Plane.
    each.value.is_cp ? yamlencode({
      cluster = {
        # Configuración para deshabilitar Flannel (cni name=none) y kube-proxy,
        # ya que posteriormente configuraremos nuestro CNI con Cilium
        network = {
          cni = {
            name = "none"
          }
        }
        proxy = {
          disabled = true
        }
        # Deshabilitamos CoreDNS ya que lo vamos a hacer una instalación custom
        # https://github.com/siderolabs/talos/discussions/10012
        # https://oneuptime.com/blog/post/2026-03-03-override-default-machine-configuration-values-in-talos/view
        coreDNS = {
          disabled = true
        }
        # Control de Admisión Híbrido
        apiServer = {
          # Configurammos el admisionControl de tal modo que si es un clúster de desarrollo, no tengamos que agregar el siguiente label a los namespaces:
          # kubectl label namespace <nombre-namespace> pod-security.kubernetes.io/enforce=privileged --overwrite
          # https://docs.siderolabs.com/kubernetes-guides/security/pod-security#configuration
          admissionControl = [
            {
              name = "PodSecurity"
              configuration = {
                apiVersion = "pod-security.admission.config.k8s.io/v1"
                kind       = "PodSecurityConfiguration"
                defaults = {
                  enforce         = var.is_development ? "privileged" : "baseline"
                  enforce-version = "latest"
                  audit           = var.is_development ? "privileged" : "restricted"
                  audit-version   = "latest"
                  warn            = var.is_development ? "privileged" : "baseline"
                  warn-version    = "latest"
                }
                exemptions = {
                  usernames      = []
                  runtimeClasses = []
                  namespaces     = [] # Lo dejamos vacío ya que Talos ya exime a "kube-system" internamente
                }
              }
            }
          ]
        }
      }
    }) : "" # Si es un worker, devuelve una cadena vacía que compact() eliminará
  ])
}



# Archivos snippets (metadata y user-data)
# Para que el proveedor nocloud de Talos se active correctamente y lea el user-data, necesita
# un archivo llamado meta-data (aunque esté vacío o solo tenga el instance-id).
resource "proxmox_virtual_environment_file" "meta_data" {
  for_each     = var.vms
  provider     = proxmox
  node_name    = var.node_name
  content_type = "snippets"
  datastore_id = "local"
  source_raw {
    data = yamlencode({
      instance-id    = each.key
      local-hostname = each.key
    })
    file_name = "metadata-${each.key}.yaml"
  }
}

resource "proxmox_virtual_environment_file" "user_data" {
  for_each     = var.vms
  provider     = proxmox
  node_name    = var.node_name
  content_type = "snippets"
  datastore_id = "local"
  source_raw {
    # Aquí unimos la configuración base de Talos con los parches estáticos de red y el hostname
    data      = data.talos_machine_configuration.this[each.key].machine_configuration
    file_name = "userdata-${each.key}.yaml"
  }
}

# Espera a que Proxmox haya procesado los snippets (10s)
resource "time_sleep" "wait_for_snippets" {
  depends_on = [
    proxmox_virtual_environment_file.meta_data,
    proxmox_virtual_environment_file.user_data,
  ]
  create_duration = "10s"
}



# Crear VM sin arrancar (started = false)
# https://registry.terraform.io/providers/bpg/proxmox/0.110.0/docs/resources/virtual_environment_vm
# Optimizaciones de VMs en Proxmox: https://www.youtube.com/watch?v=Lie4No0mQ6U
resource "proxmox_virtual_environment_vm" "talos_vm" {
  for_each   = var.vms

  provider   = proxmox
  node_name  = var.node_name
  vm_id      = each.value.vm_id
  name       = each.key
  tags       = each.value.tags
  started    = false # Forzamos a que el ciclo nativo NO las encienda de golpe

  cpu {
    cores = each.value.cores
    # En caso de tener un clúster heterogéneo (con CPUs INTEL y AMD) donde posiblemente se quieran hacer migraciones
    # en caliente, a type asignarle el valor de "x86-64-v3". Este tipo soporta casi cualquier procesador Intel o AMD
    # de los últimos 8-10 años (actualmente año 2026) y tiene un rendimiento general del ~95-98% en comparación al
    # rendimiento nativo (host).
    # - Lo que sacrificamos (~2% de performance extremo): Perderemos el uso de instrucciones ultra-específicas de
    #   arquitecturas muy nuevas (como AVX-512 si los procesadores actuales las tuviesen). Para cargas de trabajo
    #   web tradicionales (Java, Go, Python) e infraestructura estándar, la diferencia de rendimiento es completamente
    #   imperceptible en el mundo real.
    # - Lo que ganamos (Flexibilidad Absoluta): Ganamos la capacidad de cazar cualquier oferta de Mini PC Ryzen usada
    #   en el mercado, meterla al clúster, registrarla en el locals.tf y dejar que Terraform la aprovisione. Podremos
    #   migrar en caliente el nodo de observabilidad worker-ops-02 hacia el nuevo hardware de forma 100% invisible
    #   para los usuarios y sin desconectar los paneles de Grafana.
    type  = "x86-64-v3"
  }

  memory {
    dedicated = each.value.memory
  }

  agent {
    enabled = true # QEMU Guest Agent para Talos
  }

  network_device {
    mac_address = each.value.mac_address
    bridge      = "vmbr0"
    model       = "virtio"
    firewall    = false
  }

  # Disco destino: El disco duro de la VM (se crea vacío, la API de Proxmox lo maneja sin SSH)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "raw"
    # Al estar utilizando local-lvm (que en Proxmox es un esquema de aprovisionamiento ligero basado en LVM-Thin),
    # el espacio que borren las bases de datos pesadas como ScyllaDB o PostgreSQL nunca será devuelto a los discos
    # NVMe físicos. El almacenamiento de las Mini PCs se llenará lentamente hasta colapsar, a pesar de que se vea
    # espacio libre dentro de Kubernetes.
    # Para solucionarlo, modificamos la configuración de Terraform para habilitar el flag 'discard' en la pila de
    # virtualización con el valor 'on'. Además, para que la señal de descarte viaje de forma eficiente a nivel de
    # bus PCIe, se recomienda activar la propiedad de emulación 'ssd = true' (en caso de que aplique).
    discard      = "on"             # OBLIGATORIO: Habilita el reenvío de bloques eliminados a Proxmox
    # ¿Por qué activar el flag 'ssd = true' en discos NVMe/SSD?
    # Los sistemas operativos modernos (incluyendo el Kernel de Talos) cambian sus algoritmos internos de entrada
    # y salida (I/O Schedulers) cuando saben que el medio es de estado sólido. Desactivan la optimización de
    # rotación de aguja (necesaria en HDDs) y habilitan el procesamiento en paralelo extremo.
    ssd          = each.run_on_ssd  # RECOMENDADO: Informa a la VM que el medio físico subyacente es un NVMe/SSD
  }

  # Lectora ISO (unidad de CD-ROM): Desde donde va a bootear la primera vez
  cdrom {
    interface = "ide3" # Se usa la interfaz IDE para simular la lectora de CD
    #file_id   = proxmox_download_file.talos_image.id
    #file_id   = var.use_local_iso ? var.local_iso : proxmox_download_file.talos_image.id
    # Sintaxis corregida usando el índice [0] solo si se crea el recurso
    file_id   = var.use_local_iso ? var.local_iso : proxmox_download_file.talos_image[0].id
  }

  # Indicamos que arranque desde el disco local (el primer arranque, al no haber un SO instalado en scsi0
  # lo salta y arranca desde la unidad de CD (ide3))
  boot_order = ["scsi0", "ide3"]

  # Activamos la unidad Cloud-Init de Proxmox e inyectamos el snippet de Talos
  # Para que la configuración completa viaje dentro de Proxmox en un disco virtual de Cloud-init, usamos
  # el "NoCloud" de Talos (Cloud-Init simulado). Este proceso sube el archivo de configuración generado
  # por Terraform a Proxmox como un snippet (un archivo .yaml) y se le inyecta a la VM mediante la unidad
  # de Cloud-Init (initialization). Cuando la VM arranca la ISO, lee el archivo localmente, aplica la IP
  # estática (y otras configuraciones) y se instala sola sin que Terraform tenga que conectarse por red a
  # aplicar nada.
  initialization {
    #type              = "nocloud"
    datastore_id      = "local-lvm"
    interface         = "ide2"   # disco cloud-init
    meta_data_file_id = proxmox_virtual_environment_file.meta_data[each.key].id
    # Le decimos a Proxmox que use nuestro snippet como user_data
    user_data_file_id = proxmox_virtual_environment_file.user_data[each.key].id
  }

  depends_on = [time_sleep.wait_for_snippets]
}

# El Temporizador (Hereda el for_each para no mezclar las VMs)
resource "time_sleep" "wait_before_start_vm" {
  for_each = var.vms
  depends_on = [proxmox_virtual_environment_vm.talos_vm]
  create_duration = "20s" # Espera 20 segundos
}

# Encendido nativo (Sin usar comandos de consola "qm start")
resource "terraform_data" "boot_vm" {
  #for_each = { for k, v in var.vms : k => v if v.role == "control-plane" }
  #for_each = { for k, v in var.vms : k => v if v.role == "worker" }
  for_each = var.vms
  # Este bloque no se ejecutará hasta que el reloj de 20s de ESTA VM termine
  input = time_sleep.wait_before_start_vm[each.key].id
  #depends_on = [time_sleep.wait_before_start_vm]
  # Se ejecuta solo en la creación
  provisioner "local-exec" {
    command = "ssh root@${var.node_ip} 'qm start ${proxmox_virtual_environment_vm.talos_vm[each.key].vm_id}'"
  }
}



# Extrae la configuración de cada VM
resource "local_file" "machine_configs" {
  for_each = var.vms

  # Esto creará una estructura limpia: ./talos/configs/pmx-01/controlplane-vm01.yaml
  filename = "${path.root}/talos/configs/${var.node_name}/${each.value.is_cp ? "controlplane" : "worker"}-${each.key}.yaml"
  content  = data.talos_machine_configuration.this[each.key].machine_configuration
}



# Una nota importante para el "Futuro" (Día 2)
# 
# En este caso, estamos usando talos_machine_configuration para generar la configuración de inicio de una
# con la IP estática y hostname requerido, por lo que no necesitamos de talos_machine_configuration_apply.
# 
# ¿Cuándo sí volveríamos a necesitar talos_machine_configuration_apply?
# 
# Únicamente en el "Día 2" de las operaciones del clúster. Si dentro de 6 meses se requiere cambiar un
# parámetro de Kubernetes, añadir un proxy, o cambiar una configuración del kernel de Talos sin destruir
# la VM, el Snippet de Cloud-Init ya no servirá (porque Cloud-Init solo corre en el primer arranque).
# 
# En ese escenario futuro, se añadiría el talos_machine_configuration_apply apuntando a las IPs ya
# existentes para actualizar los nodos en vivo.
# 
# Con esta configuración, evitamos tener que ejecutar patchs desde la terminal por cada VM:
# resource "talos_machine_configuration_apply" "this" {
#   for_each = local.vms

#   client_configuration        = var.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
#   node                        = each.value.ip # IP temporal o final si Talos ya responde

#   config_patches = [
#     yamlencode({
#       machine = {
#         network = {
#           interfaces = [
#             {
#               interface = "eth0"
#               dhcp      = false
#               addresses = ["${each.value.ip}${local.network_cidr}"]
#               routes = [
#                 {
#                   network = "0.0.0.0/0"
#                   gateway = local.network_gateway
#                 }
#               ]
#             }
#           ]
#         }
#       }
#     })
#   ]
# }

# # Este recurso se encarga de enviar los cambios generados por el DATA a las VMs reales
# resource "talos_machine_configuration_apply" "this" {
#   for_each = var.vms

#   client_configuration        = var.client_configuration # Credenciales de talosconfig
#   machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
#   node                        = each.value.ip // La IP de la VM en Proxmox

#   # Esto asegura que si cambia la seguridad, Talos aplique el parche de inmediato
#   lifecycle {
#     create_before_destroy = false
#   }
# }
# El comando para mutar el clúster
# terraform apply -var="is_development=false"






# Aquí te muestro como tengo actualmente ese fragmento de código en terraform (ya le agregué el extraMounts); tú me dirás si debo ajustarle algo:

# ```hcl
# data "talos_machine_configuration" "this" {
#   for_each         = var.vms

#   cluster_name     = var.cluster_name
#   cluster_endpoint = var.cluster_endpoint # IP del CP principal o Balanceador
#   machine_type     = each.value.is_cp ? "controlplane" : "worker"
#   machine_secrets  = var.machine_secrets

#   config_patches = compact([
#     # Parche 1: Configuración de red e instalación
#     yamlencode({
#       machine = {
#         install = {
#           image = var.install_image
#         }
#         nodeLabels = {
#           "topology.kubernetes.io/zone" = each.value.zone
#           "custom-role" = each.value.role
#         }
#         network = {
#           interfaces = [
#             {
#               deviceSelector = {
#                 hardwareAddr = each.value.mac_address  # Propiedad nativa oficial v1alpha1
#               }
#               dhcp      = false
#               addresses = ["${each.value.ip}${var.network_cidr}"]
#               routes    = [
#                 {
#                   network = "0.0.0.0/0",
#                   gateway = var.network_gateway
#                 }
#               ]
#               # Adición de VIP: Solo se inyecta en la interfaz si la máquina es Control Plane
#               vip = each.value.is_cp ? {
#                 ip = var.cluster_vip
#               } : null
#             }
#           ]
#           nameservers = [
#             "1.1.1.1",
#             "8.8.8.8"
#           ]
#         }
#         kubelet = {
#           extraArgs = {
#             rotate-server-certificates = "true" # Permite que el nodo pida renovar sus certificados automáticamente
#           }
#           extraConfig = {
#             serverTLSBootstrap = true
#           }
#           # Asegura que Kubelet apunte al IP del servicio DNS
#           clusterDNS = ["10.96.0.10"]
#           # OpenEBS Local PV necesita acceso a rutas de host específicas
#           extraMounts = each.value.node_type == "worker" ? [
#             {
#               destination = "/var/openebs/local"
#               type        = "bind"
#               source      = "/var/openebs/local"
#               options     = ["bind", "rshared", "rw"]
#             }
#           ] : []
#         }
#         # Desactiva el resolvedor de caché DNS del host y utiliza directamente los resolvedores DNS configurados
#         features = {
#           hostDNS = {
#             enabled = false
#             forwardKubeDNSToHost = false
#           }
#         }
#       }
#     }),
#     # Parche 2: Configuración del hostname (documento separado)
#     yamlencode({
#       apiVersion = "v1alpha1"
#       kind       = "HostnameConfig"
#       hostname   = each.key
#       auto       = "off"
#     }),
#     # Parche 3: Cofiguración a nivel de clúster (Solo para Control Planes)
#     each.value.is_cp ? yamlencode({
#       cluster = {
#         # Configuración para deshabilitar Flannel (cni name=none) y kube-proxy,
#         # ya que posteriormente configuraremos nuestro CNI con Cilium
#         network = {
#           cni = {
#             name = "none"
#           }
#         }
#         proxy = {
#           disabled = true
#         }
#         # Deshabilitamos CoreDNS ya que lo vamos a hacer una instalación custom
#         coreDNS = {
#           disabled = true
#         }
#         # Control de Admisión Híbrido
#         apiServer = {
#           admissionControl = [
#             {
#               name = "PodSecurity"
#               configuration = {
#                 apiVersion = "pod-security.admission.config.k8s.io/v1"
#                 kind       = "PodSecurityConfiguration"
#                 defaults = {
#                   enforce         = var.is_development ? "privileged" : "baseline"
#                   enforce-version = "latest"
#                   audit           = var.is_development ? "privileged" : "restricted"
#                   audit-version   = "latest"
#                   warn            = var.is_development ? "privileged" : "baseline"
#                   warn-version    = "latest"
#                 }
#                 exemptions = {
#                   usernames      = []
#                   runtimeClasses = []
#                   namespaces     = [] # Lo dejamos vacío ya que Talos ya exime a "kube-system" internamente
#                 }
#               }
#             }
#           ]
#         }
#       }
#     }) : "" # Si es un worker, devuelve una cadena vacía que compact() eliminará
#   ])
# }
# ```
