# Introducción

Este repositorio está dedicado a mostrar el proceso de creación y configuración de un homelab, el cual albergará sobre Proxmox un clúster de Kubernetes usando Máquinas Virtuales (VMs) de Talos Linux, lo cual facilitará la configuración de las VMs y creación del clúster desde Terraform.

La iniciativa de crear un homelab dedicado a albergar un clúster de Kubernetes partió de la necesidad de poder ejecutar diversos servicios que uso en el desarrollo de mis aplicaciones.

Inicialmente, usaba Kind en mi máquina local (una Macbook Pro) para levantar un clúster de kubernetes con un control-plane y 3 workers. Con las 16 GB de RAM de dicha máquina, en principio era suficiente para correr un par de aplicaciones y un par de DBs de Postgres, y eventualmente un servicio de almacenamiento de objetos tipo S3 como lo es SeaweedFS. Sin embargo, cuando quería levantar servicios de Observabilidad, el clúster se colgaba debido a la falta de recursos de mi Macbook (principalmente por falta de memoria RAM).

En ese orden de ideas tenía 2 opciones:

1. Buscar algún proveedor económico en la nube para crear mi clúster de Kubernetes.
2. Crear mi propio homelab en casa.

Teniendo en cuenta que esto es algo que pienso mantener por bastante tiempo, y que eventualmente tendré más servicios en mi clúster (como por ejemplo un servicio de mensajería tipo Kafka o Apache Púlsar), la opción 1 podría volverse un poco costosa a largo plazo (con valores que fácilmente podrían llegar a superar los 200 USD mensuales).

Por tanto, me decidí por la opción 2, para lo cual tuve que adquirir un router, un switch, un par de Mini PCs, cableado, etc. Así pues, la configuración de hardware que uso para este homelab es la siguiente:

- **Internet:** Starlink gen 2 con el respectivo adaptador Ethernet.
- **Router:** Tp-link Archer AX55 (eventualmente pienso cambiarlo por un router que me de redundancia de conectividad como por ejemplo el Tp-link Omada ER706W-4G).
- **Switch:** Tp-link Tl-SG108E.
- 2 Mini PCs GMKtec M7 Ultra (con Ryzen 7 Pro 6850U (8C / 16T)) con 32 GB de RAM y 1 TB de almacenamiento cada uno (1 NVMe) (eventualmente pienso agregar más mini PCs).
- Macbook Pro desde la cual accedo a todo (a la interfaz web de Proxmox, al router, al switch, al cúster de kubernetes vía `kubectl`, etc).

**Tecnologías Usadas**

- Proxmox v9.2
- Talos v1.13.4
- Kubernetes 1.36
- HashiCorp Vault v2.0.4 (sobre un LXC con Debian 12)
- Terraform v1.15.6
- Helm v1.4



## Arquitectura Física y Conectividad

El TP-Link Archer AX55 manejará el enrutamiento y el Wi-Fi, mientras que el switch administrado TL-SG108E será el corazón de la red cableada. La conexión física se da entonces de la siguiente forma:

1. **Starlink (Modo Bypass/Puente):** El cable del adaptador Ethernet de Starlink va directo al puerto WAN del TP-Link Archer AX55.
2. **Router a Switch:** Se conecta un cable Cat6 desde cualquier puerto LAN del Archer AX55 hacia el Puerto 1 del Switch TL-SG108E.
3. **Mini PCs al Switch:** Se conecta la Mini PC 1 al Puerto 2 y la Mini PC 2 al Puerto 3 del switch.
4. **MacBook Pro:** Se conecta vía Wi-Fi al Archer AX55 (gracias al router, tendrá visibilidad total hacia el switch y las Mini PCs).


### Diseño del Direccionamiento IP y Segmentación (La Red)

Para un homelab con Kubernetes (Talos) y Proxmox, no es buena idea tener IPs dinámicas, ya que si un nodo cambia de IP, el clúster se rompe. Por tal razón, debido a que el Gatwey de mi router es `192.168.0.1`, usaré la subred estándar `192.168.0.0/24`, pero dividiendo el direccionamiento de forma estricta:

- **Rango de IPs Estáticas (Para Infraestructura):** `192.168.0.1` a `192.168.0.149` (Aquí irán el Router, Switch, Nodos de Proxmox y las VMs de Talos).
- **Rango DHCP (Para dispositivos personales):** `192.168.0.150` a `192.168.0.254` (Aquí entrará la MacBook por Wi-Fi, celulares, etc.).


### Plan de IPs Inicial:

| Dispositivo / Servicio | Dirección IP sugerida      | Tipo de Asignación              |
|------------------------|----------------------------|---------------------------------|
|Router TP-Link AX55     | `192.168.0.1`              |Estática (Por defecto)           |
|Switch TL-SG108E        | `192.168.0.2`              |Estática                         |
|Proxmox VE - Nodo 1     | `192.168.0.10`             |Estática (Configurada en la ISO) |
|Proxmox VE - Nodo 2     | `192.168.0.11`             |Estática (Configurada en la ISO) |
|Futuras VMs (Talos K8s) | `192.168.0.30` en adelante |Estáticas / Reservas DHCP        |



## Dependencias (en Macbook Pro)

Estas dependencias son requeridas para trabajar con Terraform y Kubernetes desde la máquina local (en mi caso, como estoy usando una Macbook, usaré `brew` para instalar paquetes; en caso de usar Linux también se podría usar `brew`, aunque dependiendo de la distribución se podría usar el gestor nativo (`apt`, `dnf`, `yum`, `pacman`, etc.); en caso de usar Windows, se podrían usar alternativas como `winget`, `chocolatey` o `scoop`):

- **Homebrew** (para instalar paquetes en Mac):
```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Validar instalación
brew --version
# Homebrew 5.1.0

# Ejecutar upgrade
brew upgrade
```

- **Terraform** (para automatizar creación de VMs sobre Proxmox y configuración del clúster):
```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Validar instalación
terraform version
# Terraform v1.15.6
```

- **Talosctl** (para interactuar con el sistema operativo inmutable de las VMs de Proxmox):
```sh
brew install talosctl

# Validar instalación
talosctl version
# Client:
# 	Tag:         v1.13.4
# 	SHA:         undefined
# 	Built:       2026-06-09T15:34:28Z
# 	Go version:  go1.26.4
# 	OS/Arch:     darwin/amd64
```

- **Kubectl** (para administrar el clúster de Kubernetes una vez esté vivo):
```sh
brew install kubernetes-cli

# Validar instalación
kubectl version
# Client Version: v1.36.2
# Kustomize Version: v5.8.1
```

- **k9s** (para monitorear y gestionar clústeres de Kubernetes desde la terminal):
```sh
brew install derailed/k9s/k9s

# Validar instalación
k9s version
# Version:    v0.51.0
```

- **Helm** (para instalar servicios en el clúster de kubernetes):
```sh
brew install helm

# Validar instalación
helm version
# version.BuildInfo{Version:"v4.1.3", GitCommit:"c94d381b03be117e7e57908edbf642104e00eb8f", GitTreeState:"clean", GoVersion:"go1.26.1", KubeClientVersion:"v1.35"}
```

- **Helmfile** y plugins de helm:
```sh
brew install helmfile

# Validar instalación
helmfile --version
# helmfile version v1.4

# Instalar plugin helm diff (se requiere haber instalado previamente helm):
helm plugin install https://github.com/databus23/helm-diff --verify=false
helm plugin install https://github.com/jkroepke/helm-secrets --verify=false
```

- **Cilium-cli** (para administrar y depurar Cilium CNI en clústers de Kubernetes):
```sh
brew install cilium-cli

# Validar instalación
cilium version
# cilium-cli: v0.19.5 compiled with go1.26.4 on darwin/amd64
# cilium image (default): v1.19.4
# cilium image (stable): v1.19.5
# cilium image (running): unknown. Unable to obtain cilium version. Reason: release: not found
```

- **Watch** (para pruebas y monitoreo de procesos en tiempo real):
```sh
brew install watch

# Validar instalación
watch -version
# watch from procps-ng 4.0.6
```

- **Stern** (para visualizar logs de Kubernetes de forma rápida):
```sh
brew install stern

# Validar instalación
stern --version
# version: 1.33.1
```

- **Vault** (para gestionar la bóveda de secretos de Vault a través de su CLI):
```sh
brew tap hashicorp/tap
brew install hashicorp/tap/vault

# Validar instalación
vault version
# Vault v2.0.4
```

Para validar que tenemos instaladas las dependencias que requerimos, podemos ejecutar `make check-deps`.


### Configuración Post-Instalación de Dependencias (Opcionales)

#### Terraform

- Autocompletado de comandos:
```sh
# Bash
terraform -install-autocomplete

# Zsh (añadir a vvv)
autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /usr/local/bin/terraform terraform
```

- Variables de entorno útiles:
```sh
# Deshabilitar telemetría (opcional)
export CHECKPOINT_DISABLE=1

# Establecer nivel de logs
export TF_LOG=INFO  # TRACE, DEBUG, INFO, WARN, ERROR

# Archivo de logs personalizado
export TF_LOG_PATH="./terraform.log"

# Plugin cache para acelerar downloads
export TF_PLUGIN_CACHE_DIR="$HOME/.terraform.d/plugin-cache"
mkdir -p $TF_PLUGIN_CACHE_DIR
```





# Instalación y Configuración de Proxmox VE

Con la red lista, se preparan las Mini PCs:

1. **Preparación del medio:**

   - Descargar la última versión estable de Proxmox VE ISO Installer desde su página oficial; en mi caso, la `9.2`.
   - Flashear la ISO de Proxmox VE en una USB (de por lo menos 4 GB) usando BalenaEtcher (o si se desea, también se puede usar Rufus en Windows). En caso de usar Rufus, si pregunta en qué modo escribir, seleccionar "DD Image mode".

2. **Instalación en Mini PC 1 y Mini PC 2 (Nodos de Proxmox):** Para esto, conectamos temporalmente un monitor y teclado a cada Mini PC (también podríamos usar un JetKVM en caso de disponer de uno), introducimos la USB, encendemos la Mini PC presionando la tecla para entrar al menú de arranque (Boot Menu, en mi caso, `ESC`) y seleccionamos la USB. Desde el asistente gráfico de Proxmox, seguimos las siguientes instrucciones:

   - **Target Harddisk:** Seleccionar el disco NVMe de 1 TB.
   - **Country / Timezone:** Configurar la ubicación y zona horaria.
   - **Password and Email:** Definir la contraseña de `root` y un correo electrónico para alertas.
   - **Management Network Configuration:** Aquí es donde se define la identidad estática del nodo:
     - **Management Interface:** Seleccionar la tarjeta de red Ethernet cableada (por lo general, Proxmox ya indica la interfaz que está conectada).
     - **Hostname (FQDN):** Para la Mini PC 1, `pmx-01.eljavatar.local` (o el dominio interno que se prefiera); Para la Mini PC 2, `pmx-02.eljavatar.local`.
     - **IP Address:** Para la Mini PC 1, `192.168.0.10/24`; Para la Mini PC 2, `192.168.0.11/24`.
     - **Gateway:** `192.168.0.1`.
     - **DNS Server:** Usar `1.1.1.1` o `8.8.8.8` para resolver directo con Cloudflare o Google respectivamente (también se podría asignar el Gateway del router (`192.168.0.1` en mi caso) para usar el del Proveedor de Internet (ISP), sin embargo, suele ser más lento, además de que los ISPs son más propensos a realizar ataques de intermediario (man-in-the-midle) y no suelen cifrar las consultas).

   Al finalizar, el instalador mostrará un mensaje confirmando el éxito y la URL de acceso, por ejemplo: `https://192.168.0.10:8006/`. El sistema se reiniciará indicando que se debe desconectar la USB. Ahí ya se puede desconectar también el monitor y el teclado de la Mini PC ya que de aquí en adelante todo es remoto.

3. **Verificación Final:** Ir a la máquina local (en mi caso la Macbook Pro), conectarse al Wi-Fi habitual y abrir el navegador. Dentro del navegador intentar ingresar a:

   - `https://192.168.0.10:8006` (Aceptar el aviso de certificado SSL inseguro).
   - `https://192.168.0.11:8006`

   Ahí se debería ver la pantalla de login de Proxmox en ambas direcciones. El usuario es `root` y la contraseña es la que se definió en la instalación.



## Limpieza de Repositorios, Mensaje de Suscripción y Herramientas Utilitarias

Por defecto, Proxmox viene configurado con repositorios de pago (Enterprise). Como estamos en un entorno de Homelab, lo cambiamos al repositorio comunitario gratuito y removemos el molesto aviso de "No-Subscription" que sale cada vez que se inicia sesión.

Para esto, se siguen los siguientes pasos en ambos nodos de Proxmox (pmx-01 y pmx-02):

1. En la interfaz web de Proxmox, seleccionar el nodo en el menú de la izquierda.

2. Ir a la sección *Shell* (la consola web de comandos).

3. Para automatizar este proceso de forma segura, utilizamos un script comunitario muy famoso y verificado en el mundo de los Homelabs ([Proxmox VE Post Install](https://community-scripts.org/scripts/post-pve-install)). Ejecutar el siguiente comando en la Shell:
   ```sh
   bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh)"
   ```

4. El script hará unas preguntas interactivas en la consola:
   - **Repositorios `enterprise`:** Se le puede indicar que los deshabilite o directamente eliminarlos.
   - **Repositorios `pve-no-subscription`:** Indicarle que los active.
   - **Deshabilitar el banner de suscripción:** Indicarle que Sí (y).
   - **Opciones de HA:** El clúster lo vamos a gestionar directamente con Kubernetes, así que esto lo podemos deshabilitar; además, no es muy recomendable configurar un clúster de Proxmox con solo 2 Nodos (eventualmente configuraremos backups, el modo datacenter, entre otros, pero eso será en otro momento).
   - **Actualizar el sistema ahora:** Es recomendable decirle que Sí (y) para que el nodo quede al día con los últimos parches de seguridad.

5. Adicionalmente, también sería recomendable instalar [ProxMenux](https://proxmenux.com/en/docs/installation/), ya que contiene muchas herramientas útiles. Existen muchos tutoriales que explican las utilidades de ProxMenux, por lo cual, a continuación solo dejaré el script de instalación y en el siguiente paso mostraré cómo lo vamos a utilizar:
   ```sh
   bash -c "$(wget -qLO - https://raw.githubusercontent.com/MacRimi/ProxMenux/main/install_proxmenux.sh)"
   ```

   Una de las cosas interesantes de ProxMenux, es que nos instala un monitor al cual podemos acceder desde el navegador a través del puero `8008` de cada uno de los Nodos en los que hemos instalado Proxmox. En mi caso, accedería a este monitor a través de `http://192.168.0.10:8008` y `http://192.168.0.11:8008`.

6. Los discos NVMe son rápidos, pero usan memoria NAND flash (Non-Volatile Memory Express), con un número limitado de ciclos de escritura. En un servidor Proxmox que está encendido 24/7 se generan escrituras constantes (logs del sistema, servicios, contenedores, máquinas virtuales, etc.), lo cual no representa un problema inmediato, pero sí genera un desgaste acumulativo con el tiempo. Por tal razón, pensando en extender la vida útil de nuestro NVMe, conviene reducir escrituras inncecesarias. Para esto, vamos a instalar una utilidad que viene dentro de las opciones de **ProxMenux** (las opciones de los menús pueden cambiar entre diversas versiones, por tal razón, en caso de que sean distintas, se debería buscar en la documentación cómo llegar hasta la opción de *Script post-instalación perzonalizado*):
   - En el Shell, ejecutar el comando `menu`.
   - Esto abrirá un menú de opciones, el cual tiene muchas opciones que se pueden revisar en su documentación. En este caso, entramos a la opción `Settings post-install Proxmox` > `Customizable post-installation script`.
   - Aquí se pueden seleccionar muchas opciones, las cuales se pueden revisar en la documentación. Sin embargo, en este caso solo marcamos las siguientes opciones (con barra espaceadora marcamos o desmarcamos):
     - Install common system utilities
     - Optimize journald
     - Optimize logrotate
     - Optimize Memory
     - Remove subscription banner
     - Install and configure Log2RAM
   - Pulsamos Enter, y debido a que habíamos seleccionado `Install common system utilities`, se nos abrirá una lista de herramientas a instalar. De este listado, las que suelo seleccionar son: `dos2unix`, `htop`, `btop`, `iftop`, `iotop`, `iperf3`, `s-tui`, `ipset`, `iptraf-ng`, `net-tools`, `unzip` y `zip`.
   - Al pulsar Enter, se empezarán a instalar estas herramientas.
   - Posteriormente, para la configuración de `Log2RAM`, se nos pide el tamaño máximo (en MB) para `/var/log` en RAM, que para nuestro caso lo dejamos en `512`.
   - Luego, se nos pide elegir el intervalo de sincronización (en horas), que para nuestro caso, lo dejaremos en 6 (cada 6 horas).
   - Cuando nos pregunta que si queremos habilitar el sincronizado en caso de que `/var/log` exceda el 90% de su tamaño (de los 512MB que asignamos), le decimos que Si.
   - Al finalizar la instalación nos pide reiniciar, a lo cual le decimos que Si para que se apliquen correctamente los ajustes.
   
   Este proceso lo debemos realizar en cada nodo (para más detalles, podemos ver [este video en YouTube](https://youtu.be/wNQ12uVFxyc?si=TaZryg4934bu8qWe&t=1654) a partir del minuto 27:34).



## Optimización de Consumo de Energía

Aplicar optimizaciones de energía en un Homelab de alto rendimiento basado en Kubernetes es un dilema clásico entre el ahorro en la factura eléctrica y la estabilidad transaccional de los servicios.

Al analizar mi hardware (2 Mini PCs M7 Ultra) y mi catálogo de servicios (especialmente ScyllaDB, Apache Pulsar, PostgreSQL y Keycloak), podemos deducir que tiene sentido aplicar algunas optimizaciones, pero de forma selectiva y con extrema precaución, ya que un mal ajuste puede degradar el rendimiento o corromper las bases de datos.

A continuación, veremos un desglose del impacto real, lo positivo, lo negativo y cuál es la mejor estrategia para este escenario en particular:


### 1. El Gobernador de CPU: ¿`powersave` o `performance`?

Es importante aclarar un mito técnico: en los procesadores modernos de Intel y AMD (que usan los controladores `intel_pstate` o `amd_pstate` de forma nativa en el Kernel de Proxmox), el modo `powersave` no significa "vuelve mi computador lenta".

- **Cómo funciona realmente:** El modo `powersave` actúa como un regulador dinámico inteligente (similar al antiguo `ondemand`). Cuando las Mini PCs están inactivas de madrugada, baja las frecuencias al mínimo (~800 MHz) reduciendo drásticamente el consumo en vatios. En cuanto una de las aplicaciones en Java o una consulta pesada en ScyllaDB exige potencia, el Kernel eleva la frecuencia al máximo en microsegundos.
- **Impacto Positivo:** Reducción notable de la temperatura en reposo, menos ruido de los ventiladores de las Mini PCs y una extensión de la vida útil del hardware.
- **Impacto Negativo (Latencia de Cola / Latency Spikes):** El microsegundo que le toma al procesador pasar de 800 MHz a 4.0 GHz genera micro-latencias. Para los backends de Java o Go esto es imperceptible; sin embargo, para ScyllaDB y Apache Pulsar, que procesan miles de operaciones por segundo y exigen predictibilidad estricta, ese cambio de ritmo continuo puede inflar la latencia de las consultas de 2ms a 15ms de forma errática; en el caso de mi Homelab, latencias de 15ms es algo tolerable, por lo que no sería contraproducente activar el modo `powersave`.


### 2. El comando powertop `--auto-tune`: El verdadero peligro en Kubernetes

`powertop` es una excelente herramienta para laptops, pero ejecutar su bandera `--auto-tune` a ciegas en un servidor de Proxmox con almacenamiento NVMe acoplado a Kubernetes es altamente desaconsejable.

`powertop --auto-tune` activa de forma agresiva las siguientes funciones automáticas:

1. **ASPM (Active State Power Management) en buses PCIe:** Pone a "dormir" las ranuras PCIe de la placa. Esto provoca que los discos NVMe (donde correrá el almacenamiento de OpenEBS para Scylla y Postgres) entren en estados de ahorro de energía profundos. Al despertar bajo un pico de escritura de la base de datos, el disco puede tardar de más, provocando timeouts de I/O en Kubernetes y corrupciones latentes en el sistema de archivos de Talos Linux. 
2. **Autosuspend de USB y Tarjetas de Red:** Si las Mini PCs usan adaptadores de red de alta velocidad internos o externos que admitan este modo, `powertop` podría bajarles la energía durante segundos de baja actividad, provocando caídas momentáneas en los latidos (*keepalives*) del clúster de Talos, asumiendo falsamente que un nodo murió.


### 3. Recomendación para Optimizar el Consumo de Energía para este Homelab

Para lograr un balance perfecto (ahorrar energía sin poner en riesgo las bases de datos), seguiremos la siguiente estrategia en la Shell de Proxmox de pmx-01 y pmx-02:

- **Paso 1: Usar el gobernador dinámico (Solo si el Kernel lo soporta):** Para esto, primero debemos ejecutar en la Shell de Proxmox de cada Mini PC:

  ```sh
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
  ```

  Si el resultado nos muestra `performance powersave` (típico de drivers modernos de Intel/AMD (`amd_pstate`/`intel_pstate`)), deberíamos dejarlo solo en `powersave`; si nos muestra algo como `performance powersave ondemand conservative userspace`, debemos configurarlo en `ondemand` para asegurar el escalado (esto aplicaría para procesadores de generaciones antiguas donde el Kernel de Linux no usa el driver nativo moderno de AMD/Intel, sino el driver ACPI genérico (`acpi-cpufreq`)).
  
  Para esto vamos a hacer uso de **ProxMenux** (las opciones de los menús pueden cambiar entre diversas versiones, por tal razón, en caso de que sean distintas, se debería buscar en la documentación cómo llegar hasta la opción de *Gobernador de escalado de CPU*):

  - En el Shell, ejecutar el comando `menu`.
  - Entramos a la opción `Proxmox VE Helper Scripts` > `Proxmox & Virtualization` > `PVE CPU Scalling Governor`.
  - Ahí nos mostrará cómo queremos ejecutar el Script, si desde `GitHub` o desde el `Mirror`; en mi caso selecciono que lo haga desde `GitHub` y luego seleccionamos `Yes` para proceder.
  - En mi caso me indica que CPU Scaling Governor está configurado en `performance`, así que en la lista que muestra, marcamos la opción `powersave` (con la barra espaceadora) y pulsamos Enter (en caso de que aparezca `ondemand`, seleccionar esta opción, ya que en el driver genérico antiguo, el modo llamado `powersave` bloquea la CPU a la frecuencia mínima absoluta de por vida (por ejemplo, fija el procesador a 800 MHz y nunca lo deja subir aunque servicios como ScyllaDB o Apache Pulsar estén colapsando)).
  - Luego nos muestra un mensaje diciendo que el CPU Scaling Governor ha sido configurado en `powersave`, y pulsamos Enter para continuar.
  - Luego nos indica que si queremos configurar un `crontab` para que la configuración se mantenga incluso después de reiniciar las Mini PCs, seleccionamos la opción `yes` y pulsamos Enter.
  - Luego nos muestra la terminal en donde nos indica que pulsemos Enter para retornar al menú principal.
  - Finalmente salimos de ProxMenux.

  Con esta configuración el procesador escalará por sí solo ante la demanda de los contenedores.

- **Paso 2: Usar `powertop` solo para auditar, NO para auto-tunear:** Instalamos `powertop` ejecutando `apt install powertop`, lo abrimos y revisamos la pestaña de *Tunables*. En lugar de usar `--auto-tune`, activamos manualmente únicamente las optimizaciones relacionadas con los controladores de audio integrados o puertos de video que no estemos usando en las Mini PCs. Jamás deberíamos tocar los parámetros relacionados con "SATA link", "PCIe ASPM" o las interfaces de red Ethernet/Fibra.

- **Paso 3: Confiar en la inmutabilidad de Talos Linux:** No deberíamos intentar meter herramientas de ahorro de energía dentro de las VMs de Talos. Talos ya viene compilado de forma minimalista a nivel de Kernel y no tiene procesos basura de fondo corriendo en los workers, garantizando que cuando la CPU de Proxmox se relaje, las VMs se relajarán al máximo de forma natural.



## Optimización del Almacenamiento Interno

Teniendo en cuenta que en mi caso instalé Proxmox en máquinas con un solo disco de 1 TB, el instalador por defecto creó dos particiones de almacenamiento lógico visibles en la interfaz:

- **local:** Espacio destinado para almacenar imágenes ISO, templates de contenedores y respaldos.
- **local-lvm (o local-zfs):** Destinado exclusivamente para los discos virtuales de las VMs.

Dado que se van a manejar servicios pesados de datos (como SeaweedFS, Postgres y MongoDB), es crucial verificar que el almacenamiento asignado a las VMs sea de tipo **Thin Provisioning (LVM-Thin)**. Esto permitirá sobre-asignar espacio de manera flexible sin que se reserve el 100% del tamaño del disco virtual desde el primer día.

*Verificación:* Ir a Storage en la vista de Datacenter y asegurarse de ver local-lvm con soporte para Disk image y Container.

Además, no está de más asegurar que la interfaz de red virtual (`vmbr0`) esté lista para bridgear el tráfico de las futuras VMs hacia el switch (esto se valida en Datacenter -> pmx-01 > System > Network).





# Instalación de HashiCorp Vault en Proxmox

Para ver cómo Instalar y Configurar HashiCorp Vault en nuestro HomeLab (el cual usaremos como almacen y administrador de secretos para nuestro clúster de Kubernetes), ir a su respectivo [README](VAULT_README.md) que se encuentra en este mismo repositorio.





# Preparación para la Automatización (Terraform + Talos)

## Planificación de la Topología para el Clúster de Kubernetes (Talos Linux)

Ahora que los Nodos de Proxmox están listos y preparados para correr VMs, definimos la arquitectura del clúster de Kubernetes para que soporte con holgura los servicios requeridos.

### Análisis del Stack de Servicios

1. **Heavy Hitters (Consumo Crítico):** Apache Pulsar (Java/JVM, intensivo en RAM/IO) y ScyllaDB (C++, optimizado para exprimir el almacenamiento y la CPU).

2. **Storage Line (I/O Intensivo):** SeaweedFS, Postgres y MongoDB.

3. **Observabilidad Eficiente:** Se eligió VictoriaMetrics + OpenObserve, ya que es infinitamente más ligero que el stack LGTM completo y consume una fracción de la RAM y CPU.

4. **Runtime & Core Apps:** Keycloak, Knative/OpenFaaS, Redis, Etcd, microservicios en Java (Spring Boot) y Go, y el Frontend.

### Distribución de VMs

Para aprovechar al máximo los 32 hilos y 64 GB de RAM, dejando aproximadamente un 15% de margen libre en cada Mini PC para que el hipervisor Proxmox opere con holgura (unos 4-5 GB de RAM libres por máquina), creamos 3 Control Planes y 4 Workers especializados en total.

1. 🖥️ **Mini PC 1 (pmx-01)** (Disponible: 16 vCPUs / 32 GB RAM -> Consumo estimado: 14 vCPUs asignadas y 26 GB de RAM):
   - `cp-01` **(Control Plane 1)**: 2 vCPUs, 3 GB RAM, 20 GB Disco.
   - `cp-03` **(Control Plane 2)**: 2 vCPUs, 3 GB RAM, 20 GB Disco (cuando agreguemos una tercera Mini PC, moveremos este control plane a dicha Mini PC).
   - `worker-data-01` **(Worker de Bases de Datos y Storage)**: 4 vCPUs, 10 GB RAM, 400 GB Disco.
     - *Servicios asignados:* Postgres (Primary), MongoDB (Primary), SeaweedFS (Master/Volume 1), Redis, Etcd.
   - `worker-apps-01` **(Worker de Aplicaciones y Serverless)**: 6 vCPUs, 10 GB RAM, 100 GB Disco.
     - *Servicios asignados:* Apps en Java y Go, Knative/OpenFaaS, Keycloak, Frontend.

2. 🖥️ **Mini PC 2 (pmx-02)** (Disponible: 16 vCPUs / 32 GB RAM -> Consumo estimado: 14 vCPUs asignadas y 26 GB de RAM):
   - `cp-02` **(Control Plane 3)**: 2 vCPUs, 3 GB RAM, 20 GB Disco.
   - `worker-heavy-02` **(Worker para Cargas Pesadas e Infraestructura)**: 6 vCPUs, 12 GB RAM, 200 GB Disco.
     - *Servicios asignados:* Apache Pulsar (BookKeeper, Broker, ZooKeeper), ScyllaDB.
   - `worker-ops-02` **(Worker de Observabilidad y Réplicas)**: 6 vCPUs, 11 GB RAM, 400 GB Disco.
     - *Servicios asignados:* VictoriaMetrics, OpenObserve, Pyroscope, Grafana, Réplicas de Postgres/MongoDB (en caso de armar clusters de DB), SeaweedFS (Volume 2).

### Beneficios de esta distribución:

1. **Aislamiento del "Vecino Ruidoso" (Noisy Neighbor):** Apache Pulsar y ScyllaDB pueden llegar a estresar mucho la CPU y la memoria. Al aislarlos en su propio Worker (`heavy-02`), se garantiza que un pico de tráfico en la mensajería no deje sin recursos a Keycloak o a las APIs de Go/Java que están en `apps-01`.

2. **Facilidad de Migración:** Al tener los servicios separados lógicamente por etiquetas de Kubernetes (usando `nodeSelector` o `tolerations`), si el día de mañana se quiere hacer mantenimiento en la máquina que aloja el nodo 2 de Proxmox, se puede desalojar (`kubectl drain`) la VM de aplicaciones o de observabilidad hacia el nodo 1 de Proxmox de manera transparente, ya que el dimensionamiento está pensado para que puedan coexistir temporalmente en situaciones de emergencia.

3. **Aprovechamiento del Almacenamiento:** SeaweedFS se distribuirá entre el worker de datos y el de observabilidad, permitiendo simular un entorno S3 distribuido real usando los discos NVMe locales de ambas máquinas físicas.



## Configuración de las Credenciales que usará el Proveedor de Proxmox desde Terraform

_**Nota:** Los pasos a continuación describen la forma en que creamos el API Token de Autenticación en Proxmox que usaremos desde Terraform, sin embargo, en [este enlace](https://registry.terraform.io/providers/bpg/proxmox/0.110.0/docs#api-token-authentication) se detalla cómo podríamos hacerlo a través de la shell de cada Nodo de Proxmox._

Para que Terraform pueda conectarse a las Mini PCs y crear las VMs, necesita un token de acceso seguro. Se debe hacer este proceso en ambas Mini PCs (`https://192.168.0.10:8006` y `https://192.168.0.11:8006`):

1. Abrir la interfaz web de Proxmox.
2. Ir a Datacenter > Permissions > **Users**.
3. Hacer clic en Add y crear un usuario llamado `terraform-prov@pve` (en caso de que solicite asignar contraseña, se puede dejar en blanco o asignarle una temporal).
4. Ir a API Tokens (justo debajo de Users) y hacer clic en Add.
   - Seleccionar el usuario `terraform-prov@pve@pam`.
   - Poner un ID al Token, por ejemplo: `tf-token`.
   - Desmarcar la casilla "Privilege Separation" (para simplificar los permisos del Homelab). Esto lo que hace es indicar que el usuario que se está creando heredará los permisos del usuario que lo está creando, que en este caso es el usuario *root*.
   - Hacer clic en Add.
5. ⚠️ **MUY IMPORTANTE:** Proxmox mostrará en pantalla el Token ID y el Secret. Se deben copiar y guardar en un bloc de notas temporal ya que No se volverán a mostrar.
6. Ir a Datacenter > Permissions > click en Add > **API Token Permission**.
   - Path: `/`
   - Token: Seleccionar `terraform-prov@pve@pam!tf-token`.
   - Role: Seleccionar `Administrator`.
   - Propagate: Debe estar seleccionado.
   - Hacer clic en Add.
7. Ir a Datacenter > Permissions > click en Add > **User Permission**.
   - Path: `/`
   - Token: Seleccionar `terraform-prov@pve@pam`.
   - Role: Seleccionar `Administrator`.
   - Propagate: Debe estar seleccionado.
   - Hacer clic en Add.

*Se deben repetir exactamente estos mismos pasos en la segunda Mini PC para obtener su respectivo token.*



## Generar llave SSH para Acceder a Proxmox desde Terraform

Aunque Talos no usa SSH de forma nativa (se administra 100% vía API con `talosctl`), y aunque el proveedor `bpg/proxmox` utiliza la API web (puerto `8006`) para casi todo (crear la estructura de las VMs, asignar RAM, CPUs y encenderlas), la infraestructura de Proxmox sí requiere la conectividad SSH de Terraform para preparar el terreno (que para nuestro caso de configuración automática, será para subir los snippets con la configuración 0).

1. El primer paso es generar la llave en nuestra máquina local:

   ```sh
   ssh-keygen -t ed25519 -C "correo@email.com" -f ~/.ssh/id_proxmox_terraform
   # Contraseña: Al pedir una passphrase, presionar Enter dos veces para dejarla en blanco ya que queremos que
   # Terraform automatice las conexiones sin pedir claves interactivamente.
   ```

2. El siguiente paso es configurar el archivo SSH Config para que la máquina local sepa exactamente qué clave usar cuando se conecta a Proxmox. Para esto, editamos el archivo de configuración:

   ```sh
   # Abrimos el archivo
   nano ~/.ssh/config
   ```

   Y en el archivo que se abre agregar las siguientes líneas:

   ```text
   Host 192.168.0.10 192.168.0.11
       User root
       IdentityFile ~/.ssh/id_proxmox_terraform
       IdentitiesOnly yes
   ```

   `IdentitiesOnly yes` evita que la máquina local intente usar otras llaves, previniendo bloqueos por demasiados intentos fallidos.

3. Copiar la llave pública a ambos nodos de Proxmox para autorizar el acceso:

   ```sh
   ssh-copy-id -i ~/.ssh/id_proxmox_terraform.pub root@192.168.0.10
   ssh-copy-id -i ~/.ssh/id_proxmox_terraform.pub root@192.168.0.11
   ```

   Al intentar copiar la llave en cada servidor de proxmox, debemos ingresar la contraseña del usuario `root` que se configuró al instalar Proxmox (Que es la misma con la que se accede a la interfaz web de Proxmox).

Para validar que nuestra llave funciona, podemos intentar acceder a ambos servidores vía SSH y deberíamos poder acceder sin que se nos pida ingresar la contraseña:

```sh
ssh -i /Users/andres/.ssh/id_proxmox_terraform 'root@192.168.0.10'
ssh -i /Users/andres/.ssh/id_proxmox_terraform 'root@192.168.0.11'
```



## Obtener la imagen inmutable de Talos Linux

Talos Linux no utiliza instaladores tradicionales; funciona mediante imágenes de disco pre-construidas. Cuando el PC tiene un procesador AMD Ryzen moderno (como en el caso de mis mini PCs), es ideal que la imagen incluya el agente de QEMU para que Proxmox pueda ver métricas internas de la VM (como por ejemplo su IP real).

Para obtener la imagen preconstruída se deben seguir los siguientes pasos:

1. Abrir el navegador en la máquina local (en mi caso, en mi Macbook) y entrar a la herramienta oficial: [Talos Image Factory](https://factory.talos.dev/).
2. Configurar las opciones:
   - **Hardware Type:** Cloud Server (esta es para homelab environments como Proxmox).
   - **Talos Version:** Seleccionar la última estable (ej. `v1.13.x` o superior); en mi caso, fue la `v1.13.4`.
   - **Cloud:** Nocloud (ya que vamos a ejecutar sobre Proxmox).
   - **Architecture:** amd64.
3. En la sección de Extensions, buscar y seleccionar:
   - `siderolabs/qemu-guest-agent` (Fundamental para que Proxmox se comunique con la VM).
4. **Bootloader:** auto.
5. En el último step, se verán los links de descarga. Se puede descargar en formato `raw.xz` o `iso`; Sin embargo, en este caso copiamos el link de la versión `iso` ya que usaremos dicho enlace para descargar directamente la imagen en nuestos nodos Proxmox. Por lo general, este enlace tendrá la siguiente forma: `https://factory.talos.dev/image/.../v1.13.4/nocloud-amd64.iso`.
6. Adicionalmente, se debe copiar ambién el enlace de la sección *Initial Installation*, ya que este lo necesitaremos al momento de generar la configuración de Talos. Este enlace debería tener la forma `factory.talos.dev/nocloud-installer/...:v1.13.4` donde los `...` corresponden al mismo checksum del enlace del archivo `iso`.



## Descargar la imagen en el servidor Proxmox

Después de haber generado la imagen de Talos, se debe agregar dicha imagen en cada Nodo de Proxmox. Aquí tenemos 2 opciones: subir un iso, o descargarla directamente al Nodo desde algún enlace.

En este caso, como en el paso anterior obutvimos un enlace, usaremos la opción de descargar desde un enlace. Este proceso se debe hacer en ambas Mini PCs (`https://192.168.0.10:8006` y `https://192.168.0.11:8006`):

1. Abrir la interfaz web de Proxmox.
2. Ir a Datacenter -> `pmx-01` (ó `pmx-02` según corresponda) -> `local (pmx-01)` (ó `local (pmx-02)`) > ISO Images.
3. Hacer clic en **Download from URL**.
4. En el campo URL, pegar el enlace que habíamos obtenido y hacer clic en **Query URL**.
5. En File name, podemos ajustar el nombre; Ese es el nombre con el quedará la iso en nuestro nodo Proxmox. En este caso, le pondré `talos-nocloud-amd64-with-qemu.iso`.
6. Hacer clic en **Download**. Esto mostrará un cuadro de dialogo con el proceso de descarga; se debe esperar hasta que muestre `TASK OK`; en ese momento ya se puede cerrar ese cuadro de diálogo.



## Creación del API Token de Cloudflare para la validación de nuestro dominio

_**NOTA:** (Opcional) Para realizar este paso es obligatorio tener un dominio asociado a nuestra cuenta de Cloudflare, ya sea que lo hayamos registrado ahí mismo en Cloudflare o que lo hayamos transferido desde otro proveedor; en mi caso, registré el dominio `eljavatar.org`._

Cuando configuremos nuestro Certificado TLS para tráfico seguro externo, lo haremos usando el emisor Let's Encrypt. Let's Encrypt necesita un API token de Cloudflare para automatizar la validación del dominio mediante el sistema DNS (desafío DNS-01). Específicamente, le permite crear registros TXT temporales, obtener certificados comodín (wildcard, como por ejemplo `*.eljavatar.org`) y renovarlos cada 90 días sin abrir puertos en el servidor ni intervención manual.

Para crear el API Token con las configuraciones que requerimos, debemos hacer lo siguiente:


### Creación det Token en Cloudflare

Para iniciar el proceso de configuración del token, debemos seguir los siguientes pasos, teniendo en cuenta que ya hemos de haber registrado previamente nuestro dominio dentro de Cloudflare:

1. Iniciar sesión en el panel de Cloudflare.
2. En la esquina superior derecha, hacer clic en el ícono del perfil y seleccionar **Profile**.
3. En el menú lateral izquierdo, hacer clic en **API Tokens**.
4. Hacer clic en el botón azul **Create Token**.
5. Ir a la sección **Custom token** y en la opción **Create Custom Token** (Crear token personalizado), hacer clic en **Get Started**.

Esto nos mostrará una serie de configuraciones que veremos a continuación para configurar de forma segura nuestro token, otorgándole solo los mínimos privilegios que requerimos.


### Configuración de la Política de Permisos (La Matriz Segura)

Configuraremos los campos exactamente de la siguiente manera para restringir el acceso:

- **Token name:** `k8s-homelab-cert-manager-dns01`
- **Permissions (Permisos):**
  - En el primer permiso: **Account** |> **Account Settings** |> **Read** (manteniendo el principio de mínimo privilegio, le otorgamos un permiso que tendría el menor impacto posible para nuestra cuenta).
  - Agregar otra fila y seleccionar **Zone** |> **DNS** |> **Edit**
  - *(Opcional pero recomendado para depuración):* Añadir otra fila con **Zone** |> **Zone** |> **Read** (Permite a cert-manager listar nuestros dominios para verificar que el ID de la zona es correcto).
- Account Resources:
  - Dejamos seleccionado **Include** |> **All accounts** (el alcance lo limitamos de forma estricta usando Zone Resources, y por tanto, el token queda bloqueado exclusivamente para ese dominio; además, el token no tendrá permisos para hacer nada en ninguna cuenta, ya que no le asignamos ningún permiso crítico a nivel de `Account` en la matriz anterior).
- **Zone Resources (Recursos de la zona):**
  - Seleccionar **Include** |> **Specific zone** |> **`eljavatar.org`**
- **TTL (Tiempo de vida):** Lo dejaremos en blanco para que no expire, ya que `cert-manager` lo usará continuamente cada 60-90 días para renovar los certificados automáticamente.

Finalmente, hacemos clic en **Continue to summary** y luego en **Create Token**.

**⚠️ Importante:** Debemos copiar el API token generado inmediatamente y guardarlo en un lugar seguro ya que Cloudflare no nos permitirá volver a ver el valor del token por motivos de seguridad.



## Habilitar Acceso desde Internet con Cloudflare Tunnel

_**NOTA:** (Opcional) Para realizar este paso es obligatorio tener un dominio asociado a nuestra cuenta de Cloudflare, ya sea que lo hayamos registrado ahí mismo en Cloudflare o que lo hayamos transferido desde otro proveedor._

Es posible dar acceso a los servicios y aplicaciones alojados en nuestro clúster local (y en general a cualquier aplicación que tengamos corriendo en el clúster) configurando un DNS público en Cloudflare apuntando a la IPv4 que nos asigna nuestro proveedor de internet, y configurando nuestro router físico para que haga un *Port Forwarding* de los puertos externos `80` y `443` hacia los respectivos puertos internos `80` y `443` de la IP de nuestro Gateway (que en nuestro caso será la `192.168.0.70`).

De esta forma, el tráfico desde internet viajaría así: `Usuario -> Cloudflare (Proxy) -> Nuestro Router -> Cilium Gateway (192.168.0.70:443) -> HTTPRoute -> Service -> Deployment (Pod de la aplicación)`.

Sin embargo, hacerlo de esta manera significa que estaríamos abriendo los puertos `80` y `443` en nuestro router, lo cual, por motivos de seguridad, es una práctica no recomendada para la administración de un Homelab profesional, ya que expondría nuestra IP residencial a escaneos maliciosos de Internet.

La solución a esto es usar **Cloudflare Tunnels** (aunque también existen otras alternativas a Cloudflare). Este mecanismo funciona mediante un modelo *Zero Trust*: en lugar de que nuestro router abra un puerto para "escuchar" conexiones que vienen de fuera, un pequeño agente que corre dentro de nuestro clúster de Kubernetes abre una conexión **saliente y segura** hacia los servidores globales de Cloudflare.

El tráfico de Internet entra a Cloudflare, viaja cifrado por ese tubo saliente y llega directamente a nuestro clúster de Kubernetes, sin necesidad de abrir un solo puerto en nuestro router, sin importar si nuestra IP residencial es dinámica o si estamos detrás de un CGNAT de nuestro proveedor de internet (la tecnología que usan los ISPs para que varios clientes compartan una misma dirección IP pública).

De este modo, el flujo de tráfico se daría de la siguiente forma:

`Usuario -> Cloudflare (Internet) -> Cloudflare Tunnel (Pod) -> Cilium Gateway (192.168.0.70:443) -> HTTPRoute -> Service -> Deployment (Pod de la aplicación)`.

De esta forma obtenemos los siguientes beneficios en cuanto a seguridad:

- **Perímetro Ciego:** Nuestro router residencial mantiene bloqueados todos los puertos entrantes (`80`, `443`, etc.). De este modo, *Shodan* o cualquier escáner de malware de internet verá nuestra IP pública como totalmente cerrada.
- **Protección DDoS Gratuita:** Al pasar todo por la red de Cloudflare, si alguien intenta atacar nuestro dominio (`eljavatar.org`), la mitigación ocurre en los servidores perimetrales de Cloudflare y nuestra conexión residencial nunca se saturará de tráfico basura.

Así pues, los pasos para crear nuestro túnel son los siguientes:

1. Ir al panel de Cloudflare y en el menú izquierdo hacer clic en **Zero Trust**. Si es la primera vez que accedemos, probablemente nos saldrá una Landing page de bienvenida a *Cloudflare Zero Trust*, en la cual debemos seguir los siguientes pasos:
   - Hacer clic en **Get started**.
   - Selecionar el plan gratuito **(Zero Trust Free)**.
   - En la págna de *Activate Zero Trust Free*, aceptar los términos y hacer clic en **Activate**.
   - En la página de confirmación y resumen, validar que el costo es $0, y hacer clic en **Continue to Zero Trust**.

2. Ir a **Networks** -> **Tunnels & Mesh** (o puede que solo diga **Tunnels**) y hacer clic en **Create a tunnel**.

3. Hacer clic en **Select Cloudflared**.

4. Le ponemos un nombre descriptivo al túnel (ej. `eljavatar_k8s_talos_cluster`) y damos clic en **Save tunnel**.

5. En la siguiente pantalla, Cloudflare nos mostrará los comandos para instalar el agente (`cloudflared`) en diversos sistemas operativos. Como tal no nos interesa instalarlo en nuestra máquina local, ya que lo que realmente necesitamos de ahí es un Token largo que aparece en el bloque de código. Así que copiamos cualquiera de los bloques que muestren el token para poder obtenerlo y lo guardamos en un bloc de notas. Al pegarlo en un bloc de notas, se vería algo así (copiaré uno de los bloques que se muestran para Mac):
   ```sh
   cloudflare tunnel run --token my_token_tunnel_clouflare
   ```

   **⚠️ Importante:** Debemos copiar el token del túnel generado inmediatamente y guardarlo en un lugar seguro ya que Cloudflare no nos permitirá volver a ver el valor de este token por motivos de seguridad.

6. Después de guardarnos el token, hacemos clic en **Next**.

7. Finalmente se nos muestra la página de *Route Traffic*. En esta página podremos configurar el acceso a algún servicio en específico dentro de la pestaña *Published applications*. Aquí es obligatorio configurar un acceso (a pesar de que aún no tengamos levantado ningún servicio) ya que hay campos que son obligatorios (como el *Domain*, *Type* y *URL*) para poder completar la configuración. Así que agregaremos un hostname y service de prueba que después podremos editar o eliminar:
   - En la sección **Hostname**:
     - **Subdomain:** prueba (o el valor que queramos)
     - **Domain:** seleccionamos nuestro dominio
   - En la sección **Service**:
     - **Type:** HTTP
     - **URL:** localhost:8080

8. Para terminar, hacer clic en **Complete setup**.

Al finalizar, nos mostrará nuestro túnel en estado `Inactive`, ya que aún no tenemos ningún agente de `clauflared` corriendo, sin embargo, después de que levantemos dicho pod en nuestro clúster pasará a estado `Healthy`.



## Crear los archivos Terraform para crear el Clúster de Kubernetes

Para gestionar dos nodos independientes de Proxmox que formarán un único clúster de Kubernetes de forma limpia, utilizaremos el proveedor moderno `bpg/proxmox` (en este caso, la versión 0.110.0). Así pues, creamos en la carpeta `terraform/` los siguientes archivos (el contenido de dichos archivos se puede revisar en este mismo repositorio (excepto el archivo `terraform/terraform.tfvars`)):

- `terraform.tfvars`: En este archivo crearemos variables de entorno que usarán los otros archivos de terraform, como por ejemplo, el api_token de los nos nodos de proxmox (este archivo lo agregamos al `.gitignore` para evitar exponer secretos o variables sensibles):

  ```bash
  pmx01_token = "terraform-prov@pve@pam!tf-token=SECRET_DE_PMX01"
  pmx02_token = "terraform-prov@pve@pam!tf-token=SECRET_DE_PMX02"
  vault_token = "TOKEN_DE_LOGIN_DE_VAULT"
  # Estas variables a continuación solo serían necesarias si tenemos un dominio Cloudflare,
  # y ejecutamos terraform usando use_prod_domain=true
  personal_email = "personal-email@example.com"
  cloudflare_account_email = "cloudflare-account@example.com"
  # En secciones previas ya vimos cómo se crean estos tokens
  cloudflare_api_token = "TOKEN_DE_CLOUDFLARE"
  cloudflare_tunnel_token = "TOKEN_DEL_TUNNEL_DE_CLOUDFLARE"
  ```

- `variables.tf`: En este archivo especificamos las variables que usaremos, incluyendo las que definimos en el archivo `terraform.tfvars` para que sus valores puedan ser usados desde los scripts de terraform.

- `locals.tf`: En este archivo especificamos lo que se denominan como variables calculadas (las que se construyen por ejemplo a través de aplicarles una función) y las constantes que usaremos.

- `providers.tf`: En este archivo especificamos los provider de proxmox para cada una de los nodos, los cuales tendrán como endpoint la respectiva IP de cada nodo (`https://192.168.0.10:8006/` y `https://192.168.0.11:8006/`).

- `main.tf`: En este archivo especificamos las VMs que se crearán en cada uno de los nodos de proxmox, indicando detalles como por ejemplo el id de la VM, el Nodo sobre el cual se crearán (el provider), la memoria asignada, la cantidad de cores y el espacio en disco asignado; además, también hacemos el bootstrap automático del clúster.

- `k8s-bootstrap.tf`: En este archivo especificamos la configuración y componentes que requerimos para que nuestro clúster de Kubernetes quede en un estado Ready to Work (CNI, CoreDNS, CSI, etc.).

- `talos-patches.tf`: Actualmente este archivo no contiene nada, pero en caso de que en el futuro se requiera realizar un cambio directamente sobre una VM (como por ejemplo cambiar los DNS), lo definiríamos en este archivo.



## Inicialización y Despliegue de la Infraestructura

Una vez creados los archivos `variables.tf`, `local.tf`, `providers.tf` y `main.tf` y el archivo secreto `terraform.tfvars` protegido por el `.gitignore`, debemos ejecutar los siguientes comandos en la terminal (desde la ruta del proyecto donde se encuentran estos archivos, no en la `shell` de los nodos de Proxmox):

```sh
# NOTA: Por lo general se suele usar solamente comandos como 'terraform init', 'terraform apply', etc., sin
# embargo, para evitar saltar hasta el directorio 'terraform/' que es donde tenemos nuestros scripts de
# terraform, usamos el flag global -chdir, el cual le indica a Terraform que cambie temporalmente su entorno
# de ejecución a la carpeta especificada antes de correr cualquier subcomando

# 1. Descargar los plugins y los proveedores (bpg/proxmox, siderolabs/talos, etc.)
terraform -chdir=terraform init

# 2. Validar que la sintaxis sea correcta y no existan errores
terraform -chdir=terraform validate

# 3. Ver una previsualización de lo que Terraform va a crear en Proxmox
terraform -chdir=terraform plan

# 4. Crear de forma masiva las 7 máquinas virtuales (confirmar escribiendo yes)
terraform -chdir=terraform apply
# Por defecto, el script de Terraform está preparado para ejecutar con las siguientes propiedades:
# - auto_config_cluster=true -> Crea las VMs en Proxmox, hace el bootstrap del clúster y deja el clúster
#   con todas las configuraciones necesarias para empezar a usarlo. Si se asigna a false, Solo crea las
#   VMs y hace el bootstrap.
# - is_development=true -> Configura un admisionControl de tal modo que no se tenga que agregar un label
#   a cada namespace para forzar que los pods tengan privilegios. Para entornos productivos, lo ideal
#   sería que estuviera seteado en false.
# - use_local_iso=false -> Por defecto, el script descarga la imagen de Talos y la sube a cada nodo de
#   Proxmox. En caso de tener problemas de conectividad a internet, lo ideal sería asignarlo en true, pero
#   se debería subir la ISO como lo vimos anteriormente.
# - use_prod_domain=true -> Indica que va a crear el secret con el token de Cloudflare, además de el
#   respectivo ClusterIssuer para Let's Encrypt y agregar la respectiva configuración del listener en
#   el manifiesto del Gateway API (solo tiene efecto si auto_config_cluster=true).
# - use_letsencrypt_prod=false -> Indica que por defecto, Let's Encrypt firmará los certificados a través
#   de su servidor ACME de Staging (solo tiene efecto si use_prod_domain=true).

# Aquí vemos un ejemplo de cómo usar estas variables:
terraform -chdir=terraform apply \
  -var="auto_config_cluster=false" \
  -var="is_development=false" \
  -var="use_local_iso=true" \
  -var="use_prod_domain=false" \
  -var="use_letsencrypt_prod=true"

# Para ver más comandos y opciones de lo que podemos hacer con Terraform, podemos ver este recurso didáctico de 
# 90 días de DevOps con Roxs, donde dedican un par de secciones solo a Terraform:
# https://90daysdevops.295devops.com/semana-04/dia22/


# Alternativa para evitar pasar el flag '-chdir=terraform' en cada comando:
# Debido a que configuramos un archivo 'Makefile' podríamos ejecutar los comandos de terraform mediante 'make':
make tf-init

make tf-validate

make tf-plan

make tf-apply

# En caso de querer pasar parámetros:
make tf-apply \
  AUTO_CONFIG_CLUSTER=false \
  IS_DEVELOPMENT=false \
  USE_LOCAL_ISO=true \
  USE_PROD_DOMAIN=false \
  USE_LETSENCRYPT_PROD=true
```

Si no se obtiene ningún error, el `apply` creará las respectivas VMs en cada uno de los Nodos de Proxmox e inicializará el clúster (`bootstrap`). Además si se ejecuta con `auto_config_cluster=true`, se configurará todo el clúster de forma automática (CNI, Certificados, Almacenamiento, etc.).



# Bootstrap del Clúster (El Nacimiento de Kubernetes)

Por lo general, para inicializar un clúster con Talos se suelen seguir una serie de pasos mediante los cuales primero se genera una configuración usando `talosctl`, y se aplican dichas configuraciones a cada VM según corresponda (si es `controlplane` o si es `worker`), para finalmente hacer el `bootstrap` (inicialización del clúster). Sin embargo, mediante Terraform, y usando el provider de `siderolabs/talos` podemos generar toda esta configuración automáticamente. Así pues, aquí veremos estas 2 formas de inicializar nuestro clúster: la forma automática y la forma manual.



## Opción A: Bootstrap Automático (Recomendada)

El archivo `main.tf` está preparado para crear las VMs en Proxmox y aplicar la configuración 0 de las VMs de Talos. De este modo, al ejecutar `terraform apply`, se realizan los siguientes pasos:

1. **Descarga de la ISO:** Terraform realiza la descarga automática de la ISO de Talos y se almacena en cada uno de los Nodos de Proxmox.
2. **Creación de Snippets de Inicialización:** Se generan archivos YAML mediante un bloque `data` de tipo `talos_machine_configuration` y se almacenan como snippets en cada uno de los Nodos de Proxmox.
3. **Creación de VMs y Primer arranque:** Terraform creará la VM con un disco `scsi0` vacío. Al encenderse, la VM intentará leer `scsi0`, fallará y pasará automáticamente a `ide3` (la ISO de Talos). Sin embargo, postponemos unos segundos su encendido para que cuando arranque la ISO ya se haya detectado la unidad Cloud-Init de Proxmox (`ide2`).
4. **Lectura de Configuración Estática:** Durante el arranque de la ISO, Talos detectará la unidad Cloud-Init de Proxmox (`ide2`), leerá el user-data (el YAML generado por el bloque `data` de tipo `talos_machine_configuration` de Talos) y aplicará inmediatamente la IP estática y hostname que se le configuró.
5. **Instalación:** Al procesar el YAML, Talos verá la directiva `install.image` y procederá a auto-instalarse en el disco local (`scsi0`). Al terminar, la VM se reiniciará sola.
6. **Segundo arranque:** Tras el reinicio, como `scsi0` ya tiene el cargador de arranque de Talos consolidado, iniciará directamente desde el disco duro ignorando la ISO de la lectora.
7. **Bootstrap:** Finalmente, después de esperar unos segundos, Terraform realiza el bootstrap del clúster, lo que da nacimiento al clúster de kubernetes. Adicionalmente, se extraen los respectivos archivos de configuración.

_**NOTA:** Como se puede apreciar en esta lista de pasos, con el modo automático no necesitaremos descargar manualmente la imagen en cada uno de los nodos de Proxmox, puesto que esto ya lo hace Terraform (el paso de obtener la imagen inmutable de Talos desde la Factory sigue siendo requerido, ya que necesitamos los enlaces). Sin embargo, si la conexión a internet es inestable o lenta, podría ser conveniente tener con antelación la imágen en cada nodo de Proxmox, y hacer el apply de la siguiente forma: `terraform apply -var="use_local_iso=true"`; de esta forma le indicamos a Terraform que no descargue una imagen sino que use la que se descargó previamente en cada nodo de Proxmox._


### Configurar el CLI local (`talosctl`)

Para que la máquina local (en este caso mi Macbook) sepa cómo y a dónde conectarse de forma segura, se deben ejecutar los siguientes comandos para configurar los endpoints:

```sh
# Esto es necesario para posteriormente mergear este contexto en el '~/.talos/config' global
export TALOSCONFIG=./talos/talosconfig
```



## Opción B: Bootstrap Manual

Este es el camino manual, y esto requeriría en primer lugar, eliminar (o comentar) el código del archivo `terraform/main.tf` y agregar el código que se encuentra en el archivo `terraform/main.tf.manual`; además debemos también eliminar (o comentar) el código del archivo `terraform/k8s-bootstrap.tf`. En tal caso de querer hacer el bootstrap del clúster a través de esta forma, las variables que explicamos anteriormente que se pueden usar al hacer el `terraform apply`, dejarían de cobrar relevancia, ya que se deberían realizar manualmente cada una de las configuraciones que se explican en las siguientes secciones.


### Generar los Archivos de Configuración del Clúster

En muchos tutoriales indican que primero se debe obtener la IP de la VM que será usada como Control Plane principal para generar la configuración con dicha IP. Sin embargo, las IPs que se les asignan a dichas VMs, están dadas por el servidor DHCP del router, y como ya habíamos indicado previamente, en nuestro homelab no es recomendable que estas VMs tengan IPs dinámicas.

Por tanto, en este caso vamos a generar la config con la IP `192.168.0.30` (que es la IP que escogimos como IP virtual del clúster para garantizar alta disponibilidad de los control planes), y posteriormente ajustaremos las IPs de las VMs.

En la terminal de la máquina local (en mi caso mi MacBook Pro), hay que asegurarse de estar en la carpeta del proyecto y ejecutar el siguiente comando para crear las plantillas de configuración:

```sh
talosctl gen config eljavatar-k8s-talos-cluster https://192.168.0.30:6443 \
    --output-dir talos \
    --install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.13.4
```

*(Nota: El puerto `6443` es el puerto estándar de la API de Kubernetes).*

Este comando generará 3 archivos cruciales en el directorio `talos` del proyecto (los cuales se deben proteger y añadir al `.gitignore` para no subirlos a GitHub):

- `controlplane.yaml`: La configuración que le aplicaremos a las 3 VMs de Control Plane.
- `worker.yaml`: La configuración que le aplicaremos a los 4 Workers.
- `talosconfig`: El archivo de credenciales de administración (equivalente al `kubeconfig`, pero para el sistema operativo).

**¿Para qué se usa `--install-image`?**

Talos Linux es un sistema operativo inmutable y efímero que corre inicialmente en la memoria RAM (gracias al ISO). Cuando se ejecuta un nodo por primera vez desde la ISO, Talos está técnicamente "en vivo" (live CD), pero aún no se ha instalado permanentemente en el disco duro virtual de la máquina de Proxmox (`scsi0`).

El parámetro `--install-image` le dice a Talos qué imagen de contenedor (Docker/OCI) debe descargar y "quemar" en el disco duro (`scsi0`) para que, cuando la máquina virtual se reinicie, inicie directamente desde el disco y no dependa de la ISO.

Si no se especifica `--install-image`, el comando `talosctl gen config` pone una imagen por defecto dentro del archivo YAML (usualmente algo genérico como `ghcr.io/siderolabs/installer:v1.13.4`).

Talos viene por defecto "desnudo" (sin controladores adicionales). Si el entorno requiere extensiones (como controladores de almacenamiento para Proxmox, QEMU Guest Agent, etc.), la Image Factory genera un instalador personalizado que empaqueta todo eso. Ese hash largo (`ce4c980550dd...`) es el identificador único de esa combinación de controladores.

Así pues, si se usa un instalador genérico (es decir, si no se le pasa `--install-image`), el riesgo es que se podría perder soporte optimizado para características específicas del entorno (como el QEMU Guest Agent que activamos en Terraform para reportar la IP a la interfaz de Proxmox de forma limpia).


### Crear los Parches de Red Estática (Machine Config Patches)

Para no agregar IPs estáticas a los archivos YAML principales (`controlplane.yaml` y `worker.yaml`, lo cual rompería la escalabilidad), creamos pequeños archivos de parche individuales para cada VM, los cuales ubicaremos en la carpeta `talos/patches/init` de este proyecto ([How to Configure Static IP Addresses in Talos Linux](https://oneuptime.com/blog/post/2026-03-03-configure-static-ip-addresses-in-talos-linux/view), [The Bare Metal Kubernetes Blueprint: Deploy Talos Linux](https://www.servermo.com/howto/deploy-talos-linux-kubernetes-bare-metal/)).

Estos archivos tienen la siguiente estructura:

```yaml
machine:
  nodeLabels:
    topology.kubernetes.io/zone: "pmx-01"
    custom-role: cp
  network:
    interfaces:
      - interface: eth0
        # Si no quisiéramos usar interface: eth0, podríamos usar un selector por mac address
        # pero esto implica tener que crear las VMs con esta misma dirección mac
        # deviceSelector:
        #   hardwareAddr: "52:54:00:12:34:56"
        dhcp: false
        addresses:
          - 192.168.0.31/24
        routes:
          - network: 0.0.0.0/0
            gateway: 192.168.0.1
        # SOLO PARA LOS CONTROL PLANE
        vip:
          ip: 192.168.0.30 # <--- Elegimos una IP LIBRE de la subred para el clúster HA
    nameservers:
      - 1.1.1.1
      - 8.8.8.8
  kubelet:
    extraArgs:
      rotate-server-certificates: "true" # Permite que el nodo pida renovar sus certificados automáticamente
    extraConfig:
      serverTLSBootstrap: true
    clusterDNS:
      - 10.96.0.10
    # Este extraMounts solo aplicaría a los Workers
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
    extraMounts:
      - destination: /var/openebs/local
        type: bind
        source: /var/openebs/local
        options:
          - bind
          - rshared
          - rw
cluster:
  # Esta configuración es para deshabilitar Flannel (ya que vamos a instalar Cilium posteriormente)
  network:
    cni:
      name: none
  proxy:
    disabled: true
  coreDNS:
    disabled: true
  apiServer:
    admissionControl:
      - name: PodSecurity
        configuration:
          apiVersion: pod-security.admission.config.k8s.io/v1
          kind: PodSecurityConfiguration
          defaults:
            audit: privileged
            audit-version: latest
            enforce: privileged
            enforce-version: latest
            warn: privileged
            warn-version: latest
          exemptions:
            namespaces: []
            runtimeClasses: []
            usernames: []
---
apiVersion: v1alpha1
kind: HostnameConfig
hostname: cp-01
auto: off # Desactiva la generación automática
```

En estos archivos podemos apreciar que configuramos una IP Virtual (VIP) integrada de Talos, lo cual es crítico debido a que vamos a levantar al menos 3 nodos de Control Plane. Si dejamos nuestras configs de kubernetes y talos apuntando rígidamente a la IP de un solo nodo de kubernetes (como `192.168.0.31`), en el momento en que la máquina física que aloja dicho nodo entre en mantenimiento o la VM se apague, perderemos el acceso a la API de Kubernetes, rompiendo el propósito de tener 3 planos de control.

**¿Cómo funciona la VIP de Talos?:** Talos utiliza el protocolo VRRP a nivel de sistema operativo. Elegimos una IP libre de la red de Proxmox (por ejemplo, `192.168.0.30`) que no pertenezca a ninguna máquina física ni virtual para que Talos la levante de forma flotante en el nodo de kubernetes que actúe como líder. Si ese nodo falla, la IP migra automáticamente a cualquiera de los otros dos Control Planes en milisegundos; además, para que esto se de, el `cluster endpoint` y el archivo `kubeconfig` deberán apuntar siempre a esa IP Virtual.

Así pues, creamos 7 archivos tipo `yaml`, en los cuales lo único que cambiamos es la propiedad `machine.network.interfaces[0].addresses[0]`, los `nodeLabels` y el `hostname`; además, para los que son de tipo control plane, también configuramos la `vip` y las configuraciones a nivel de `cluster`. A continuación vemos las IPs que usaremos.

IPs para los **control-plane**:

- `patches/init/cp-01.yaml`: `192.168.0.31/24`
- `patches/init/cp-02.yaml`: `192.168.0.32/24`
- `patches/init/cp-03.yaml`: `192.168.0.33/24`

IPs para los **workers**:

- `patches/init/worker-data-01.yaml`:  `192.168.0.40/24`
- `patches/init/worker-apps-01.yaml`:  `192.168.0.41/24`
- `patches/init/worker-heavy-02.yaml`: `192.168.0.42/24`
- `patches/init/worker-ops-02.yaml`:   `192.168.0.43/24`


### Aplicar la Configuración Combinada a las Máquinas Virtuales

Con los comandos que veremos en esta sección es que hacemos el cambio de IPs actuales que fueron asignadas dinámicamente por el servidor DHCP del router, por las IPs estáticas que indicamos manualmente en los anteriores archivos.

Pero primero debemos obtener primero dichas IPs dinámicas que tiene cada VM. Para esto, gracias a que nuestra imagen tiene el agente QEMU, podemos encontrarlas en Datacenter -> pmx-01 (ó pmx-02) -> 101 (talos-cp-01) (ó la VM que corresponda) > Summary (También se podría obtener de > Console, pero sin la máscara (`/24`)). En mi caso, las IPs fueron las siguientes:

Para los **control-plane**:

- `101 (talos-cp-01)`: `192.168.0.154`
- `102 (talos-cp-02)`: `192.168.0.187`
- `103 (talos-cp-03)`: `192.168.0.248`

Para los **workers**:

- `201 (talos-worker-data-01)`: `192.168.0.155`
- `202 (talos-worker-apps-01)`: `192.168.0.190`
- `203 (talos-worker-heavy-02)`: `192.168.0.170`
- `204 (talos-worker-ops-02)`: `192.168.0.191`

Antes de configurar las IPs estáticas, necesitamos saber los nombres de interfaces en nuestra máquina. Cuando ya estén encendidas las VMs (incluso en modo `maintenance`), ejecutamos lo siguiente (hacemos esto con al menos una IP de VM Talos de cada Nodo Proxmox):

```sh
# List network interfaces (identificamos las que estén up)
talosctl get --insecure links --nodes 192.168.0.154

# Get detailed interface information (identificamos la que tenga la IP que le estamos pasando)
talosctl get --insecure addresses --nodes 192.168.0.154
```

En caso de que el nombre de la interface sea distinto a `eth0`, debemos reemplazar en los archivos de patches anteriores por el valor correcto en la propiedad `machine:network:interfaces:[0]:interface`. Algunos nombres de interface que podríamos obtener serían `eth0`, `eth1`, `eno1`, `eno2`, `enp0s3`, `enp0s8`, `ens3`, `ens4`, etc.

Por otro lado, antes de aplicar los patches de configuración inicial, debemos crear el directorio que usará OpenEBS del directorio `/var` (podemos ver más acerca de la configuración de OpenEBS Local PV en Talos en [este tutorial](https://oneuptime.com/blog/post/2026-03-03-set-up-openebs-local-pv-on-talos-linux/view)):

```sh
# Creemos la ruta del host en cada worker antes de agregarlo como un bind mount de kubelet.
talosctl exec --nodes <IP_DINAMICA_ACTUAL_WORKER_DATA> -- mkdir -p /var/openebs/local
talosctl exec --nodes <IP_DINAMICA_ACTUAL_WORKER_APPS> -- mkdir -p /var/openebs/local
talosctl exec --nodes <IP_DINAMICA_ACTUAL_WORKER_HEAVY> -- mkdir -p /var/openebs/local
talosctl exec --nodes <IP_DINAMICA_ACTUAL_WORKER_OPS> -- mkdir -p /var/openebs/local

# Verificamos que se creó el path
talosctl ls /var/openebs --nodes <IP_DINAMICA_ACTUAL_WORKER_DATA>
```

Las IPs dinámicas que acabamos de obtener las debemos reemplazar según corresponda en las siguientes instrucciones que debemos ejecutar en la terminal desde la máquina local (en mi caso, la Macbook Pro):

```sh
# --- CONTROL PLANES ---
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_CP_01> --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-01.yaml
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_CP_02> --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-02.yaml
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_CP_03> --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-03.yaml

# --- WORKERS ---
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_WORKER_DATA> --file talos/worker.yaml --config-patch @talos/patches/init/worker-data-01.yaml
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_WORKER_APPS> --file talos/worker.yaml --config-patch @talos/patches/init/worker-apps-01.yaml
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_WORKER_HEAVY> --file talos/worker.yaml --config-patch @talos/patches/init/worker-heavy-02.yaml
talosctl apply-config --insecure -n <IP_DINAMICA_ACTUAL_WORKER_OPS> --file talos/worker.yaml --config-patch @talos/patches/init/worker-ops-02.yaml
```

Estos cambios de IP se aplican inmediatamente sin reiniciar las VMs (aunque unos segundos después se reinician), por tanto, tan pronto los hayamos ejecutando podemos ir validando que se haya asignado la nueva IP en cada una de las VMs. Además en la consola también se puede apreciar que se actualiza el tipo de instancia, ya sea por `controlplane` o `worker` según sea el caso.

#### Problema de reinicio de los Control Planes

*NOTA: En nuestro caso, en el archivo `main.tf` agregamos la instrucción `boot_order = ["scsi0", "ide3"]`, lo cual evita este problema, sin embargo, lo dejo documentado ya que sirve para entender cómo funciona el proceso de instalación de Talos.*

Como mencioné anteriormente, el cambio de IP se aplica sin reiniciar las VMs, sin embargo, cuando aplicamos la configuración de los archivos `controlplane.yaml` o `worker.yaml` según sea el caso, se realizan otros ajustes que sí hacen que se reinicien las VMs unos segundos después, y para el caso específico de las VMs asignadas como control plane, estas van a reiniciar con la IP que tenían previamente y de nuevo con type `unknown`.

En este punto, si intentamos ejecutar de nuevo `talos apply-config...`, obtendremos un error como el siguiente:

```
error applying new configuration: rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial tcp 192.168.0.154:50000: connect: connection refused"
```

Este es un comportamiento directamente relacionado con la instalación en el disco duro virtual. Veamos qué es lo que pasa exactamente en este escenario:

1. **El primer `apply-config` gatilla la instalación:** Cuando se ejecuta el comando por primera vez, Talos recibe la configuración, aplica temporalmente el parche de IP estática y, al ver que es su primer arranque, procede a formatear el disco virtual (`scsi0`) e instalar el sistema operativo de forma permanente.
2. **La VM se reinició:** Al aplicar el cambio de IP no se reinicia la máquina; sin embargo, para completar la instalación del control-plane, Talos reinicia automáticamente la máquina virtual.
3. **El bucle de arranque de Proxmox (El problema central):** Al reiniciarse, debido al orden de arranque o a que la ISO sigue montada, **la VM volvió a arrancar desde la ISO en modo Live CD** en lugar de arrancar desde el disco duro donde se acababa de instalar.
4. **Por eso volvió a la IP dinámica:** Al arrancar desde la ISO de nuevo, toda la configuración estática que se le había enviado previamente se borra (porque la ISO es efímera y corre en RAM), el router le vuelve a dar la IP (en mi caso, `.154`, `.187` y `.248`) por DHCP, y el estado de la máquina pasa a `unknown` (porque vuelve al estado de fábrica, esperando configuración).
5. **El error de conexión rechazada (Puerto 50000):** Cuando se intenta enviar el comando de nuevo a la IP dinámica (por ejemplo a la `.154`), da `connection refused`. Esto pasa porque tras el reinicio desde la ISO, el demonio interno de Talos (`talosd`) a veces entra en un estado de protección o mantenimiento, o los certificados temporales cambiaron, bloqueando el puerto API 50000.

En los Workers esto no sucede porque ellos no intentan formar el cluster de inmediato ni sufren el mismo flujo crítico de votación de Etcd que los Control Planes al reiniciarse.

#### Solución al Problema de reinicio de los Control Planes

Para solucionar esto, se debe romper el bucle para que las VMs inicien desde el disco duro virtual donde ya está instalado Talos.

##### Paso 1: Cambiar el orden de arranque en Proxmox

Nos debemos asegurar de que el disco duro (`scsi0`) sea la prioridad número uno de booteo y, idealmente, remover la ISO de la unidad lectora de CD-ROM. Para esto, se deben seguir los siguientes pasos:

1. Ir a la interfaz web de Proxmox.
2. Seleccionar la VM correspondiente al `cp-01` (hacer esto para los 3 control planes).
3. Ir a Options -> Boot Order.
4. Hacer doble clic y desmarcar la ISO (o el CD-ROM, que en nuestro caso, es el `ide3`) y asegurarse de que `scsi0` (el disco duro virtual) esté marcado y en la **posición #1**.
5. *Opcional pero recomendado:* Ir a Hardware, seleccionar la lectora de CD-ROM con la ISO de Talos y darle a Edit -> seleccionar **Do not use any media** (quitar la ISO).

##### Paso 2: Reiniciar las VMs de los Control Planes

Apagar y encender las VMs de los control planes desde Proxmox para obligarlas a leer el disco duro.

Al arrancar desde el disco, se podrá notar una de dos situaciones dependiendo de si la instalación logró guardarse por completo antes del reboot:

- **Caso A (Ideal):** La VM levanta directamente con la IP estática que se le había asignado (la `.31`, `.32`, etc.). Si es así, ¡listo! Ya se puede continuar con el cluster.
- **Caso B (Lo más probable por el estado unknown):** La VM levanta desde el disco duro pero vuelve a pedir IP por DHCP (por ejemplo, la `.154`) porque no guardó el parche, por lo que debemos volver a aplicarlo en cada VM. Pero hay una gran diferencia: ahora que está corriendo desde el disco, el puerto 50000 volverá a estar abierto y receptivo.

##### Paso 3: Volver a aplicar la configuración (Si cayó en el Caso B)

Si las máquinas volvieron a tomar la IP por DHCP pero ya arrancando desde el disco, se debe volver a lanzar los comandos de `talos apply-config...` para los control planes. Esta vez se aplicará de forma definitiva, la IP cambiará a la estática permanentemente y los Control Planes comenzarán a inicializar el cluster de Kubernetes (`etcd`).

```sh
talosctl apply-config --insecure -n 192.168.0.154 --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-01.yaml
talosctl apply-config --insecure -n 192.168.0.187 --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-02.yaml
talosctl apply-config --insecure -n 192.168.0.248 --file talos/controlplane.yaml --config-patch @talos/patches/init/cp-03.yaml
```


### Configurar el CLI local (`talosctl`)

Para que la máquina local (en este caso mi Macbook Pro) sepa cómo y a dónde conectarse de forma segura, se deben ejecutar los siguientes comandos para configurar los endpoints:

```sh
# Decirle a talosctl dónde buscar el archivo de configuración creado
export TALOSCONFIG=./talos/talosconfig

# Configurar el nodo por defecto y los endpoints de confianza
# Como mencionamos anteriormente, 'config endpoint' debe apuntar a la IP Virtual,
# pero 'config node' si debe apuntar a una IP real (en este caso, la del CP 01)
talosctl config endpoint 192.168.0.30
talosctl config node 192.168.0.31
```


### El Bootstrap del Clúster

En un entorno tradicional se tendría que correr `kubeadm init`, configurar certificados, etc. En Talos, solo se necesita ejecutar el comando de `bootstrap` una única vez y apuntando exclusivamente al **Control Plane 1** (como el clúster aún no existe, la IP virtual flotante `.30` tampoco existe aún, por tanto, para hacer el bootstrap se debe apuntar a la IP real de una VM de tipo control plane):

```sh
# Ejecutar el Bootstrap (Solo una vez al Control Plane 1)
talosctl bootstrap -n 192.168.0.31

# En caso de que se desee pasar la configuración directamente (por ejemplo, porque en la sesión hay otra
# variable de entorno llamada TALOSCONFIG apuntando a otro cluster con una ruta distinta, y se quiera
# crear en la misma sesión del terminal otro clúster), se puede usar el siguiente comando
#talosctl --talosconfig ./talos/talosconfig bootstrap -n 192.168.0.31
```

Este comando le indica a `talos-cp-01` que inicialice la base de datos `etcd`. Una vez que el primer nodo esté listo, los otros dos Control Planes se unirán a él automáticamente para formar el quórum de Alta Disponibilidad, y posteriormente los Workers se acoplarán solos.

Para monitorear este proceso de inicialización, podemos ejecutar el siguiente comando (lo pongo como referencia, ya que en nuestro caso terminará lanzando un error por timeout (ver la nota a continuación para entender el por qué)):

```sh
talosctl health
```

_**NOTA:** Debido a que desactivamos el CNI por defecto (`cni: name: none`), los nodos del clúster entrarán en estado `NotReady`. Kubernetes necesita un CNI para asignar IPs a los pods y levantar componentes críticos como `coredns` (además, en nuestro caso haremos más adelante la instalación de CoreDNS manualmente mediante `helm`). Como `coredns` se quedará en estado `Pending`, el plano de control nunca se considerará completamente "saludable" y `talosctl health` se quedará esperando hasta lanzar un error por timeout._



## Asociar el kubeconfig de Kubernetes al archivo global

El proceso de inicialización puede tardar entre 2 y 3 minutos. Cuando se vea que los servicios de `red` (estos aún no los podremos ver en estado saludable por lo que explicamos anteriomente) y `etcd` están en estado saludable, asociamos al archivo de configuración global `~/.kube/config` el archivo de accesos para `kubectl` de éste clúster que se acabó de crear, ejecutando lo siguiente:

```sh
#talosctl kubeconfig ./talos/kubeconfig
#export KUBECONFIG=./talos/kubeconfig
talosctl kubeconfig ~/.kube/config --talosconfig ./talos/talosconfig
```

En muchos tutoriales se suele ver que esta configuración se hace ejecutando `talosctl kubeconfig ./talos/kubeconfig` y `export KUBECONFIG=./talos/kubeconfig` para crear el kubeconfig y crear la variable de entorno respectivamente. Sin embargo, si se cierra la terminal, o nos pasamos a otra terminal, deberíamos volver a asignar la variable de entorno.

Por tanto, en lugar de crear un archivo `kubeconfig` separado por cada clúster, se le puede indicar a `talosctl` que fusione las credenciales de este nuevo homelab dentro del archivo de configuración global de la máquina local (`~/.kube/config`), inyectando así el contexto `eljavatar-k8s-talos-cluster` de forma segura en el archivo global de la máquina local de desarrollo.

De esta forma, en caso de reiniciar la terminal, o de tener varios clústers de kubernetes, no es necesario ir hasta la carpeta del repositorio y configurar la variable de entorno para ejecutar comandos de `kubectl`.

Para asegurarnos de que el contexto de nuestro clúster se haya fusionado en el archivo `~/.kube/config`, podemos abrirlo usando:

```sh
nano ~/.kube/config
```

Así pues, para cambiar de un clúster a otro, simplemente se usaría el siguiente comando nativo de Kubernetes desde cualquier carpeta de la máquina local:

```sh
# Primero, obtenemos los nombres de contextos que tenemos configurados:
kubectl config get-contexts

# En caso de querer renombrar el contexto.
# En versiones recientes de Talos, el nombre del contexto se crea anteponiendo 'admin@', por tanto,
# si queremos renombrar nuestro contexto de modo tal que no tenga ese 'admin@', usamos esto:
kubectl config rename-context admin@eljavatar-k8s-talos-cluster eljavatar-k8s-talos-cluster

# Seteamos el contexto que queremos esté activo:
kubectl config use-context eljavatar-k8s-talos-cluster
```

Después de esto, se puede verificar que el clúster esté completamente operativo y reconozca los 7 nodos mediante los siguientes comandos:

```sh
# Verificar el clúster de kubernetes
kubectl cluster-info

# Verificar el estado de los nodos
kubectl get nodes -o wide

# Ver los miembros del clúster de talos
talosctl get members

# También se podría monitorear/validar con k9s
k9s

# Adicionalmente, podemos ver los servicios que se están ejecutando en algún nodo en específico
talosctl -n 192.168.0.31 services

# También podemos acceder al dashboard de un nodo en específico (por ejempo para ver logs del SO)
talosctl -n 192.168.0.31 dashboard

# También podemos ver los pods que están corriendo actualmente en el clúster
kubectl get pods -A -o wide
```



## Controlar `talosctl` globalmente sin pisar otros clústeres

Esto puede ser opcional, pero sería necesario si en algún momento se quisieran gestionar varios clústeres de kubernetes creados a partir de Talos. Si `kubectl` usa el contexto de `~/.kube/config`, ¿cómo sabe `talosctl` a qué clúster/nodo físico le está enviando un comando (como un parche, un reinicio o una actualización) si estamos parados en otra carpeta de la máquina local?

Talos resuelve esto exactamente de la misma manera que Kubernetes, utilizando **Contextos** dentro de su propio archivo de configuración, pero con una ventaja: se pueden fusionar las credenciales de Talos en un archivo global en el Home.

Para lograr que `talosctl` sea global y agnóstico de la carpeta donde se esté ubicado (como hacemos con `kubectl`), seguimos la siguiente estrategia:

### Paso A: Fusionar el archivo de Talos en la configuración global de la Máquina local

Así como Kubernetes usa `~/.kube/config`, Talos busca por defecto sus accesos en `~/.talos/config`.

Una vez creado el clúster actual, se puede fusionar de forma permanente el `talosconfig` local del repositorio dentro del Home ejecutando lo siguiente:

```sh
# Crea el directorio por si no existe
mkdir -p ~/.talos

# Forzamos a talosctl a escribir en el archivo global heredando el del proyecto
# Esto lo hacemos, porque a diferencia de otras herramientas, el comando 'talosctl config merge' toma por defecto
# el archivo que se tiene activo en la variable de entorno o en la ruta local actual y le fusiona el contenido de
# otro. Si el directorio actual en la terminal es la raíz del proyecto, el comando 'talosctl config merge' aplica
# el merge sobre el propio archivo local ./talos/talosconfig.
# Esto requiere que previamente se haya ejecutado 'export TALOSCONFIG=./talos/talosconfig'
TALOSCONFIG=~/.talos/config talosctl config merge ./talos/talosconfig
```

Para verificar que se mergeó, correctamente, podemos abrir el archivo de config global:

```sh
nano ~/.talos/config
```

Además, si ejecutamos `talosctl config contexts` desde otra terminal, deberíamos poder ver la lista de contextos globales. En mi caso, la salida es algo como esto:

```
CURRENT   NAME                          ENDPOINTS      NODES
*         eljavatar-k8s-talos-cluster   192.168.0.30   192.168.0.31
```

### Paso B: Cambiar de clúster en Talos

En caso de tener múltiples clústeres de Talos registrados en la máquina local de desarrollo, para saber a cual se está apuntando o cambiarlo, podemos usar los siguientes comandos:

```sh
# Listar los clústeres de Talos que la máquina local conoce
talosctl config contexts

# Ver información del contexto actual (opcional)
talosctl config info

# Cambiar el contexto activo global de Talos al que corresponda
talosctl config context eljavatar-k8s-talos-cluster
```

### Paso C: Cómo se aplican los comandos de forma segura (Ej: Agregar una 3ra Mini PC)

Cuando se ejecuta un comando operativo de Talos (como aplicar un parche de red estática a un nuevo nodo), Talos exige dos niveles de validación obligatorios en el comando para evitar desastres:

1. El contexto activo (que define las llaves criptográficas de cifrado).
2. El nodo específico (`-n <IP_DEL_NODO>`) al que va dirigido el comando.

Así pues, si en el futuro se agrega una tercera Mini PC (pmx-03) y se quiere patchear su IP, el comando se ejecutaría desde cualquier lugar de la máquina local así:

```sh
# Configurar una nueva VM
talosctl apply-config --insecure -n <IP_DINAMICA_DE_LA_NUEVA_VM> --file /ruta/al/repo/talos/controlplane.yaml --config-patch @/ruta/al/repo/talos/patches/init/cp-04.yaml

# Aplicar un patch a una VM ya existente:
talosctl patch machineconfig \
  --nodes <IP_FIJA_ALGUNA_VM_EXISTENTE> \
  --patch @/ruta/al/repo/talos/patches/some-patch.yaml
```

Talos validará: "*¿Tengo las llaves de cifrado del contexto activo para hablar con esta IP?*" Si coinciden, aplicará el cambio. Si por error se intenta enviarle un comando del Homelab a una IP de otro clúster (por ejemplo del trabajo), la firma criptográfica fallará inmediatamente y rechazará la conexión. El sistema es extremadamente seguro.

**NOTA:** Esta sería la forma manual de hacerlo, sin embargo, lo recomendable sería agregar el respectivo bloque `talos_machine_configuration_apply` en los archivos de Terraform; de esta forma, al ejecutar `terraform apply`, los cambios se aplicarán uniformemente a todas las VMs (o incluso a ciertas VMs en específico). De este modo, al configurar herramientas como FluxCD podríamos tener un flujo de Despliegue continuo en nuestro clúster.

Si no se desea usar la ruta absoluta del proyecto, siempre se puede igual acceder al directorio donde está el repositorio.



## Eliminar el clúster de Talos y Kubernetes (Opcional)

Por lo general, no vamos a querer eliminar nuestro clúster, pero si ese fuera el caso (porque por ejemplo quisiéramos usar nuestro servidor Proxmox con un propósito distinto), a continuación dejo los pasos para hacerlo (sin tener que eliminar manualmente las VMs desde la interfaz web de Proxmox):

### Paso 1: Destruir las VMs desde la máquina local

Dado que creamos la infraestructura con Terraform, no es necesario borrar nada a mano en la interfaz de Proxmox. Dejaremos que Terraform limpie su propio rastro para que su archivo de estado (`terraform.tfstate`) quede en cero.

Estando ubicados en la carpeta del repositorio (donde tenemos el archivo `main.tf`), ejecutamos lo siguiente:

```sh
make tf-destroy
# O: terraform -chdir=terraform destroy
```

Esto apagará y eliminará por completo las VMs de los nodos de Talos en ambas Mini PCs que estén configuradas en el archivo `main.tf` (que en este caso son 7), liberando CPU, RAM y almacenamiento.

### Paso 2: Limpiar los archivos de configuración locales

#### 1. Limpiar el archivo `~/.kube/config` (Kubernetes)

Como es posible que tengamos otros clústeres configurados localmente que no queramos perder, lo ideal es usar `kubectl` para remover solo el contexto de este clúster. Para eso, ejecutamos lo siguiente:

```sh
# Obtenemos el nombre del contexto:
kubectl config get-contexts
kubectl config get-clusters
kubectl config get-users

# Eliminamos el contexto
kubectl config unset current-context
kubectl config delete-context eljavatar-k8s-talos-cluster # Resultado de get-contexts
kubectl config delete-cluster eljavatar-k8s-talos-cluster # Resultado de get-clusters
kubectl config delete-user admin@eljavatar-k8s-talos-cluster # Resultado de get-users
kubectl config unset current-context

# Para verificar, abrir el archivo ~/.kube/config y corroborar que ya no exista el contexto de este clúster:
nano ~/.kube/config

# Además, si ejecutamos el siguiente comando, ya no nos debería aparecer este contexto:
kubectl config get-contexts
```

Este mismo resultado podemos lograrlo ejecutando el siguiente Script:

```sh
# Otorgamos permisos al script
chmod +x clean_kubeconfig.sh

# Ejecutamos
./clean_kubeconfig.sh # ó ./clean_kubeconfig.sh nombre-contexto
```

En caso de que no tengamos otros contextos de kubernetes configurados, podríamos simplemente ejecutar `rm -f ~/.kube/config`.

#### 2. Limpiar el archivo `~/.talos/config` (Talos)

Al igual que con kubernetes, es posible que tengamos otros contextos configurados que queremos mantener, así que del mismo modo, lo ideal es usar `talosctl` para remover solo el contexto de este clúster. Para eso, ejecutamos lo siguiente:

```sh
# A diferencia de kubectl, talosctl no permite eliminar un contexto que está actualmente en uso para evitar
# dejar la herramienta en un estado inválido.
# Por tanto, si tenemos otros clústeres en talosctl y no queremos borrar todo el archivo, se debe obligar
# a Talos a apuntar a "ningún lado" o a otro contexto antes de borrarlo:
talosctl config add temporal --endpoints 127.0.0.1
talosctl config context temporal

# Remover el contexto
talosctl config remove eljavatar-k8s-talos-cluster # Al pedir confirmación, presionar 'y'

# Opcional: Si se quiere dejar el archivo impecable después de esto, se puede ejecutar el siguiente comando
# después de recrear el clúster
# talosctl config remove temporal

# Para verificar, abrir el archivo ~/.talos/config y corroborar que ya no exista el contexto de este clúster:
nano ~/.talos/config

# Además, si ejecutamos el siguiente comando, ya no nos debería aparecer este contexto:
talosctl config contexts
```

*Nota:* En versiones anteriores de talos, no se podían eliminar contextos mediante `talosctl`, así que en esos casos, lo que habría que hacer es abrir el archivo de configuración usando `nano ~/.talos/config` y eliminar de las secciones `contexts` y `clients` únicamente las líneas correspondientes al contexto en cuestión.

En caso de que no tengamos ningún otro contexto, el archivo `~/.talos/config` se vería de la siguiente forma:

```yaml
context: temporal
contexts:
    temporal:
        endpoints: []
```

Si quisiéramos dejarlo limpio de contextos (sin tener que eliminar dicho archivo), podríamos reemplazar su contenido por lo siguiente:

```yaml
context: null
contexts: {}
```

Aún así, del mismo modo que con kubernetes, en caso de que no tengamos otros contextos de talos configurados, podríamos simplemente ejecutar `rm -f ~/.talos/config`.

También hay que asegurarse de borrar de la carpeta local `talos/` del proyecto, los archivos `controlplane.yaml`, `worker.yaml` y `talosconfig` antiguos para que no causen confusiones (si hacemos el bootstrap del clúster de la forma automática (Opción A) y no hacemos modificaciones o patches manuales sobre dichos archivos, el comando `terraform destroy` también los eliminaría automáticamente).





# Configuración del Clúster

_**NOTA DE DESARROLLADOR:** Cuando se ejecuta el comando `terraform apply` por defecto se hace con la variable `auto_config_cluster=true`, lo que significa que todo el proceso que detallo en esta sección de configuración se realizará de forma automática. Sin embargo, lo dejo documentado ya que fue el proceso manual que yo mismo seguí antes de pasar a automatizar todo con Terraform. Además es una gran fuente de documentación en la que no solo muestro los comandos para ejecutar cada paso, sino que también trato de explicar lo más detallado posible cada una de estas configuraciones._



## Configuración de la Red de Pods (CNI)

Talos Linux viene preparado para trabajar con **Flannel** por defecto para ofrecer una experiencia inicial sencilla y lista para usar, ya que Flannel funciona sin depender de componentes complejos y cubre las necesidades básicas de red. Sin embargo, **Cilium** es el estándar de la industria preferido para producción debido a su mejor rendimiento y seguridad, además de que ofrece varias ventajas técnicas significativas frente a Flannel:

- **Tecnología eBPF:** Reemplaza las reglas tradicionales de `iptables` procesando la red directamente en el kernel de Linux, lo que reduce la latencia y mejora el rendimiento.
- **Network Policies avanzadas:** Mientras que Flannel se limita a asignar IPs sin bloquear tráfico, Cilium permite restringir la comunicación entre pods a nivel de capa 3, 4 e incluso capa 7 (por ejemplo, filtrando peticiones HTTP o cabeceras).
- **Observabilidad superior:** Incluye *Hubble*, una herramienta que permite visualizar gráficamente el tráfico de red del clúster.

Estas características permiten que en lugar de tener reglas de rango de IP que varían a medida que los pods se reinician, se puedan escribir reglas basadas en la identidad: por ejemplo, permitir que `role=frontend` acceda a `role=api`, independientemente de dónde se ejecuten. La aplicación de eBPF proporciona ese control, además de la posibilidad de observar a nivel de paquete qué pods se comunican y qué se descarta, sin necesidad de sidecars. En [este artículo](https://www.pimwiddershoven.nl/entry/networking-on-talos-linux-with-cilium/) se pueden encontrar más a detalle otras razones del por qué preferir Cilium sobre Flannel (también pueden versen algunos ejemplos de configuración de Network policies, ya que por defecto, no existe ninguna política, por lo que se permite todo el tráfico).

Recordemos que cuando levantamos las VMs y aplicamos las configuraciones de Talos, desactivamos el CNI de Flannel y desactivamos el `kube-proxy` predeterminado para que Cilium pueda reemplazarlo:

```yaml
cluster:
  network:
    cni:
      name: none
  proxy:
    disabled: true
  coreDNS:
    disabled: true
```

`kube-proxy` es el componente que programa las reglas de iptables para que los servicios de tipo `ClusterIP` y `NodePort` se dirijan a los pods correctos. Cilium puede realizar la misma función en eBPF interceptando el tráfico de servicio en el kernel sin escribir reglas de iptables, lo que resulta más rápido y proporciona visibilidad a nivel de servicio en Hubble; esta es la técnica de `kubeProxyReplacement`, y solo funciona si el `kube-proxy` predeterminado no está en uso.

Al deshabilitar `kube-proxy`, Cilium necesita otra forma de acceder a la API de Kubernetes. Para esto, Talos expone [KubePrism](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/kubeprism) en `localhost:7445`, un balanceador de carga local que actúa como interfaz para los endpoints de los Control Plane. Así pues, Cilium utiliza este balanceador como endpoint de su API.

Adicionalmente, también deshabilitamos CoreDNS para que no se levante desde el bootstrap del clúster; esto debido a que queremos customizar algunos aspectos de su despliegue como por ejemplo la cantidad de réplicas y los nodos de Talos sobre los que queremos que se levanten sus pods,lo cual haremos más adelante usando helm.


### Aplicar CRDs de Gateway API

Antes de instalar Cilium, se deben aplicar manualmente los CRDs de Gateway API, ya que si no se aplican, el operador de Cilium fallará al arrancar y entrará en un ciclo de error (*CrashLoopBackOff*). El Helm Chart de Cilium con `gatewayAPI.enabled: true` asume que las definiciones de Kubernetes para Gateway API ya existen en el clúster, y como Cilium no las instala por uno de forma automática, debemos hacerlo manualmente (en algunos tutoriales no los aplican manualmente ya que instalan Cilium usando la herramienta de comandos nativa (`cilium install --set gatewayAPI.enabled=true`) la cual detecta que faltan las CRDs y las descarga de internet e instala automáticamente, pero como en este caso estamos configurando un `values.yaml` para Helm, estamos haciendo la instalación pura y Helm no automatiza esta descarga):

```sh
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.4.1/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml

# Verificación:
kubectl get gatewayclass
# Como no tenemos ninguno creado, deberíamos obtener algo como "No resources found"
```

**¿Para qué sirven estos dos manifiestos?**

Kubernetes no incluye de forma nativa los recursos de Gateway API (como `Gateway`, `HTTPRoute` o `TLSRoute`) en su núcleo básico, por lo tanto, se manejan como Custom Resource Definitions (CRDs) externas:

- **`standard-install.yaml`**: Instala las CRDs oficiales y estables del proyecto de Kubernetes (como `GatewayClass`, `Gateway`, `HTTPRoute` y `ReferenceGrant`). Esto le enseña al clúster de Talos a entender el nuevo estándar que reemplaza al clásico `Ingress`.
- **`gateway.networking.k8s.io_tlsroutes.yaml`**: Instala la CRD experimental para TLSRoutes. Esto es vital para bases de datos y mensajería en Proxmox (como Apache Pulsar o PostgreSQL), ya que permite enrutar tráfico cifrado directamente a nivel de TLS sin necesidad de romper el cifrado en el balanceador.


### Validar y Aprobar los certificados

Por defecto, cuando un nodo (VM) de Talos se une al clúster, Kubernetes aprueba de forma automática su certificado de cliente (para que el nodo pueda leer de la API). Sin embargo, por motivos de seguridad estricta, Kubernetes **nunca aprueba de forma automática los certificados del servidor `kubelet`**, y debido a que cuando levantamos las VMs de Talos añadimos el parámetro `rotate-server-certificates = "true"`, estos certificados se renovaron y por tanto deben ser aprobados manualmente (aunque a continuación veremos cómo se puede automatizar este proceso):

```sh
# Listar las solicitudes de certificados (CSR)
# Esto mostrará una lista de recursos con nombres como 'csr-xxxxx' o 'node-csr-xxxxx' con condition 'Pending'
kubectl get csr

# Se puede aprobar cada certificado con 'kubectl certificate approve csr-xxxx', ó usar el siguiente
# comando para aprobarlos todos a la vez:
kubectl get csr -o name | xargs kubectl certificate approve
```

Una vez aprobados los nuevos CSRs, la condición en `kubectl get csr` cambiará a `Approved,Issued`.

_**Nota:** Esta es la forma manual de aprobar certificados, sin embargo, lo recomendabe es que haya un proceso que realice esta aprobación de forma automática como lo veremos a continuación._

#### Aprobar certificados automáticamente

##### El problema del certificado del Kubelet

Cada nodo (VM) de Talos Linux tiene un componente llamado `kubelet` (el encargado de levantar los contenedores). El Kubelet expone una API interna cifrada (TLS) en el puerto `10250` de modo que cuando se ejecutan comandos como `kubectl logs`, `kubectl exec` o `kubectl port-forward` para por ejemplo ver qué pasa dentro de Apache Pulsar o Postgres o cualquier aplicación, el servidor central de Kubernetes se conecta al Kubelet del nodo (la VM de Talos) que está corriendo sobre Proxmox.

Por seguridad estricta, Talos genera un certificado al iniciarse el `kubelet` sin la intervención de ningún firmante, y dicho certificado es el que usa ese endpoint TLS que mencionamos antes; sin embargo este certificado vence cada pocos días. Cuando caduca, Kubernetes bloquea la comunicación y comandos como `kubectl logs` o `kubectl top nodes` dejan de funcionar, arrojando errores de certificados TLS expirados o inválidos.

Sin embargo, el problema no es solo que este certificado inicial caduque, sino que el tráfico del Control Plane interno del clúster entre el `apiserver` y cada `kubelet` está cifrado pero no autenticado. Cualquiera que se encuentre en una posición man-in-the-middle puede interceptar las sesiones de ejecución de `kubectl`.

##### Solución

La solución consiste en que `kubelet` solicite un certificado de servicio a un firmante real en lugar de autofirmarlo. Kubernetes cuenta con un firmante integrado para este propósito (`kubernetes.io/kubelet-serving`), respaldado por la CA (Certificate Authority) del clúster.

Cuando `kubelet` se inicia con el arranque del certificado de servicio habilitado, envía una solicitud `CertificateSigningRequest` al `apiserver` solicitando un certificado de servicio con el nombre de host y la IP del nodo como SAN (Subject Alternative Name: es una extensión de los certificados digitales X.509 que permite asociar múltiples nombres de host, dominios o direcciones IP a un mismo certificado) (*significa que el certificado digital validará y aceptará conexiones cifradas HTTPS/TLS dirigidas específicamente a ese nodo, ya sea que uno se conecte usando su nombre de red oficial (hostname) o su dirección IP directa*). Si se aprueba, la solicitud es firmada por la CA del clúster, `kubelet` obtiene el certificado y el `apiserver` (con `--kubelet-certificate-authority` configurado con la CA del clúster) ahora tiene algo con lo qué verificar.

**Paso 1: Activar el autorenovado en Talos (Bootstrap)**

Kubernetes tiene un sistema para renovar estos certificados, pero no los aprueba automáticamente por miedo a que un nodo falso se infiltre en el clúster, y por ende, requiere que un humano apruebe manualmente cada renovación de cada nodo todo el tiempo (tal como lo hicimos con `kubectl certificate approve`).

De esta forma, con la configuración `rotate-server-certificates: "true"` que estamos seteando al configurar las VMs, le decimos a Talos que el Kubelet tiene permiso de solicitar la renovación de sus credenciales:

```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: "true"
    extraConfig:
      serverTLSBootstrap: true
```

Adicionalmente, también podemos ver que agregamos `serverTLSBootstrap: true`. Por defecto, cuando un nodo se une a Kubernetes, genera automáticamente un certificado de cliente TLS para poder autenticarse y hablar de forma segura con el `apiServer` (un proceso conocido como `Node TLS Bootstrapping`).

Sin embargo como ya lo habíamos mencionado previamente, la comunicación en sentido inverso (cuando el `apiServer` necesita conectarse directamente al `kubelet` de un nodo, por ejemplo para ejecutar comandos con `kubectl exec` o leer métricas mediante Metrics Server (a través de `kubelet/metrics`)) se realiza usando certificados autofirmados generados de forma local por cada nodo. Esto expone al clúster a ataques de tipo Man-in-the-Middle (MitM) porque el `apiserver` no tiene una forma de validar rigurosamente la autenticidad de esa conexión.

Al activar `serverTLSBootstrap: true`, se obliga al proceso `kubelet` de cada nodo a solicitar de manera formal un certificado de servidor firmado por la **Autoridad de Certificación** (CA) interna del clúster. De este modo, el flujo se daría de la siguiente forma:

1. El nodo emite una petición de firma de certificado (*CSR* o Certificate Signing Request) pidiendo un certificado de servidor antes de que caduque (tras el siguiente reinicio (o al ejecutar `talosctl service kubelet restart`), cada nodo tendrá una CSR pendiente en el `apiserver`, a la espera de aprobación).
2. Por motivos de seguridad, Kubernetes *no aprueba estas CSR automáticamente*. Quedan en estado *Pending* permanentemente.
3. Aquí es donde entra el aprovador automático que veremos a continuación: intercepta esas peticiones en estado pendiente, analiza de manera segura que la IP y el nombre correspondan a un nodo del clúster legítimo (que en nuestro caso, son las VMs que levantamos sobre Proxmox en el rango de IPs `192.168.0.0/24` y con nombres que empiezan con `cp-` o `worker-`) y, si todo cumple con las reglas, aprueba la CSR en segundos.

**Paso 2: Instalar el aprobador automático**

Como Kubernetes no aprueba estos certificados solo, se debe desplegar el controller `kubelet-csr-approver`, cuya única función de vida será escuchar los CSR de tipo `kubelet-server` y aprobarlos al instante si provienen de un nodo legítimo del clúster. Este Pod actúa como un vigilante jurado: revisa si la solicitud de renovación viene de un nodo (VM) real y legítimo que levantamos sobre nuestro servidor Proxmox, y si es así, firma y aprueba la solicitud al instante:

```sh
helm repo add kubelet-csr-approver https://postfinance.github.io/kubelet-csr-approver
helm repo update

helm install kubelet-csr-approver kubelet-csr-approver/kubelet-csr-approver --version 1.2.14 \
  --namespace kube-system \
  -f k8s/deployments/kubelet-csr-approver-values.yaml

# Para validar quién firmó el certificado
echo | openssl s_client -connect 192.168.0.40:10250 -showcerts 2>/dev/null | openssl x509 -noout -issuer -subject
# issuer=O=kubernetes
# subject=O=system:nodes, CN=system:node:worker-data-01
```

_**Nota:** Hay que tener en cuenta que al igual que los pods de `coredns`, debido a que en este punto aún no tenemos un CNI configurado en nuestro clúster, los pods de `kubelet-csr-approver` van a quedar temporalmente en estado `Pending`._


### Instalar Cilium

El paso a seguir será entonces instalar Cilium en nuestro clúster:

```sh
# Agregamos el repositorio
helm repo add cilium https://helm.cilium.io
helm repo update

# En caso de que en cilium-values.yaml habilitemos routingMode en native:
# En el archivo cilium-values.yaml, configuramos la propiedad ipv4NativeRoutingCIDR.
# Para confirmar el CIDR de los pods, podemos ejecutar lo siguiente (en caso de ser
# distinto de "10.244.0.0/16", actualizar el valor en el archivo cilium-values.yaml):
# kubectl get pods -n kube-system -l component=kube-controller-manager -o yaml | grep cluster-cidr
# kubectl cluster-info dump | grep -i podcidr

# Instalamos Cilium usando los valores configurados
helm install cilium cilium/cilium --version 1.18.0 \
  --namespace kube-system \
  -f k8s/deployments/cilium-values.yaml


# NOTA: Si en este momento hacemos un 'kubectl get pods -A -n kube-system' veremos que el pod de
# hubble-relay tendrá en Ready 0/1 de pods (a pesar de que el status sea Running). Esto se debe a
# que aún no se ha configurado el servidor DNS del clúster (coreDNS), lo cual haremos a continuación


# Si en el futuro se quiere habilitar BGP (Ó modificar directamente el values):
# helm upgrade cilium cilium/cilium --namespace kube-system \
#   --reuse-values \
#   --set bgpControlPlane.enabled=true

# En caso de errores (Por el momento no podríamos ver logs con kubectl, así que lo hacemos con talosctl):
# Primero obtenemos la lista de containers
talosctl -n 192.168.0.31 containers -k # Reemplazar por la IP de la VM que queramos inspeccionar
# Y vamos inspeccionando los contenedores para encontrar la causa del error
talosctl -n 192.168.0.31 logs -k kube-system/cilium-wdk4z:cilium-agent:f75da14b594f
talosctl -n 192.168.0.31 logs -k kube-system/cilium-9dfmg:install-cni-binaries:9bd9be361811
talosctl -n 192.168.0.31 logs -k kube-system/cilium-envoy-rvvj4:cilium-envoy:80a0b64cfc3f
talosctl -n 192.168.0.31 logs -k kube-system/cilium-9dfmg:config:bcf171571b82
talosctl -n 192.168.0.31 logs -k kube-system/cilium-9dfmg:clean-cilium-state:90f8ccbda429
```

En el archivo `k8s/deployments/cilium-values.yaml` se pueden apreciar los bloques `cgroup` y `securityContext`, los cuales son específicos de Talos. Talos no monta automáticamente cgroup v2 como lo hace una distribución típica, por lo que es necesario indicarle a Cilium dónde encontrarlo.

Por otro lado, las listas de capacidades (`securityContext.capabilities`) son más limitadas que las predeterminadas de Cilium porque Talos funciona con un perfil de seguridad más estricto y rechaza los pods que solicitan más recursos de los necesarios. Esto se debe a que en los valores por defecto, se incluye la capacidad `SYS_MODULE`, la cual le permite a un contenedor cargar dinámicamente módulos directamente en el kernel de Linux, mientras que Talos es un sistema operativo minimalista y ultra-seguro que bloquea por completo la carga de módulos de kernel desde cargas de trabajo de Kubernetes; es por esta razón que en nuestro archivo de values sobreescribimos dicha lista de capacidades.


### Instalar CoreDNS

Por defecto, en Talos Linux la configuración y despliegue del servidor DNS del clúster (CoreDNS) se administra a nivel de clúster, y los manifiestos nativos que maneja Talos internamente para CoreDNS tienen prioridad sobre los `inlineManifests` (que son los que podríamos personalizar para por ejemplo especificar en qué nodo queremos que se levante) durante el bootstrap.

Esto quiere decir que si intentamos modificar el Deployment con `inlineManifests` sin deshabilitar primero el CoreDNS interno, Kubernetes ignorará los cambios o se generará un conflicto de reconciliación ("race condition"), y al deshabilitar CoreDNS (que es lo que estamos haciendo), si queremos que CoreDNS se levante desde el bootstrap del clúster, tendríamos que declarar en el `inlineManifests` todos los manifiestos para desplegarlo, lo cual sería bastante tedioso.

Por tanto, si queremos customizar el despliegue de CoreDNS, la [documentación oficial de Sidero](https://github.com/siderolabs/talos/discussions/10012) indica que se debe obligatoriamente deshabilitar `coreDNS: disabled: true` a nivel de cluster y luego desplegar manualmente CoreDNS, ya sea con manifiestos propios, o con Helm como lo haremos a continuación:

```sh
# Agregamos el repositorio
helm repo add coredns https://coredns.github.io/helm
helm repo update

# Instalamos CoreDNS usando los valores configurados
helm upgrade --install coredns coredns/coredns --version 1.46.0 \
  --namespace kube-system \
  -f k8s/deployments/coredns-values.yaml
```

En el archivo `k8s/deployments/coredns-values.yaml` especificamos reglas de `nodeAffinity` para que se instalen 3 instancias (para alta disponibilidad) de CoreDNS en nodos (VMs de Talos) de tipo `apps` (`worker-apps-01`), `data` (`worker-data-01`) y `ops` (`worker-ops-02`), en conjunto con reglas de `podAffinity` para indicarle además que intente por todos los medios no poner dos CoreDNS en el mismo nodo, pero si no hay otra opción, que las coloque juntas en pro de mantener las 3 réplicas vivas.


### Validar Instalación de Cilium en el Clúster

Cilium lee el archivo `~/.kube/config`. Si se tienen varios clústeres, se debe cambiar el contexto activo antes de usar cilium (`kubectl config current-context`).

```sh
# Validar qué clúster está viendo Cilium
# Esto espera a que el agente de cada nodo y el operador informen que están listos,
# luego imprime un resumen de lo que se está ejecutando:
cilium status --wait

# Verificación en el clúster
# Como instalamos el chart con 'gatewayAPI.enabled: true', podemos verificar que Cilium ha tomado
# el control y está listo para aprovisionar los balanceadores con el siguiente comando (se debería
# ver una clase llamada cilium con el estado Accepted: True. Esto confirmará que el puente entre las
# CRDs de Gateway API que se acabaron de instalar y el motor eBPF de Cilium se realizó con éxito):
kubectl get gatewayclass

# Como el Cilium que instalamos ya tiene Hubble activado, podemos abrir la interfaz gráfica en
# el navegador local con:
cilium hubble ui

# Adicionalmente, podemos validar el estado de salud de Talos:
talosctl health
```

_**Nota:** En clústeres nuevos con Talos, a veces los nodos generan una segunda tanda de CSRs unos minutos después de aprobar la primera, pero gracias a que instalamos el aprobador de certificados, éstos CSRs deberían aprobarse automáticamente. Sin embargo, en tal caso de que al intentar validar el estado de Cilium (`cilium status`) o el estado de salud de talos (`talosctl health`) veamos que hay errores por certificados TLS, deberíamos volver a ejecutar `kubectl get csr` y aprobar los que estén en `Pending` (`kubectl get csr -o name | xargs kubectl certificate approve`)._

- **Opcional:** Solo en caso de que haya que volver a aprobar nuevos certificados, después de que la condición cambie a `Approved,Issued` (al ejecutar `kubectl get csr`), los agentes de Cilium deben enterarse de que la vía de comunicación TLS es totalmente segura y válida, y para eso se les debe dar un reinicio rápido a los componentes de cilium y coredns

  ```sh
  # Reinicia los operadores y agentes de Cilium
  kubectl rollout restart deployment cilium-operator -n kube-system
  kubectl rollout restart daemonset cilium -n kube-system
  kubectl rollout restart daemonset cilium-envoy -n kube-system
  kubectl rollout restart deployment hubble-relay -n kube-system

  # Reinicia CoreDNS para que tome la nueva red de Cilium limpia
  kubectl rollout restart deployment coredns -n kube-system
  ```

Adicionalmente, para una verificación más exhaustiva, podemos ejecutar una prueba de conectividad de Cilium. Esta prueba crea unos namespaces temporales, despliega un pequeño conjunto de pods y realiza pruebas de conectividad `pod-to-pod`, `pod-to-service`, y de DNS en todo el clúster; al finalizar la prueba, borra todos los recursos que creó para esta prueba. Aunque tarda unos minutos, es la forma más segura de confirmar que Cilium funciona correctamente antes de añadirle cargas de trabajo reales:

```sh
# Por lo general, se suele ver que solo se ejecuta 'cilium connectivity test' para realizar la prueba.
# Sin embargo, en nuestro caso agregamos los siguientes parámetros:
# - test '!pod-log-errors': Indicamos que ignore el test que lee el log de errores de los pods que se crean, ya
#   que la prueba `check-log-errors` de Cilium es extremadamente estricta. Este test analiza los registros de
#   texto (logs) de todos los Pods del sistema buscando palabras clave como `error` o `failed`; sin embargo,
#   pueden darse casos en los que por ejemplo al hacer un refresh de la conexión por flujo (stream) hacia Hubble
#   Relay la operación se cancela de golpe porque el pod se reinicia, y estas pequeñas trazas de errores hacen
#   que dicho test no pase. Por eso es mejor ignorar dicho test.
# - namespace-labels: Talos Linux viene fuertemente endurecido por defecto a nivel de seguridad, y por tanto,
#   aplica de manera estricta los Pod Security Standards de Kubernetes en modo Baseline o Restricted para los
#   nuevos namespaces. Como Talos bloquea por defecto los privilegios en namespaces nuevos (en este caso, los
#   que se crean automáticamente para la prueba), los Pods de pruebas de Cilium no obtienen los permisos de
#   red del kernel de Talos para abrir los sockets de DNS, provocando que el comando curl falle silenciosamente
#   por timeout al resolver. Así, con esta bandera, le indicamos a Talos que permita la ejecución de los
#   contenedores de prueba dándole privilegios a su namespace.
#   https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium#known-issues
cilium connectivity test --test '!pod-log-errors' \
  --namespace-labels pod-security.kubernetes.io/enforce=privileged 

# En caso de que no se eliminen automáticamente los namespaces después de la prueba, podemos ejecutar:
cilium connectivity test --cleanup
# También podríamos forzar la eliminación manual de los namespaces (esto requiere ejecutar primero
# un 'kubectl get ns', e identificar los nombres de los namespaces requerimos eliminar):
kubectl delete ns cilium-test-1 cilium-test-ccnp1 cilium-test-ccnp2
```

#### Troubleshooting en caso de que falle el `connectivity test` por DNS

_**NOTA:** Este problema ya lo estamos solucionando al deshabilitar `hostDNS` desde el momento en que hacemos el bootstrap, sin embargo, lo dejo documentado ya que es una de las causas de errores por DNS en las últimas versiones de Talos._

Al ejecutar el test de conectividad, es posible que obtengamos errores como los siguientes:

```
  [.] Action [no-policies/pod-to-world:http-to-one.one.one.one.-ipv4-0: cilium-test-1/client-657b75749d-vts9f (10.244.2.148) -> one.one.one.one.-http (one.one.one.one.:80)]
  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 http://one.one.one.one.:80" failed: command failed (pod=cilium-test-1/client-657b75749d-vts9f, container=client): command terminated with exit code 28
  [.] Action [no-policies/pod-to-world:https-to-one.one.one.one.-ipv4-0: cilium-test-1/client-657b75749d-vts9f (10.244.2.148) -> one.one.one.one.-https (one.one.one.one.:443)]
.  ❌ command "curl --silent --fail --show-error --connect-timeout 2 --max-time 10 -4 -H Host: one.one.one.one -w %{local_ip}:%{local_port} -> %{remote_ip}:%{remote_port} = %{response_code}\n --output /dev/null --retry 3 --retry-all-errors --retry-delay 3 https://one.one.one.one.:443" failed: command failed (pod=cilium-test-1/client-657b75749d-vts9f, container=client): command terminated with exit code 28
```

Para encontrar las causas del por qué de estos errores, a continuación tenemos algunos comandos que nos pueden ayudar a descubrir las razones (podemos ver otras opciones para este mismo propósito en [este artículo](https://oneuptime.com/blog/post/2026-03-13-troubleshoot-intermittent-dns-failures-cilium/view)):

```sh
# Confirmar si el fallo está relacionado con el DNS
# Reemplazamos por valores reales:
# - <namespace> -> cilium-test-1
# - <pod-name> -> client-657b75749d-zqptr
# - api.example.com -> google.com
kubectl exec -n <namespace> -it <pod-name> -- \
  sh -c 'for i in $(seq 5); do nslookup api.example.com; sleep 1; done'

# kubectl exec -n cilium-test-1 -it client-657b75749d-zqptr -- \
#   sh -c 'for i in $(seq 5); do nslookup google.com; sleep 1; done'

# Otra forma de validar el nslookup sería creando un pod temporal:
# Creamos el namespace y le otorgamos privilegios PSA obligatorios para Talos
kubectl create ns pruebadns --dry-run=client -o yaml | kubectl apply -f -
# Aplicamos privilegios
kubectl label namespace pruebadns pod-security.kubernetes.io/enforce=privileged --overwrite
# Creamos el pod e ingresamos a una shell interactiva
kubectl run net-test -it --rm -n pruebadns --image=alpine -- sh
# Una vez dentro del pod ejecutamos lo siguiente
nslookup google.com

# - Si obtenemos algo como 'Server: 10.96.0.10', indica que el pod de pruebas le preguntó correctamente a la
#   IP interna del servicio de CoreDNS en el clúster de Kubernetes.
# - Si obtenemos también algo como 'Non-authoritative answer... Address: 172.217.30.174', confirma que CoreDNS
#   tomó la petición, la reenvió de forma exitosa a internet, y obtuvo la IP pública real de Google y se la
#   devolvió al pod en milisegundos.

# Si al ejecutar lo anterior obtenemos un timeout, o respuestas tipo REFUSED, NXDOMAIN, o SERVFAIL, significa
# que CoreDNS tiene sus rutas eBPF rotas y procederemos a revisar los logs internos de CoreDNS:
kubectl logs -n kube-system -l k8s-app=kube-dns
```

Si al ejecutar este último comando de logs obtenemos una traza de errores similar a la siguiente, significa que CoreDNS le está preguntando a una IP inválida:

```
[INFO] 10.244.2.148:54544 - 39350 "A IN one.one.one.one. udp 44 false 1232" - - 0 2.000241102s
[ERROR] plugin/errors: 2 one.one.one.one. A: read udp 10.244.6.17:57446->169.254.116.108:53: i/o timeout
[INFO] 10.244.2.148:54544 - 39350 "A IN one.one.one.one. udp 44 false 1232" - - 0 2.000297078s
[ERROR] plugin/errors: 2 one.one.one.one. A: read udp 10.244.6.17:57754->169.254.116.108:53: i/o timeout
[INFO] 10.244.2.148:47175 - 52682 "A IN google.com. udp 28 false 512" - - 0 2.0002707s
[ERROR] plugin/errors: 2 google.com. A: read udp 10.244.6.17:53023->169.254.116.108:53: i/o timeout
[INFO] 10.244.2.148:43608 - 20450 "A IN google.com. udp 28 false 512" - - 0 2.00074737s
[ERROR] plugin/errors: 2 google.com. A: read udp 10.244.6.17:56816->169.254.116.108:53: i/o timeout
```

**El Origen del Problema: La IP `169.254.116.108`:** Esa IP (`169.254.116.108`) es una IP de enlace local (*Link-Local*). Los logs demuestran que CoreDNS sí está recibiendo las peticiones DNS de los Pods de prueba, pero cuando CoreDNS intenta reenviar la pregunta ("*¿Qué IP tiene one.one.one.one?*") hacia los servidores DNS del host externo, le está preguntando a esa IP `169.254.116.108` en el puerto `53`, la cual no responde (`i/o timeout`).

**¿Por qué CoreDNS le pregunta a esa IP?:** Por defecto, en Talos Linux, CoreDNS hereda el archivo `/etc/resolv.conf` del nodo de la máquina virtual a través de la directiva `forward . /etc/resolv.conf`. Esa IP link-local suele ser inyectada automáticamente por ciertos entornos de virtualización (o nubes con mecanismos de metadatos como la unidad Cloud-Init de Proxmox) o DHCPs internos cuando no se especifica un servidor DNS de manera explícita. Al estar en Proxmox, las VMs de Talos heredan esa IP como su DNS primario, pero no hay ningún servidor DNS real escuchando ahí dentro de la red local.

Asi pues, a pesar que configuramos los nameservers `1.1.1.1` y `8.8.8.8` en cada VM (en su bloque `network`), Talos sigue exponiendo y priorizando la IP link-local `169.254.116.108` en el archivo `/etc/resolv.conf` interno de los nodos, lo que arrastra a CoreDNS al bucle de timeouts. Es decir, Talos añade los DNS que le dimos, pero mantiene y prioriza los que detecta mediante DHCP o metadatos de Proxmox en la raíz del nodo. Como CoreDNS lee el archivo del nodo, se queda con la IP inválida (Para ver más opciones acerca de la configuración del Servidor de caché DNS de Talos, además de saber cómo ver el contenido del archivo `/etc/resolv.conf`, podemos verlo en la [documentación de Talos](https://docs.siderolabs.com/talos/v1.13/networking/host-dns)).

Para solucionar este problema, primero ejecutamos el siguiente comando para editar el archivo de configuración en vivo de CoreDNS:

```sh
kubectl edit configmap coredns -n kube-system
```

Esto abrirá el editor de texto (generalmente vi/nano). Ahí se debe buscar la sección que dice `forward . /etc/resolv.conf`. Esa línea es la que obliga a heredar la IP `169.254.116.108`. Ese fragmento exacto es el que debemos cambiar para que apunte directamente a DNS públicos:

```sh
# Antes:
forward . /etc/resolv.conf

# Cambiar a:
forward . 1.1.1.1 8.8.8.8
```

Luego debemos guardar los cambios y cerrar el editor. Para que CoreDNS aplique la nueva configuración de inmediato sin esperar, forzamos su reinicio:

```sh
kubectl rollout restart deployment coredns -n kube-system
```

Finalmente eliminamos los namespaces que se habían creado previamente para la anterior prueba de conectividad (con `cilium connectivity test --cleanup`) y volvemos a lanzar la prueba.



## Configuración del Balanceador local

Como estamos en un servidor local (bare-metal) y no en AWS/GCP/Azure, Kubernetes no sabe qué hacer cuando se crea un servicio de tipo `LoadBalancer`. Por lo tanto, necesitamos un servicio que le asigne IPs de la red local (en mi caso `192.168.0.X`) a los servicios que se desplieguen (como el panel de Grafana, Keycloak o las APIs). En este caso veremos 2 opciones:

- Mediante Cilium (Recomendada)
- Mediante MetalLB


### Opción A: Cilium L2 Announcement (Recomendada)

Cilium puede anunciar direcciones IP de servicio en la red local mediante ARP. Antes, esto implicaba ejecutar MetalLB u otro proyecto de balanceador de carga bare-metal junto con su CNI. Cilium lo hace directamente, sin necesidad de instalar ni operar ningún componente adicional. Cuando un pod que gestiona el tráfico falla, Cilium transfiere la IP a un pod que funciona correctamente y envía una actualización ARP gratuita y, el conmutador de red envía inmediatamente el tráfico al nuevo nodo.

Para ello se necesitan tres elementos: la función debe estar habilitada en Cilium, se necesita un conjunto de direcciones IP que Cilium pueda asignar a los servicios de tipo `LoadBalancer` y una política que le indique a Cilium qué direcciones IP debe anunciar en qué interfaces.

El primer elemento ya lo tenemos cubierto desde la instalación del chart de cilium en el clúster, ya que en nustro archivo `cilium-values.yaml` habilitamos la siguiente configuración:

```yaml
l2announcements:
  enabled: true
```

A continuación, se crea el grupo de direcciones IP. Para esto se debe escoger un rango de IPs que estén por fuera del rango del servidor DHCP del router, y que tampoco estén siendo usadas por otro servicio (como por ejemplo la `.31` o la `.40`). En este caso, usaremos el rango que va desde la IP `192.168.0.70` hasta la `192.168.0.149`:

```sh
kubectl apply -f k8s/cilium-ip-pool.yaml

# Para validar:
kubectl get ciliumloadbalancerippool -A
```

Si en el futuro queremos ajustar este rango de IPs, solamente debemos editar el rango en el archivo `k8s/cilium-ip-pool.yaml` y volver a aplicar los cambios.

Por último, configuramos la Announcement policy. Ésta le indica a Cilium qué nodos deben responder a las solicitudes ARP para esas direcciones IP y a través de qué interfaces:

```sh
kubectl apply -f k8s/cilium-l2-policy.yaml

# Para validar:
kubectl get ciliuml2announcementpolicy -A
# Con el siguiente comando, buscamos campos referentes a L2 Announcements y reemplazo de kube-proxy.
kubectl -n kube-system exec ds/cilium -- cilium status
```

En el archivo `k8s/cilium-l2-policy.yaml` se configuraron las interfaces de red más comunes (`eth*`, `enp*`, `ens*`, etc.). Sin embargo, no está de más validar cuál es la interface que estamos usando. Para esto, podemos ejecutar lo siguiente (para al menos una VM por cada Nodo de Proxmox):

```sh
# List network interfaces (identificamos las que estén up)
talosctl get links --nodes 192.168.0.31

# Get detailed interface information (identificamos la que tenga la IP que estamos consultando)
talosctl get addresses --nodes 192.168.0.31
```

En caso de que la interface de red no coincida con las que tenemos configuradas en `k8s/cilium-l2-policy.yaml`, debemos agregarla a dicho archivo en la sección `spec.interfaces`.


### Opción B: MetalLB

MetalLB es un balanceador de carga de red para Kubernetes y su función principal es asignar direcciones IP externas a los servicios y hacerlos accesibles fuera del clúster.

En primer lugar, debemos instalar MetalLB en el clúster:

```sh
# Agregamos el repositorio
helm repo add metallb https://metallb.github.io/metallb
helm repo update

# Instalamos MetalLB sobre un nuevo namespace (se creará en caso de no existir)
helm install metallb metallb/metallb\
  --namespace metallb-system --create-namespace

# Para validar, podemos comprobar los pods creados en este namespace:
kubectl get pods -n metallb-system
```

Posteriormente, aplicamos el manifiesto que configurará el pool de IPs que serán asignadas para los diversos servicios y que las anunciará para acceder a dichos servicios por fuera del clúster:

```sh
kubectl apply -f k8s/metallb-config.yaml
```



## Establecimiento de la confianza inicial en un clúster de Kubernetes: cert-manager, una CA interna y TLS de kubelet

Con Cilium gestionando la red, los pods ya pueden comunicarse entre sí. Sin embargo, la mayor parte de la comunicación se realiza mediante TLS autofirmado, en el cual ninguna de las partes confía. Esta sección corrige este problema.

La razón por la que se da esta comunicación entre cargas de trabajo usando certificados TLS autofirmados en los que ninguno confía, es que Kubernetes no lo hace sonar como un fallo, ya que cuando por ejemplo un pod accede a un endpoint `https://` de otro pod con `InsecureSkipVerify` recibe una respuesta positiva.

Así mismo, el comando `kubectl logs` funciona porque la comunicación se hace con el `apiserver`, no directamente con el `kubelet`, y como la conexión del `apiserver` con el `kubelet` no requiere verificación por defecto, no nos aparece ningún mensaje de error que indique que la mitad del tráfico de los Control Plane no está verificado.

Para solucionar esto, necesitamos de 3 partes principalmente:

1. Un **cert-manager** con una CA (Certificate Authority) interna autofirmada, de esta forma cualquier elemento del clúster puede solicitar un certificado TLS y obtenerlo.

2. **trust-manager** envía esa CA a cada `namespace` como un `ConfigMap` montable, de modo que las cargas de trabajo (los pods, daemons, jobs, etc.) puedan verificar lo que cert-manager entrega.

3. Un **aprobador de CSR** (este ya lo tenemos instalado) para que el propio `kubelet` obtenga un certificado de servicio firmado por una CA que el clúster conozca, en lugar de uno autofirmado en el que nadie confía.

Además, se requiere un emisor de **Let's Encrypt** para todo lo que esté expuesto a internet (sólo en caso de tener un dominio asociado a nuestra cuenta de Cloudflare). Ninguno de estos elementos es específico de Talos, por tanto, tienen la misma estructura en cualquier distribución. El único detalle específico de Talos son unas líneas en la configuración de la máquina que activa la rotación de certificados para `kubelet` (las cuales ya vimos anteriormente cuando [configuramos el aprobador automático de certificados](#validar-y-aprobar-los-certificados)).


### ¿Qué significado tiene "TLS" en un clúster de Kubernetes por defecto?

Antes de añadir nada, conviene precisar qué está ya cifrado y qué no.

El clúster incluye una infraestructura de clave pública (PKI) basada en la CA del clúster kubeadm/Talos. Ésta firma el certificado de `servicio del apiserver`, el certificado de `cliente del apiserver` para comunicarse con otros componentes, los certificados de `cliente del controller-manager y del scheduler`, y el certificado de `cliente del kubelet`. Ésta es la parte que viene configurada correctamente de fábrica: los componentes del Control Plane se verifican entre sí.

**¿Qué falta en ese escenario?**

- **El endpoint de servicio del kubelet:** Cada `kubelet` escucha en el puerto `10250` con un certificado autofirmado que genera al iniciarse. El `apiserver` se conecta a él para obtener registros (`logs`), ejecutar comandos (`exec`), crear túneles de red (`port-forward`) y recopilar métricas, y por defecto, no realiza ninguna verificación cuando se realizan estas acciones (la familia de banderas `--kubelet-insecure-tls` está implícita en la configuración del `apiserver` en la mayoría de las distribuciones). La conexión está cifrada pero no autenticada, lo que significa que cualquiera que se encuentre en la ruta puede interceptarla.

- **Tráfico entre cargas de trabajo (workload-to-workload):** Un servicio frente a un pod es una IP en la capa CNI. No hay TLS a menos que la aplicación o un sidecar lo implemente. Cilium puede cifrar la red subyacente con WireGuard o IPsec, pero se trata de cifrado de transporte entre nodos, no de TLS de extremo a extremo entre cargas de trabajo (por ejemplo entre pods), es decir, los datos viajan cifrados entre servidores, pero viajan "en texto plano" (sin cifrar) dentro del propio servidor, pues una vez que el tráfico llega al nodo de destino, se descifra antes de entregarse al pod.

- **Gateway API (ó Ingress):** Un pod puede servir peticiones HTTPS, pero necesita un certificado. Sin un emisor, significa que ese certificado es autofirmado, fue rotado manualmente o fue copiado de alguna fuente externa.

La CA del clúster es un sistema cerrado: los componentes del clúster poseen su clave privada (o, mejor dicho, el administrador del controlador la posee, mediante las banderas `--cluster-signing-*`) y solo firma las solicitudes enviadas a través de la API CSR de Kubernetes. Deliberadamente, no se expone para la emisión general de TLS, por lo tanto, la capa de confianza necesita su propia CA, independiente de la CA del clúster y disponible para las cargas de trabajo bajo demanda.

Eso es precisamente lo que cert-manager y trust-manager nos ofrecen, ya que sirven para automatizar la seguridad en Kubernetes: `cert-manager` emite y renueva certificados digitales, mientras que `trust-manager` distribuye los paquetes de confianza (como los certificados CA) por todo el clúster. Veamos un resumen rápido de las principales funciones de cada uno:

**Funciones principales de cert-manager:**

- **Creación automática:** Genera certificados TLS para que las aplicaciones usen HTTPS sin intervención manual.
- **Renovación periódica:** Evita que los sitios o servicios fallen al renovar los certificados antes de que caduquen.
- **Integración externa:** Se conecta con proveedores como Let's Encrypt o HashiCorp Vault.

**Funciones principales de trust-manager:**

- **Distribución de confianza:** Copia y sincroniza los certificados públicos de una entidad certificadora (CA) en diferentes namespaces.
- **Paquetes centralizados:** Facilita que los servicios de la red reconozcan las mismas autoridades emisoras sin configurar cada uno por separado.
- **Actualización sincronizada:** Si la autoridad cambia, actualiza las referencias en todo el entorno de manera automática.


### Cert Manager: una CA a la que el clúster puede solicitar cosas

Cert Manager es un controlador que supervisa los CRs (Custom Resources) de tipo `Certificate` y los concilia en Secretos de Kubernetes con pares de claves TLS en su interior. La parte interesante es el modelo de emisor: un `Certificate` hace referencia a un emisor (`Issuer` o `ClusterIssuer`), y dicho emisor decide cómo se produce realmente el certificado. Los distintos emisores hacen diferentes cosas: ACME (Let's Encrypt), Vault, una CA interna almacenada en un Secret o un pass-through autofirmado. El manifiesto de la carga de trabajo (del pod) no cambia cuando se reemplaza uno, solo cambia la referencia del emisor.

#### Paso A: Instalar cert-manager

Para instalar cert-manager, añadimos el repositorio oficial de Helm e instalamos el componente:

```sh
# Agregar el repositorio de Helm
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Instalar cert-manager en su namespace dedicado
helm install cert-manager jetstack/cert-manager --version 1.21.0 \
  --namespace cert-manager --create-namespace \
  -f k8s/deployments/cert-manager-values.yaml
```

Esto nos proporcionará el controlador, los webhooks y los tres CRD (`Certificate`, `Issuer`, `ClusterIssuer`). Por defecto, no nos proporciona ningún emisor, por tanto, si solicitamos un certificado en este momento, fallará porque no hay nada que lo emita aún.

#### Paso B: Creación de la CA interna

El clúster necesita una CA (Certificate Authority) autofirmada (que en nuestro caso llamaremos `internal-ca-issuer`) que firme todos los certificados que las cargas de trabajo utilizan para comunicarse entre sí. Es la CA en la que "todos los componentes del clúster confían". Para el caso de los certificados públicos, estos provienen de Let's Encrypt, el cual es un emisor independiente que veremos más adelante.

La CA debe crearse desde cero en un clúster nuevo, sin embargo, esa creación plantea un problema del tipo "el huevo o la gallina" que cert-manager resuelve con un truco de arranque deliberado.

En cert-manager, un `ClusterIssuer` de CA apunta a un `Secret` que contiene la clave privada y el certificado de la CA. En un clúster nuevo, ese `Secret` no existe, por lo tanto, no se puede escribir un `ClusterIssuer` para la CA, lo que significa que no se puede emitir el certificado de la CA, y por consiguiente, el `Secret` nunca se crea. Para evitar este problema, cert-manager incluye un tipo de emisor `selfSigned` (autofirmado), el cual no tiene un `Secret` asociado, simplemente firma lo que se le proporciona con la clave integrada en la propia solicitud.

Así pues, este emisor (`selfsigned-issuer`) solo se utiliza para emitir exactamente un certificado (el par de claves propio de la CA) y, a continuación, se apunta al verdadero CA: el emisor (`internal-ca-issuer`) que apunta al secreto (`internal-ca-secret`) que acaba de producir el certificado (`internal-ca-cert`).

Para crear estos emisores, secreto y certificado, ejecutamos lo siguiente:

```sh
kubectl apply -f k8s/internal-ca.yaml

# Para validar, ejecutamos los siguientes comandos (la columna READY debe marcar True):
kubectl get clusterissuer -o wide
kubectl get certificate -n cert-manager internal-ca-cert -o wide
# El Secreto debe contener el par de claves CA (tls.cert y tls.key)
kubectl describe secret -n cert-manager internal-ca-secret

# Si la columna READY dice False, debemos investigar el motivo exacto inspeccionando el recurso:
kubectl describe certificate internal-ca-cert -n cert-manager

# Logs de cert-manager (en caso de errores)
kubectl logs -n cert-manager -l app.kubernetes.io/instance=cert-manager --tail=100
```

En este manifiesto multi-documento `k8s/internal-ca.yaml` podemos apreciar que los recursos de tipo `ClusterIssuer` no se crean sobre un namespace en específico; esto es porque en Kubernetes existen dos tipos de recursos: los que están aislados por namespace (como los Pods, Services o Issuer) y los que son globales para todo el clúster (como los Nodes, Namespaces o ClusterIssuer).

Los `ClusterIssuer` se diseñaron como un recurso global por arquitectura: Al no tener `namespace`, cualquier recurso `Certificate` de cualquier `namespace` del clúster puede utilizarlo para pedir un certificado. Si usáramos un `Issuer` común, tendríamos que clonar la configuración del emisor en cada namespace de las aplicaciones y servicios (Java, Go, Postgres, etc.), lo cual sería ineficiente.


**Cómo usar esa CA interna**

Al tener lista nuestra CA interna, cualquier `namespace` podría solicitar solicitar un certificado de carga de trabajo aplicando un manifiesto como el siguiente:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-apps-cert
  namespace: my-apps
spec:
  secretName: my-apps-tls
  dnsNames:
    - some-app.my-apps.svc.cluster.local
    - some-app.eljavatar.home
  issuerRef:
    name: internal-ca-issuer
    kind: ClusterIssuer
```

En este ejemplo, cert-manager genera el par de claves, firma el certificado con `internal-ca-issuer`, guarda el resultado en el Secret `my-apps-tls` como `tls.crt` y `tls.key`, y lo rota antes de su vencimiento. La carga de trabajo montaría este Secret como un volumen y se olvidaría por completo del ciclo de vida de TLS.

Esto ya nos brindaría la mitad de la confianza: cualquier carga de trabajo puede solicitar un certificado de servidor. La otra mitad consiste en asegurar que los pares puedan verificarlo.

_**Nota 1:** A pesar de que usemos un certificado firmado por la CA interna, dicho certificado solo sirve dentro del clúster, por lo tanto, si intentamos entrar a algún servicio desde el navegador (por ejemplo a `grafana.eljavatar.home`), veremos la típica advertencia de "*Conexión no segura (Certificado no reconocido)*". Esto pasa porque la máquina local (en este caso mi Macbook) no conoce la CA interna del clúster. Para evitar ver este mensaje, solo debemos descargar el certificado raíz del clúster e instalarlo en el llavero del sistema operativo (Keychain en Mac / Certificados en Windows) como "Confiable", y veremos el candado verde de forma 100% nativa y local._

_**Nota 2:** Esto es solo un ejemplo de solicitud de un certificado (`my-apps-tls`) firmado por la CA interna para demostrar que la infraestructura interna funciona; sin embargo, más adelante, cuando creemos el Gateway de Cilium, colocaremos el certificado TLS directamente en dicho Gateway, para que el proxy de Cilium (basado en Envoy) se encargue de cifrar el tráfico hacia afuera, por lo cual sería innecesario crear certificados internos individuales para las aplicaciones en esta etapa._


### Trust Manager: distribuyendo el paquete de CA a todas partes

Un certificado firmado solo es útil si la otra parte dispone del certificado público de la CA para validarlo. Con una sola CA, basta con una copia del archivo `tls.crt` del `internal-ca-secret` montada en cada carga de trabajo que necesite verificar a un par.

La solución más sencilla consiste en copiar el Secret en cada namespace. Esto funciona, en cierto modo, pero no es escalable: cada nuevo namespace requiere una copia, y la rotación implica volver a copiarlo en todas partes. Peor aún, el Secret de origen de la verdad (`internal-ca-secret`) en el namespace `cert-manager` también contiene la clave privada de la CA. Montar ese Secret para distribuir la confianza implicaría entregar la clave privada a cada carga de trabajo que solo necesitara el certificado público.

Trust Manager es la solución. Se trata de un pequeño controlador (una instalación independiente de cert-manager, aunque del mismo proyecto) que supervisa un CR de tipo `Bundle`, lee el certificado solicitado (solo la parte pública) de uno o más Secrets o ConfigMaps de origen y lo proyecta como un ConfigMap en cada namespace que se seleccione. El ConfigMap tiene una clave fija (en nuestro caso, `internal-ca-bundle.crt`) para que las cargas de trabajo puedan montarlo sin importar qué CA contenga.

#### Paso A: Instalar trust-manager

Como el repositorio es el mismo que ya habíamos añadido al instalar cert-manager, solo tenemos que instalar el componente:

```sh
helm install trust-manager jetstack/trust-manager --version 0.24.0 \
  --namespace cert-manager \
  -f k8s/deployments/trust-manager-values.yaml
```

#### Paso B: Distribuir la confianza con el Bundle

Al aplicar el siguiente manifiesto, se le dice a trust-manager que tome la CA interna del paso anterior y la empaquete para distribuirla a todos los namespaces:

```sh
# Crea el configmap cluster-trusted-ca en cada namespace
kubectl apply -f k8s/trust-bundle.yaml

# Para validar, listamos el ConfigMap
kubectl get configmap cluster-trusted-ca -n default

# Si ejecutamos lo siguiente, veremos en la sección de datos (Data) la lista de certificados públicos
# agregados (en este caso, internal-ca-bundle.crt)
kubectl describe configmap cluster-trusted-ca -n default

# Logs de trust-manager (en caso de errores)
kubectl logs -n cert-manager -l app.kubernetes.io/instance=trust-manager --tail=50
```

En el manifiesto `k8s/trust-bundle.yaml` se puede apreciar que usamos `namespaceSelector.matchLabels: {}` que es un comparador vacío, mediante el cual propagamos el paquete (el certificado público) a cada namespace. Empezar de forma permisiva está bien porque el certificado público no es confidencial; solo la clave privada lo es, y esta nunca sale del namespace `cert-manager`.

Entonces, en resumen, el propósito de este Bundle no es ayudar a Cilium a descifrar el tráfico, sino ayudar a las aplicaciones internas a confiar en nuestra CA interna, y para esto, copia un ConfigMap llamado `cluster-trusted-ca` en todos los namespaces del clúster. Así, si en el futuro un Pod dentro del clúster necesita consumir un servicio a través de `https://eljavatar.home`, ese Pod podrá montar dicho ConfigMap para saber que la entidad que firmó el Gateway (`internal-ca-issuer`) (lo cual veremos más adelante) es de total confianza.

Para cargar el certificado de confianza en los Pods, podríamos hacer una inyección mediante mutación automática usando un **Mutating Webhook** como *Kyverno* o *Opa Gatekeeper*, lo cual aplicaría una política global para que cada vez que se lance un Pod en cualquier namespace, le inyecte el volumen del ConfigMap automáticamente si el Pod tiene una etiqueta específica (o a todos por igual) (Esto sería muy útil si eventualmente quisiéramos agregar por ejemplo algún sidecar a todos los pods).

Sin embargo, la forma más nativa sería agregando el volumen directamente en el `Deployment` de la aplicación; a continuación vemos un ejemplo de cómo lo haríamos:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: some-app
  namespace: my-apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: some-app
  template:
    metadata:
      labels:
        app: some-app
    spec:
      containers:
        - name: web-app
          image: nginx:alpine # Ejemplo con Alpine
          ports:
            - containerPort: 80
          volumeMounts:
            # En Alpine Linux, los certificados adicionales se colocan en esta ruta:
            - mountPath: /usr/local/share/ca-certificates/internal-ca-bundle.crt
              name: trusted-ca-volume
              subPath: internal-ca-bundle.crt # Extrae solo la llave que se definió en el Bundle
              readOnly: true
      volumes:
        - name: trusted-ca-volume
          configMap:
            name: cluster-trusted-ca # Cargamos el ConfigMap generado por nuestro Bundle
```

Hay que tener en cuenta que dependiendo de la tecnología con la que construyamos los contenedores, el sistema operativo interno buscará los certificados de confianza en carpetas distintas:

- **Debian / Ubuntu / Certificados globales de Go:** Se monta en `/etc/ssl/certs/internal-ca-bundle.crt` o `/etc/pki/tls/certs/`.
- **Alpine Linux:** Se monta en `/usr/local/share/ca-certificates/internal-ca-bundle.crt`. Las imágenes de Alpine suelen requerir que se ejecute el comando `update-ca-certificates` al arrancar si se montan en caliente, por lo que para Alpine a veces es más fácil sobreescribir directamente el archivo final de confianza en `/etc/ssl/certs/ca-certificates.crt`.

De esta forma, por ejemplo para los binarios de Go, podríamos configurar `SSL_CERT_FILE=/etc/ssl/certs/internal-ca-bundle.crt` o su equivalente según el entorno de ejecución (como lo vimos anteriormente), y el Pod verificará cualquier par firmado por una CA interna sin `InsecureSkipVerify`. Cuando la CA rota, trust-manager actualiza el ConfigMap y kubelet actualiza el punto de montaje en la siguiente sincronización.

_**Nota de desarrollador:** Si bien con este ejemplo mostramos cómo cargar el certificado de confianza en una carga de trabajo (por ejemplo en un Pod), hay que tener en cuenta que en muchos casos esto no sería necesario, ya que por defecto, cuando una aplicación en Java, Go o Python hacen una petición HTTPS (por ejemplo, el backend conectándose a la API de Keycloak usando el dominio interno), el contenedor busca los certificados de confianza en las rutas estándar de Linux (como `/etc/ssl/certs`). Por tanto, añadir manualmente esos `volumes` y `volumeMounts` solo sería estrictamente necesario si la aplicación corriera dentro de un contenedor ultra-estricto (como las imágenes Distroless de Google) que viene completamente vacío y no tiene librerías de certificados raíz instaladas, o si queremos obligar a una aplicación interna vieja a confiar únicamente en nuestra CA interna y en nada más._

Con esto cubrimos la comunicación TLS entre cargas de trabajo. Las siguientes secciones gestionan los enlaces: el tráfico entrante desde internet y el tráfico entre el `apiserver` y los `kubelets`.



## Let's Encrypt para el borde público (Tráfico entrante desde Internet)

_**NOTA:** Let's Encrypt necesita validar que somos los dueños legítimos de un dominio registrado globalmente (que en mi caso es `eljavatar.org`). Por tanto, si no tenemos comprado el dominio, **No podermos usar Let's Encrypt de ninguna forma**. Esto se debe a que Let's Encrypt es una entidad certificadora pública global que jamás emitirá certificados para dominios falsos, locales o no registrados (como por ejemplo un dominio `.home`). Así pues, si no tenemos un dominio comprado, tendremos que usar únicamente el `internal-ca-issuer` auto-firmado para todo._

Para cualquier servicio accesible desde internet, una CA interna no resulta útil ya que como mencionamos anteriormente, es interna del clúster. Por tanto, los navegadores no confiarán en ella y habría que enviar el paquete de confianza (el archivo `.crt`) a cada dispositivo que acceda al sitio. Let's Encrypt es la solución estándar: una CA de confianza pública que emite certificados gratuitos de 90 días mediante el protocolo ACME.

El emisor ACME de cert-manager gestiona el protocolo. Lo único que necesita configurar es cómo se responde al desafío DNS-01 del servidor ACME, en este caso, con Cloudflare (para ver cómo sería para el caso de HTTP-01, se puede revisar [este enlace](https://www.pimwiddershoven.nl/entry/bootstrapping-trust-in-a-kubernetes-cluster-with-cert-manager/#lets-encrypt-for-the-public-edge)).

- **Inyección de credenciales y llamada a la API:** Cuando un recurso `Certificate` solicita una firma a través del `ClusterIssuer` con DNS-01, `cert-manager` lee el token de acceso del Secret de Kubernetes (que en este caso llamamos `cloudflare-api-token-secret`). Utilizando este token, realiza una petición HTTPS externa hacia la API global de Cloudflare para indicarle que cree un nuevo registro de tipo TXT bajo el nombre exactamente formateado: `_acme-challenge.eljavatar.org` (o el nombre de dominio que tengamos).

- **Propagación y verificación asíncrona:** El valor de este registro TXT contiene una clave criptográfica (un hash del token emitido por Let's Encrypt combinado con la llave de cuenta de nuestro clúster). Una vez creado el registro en los servidores DNS de Cloudflare, `cert-manager` realiza consultas internas (haciendo un "self-check") para asegurarse de que el cambio ya es visible en internet.

- **Validación por Let's Encrypt y limpieza:** Cuando el registro es público, `cert-manager` le avisa a los servidores de Let's Encrypt. Let's Encrypt realiza una consulta DNS global (`dig txt _acme-challenge.eljavatar.org`), comprueba que el hash coincide perfectamente con lo esperado, y emite el certificado firmado. Acto seguido, `cert-manager` vuelve a llamar a la API de Cloudflare para eliminar el registro TXT temporal, dejando nuestra zona DNS limpia. Todo este proceso suele demorar entre 30 y 60 segundos debido a los tiempos de propagación DNS.

**Seguridad y RBAC en el caso de DNS-01**

A diferencia de HTTP-01 (que requiere permisos para crear objetos de red como `HTTPRoute`), el solucionador DNS-01 no modifica nada dentro del clúster. El control de accesos se traslada fuera de Kubernetes:

- **A nivel de Kubernetes (RBAC):** `cert-manager` solo necesita permisos de lectura básicos sobre el Secret local que almacena el token de Cloudflare. Ningún componente de red (ni Cilium, ni la Gateway API) se entera de que ocurrió una validación.

- **A nivel de Cloudflare (Seguridad Externa):** El principio de mínimo privilegio se mantiene mediante el uso de un API Token limitado. En lugar de usar la "Global API Key" de la cuenta, anteriormente creamos un token restringido en la interfaz de Cloudflare que solo tenía permisos de edición de DNS (`Zone.DNS:Edit`) y que estaba limitado exclusivamente a la zona específica de nuestro dominio (`eljavatar.org`). Así, si el clúster se viera comprometido, el atacante solo podría alterar registros DNS de ese dominio, pero jamás tomar el control de nuestra cuenta de Cloudflare ni ver nuestras tarjetas de crédito o configuraciones de otros sitios.

Antes de continuar con la configuración del Token, veamos una comparativa rápida de las diferencias entre configurar un ClusterIssuer de Let's Encrypt con HTTP-01 vs. DNS-01:

| Característica | `http01` (Gateway API) | `dns01` (Cloudflare) |
|----------------|------------------------|----------------------|
| **Mecanismo de validación** | Let's Encrypt intenta acceder a una URL pública (`http://eljavatar.org...`). El `ClusterIssuer` crea automáticamente una ruta temporal en el Gateway para responder esa petición. | `cert-manager` usa las APIs de Cloudflare para crear temporalmente un registro DNS de tipo TXT (`_://eljavatar.org`). Let's Encrypt valida ese registro en internet. |
| **¿Soporta certificados Wildcard (`*.tudominio.org`)?** | **No**. Solo sirve para dominios explícitos (ej. `app.eljavatar.org`). | **Sí**. Es obligatorio usar `dns01` si queremos emitir un certificado que cubra cualquier subdominio mediante un asterisco. |
| **Requisito de Red** | El clúster **debe estar expuesto a Internet** en el puerto 80 con una IP pública (es decir, requiere abrir un puerto en el router). | El clúster **puede estar totalmente oculto de Internet** (red privada / Homelab). No requiere abrir puertos entrantes. |
| **Dependencias** | Depende solo de la Gateway API de Kubernetes. | Depende de las credenciales de la API de Cloudflare almacenadas en un Secret. |

Por estas razones que vemos en esta tabla es que elegimos usar la opción de `dns01` con Cloudflare, ya que en nuestro YAML del Gateway (que veremos más adelante) podremos especificar el uso de un certificado Wildcard (`hostname: "*.eljavatar.org"`), lo cual nos daría la libertad de usar múltiples subdominios con este mismo certificado. Además, `dns01` protege la IP de nuestra casa/infraestructura al no obligarnos a abrir el puerto 80 al mundo entero para renovar certificados.


### Creación del Secret en nuestro Clúster de Kubernetes

Anteriormente habíamos creado un API Token de Cloudflare. Para que el `ClusterIssuer` que usará Let's Encrypt (y que veremos en los próximos pasos) pueda consumir este token, debemos guardarlo en un Secret dentro del namespace donde opera `cert-manager`. Por motivos de seguridad, no comparto mi archivo `cloudflare-secret.yaml`, por tanto, a continuación listo los pasos para crear dicho manifiesto:

1. Copiar la plantilla de ejemplo para crear el archivo local:
   ```sh
   cp k8s/cloudflare-secret.yaml.example k8s/cloudflare-secret.yaml
   ```
2. Abrir `cloudflare-secret.yaml` con el editor y reemplazar `"TOKEN_DE_CLOUDFLARE_AQUÍ"` por el API Token real.
3. Aplicar el secreto en el clúster:
   ```bash
   kubectl apply -f k8s/cloudflare-secret.yaml
   ```

Otra alternativa sería crearlo directamente sin usar un manifiesto (reemplazar `"TOKEN_DE_CLOUDFLARE_AQUÍ"` por el API Token real):

```sh
kubectl create secret generic cloudflare-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token="TOKEN_DE_CLOUDFLARE_AQUI"
```

Para validar que nuestro Secret se creó correctamente con nuestro token, podemos validarlo ejecutando lo siguiente:

```sh
# El Secreto debe contener el api-token
kubectl describe secret -n cert-manager cloudflare-api-token-secret

# Podemos también extraerlo para guardarlo en una variable de entorno si lo requerimos:
export CLOUDFLARE_API_TOKEN=$(kubectl get secret --namespace cert-manager cloudflare-api-token-secret -o jsonpath="{.data.api-token}" | base64 -d); echo $CLOUDFLARE_API_TOKEN
```



### Configurar el `ClusterIssuer` de Let's Encrypt

A continuación, crearemos el emisor externo que hablará con Cloudflare y Let's Encrypt para nuestros dominios públicos (`*.eljavatar.org`). Este componente se encargará de registrar nuestro correo ante Let's Encrypt y definir cómo se resolverá el reto DNS; es decir, no necesitamos crear ninguna cuenta en la página de Let's Encrypt (ya que no tiene un panel de usuarios tradicional), sino que la "cuenta" se crea de forma totalmente transparente y automatizada la primera vez que `cert-manager` se comunica con los servidores de Let's Encrypt.

El email que configuremos puede ser un correo personal del tipo `@hotmail.com` o `@gmail.com`, ya que Let's Encrypt no restringe el dominio del remitente porque no lo usa para comprobar la propiedad de la página web, lo usará única y exclusivamente para enviarnos notificaciones de emergencia si nuestros certificados están a punto de expirar y el clúster ha fallado en renovarlos automáticamente (Para ver más opciones de configuración del `ClusterIssuer`, se puede revisar la documentación de [Cert Manager](https://cert-manager.io/docs/configuration/acme/)).

A continuación vemos los pasos para crear el `ClusterIssuer`, y debido a que en el manifiesto usamos marcadores de variables tipo `${VAR}`, tenemos 3 formas de hacerlo:

```sh
# Opción 1: Creando variables de entorno en la terminal
# Paso A: Creamos las variables de entorno
export PERSONAL_EMAIL="personal@example.com"
export CLOUDFLARE_ACCOUNT_EMAIL="cloudflare-account@example.com"
# Paso B: Usamos envsubst para reemplazar los marcadores ${VAR} antes de pasarle el resultado a kubectl
envsubst < k8s/letsencrypt-stage-cluster-issuer.yaml | kubectl apply -f -
envsubst < k8s/letsencrypt-prod-cluster-issuer.yaml | kubectl apply -f -

# Opción 2: Creando variables de entorno en el archivo .env
# Paso A: Agregamos las variables de entorno al archivo .env
PERSONAL_EMAIL=personal@example.com
CLOUDFLARE_ACCOUNT_EMAIL=cloudflare-account@example.com
# Paso B: Lee el .env, inyecta los valores en memoria temporal y se los pasa a kubectl sin modificar el
# archivo físico k8s/letsencrypt-stage-cluster-issuer.yaml
export $(cat .env | xargs) && envsubst < k8s/letsencrypt-stage-cluster-issuer.yaml | kubectl apply -f -
export $(cat .env | xargs) && envsubst < k8s/letsencrypt-prod-cluster-issuer.yaml | kubectl apply -f -

# Opción 3: Modificando el manifiesto
# Paso A: Reemplazar en el archivo k8s/letsencrypt-stage-cluster-issuer.yaml los marcadores ${VAR}
# según el valor correspondiente
# Paso B: Ejecutar el comando de kubectl
# Al escoger esta opción, lo ideal sería agregar estos archivos al .gitignore
kubectl apply -f k8s/letsencrypt-stage-cluster-issuer.yaml
kubectl apply -f k8s/letsencrypt-prod-cluster-issuer.yaml


# Para validar que se haya creado el emisor y el secreto, podemos ejecutar lo siguiente:
kubectl describe clusterissuer letsencrypt-stage-issuer
# Podemos notar que si bien el clusterissuer es de ámbito global dentro del clúster, el secreto
# se creó en el namespace donde instalamos cert-manager
kubectl describe secret -n cert-manager letsencrypt-stage-account-key
```

_**Nota de desarrollo 1:** Para pruebas iniciales, se recomienda usar la URL de staging `https://acme-staging-v02.api.letsencrypt.org/directory` para evitar bloquear nuestro dominio por exceder los límites de intentos de Let's Encrypt si algo falla en las credenciales de Cloudflare (`k8s/letsencrypt-stage-cluster-issuer.yaml`). Los certificados de prueba no son de confianza pública, pero los límites de frecuencia son flexibles, por lo que un certificado mal configurado que reintente indefinidamente no agotará su cuota. En contraste, en producción se aplican 50 certificados por dominio registrado por semana y 5 certificados duplicados por semana; un bucle en un certificado defectuoso alcanzaría ambos límites en una hora._

_**Nota de desarrollo 2:** Podemos crear los 2 `ClusterIssuer` sin problema y con total seguridad (el de `letsencrypt-stage` y el de `letsencrypt-prod`), ya que en esta instancia aún no se ha generado ningún Certificado; sin embargo, en los siguientes pasos, si no estamos seguros si el Certificado que se va a generar puede estar defectuoso o no, sería mejor crear dicho certificado usando solo el emisor `letsencrypt-stage-issuer`._



## Crear los Certificados

Cert-manager puede manejar TLS de forma descentralizada a nivel de Gateway (inyectando la anotación en el listener), lo que hará que `cert-manager` genere este objeto automáticamente tras leer el Gateway. Sin embargo, en este caso preferimos tener el control manual del ciclo de vida del certificado mediante un manifiesto explícito.

A continuación, tenemos los comandos para generar el Certificado:

```sh
# 1. En primer lugar, como los certificados deben estar en el mismo namespace que el Gateway,
#    creamos primero dicho namespace:
kubectl apply -f k8s/gateway-api-namespace.yaml

# 2. Creamos el Certificado local
kubectl apply -f k8s/cert-gateway-local.yaml

# 3. Creamos el Certificado de Let's Encrypt para Stage
# Este solo aplicaría si tenemos dominio y creamos el ClusterIssur de Let's Encrypt (sección anterior)
kubectl apply -f k8s/cert-letsencrypt-public.yaml
```

Al aplicar este último manifiesto, `cert-manager` detectará el `ClusterIssuer` de Cloudflare, creará el registro TXT en nuestro DNS y, tras validarlo, depositará las llaves TLS en el Secret `cert-letsencrypt-public-secret`. Posteriormente cuando creemos nuestro Gateway de Cilium, éste leerá ese Secret inmediatamente y empezará a servir tráfico web seguro desde Internet.

Adicionalmente, en `k8s/cert-letsencrypt-public.yaml` se puede apreciar que configuramos explícitamente `privateKey` con el algoritmo **`ECDSA` de 256 bits** en lugar del clásico RSA. Esto lo hicimos así porque las llaves ECDSA son significativamente más pequeñas, consumen menos ancho de banda en el handshake TLS y ofrecen el mismo nivel de seguridad criptográfica, lo cual reduce el consumo de CPU en el proxy de Cilium.

_**Nota:** El proceso de validación DNS de Let's Encrypt con Cloudflare tarda usualmente entre 1 y 3 minutos. Podemos monitorear el estado con `kubectl get certificate -n gateway-api-system`._


### Monitorear el progreso del Certificado

Cuando apliquemos el objeto `Certificate` de Let's Encrypt (o cuando el Gateway intente levantar el listener público), `cert-manager` creará recursos intermedios. El comando principal para auditar fallos es:

```sh
# Esto inicialmente mostrará el certificado cert-letsencrypt-public en READY=False, pero si todo sale bien,
# eventualmente después de aproximadamente 3 minutos deberá cambiar a READY=True
kubectl get certificate -n gateway-api-system -w
```

Como mencionamos anteriormente, el proceso de validación puede tomar varios minutos. Sin embargo, si después de más de 3 minutos (máximo 5) el estado se queda en `READY=False` o `READY=Unknown`, debemos empezar a rastrear la cadena de eventos hacia abajo con estos tres comandos en orden:

1. **Revisar la Solicitud de Certificado (`CertificateRequest`):**
   ```sh
   kubectl get certificaterequest -n gateway-api-system
   kubectl describe certificaterequest -n gateway-api-system <nombre-de-la-request>
   ```

2. **Revisar la Orden ACME (Order):** Let's Encrypt crea una orden de compra virtual. Aquí veremos si el dominio está aprobado.
   ```sh
   kubectl get orders -n gateway-api-system
   kubectl describe order <nombre-de-la-orden>
   ```

3. **Revisar el Desafío (Challenge):** Este es el comando más importante para DNS-01. Nos dirá exactamente si `cert-manager` logró conectarse a Cloudflare o si el registro TXT falló en propagarse.
   ```sh
   kubectl get challenges -n gateway-api-system
   kubectl describe challenge -n gateway-api-system <nombre-del-desafio>
   ```

4. **Inspeccionar los Logs en vivo (Último recurso)**: Si los objetos de Kubernetes no muestran suficiente información, podemos auditar el Pod de `cert-manager` directamente para ver las llamadas API a Cloudflare en tiempo real:
   ```sh
   kubectl logs -n cert-manager -l app.kubernetes.io/component=controller --tail=100 -f
   ```


### Usar el ClusterIssuer de Let's Encrypt de Producción

Si el validar el estado con `kubectl get certificate -n gateway-api-system` vemos que queda en `READY=True`, y no vamos a volver a recrear el Certificado (por ejemplo no necesitamos hacer más pruebas de crear/eliminar un certificado), podemos editar el archivo `k8s/cert-letsencrypt-public.yaml` para que use el `ClusterIssuer` que le pega al ACME de Let's Encrypt de Producción:

```yaml
spec:
  issuerRef:
    name: letsencrypt-prod-issuer # Cambiamos stage por prod
    kind: ClusterIssuer
    group: cert-manager.io
```

Después de hacer el ajuste, solo debemos guardar y aplicar de nuevo el manifiesto:

```sh
kubectl apply -f k8s/cert-letsencrypt-public.yaml
```

Al aplicarlo, `cert-manager` detectará el cambio de configuración, se comunicará con el servidor real de Let's Encrypt, resolverá el nuevo desafío DNS y sobreescribirá el contenido de `cert-letsencrypt-public-secret` con las llaves de producción firmadas legalmente. Por otro lado, Cilium (gracias a Envoy) detectará el cambio en el Secret en caliente y comenzará a servir el nuevo certificado válido sin necesidad de reiniciar el Gateway (en caso de ya haberlo levantado) ni interrumpir las conexiones de los usuarios.

De nuevo podemos hacer las mismas validaciones que hicimos con el de stage, pero en teoría, debería quedar también en `READY=True`.

_**Nota 1:** Es muy importante que esto lo hagamos solo si estamos seguros de que este va a ser el Certificado definitivo y no tenemos necesidad de recrear el Certificado, ya que si por ejemplo se genera con éxito el mismo certificado de producción 5 veces en una semana, Let's Encrypt bloqueará las solicitudes para ese subdominio específico durante los siguientes 7 días, causando que no se pueda generar un certificado válido para dicho dominio (en este caso `*.eljavatar.org`) usando Let's Encrypt hasta que se cumpla la ventana de tiempo (una semana desde la primera emisión). Además, esto causaría que los usuarios externos que intenten entrar a las aplicaciones vean la pantalla roja de "Conexión no segura", ya que Cilium no tendrá llaves de producción para mostrarles._

_**Nota 2:** En caso de que por alguna razón llegue a ocurrir un bloqueo en un entorno productivo real, hay que tener en cuenta que dicho bloqueo es solo para Let's Encrypt. Por tanto, como alternativa de emergencia, podríamos crear temporalmente un `ClusterIssuer` apuntando a otra entidad certificadora gratuita alternativa que use el mismo protocolo ACME (como ZeroSSL o Bypass), o degradar temporalmente el tráfico del Gateway usando el `internal-ca-issuer` mientras se espera a que expire la penalización de Let's Encrypt._



## Cilium Gateway API para el enrutamiento (HTTP/HTTPS/gRPC)

Cilium implementa Gateway API, un estándar de Kubernetes para el enrutamiento de capa 7 (HTTP/HTTPS/gRPC) y capa 4 (TCP/UDP) (a diferencia de Ingress Controller que está limitado nativamente a capa 7). Esto quiere decir que reemplaza Ingress con un modelo más expresivo: un recurso de tipo `Gateway` (global) define cómo el tráfico ingresa al clúster, y los recursos de tipo `HTTPRoute` (por cada servicio) definen las reglas de enrutamiento propiamente dichas. Veamos un poco más a detalle las diferencias entre estos 2 tipos de recursos:

1. **El `Gateway` (Configuración Global / Compartida):** El recurso `Gateway` representa la infraestructura física o el punto de entrada de red al clúster.
   - **Quién lo administra:** El administrador del clúster (desde el rol de DevOps/Plataforma).
   - **Dónde se crea:** Usualmente en un namespace centralizado de infraestructura (como `gateway-api-system` o `kube-system`).
   - **Qué hace Cilium tras bambalinas:** Cuando se aplica este Gateway, Cilium detecta la configuración, e inyecta una nueva configuración de enrutamiento mediante eBPF en sus proxies de Envoy.
   - **Frecuencia:** Se crea una sola vez (o unas pocas veces si se necesita separar tráfico público de tráfico interno).

2. **El `HTTPRoute` (Propio de cada Servicio):** El recurso `HTTPRoute` (o `TLSRoute` / `GRPCRoute`) define las reglas de enrutamiento específicas para una aplicación (dominios, rutas, redirecciones).
   - **Quién lo administra:** El equipo de desarrollo o el responsable del servicio.
   - **Dónde se crea:** En el mismo namespace donde vive la aplicación (por ejemplo, `production`, `database`, `auth`).
   - **Cómo se conecta:** Utiliza la propiedad `parentRefs` para decirle a Cilium: *"Oye, quiero enganchar mis rutas al Gateway global llamado {nombre-del-gateway} que está en el namespace central"*.
   - **Frecuencia:** Se crea uno por cada aplicación o microservicio que se quiera exponer hacia el exterior.

El recurso `Gateway` representa entonces la infraestructura física o el balanceador que escuchará el tráfico en la red local. Al crearlo, Cilium detectará que necesita una IP pública y la tomará del `CiliumLoadBalancerIPPool` que aplicamos previamente.


### Alta Disponibilidad del Gateway de Cilium

Cilium revolucionó la forma de desplegar proxies con su arquitectura moderna en modo **Shared Envoy** (que es el comportamiento por defecto en Cilium v1.18.0 y versiones posteriores). Veamos entonces cómo logra Cilium la Alta Disponibilidad real, para que en caso de que el Worker en el que está operando el Envoy que está recibiendo las peticiones se caiga, aún así sigamos recibiendo tráfico a través del Gateway (más adelante haremos una prueba en vivo para ver cómo se da este mecanismo de HA):

1. **No se levanta un Pod de Envoy por cada Gateway (Modo Shared):**
   Antiguamente (o en otros Ingress Controllers como NGINX), al aplicar un `Gateway`, el operador levantaba un nuevo `Deployment` y nuevos Pods dedicados. Cilium, por rendimiento y ahorro de memoria, instala por defecto un **DaemonSet global de Envoy** (un Pod de Envoy corriendo nativamente en cada VM de Talos desde que se instala Cilium). Cuando aplicamos el manifiesto `Gateway`, no estamos creando infraestructura nueva; simplemente estamos inyectando una nueva configuración de enrutamiento mediante eBPF en los proxies de Envoy que ya existían en todos los nodos (las VMs de Talos), por lo tanto, nuestro `Gateway` ya es altamente disponible por defecto.

2. **El responsable de la HA: La Capa 2 con ARP de Cilium (Cilium L2 Advertisement):**
   La alta disponibilidad no ocurre porque los Pods de Envoy se muevan, sino **porque la IP flotante (que en nuestro caso será la `192.168.0.70`) es administrada dinámicamente por eBPF**. Cilium genera un objeto `Lease` global en Kubernetes para elegir de forma democrática a un nodo del clúster como "Líder ARP" (estrategia de Leader/Follower). Si ese nodo muere (la VM de Talos), el eBPF del resto de los nodos detecta la pérdida del `Lease` en milisegundos, otro nodo toma el control y envía un anuncio ARP al router físico para desviar el tráfico de la IP `.70` hacia su propia interfaz.


### Levantar el Gateway de Cilium

Una vez que los certificados que creamos anteriormente pasen a estado `READY: True`, aplicamos nuestro Gateway global ejecutando lo siguiente (en caso de que no tengamos un dominio en Cloudflare, y por ende no hayamos configurado el certificado emitido por Let's Encrypt, en el archivo `k8s/gateway-api-external.yaml` deberíamos comentar o eliminar el listener `https-publico`):

```sh
# Creamos el namespace (Solo en caso de que no lo hayamos creado previamente)
kubectl apply -f k8s/gateway-api-namespace.yaml

# Creamos el Gateway
kubectl apply -f k8s/gateway-api-external.yaml

# Para validar, ejecutamos lo siguiente
kubectl get gateway -n gateway-api-system
# Aquí veremos el gateway creado y la respectiva IP asignada, y PROGRAMMED en True:
# NAMESPACE            NAME               CLASS    ADDRESS        PROGRAMMED   AGE
# gateway-api-system   external-gateway   cilium   192.168.0.70   True         23s

# También podemos ver más detalles del gateway ejecutando:
kubectl describe gateway -n gateway-api-system external-gateway
```

Gateway API es un estándar de CNCF, no una abstracción específica de Cilium, por lo que se puede cambiar de implementación más adelante sin tener que reescribir las rutas.

_**Advertencia:** La compatibilidad de Cilium con Gateway API está casi completa, pero aún no admite rutas TCP. Si se necesita enrutar tráfico TCP sin procesar (como por ejemplo bases de datos ó gRPC sobre TCP), por ahora se necesitaría de otra solución, como puede ser por ejemplo crear un túnel temporal (si se requiere promover prácticas de seguridad robustas (*Zero Trust*)) ó, aprovechando que configuramos `CiliumLoadBalancerIPPool`, asignar una IP dedicada en un `Service` de tipo `LoadBalancer` (mediante la anotación `io.cilium/lb-ipam-ips: "IP_A_ASIGNAR"`) y restringiendo el acceso público desde internet (en caso de ser necesario). Sin embargo, se está trabajando activamente en ello; Se puede consultar el hilo de discusión en GitHub en https://github.com/cilium/cilium/issues/21929._


### ¿Cómo se configuraría un Gateway Interno (Privado)?

Un **Gateway Interno** sirve para comunicar los microservicios de forma segura a través de subredes privadas, o para exponer herramientas de administración (como paneles de control de bases de datos, dashboards de Grafana o la API de Pulsar) que solo deben ser accesibles si se está conectado a la VPN de una empresa (o a la red local de la casa/oficina), protegiéndolas de ataques de internet.

**¿En qué se diferencia de un Gateway Público?**

Físicamente son casi idénticos en su código de Kubernetes, pero se diferencian en el Pool de IPs de Cilium que utilizan. Por ejemplo, supongamos que creamos dos pools de IPs en Cilium (actualmente solo tenemos uno):

- **Pool Público (192.168.0.70 - .149):** IPs de servicios expuestos al router doméstico/empresarial que tienen redirección de puertos hacia internet.
- **Pool Privado (10.0.50.1 - .50):** IPs de una VLAN aislada en Proxmox donde solo viven servidores internos o un servidor VPN (como WireGuard/Tailscale).

Así pues, el código del manifiesto sería como este (solo lo dejo como referencia, ya que en mi caso por el momento, no requiero agregar un Gateway privado):

```yaml
# cilium-ip-private-pool.yaml
# POOL DE IPs DE UNA VLAN AISLADA
apiVersion: cilium.io/v2alpha1
kind: CiliumLoadBalancerIPPool
metadata:
  name: homelab-ip-private-pool
  namespace: kube-system
spec:
  blocks:
    - start: "10.0.50.1"
      stop: "10.0.50.50"
---
# gateway-api-internal.yaml
# GATEWAY INTERNO (Solo accesible en la red privada o VPN)
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: internal-gateway
  namespace: gateway-api-system
  annotations:
    # OBLIGATORIO: Le ordena a Cilium que use el pool de IPs privadas
    io.cilium/lb-ipam-pool: "homelab-ip-private-pool"
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
```

De esta forma, Cilium le asignará la IP `10.0.50.1` a este Gateway, y si alguien desde internet intenta entrar, le será imposible interactuar con los servicios enganchados aquí.


### Configurar Redirección HTTP Global

Si revisamos el manifiesto `k8s/gateway-api-external.yaml` podemos ver que dejamos un listener para el trafíco `http` (puerto `80`). Hoy en día, **ninguna aplicación debería servir tráfico en texto plano (HTTP)** por motivos de seguridad. Sin embargo, los usuarios en Internet (o incluso uno mismo en la red local) rara vez escriben `https://` en la barra de direcciones; lo normal es escribir simplemente por ejemplo `eljavatar.home`.

Cuando hacemos esto, el navegador intenta conectarse por defecto al puerto `80` (HTTP). Si eliminamos por completo el listener HTTP del Gateway, tendríamos el siguiente resultado:

- El usuario recibirá un error de conexión inmediata (Conexión rechazada / Connection Refused).
- La experiencia de usuario será mala, ya que lo obligaremos a escribir explícitamente el protocolo `https://` manualmente cada vez.

Por lo tanto, la mejor práctica de la industria es dejar el puerto `80` abierto exclusivamente para atrapar esos descuidos y responder con una redirección permanente (Código `HTTP 301`) hacia el puerto `443` (HTTPS).

Además, a diferencia del puerto 443 (donde estamos obligados a usar hostnames para que Envoy sepa qué certificado TLS (Secret) presentarle al cliente durante el saludo), el puerto 80 viaja en texto plano. Por tanto, un único listener genérico HTTP en el puerto 80 (sin la propiedad hostname configurada, tal como lo tenemos) es capaz de capturar absolutamente todo el tráfico web sin cifrar que llegue a la IP `192.168.0.70`, sin importar si la petición viene dirigida a `.home` o a `.org`.

Así pues, para automatizar la redirección global de HTTP a HTTPS sin necesidad de alterar nuestras aplicaciones internas, Gateway API nos permite enganchar un recurso `HTTPRoute` especial que se encargue únicamente de esta tarea.

Para esto, aplicamos el siguiente manifiesto:

```sh
kubectl apply -f k8s/global-http-redirect.yaml

# Para validar, lanzamos un curl apuntando explícitamente al protocolo http:// (puerto 80):
# Prueba A: validando el dominio local
curl -vI --resolve "api.eljavatar.home:80:192.168.0.70" "http://api.eljavatar.home"
# Prueba B: validando el dominio público
curl -vI --resolve "api.eljavatar.org:80:192.168.0.70" "http://api.eljavatar.org"

# En ambos casos, deberíamos ver una salida como la siguiente:
HTTP/1.1 301 Moved Permanently
location: https://api.eljavatar.home:443/ # O https://api.eljavatar.org:443/
server: envoy
```



## Levantar el Agente de `clouflared` para habilitar Cloudflare Tunnel en el clúster

Previamente habíamos configurado un tunnel en nuestro panel de administración de Cloudflare, sin embargo, recordemos que había quedado en estado `Inactive` debido a que aún no había ningún agente de `cloudflared` que estuviera corriendo con nuestro token.

Para esto, seguimos los siguientes pasos:

1. Creamos un namespace dentro del cual correrá nuestro agente:

```sh
kubectl apply -f k8s/deployments/cloudflare-tunnel/namespace.yaml
```

2. Creamos un secreto con el token que habíamos guardado previamente cuando creamos el tunnel en Cloudflare (no confundir con el API Token que usamos para los certificados) (para esto, tenemos 3 opciones):

```sh
# Opción 1: Creando la variable de entorno en la terminal
# Paso A: Creamos la variable de entorno
export CLOUDFLARE_TUNNEL_TOKEN="token_del_tunnel"
# Paso B: Usamos envsubst para reemplazar el marcador ${CLOUDFLARE_TUNNEL_TOKEN} antes de
# pasarle el resultado a kubectl
envsubst < k8s/deployments/cloudflare-tunnel/secret.yaml | kubectl apply -f -

# Opción 2: Creando la variable de entorno en el archivo .env
# Paso A: Agregamos la variable de entorno al archivo .env
CLOUDFLARE_TUNNEL_TOKEN=token_del_tunnel
# Paso B: Lee el .env, inyecta los valores en memoria temporal y se los pasa a kubectl sin modificar el
# archivo físico k8s/deployments/cloudflare-tunnel/secret.yaml
export $(cat .env | xargs) && envsubst < k8s/deployments/cloudflare-tunnel/secret.yaml | kubectl apply -f -

# Opción 3: Modificando el manifiesto
# Paso A: Reemplazar en el archivo k8s/deployments/cloudflare-tunnel/secret.yaml el marcador
# ${CLOUDFLARE_TUNNEL_TOKEN}
# Paso B: Ejecutar el comando de kubectl
# Al escoger esta opción, lo ideal sería agregar este archivo al .gitignore
kubectl apply -f k8s/deployments/cloudflare-tunnel/secret.yaml


# Validamos que se creó el Secret (en data debe contener TUNNEL_TOKEN)
kubectl describe secret -n cloudflare-tunnel-system cloudflare-tunnel-token-secret

# Podemos ver en la terminal que TUNNEL_TOKEN tiene el valor correcto
export CLOUDFLARE_TUNNEL_TOKEN=$(kubectl get secret --namespace cloudflare-tunnel-system cloudflare-tunnel-token-secret -o jsonpath="{.data.TUNNEL_TOKEN}" | base64 -d); echo $CLOUDFLARE_TUNNEL_TOKEN
```

3. Desplegamos el agente:

```sh
# Esto levantará 2 réplicas del pod:
kubectl apply -f k8s/deployments/cloudflare-tunnel/deployment.yaml

# Validamos el estado de los pods
kubectl get pods -n cloudflare-tunnel-system -o wide

# En caso de algún error, podemos validar los logs:
kubectl logs -l app=cloudflared -n cloudflare-tunnel-system --tail=50
```

En cuanto los Pods de `cloudflared` pasen a `Running`, veremos en la interfaz web de Cloudflare Zero Trust (en *Network -> Tunnels & Mesh*) que el estado del túnel cambia a un círculo verde que dice `Healthy`.

En caso de que hayamos levantado el agente, pero por alguna razón deje de estar disponible (porque por ejemplo la VM sobre la cual se instaló no está disponible), el estado del túnel cambiará a un círculo rojo que dice `Down`.



## Configuración del Almacenamiento Local (`StorageClass`) - CSI (Container Storage Interface)

Las bases de datos (Postgres, MongoDB, ScyllaDB) y SeaweedFS (que son servicios que planeo instalar en este clúster) requieren almacenamiento persistente con baja latencia. Como cada Mini PC tiene un NVMe de 1 TB rápido, usaremos el almacenamiento local físico de los nodos a través de **OpenEBS (LocalPV Provisioner)**.

OpenEBS creará dinámicamente carpetas dentro del disco de la VM de Talos cada vez que una base de datos pida un `PersistentVolumeClaim` (PVC), garantizando que Postgres escriba directo al NVMe a máxima velocidad.


### ¿Por qué preferir OpenEBS sobre otras alternativas?

En primer lugar, hay que tener en cuenta que la gran limitación de OpenEBS es que no tiene replicación de forma nativa. Es decir, si por ejemplo el Nodo 1 muere, (los datos de los pods que corrían en ese NVMe no están en el Nodo 2), el pod se moverá al Nodo 2 (gracias a Kubernetes), pero levantará vacío o fallará por falta de volumen.

Sin embargo, en nuestro caso podemos delegar la replicación (en caso de querer alta disponibilidad) a las aplicaciones, no al disco, y cada servicio tiene su propia forma de hacerlo:

- **Bases de Datos (Postgres, MongoDB, ScyllaDB):** Tienen sus propios mecanismos de replicación nativa (Streaming Replication, Replica Sets, arquitectura distribuida de Scylla). Es un error de rendimiento masivo replicar Postgres a nivel de disco si ya se tiene un nodo primario en `worker-data-01` y una réplica en `worker-ops-02`. OpenEBS LocalPV les dará la velocidad NVMe pura que necesitan.

- **SeaweedFS:** Es un sistema de archivos distribuido por definición. Al tener el Volumen 1 en una Mini PC y el Volumen 2 en la otra, SeaweedFS se encarga de la replicación. No se necesita que el disco subyacente replique nada.

- **Apache Pulsar / ZooKeeper / BookKeeper:** BookKeeper replica los datos de los mensajes de forma nativa a través de múltiples bookies. Replicar el disco debajo rompería el consenso de Pulsar.

- **Observabilidad (VictoriaMetrics, OpenObserve, etc.):** Son cargas intensivas de escritura. OpenEBS LocalPV es perfecto aquí. La alta disponibilidad se logra con arquitecturas clusterizadas de VictoriaMetrics, no replicando discos duros virtuales.

Como se puede apreciar, la arquitectura de software que requiero ya contempla la separación por nodos físicos, por lo que la resiliencia se debería manejar en las configuraciones de los servicios (App Level), no en la capa de almacenamiento.

**¿Y si se requiere migrar después a un tipo de almacenamiento que soporte replicación?**

Es totalmente factible, pero requiere de una serie de pasos, y el impacto dependerá de si la migración se hace a nivel de infraestructura o a nivel de aplicación. El **impacto en los servicios** es que se requerirá un tiempo de inactividad controlado (downtime) para cada servicio que se migre. El proceso técnico estándar sería el siguiente:

1. Instalar el nuevo sistema de almacenamiento replicado en el clúster (convivirá con OpenEBS).
2. Escalar el Deployment/StatefulSet de la aplicación a 0 réplicas para congelar los datos.
3. Usar una herramienta como Velero o un pod temporal con `rsync` para copiar los datos del volumen de OpenEBS al nuevo volumen replicado.
4. Modificar el YAML de la aplicación para que apunte a la nueva `StorageClass`.
5. Escalar la aplicación de nuevo a 1 o más réplicas.

**¿Qué alternativas de Alta Disponibilidad podrían considerarse?**

Si en el futuro se requiere que los datos se repliquen entre los dos nodos físicos, no sería recomendable usar **Longhorn** ya que es demasiado pesado para 2 nodos y sufre de *split-brain* sin un tercer nodo testigo. Las alternativas modernas serían entonces:

- **TopoLVM:** Utiliza LVM debajo para un rendimiento excelente, muy similar a OpenEBS pero con mejor gestión de cuotas.
- **Linstor (con DRBD):** Es un sistema de gestión centralizado que automatiza la creación y el mantenimiento de los volúmenes de DRBD, LVM o ZFS sin requerir configuraciones manuales; a pesar de que es más liviano que Longhorn, por lo general requiere almacenamiento homogéneo (en [este enlace](https://www.pimwiddershoven.nl/entry/storage-on-talos-linux-with-linstor-and-drbd/) podemos ver un tutorial del uso de Linstor).
- **PGO / Replicación por software:** Dejar que herramientas como un clúster de Postgres (CloudNativePG) repliquen los datos usando almacenamiento local, en lugar de replicar a nivel de disco.
- En la [documentación de Talos acerca de CSI](https://docs.siderolabs.com/kubernetes-guides/csi/storage#openebs-mayastor-replicated-storage), podemos encontrar otras alternativas de almacenamiento.

_**Actualización Técnica:** OpenEBS a partir de su versión 4.x soporta replicación a través de Mayastor, sin embargo, como lo mencionamos previamente, en nuestro caso la replicación será gestionada por la capa de aplicación._


### Instalación de OpenEBS

OpenEBS proporciona diferentes motores de almacenamiento (LocalPV, Mayastor, etc.). El siguiente comando instala los componentes estándar de OpenEBS y en nuestro caso, instalaremos solo el StorageClass para LocalPV ([configurar OpenEBS Local PV en Talos Linux](https://oneuptime.com/blog/post/2026-03-03-set-up-openebs-local-pv-on-talos-linux/view)):

```sh
# Agregamos el repositorio
helm repo add openebs https://openebs.github.io/openebs
helm repo update

# Instalamos en un nuevo namespace
helm upgrade --install openebs openebs/openebs --version 4.5.1 \
  -n openebs --create-namespace \
  -f k8s/deployments/openebs-values.yaml
```

Para verificar que se haya creado el StorageClass, ejecutamos lo siguiente:

```sh
kubectl get sc
# Esto muestra una respuesta como esta:
# NAME                         PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
# openebs-hostpath (default)   openebs.io/local   Delete          WaitForFirstConsumer   false                  5s

# Adicionalmente, podemos comprobar que los pods se estén ejecutando en el namespace openebs
kubectl get pods -n openebs -o wide
```

**Nota técnica:** El parámetro `allowVolumeExpansion` para el aprovisionador local nativo de OpenEBS en modo `hostpath` se mapea internamente como `false` en la especificación CSI base debido a que delega la gestión de cuotas al sistema de archivos subyacente (XFS/EXT4 con proyectos de cuota, los cuales vienen desactivados por defecto).


### Usar OpenEBS como StorageClass

Para usar OpenEBS en aplicaciones con estado (StatefulSet), se puede hacer referencia a cualquiera de las StorageClasses disponibles (por ejemplo, `openebs-hostpath` para almacenamiento rápido en el disco del nodo).

Aquí dejo un ejemplo de cómo crear una `PersistentVolumeClaim` (PVC) utilizando la clase de almacenamiento local predeterminada de OpenEBS:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc-openebs
  namespace: my-apps
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: openebs-hostpath
  resources:
    requests:
      storage: 5Gi
```

Al aplicar un manifiesto como éste en el clúster, Kubernetes y OpenEBS aprovisionarán dinámicamente el volumen.


### Configurar una StorageClass personalizada (Opcional)

Si se desea utilizar motores más avanzados, como Local PV LVM o Replicated PV, se debe crear un manifiesto propio (aunque primero se debería modificar el values de openebs y actualizar la instalación, ya que en nuestro caso solo instalamos el componente de Local PV). A continuación dejo un ejemplo de creación de un `StorageClass`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: openebs-local-fast
  annotations:
    openebs.io/cas-type: local
    cas.openebs.io/config: |
      - name: StorageType
        value: "hostpath"
      - name: BasePath
        value: "/var/openebs/local"
provisioner: openebs.io/local
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

El modo de enlace `WaitForFirstConsumer` es importante porque garantiza que el PV se cree en el mismo nodo donde se programa el pod.


### Uso de discos dedicados

En algunos tutoriales mencionan la creación de un StorageClass de tipo `device`, sin embargo, OpenEBS LocalPV Device y Node Disk Manager fueron marcados como obsoletos (deprecated) en las versiones actuales de OpenEBS, por lo tanto, el StorageClass `openebs-device` de versiones anteriores (OpenEBS 3.x) no debería utilizarse en las nuevas instalaciones de OpenEBS 4.x. Si se dispone de discos dedicados en los nodos de Talos, se recomienda utilizar OpenEBS Local PV LVM o ZFS en su lugar.

Entonces, para manejar el almacenamiento de alto rendimiento tenemos dos escenarios:

#### Escenario A: Mantener un solo disco grande por VM (Recomendado por Simplicidad)

Si asignamos 300 GB de disco a un workers de Talos (como hicimos por ejemplo con la VM `worker-data-01`) como un único volumen de arranque (`/dev/sda`), no necesitamos otra StorageClass. Deberíamos usar únicamente `openebs-hostpath` para todos los servicios (incluyendo Postgres, Mongo y ScyllaDB).

Esto debido a que como el disco físico NVMe subyacente en mis Mini PCs es extremadamente rápido, `openebs-hostpath` escribirá a través del sistema de archivos de Talos a una velocidad casi idéntica a la nativa, delegando el aislamiento a las cuotas de Kubernetes.

#### Escenario B: Usar discos físicos crudos e independientes (/dev/sdb) para las DBs

Si en Proxmox le agregamos un segundo disco virtual exclusivo a `worker-data-01` y `worker-heavy-02` para separar el sistema operativo de los datos, debemos usar el motor Local PV LVM o ZFS en lugar de Device.

Sin embargo, como LVM y ZFS requieren binarios en el host que Talos Linux no incluye por su naturaleza minimalista, la única forma de lograr esto en Talos v1.13+ es utilizando el nuevo motor `rawfile` (el cual deberíamos activar en el values configurando `engines.local.rawfile.enabled: true`, además de los provisioners para `engines.local.lvm` y/o `engines.local.zfs`).



## Instalación de Componentes utilitarios


### Operadores Para Manejar Secretos Externos

Para inyectar dentro de un servicio o aplicación, variables que contienen datos sensibles como por ejemplo tokens o contraseñas, solemos hacerlo a través de secretos. El problema de los secretos nativos de Kubernetes es que se guardan en texto plano codificado en Base64 (codificado no significa cifrado o encriptado) y por lo tanto debemos procurar evitar subir estos archivos `.yaml` de secretos a nuestro repositorio, ya que cualquiera podría decodificarlos y robar nuestros datos sensibles.

Como vimos en secciones anteriores, hay diversas estrategias que podríamos usar para crear archivos de secretos con marcadores tipo `${VAR}` de modo tal que podemos leer variables de entorno y, a través de `envsubst` inyectamos dichos valores en memoria temporal y se los pasamos a `kubectl` sin modificar el archivo `.yaml` original del secreto que contiene los marcadores tipo `${VAR}`; de este modo, podríamos subir estos archivos de secretos sin riesgo de exponer datos sensibles.

Esta estrategia de usar marcadores tipo `${VAR}` sería útil para ejecuciones manuales mediante `kubectl apply`, sin embargo, no es una estrategia que podamos aplicar si queremos implementar un flujo de despliegue continuo mediante GitOps (por ejemplo usando ArgoCD o FluxCD).

Al trabajar con GitOps, nuestro repositorio de Git (que en nuestro caso es GitHub, pero podría ser cualquier otro, como por ejemplo GitLab) se convierte en la fuente de verdad, y por tanto, solo se desplegará en el clúster lo que subamos a través de nuestros commits. Esto quiere decir, que para que se pueda levantar un secreto en el clúster debemos implementar alguna estrategia para que dicho secreto se suba cifrado al repositorio de Git, de modo tal que cuando la herramienta de CD que usemos lo vaya a aplicar/instalar, lo pueda descifrar de forma segura.

Entre las principales estrategias que tenemos para lograr esto, tenemos **SealedSecrets** (de Bitnami), **SOPS** (de Mozilla) y operadores externos como **External Secrets Operator** (ESO) ó **Vault External Operator** (VSO) + Vault. En la siguiente tabla comparativa podemos apreciar las principales diferencias entre estas tres herramientas:

| Característica | SealedSecrets | Mozilla SOPS | ESO ó VSO + Vault |
|----------------|---------------|--------------|-----------------------------------------|
| **¿Qué se sube a Git?** | Un archivo encriptado (`SealedSecret`). | El archivo YAML original pero con los campos de datos cifrados. | Solo **referencias o punteros** (nombres de llaves), ningún dato real. |
| **Dependencia del Clúster** | Atado al clúster (usa la llave privada del pod controlador). | Agnóstico al clúster (usa llaves PGP/Age o KMS externas). | Totalmente agnóstico. El clúster solo lee del almacén externo. |
| **Rotación de Credenciales** | Manual y tediosa. | Manual (requiere re-encriptar con la CLI). | **Automática**. Se cambia el valor del secreto en Vault y se actualiza solo en Kubernetes. |
| **Estándar de Producción** | Para Equipos pequeños / Proyectos legacy. | Para Equipos medianos / Automatizaciones CI-CD. | El estándar de facto para Enterprise. |

#### ¿Cuál es la alternativa más recomendable para nuestro Homelab?

La alternativa más recomendable es usar un operador externo (ESO o VSO) combinado con HashiCorp Vault (el cual ya hemos [instalado previamente en un LXC sobre Proxmox](#instalaci%C3%B3n-de-hashicorp-vault-en-proxmox)), y las razones son las siguientes (podríamos usar los dos operadores, sin embargo hay que tener en cuenta que *VSO* está pensando para trabajar estrictamente con Vault ya que permite gestionar todos sus recursos nativos, como por ejemplo los secretos de tipo *database* que permiten rotación automática de credenciales, mientras que *ESO* es una opción multi-provider que nos permitiría trabajar también con otros almacenes como por ejemplo Doppler, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, etc.):

1. **Desacoplamiento Absoluto (Verdadero GitOps):** Con *SealedSecrets* o *SOPS*, si nuestro clúster físico colapsa por completo y perdemos los respaldos de las llaves maestras de cifrado, los archivos en nuestro repositorio de GitHub se vuelven basura ilegible e irrecuperable. Con **ESO** y **VSO**, los datos confidenciales reales están seguros y centralizados en nuestra bóveda (Vault). Reconstruir el homelab desde cero es tan fácil como levantar un nuevo clúster, instalar el operador externo, apuntar a Vault y ver cómo todo vuelve a la vida de inmediato.

2. **Simulación de Escenarios Corporativos Reales:** En el mundo empresarial moderno de alta regulación, nunca se permite que un desarrollador cifre un secreto a mano con una CLI y lo empuje a Git y por tanto, normalmente el equipo de seguridad provee un Administrador de Secretos (KMS / Vault). Aprender el flujo de trabajo por ejemplo de ESO (crear recursos `SecretStore` y `ExternalSecret`) nos brindará las habilidades exactas que exigen los entornos de producción actuales.

3. **Rotación Automática y Auditoría:** Si necesitamos cambiar la contraseña de una base de datos, solo la actualizamos en la interfaz o API de Vault. El operador externo (ya sea ESO o VSO) detectará el cambio en minutos, actualizará el secreto nativo de Kubernetes y (si añadimos una herramienta complementaria muy popular llamada *Reloader*) reiniciará automáticamente los Pods para que carguen la nueva credencial sin intervención manual. Además, Vault guardará logs estrictos de auditoría de qué servicios del clúster están leyendo qué contraseñas.

Además, estos operadores externos están pensados para centralizar el flujo de autenticación y comunicación con Vault, lo cual evita que tengamos que desplegar sidecards adicionales junto a nuestras aplicaciones para extraer los secretos.

Pero antes de instalar los operadores en nuestro clúster, debemos hacer unas configuraciones previas que veremos a cotninuación.

#### Creación de la ServiceAccount para el Revisor de Tokens en Vault

Para que Vault pueda verificar los tokens que le envíen nuestros operadores (ESO o VSO), necesita tres datos del clúster de Kubernetes: la URL de la API, el certificado CA para que Vault confíe en los certificados TLS de nuestro clúster (no confundir con el internal CA que generamos previamente) y un token con permisos para revisar identidades (`TokenReview`).

La URL de la API de kubernetes la podemos obtener sin tener que configurar nada adicional, sin embargo, para obtener el certificado y el token, la forma más limpia y recomendada es crear una `ServiceAccount` dedicada para Vault dentro del clúster y usar su token de larga duración (ya que Vault está fuera del clúster (en un LXC) y necesita una credencial permanente para hablar con la API de Kubernetes).

Para eso, ejecutamos los siguientes comandos:

```sh
# Creamos el namespace
kubectl apply -f k8s/external-auth-namespace.yaml

# Creamos la ServiceAccount del Reviewer y su respectivo token
kubectl apply -f k8s/vault-token-reviewer-setup.yaml
```

Cabe recalcar que a partir de Kubernetes 1.24+, las Service Accounts ya no guardan un token estático y permanente en un objeto tipo `Secret`, por eso, como se puede apreciar en el archivo `k8s/vault-token-reviewer-setup.yaml`, tuvimos que crear explícitamente un secreto de larga duración de tipo `kubernetes.io/service-account-token`.

Después de esto, podemos ejecutar los siguientes comandos para obtener los datos que necesitamos para configurar el método de autenticación de Kubernetes en Vault (en el [README de Vault](VAULT_README.md#3-extraer-datos-para-configurar-la-autenticaci%C3%B3n-en-vault) mostramos cómo usar estos datos):

```sh
# Obtener la URL de la API de Kubernetes (En nuestro caso: https://192.168.0.30:6443)
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Obtener el token del revisor
K8S_TOKEN=$(kubectl get secret vault-token-reviewer-secret -n external-auth -o jsonpath='{.data.token}' | base64 --decode)

# Obtener el certificado CA del clúster
K8S_CA=$(kubectl get secret vault-token-reviewer-secret -n external-auth -o jsonpath='{.data.ca\.crt}' | base64 --decode)
```

#### Automatización de la Sincronización del Certificado de Vault Server 

Como vimos en el paso de [exponer el certificado de Vault](VAULT_README.md#exponer-el-certificado-vía-http-dentro-del-lxc), para que los clientes (como el operador de ESO) puedan verificar la identidad del servidor de Vault, deben usar el mismo certificado TLS implementado para las conexiones HTTPS en la configuración de Vault, y es por eso que expusimos dicho certificado a través de un servidor web en la ruta `http://192.168.0.20/certs/vault.crt`, lo cual nos permitiría descargar su contenido directamente en una `ConfigMap` o en `Secret` de la siguiente forma:

```sh
# Así lo descargaríamos para el ConfigMap que requeriría ESO
kubectl create configmap vault-ca-cert \
  --from-file=vault-ca.crt=<(curl -s http://192.168.0.20/certs/vault.crt) \
  -n external-secrets

# Así lo descargaríamos para el Secret que requeriría VSO
# A diferencia de ESO, con VSO el certtificado TLS del servidor de Vault no se puede cargar
# mediante un ConfigMap. VSO requiere obligatoriamente que sea un Secret y que la clave se
# guarde con el nombre ca.crt, ya que VSO busca ese campo específico de forma predeterminada
kubectl create secret generic vault-ca-cert \
  --from-file=ca.crt=<(curl -s http://192.168.0.20/certs/vault.crt) \
  -n vault-secrets-operator
```

Sin embargo, como vimos también en la sección de [renovación automática del certificado](VAULT_README.md##renovación-automática-del-certificado), éste cambia periódicamente y por tanto, el certificado que descarguemos ahora, sólo nos servirá para las configuraciones iniciales que necesitemos hacer en nuestro clúster de Kubernetes, ya que después de un tiempo dicho certificado dejará de funcionar.

Por lo tanto, ya que el certificado en el LXC de Vault se renueva cada X cantidad de tiempo (3 meses según la configuración que realizamos), del mismo modo deberíamos procurar tener desde nuestro clúster de Kubernetes una forma automatizada de obtener dicho certificado actualizado.

Si bien es cierto que desde el mismo Cron Job que regenera el certificado en el LXC de Vault podríamos invocar un comando `kubectl` para escribir el certificado en un `Secret` o `ConfigMap` de nuestro clúster después de que se actualice, esto implicaría tener que copiar el archivo `~/.kube/config` en el contenedor LXC, pero en entornos de producción lo ideal es prevenir que una máquina virtual, contenedor o servicio externo (como Vault) tenga permisos de administración (`kubectl`) sobre el clúster por motivos de seguridad.

Por tanto, nuestra alternativa será que en lugar de que el LXC "empuje" el certificado hacia Kubernetes, hagamos que Kubernetes vaya a "buscar" el certificado al LXC, y para esto, crearemos un `CronJob` nativo de Kubernetes que corra cada 8 horas (podría ser menos ya que el consumo de recursos de este job sería muy ínfimo, pero para el caso de nuestro Homelab, este tiempo está bien). Si bien el certificado se renueva en el LXC cada 3 meses, es difícil controlar el gap entre cuando corre el job en el LXC vs cuando corre el job en nuestro clúster, por eso lo configuramos con mucho menos tiempo, ya que en el peor de los casos, el clúster tendrá el certificado desactualizado solo por 8 horas hasta la próxima ejecución del job.

Así pues, el pod de este CronJob ejecutará un comando `curl` hacia el LXC de Vault, descargará el archivo `.crt`, actualizaría los `ConfigMap` y `Secret` localmente y haría un `rollout restart` de los operadores. Para esto, el Pod que crea el job usaría una `ServiceAccount` interna del clúster con permisos estrictos únicamente sobre esos recursos, lo cual en efecto es mucho más seguro que permitir que un servicio externo tenga acceso a nuestro clúster.

Para crear este `CronJob` ejecutamos los siguientes comandos:

```sh
# 1. Crear los namespaces
# Creamos el namespace donde correrá el job
kubectl apply -f k8s/shared-ops-namespace.yaml
# Creamos los namespaces donde se insalarán posteriormente los operadores ESO y VSO, ya
# que dentro de ellos crearemos el ConfigMap y Secret con el certificado TLS de Vault.
# Además en estos también crearemos el RoleBinding que necesita la ServiceAccount del Job
kubectl apply -f k8s/eso-namespace.yaml
kubectl apply -f k8s/vso-namespace.yaml

# 2. Crear y Asignar permisos mediante RBAC (Role-Based Access Control)
# El CronJob necesita permisos exclusivos para actualizar el ConfigMap y el Secert que
# leen los operadores ESO y VSO
kubectl apply -f k8s/vault-cert-syncer-rbac.yaml

# 3. Crear el CronJob (tarea programada) que ejecutará los jobs cada 8 horas
kubectl apply -f k8s/deployments/vault-cert-syncer-cronjob.yaml

# Si revisamos la lista de configmaps y secrets, podemos
# apreciar que aún no existe uno llamado 'vault-ca-cert'
kubectl get configmap -n external-secrets -o wide
kubectl get secret -n vault-secrets-operator -o wide
```

Como podemos apreciar, aún no existe el `ConfigMap` y el `Secret` que necesitarán ESO y VSO respectivamente, y eso se debe a que solo hemos creado la *tarea programada* (el `CronJob`), es decir, aún no se ha ejecutado nada. Para que se creen/actualicen estos recursos necesitamos que se ejecute esta tarea (el `Job`), para lo cual podríamos esperar 8 horas (que es la periodicidad que le confguramos al CronJob), o forzar una primera ejecución manual mediante la creación de un Job, lo cual haremos a continuación:

```sh
# Hacemos una primera ejecución del Job para que se cree el ConfigMap y el Secret
# en los namespaces de ESO y VSO respectivamente
kubectl create job first-sync-vault-cert-manual \
  --from=cronjob/sync-vault-cert \
  -n shared-ops

# Vemos la lista de jobs creados (deben quedar en estado Completed):
kubectl get jobs -n shared-ops -o wide

# Vemos los pods creados por los jobs (deben quedar en estado Completed):
# READY quedaría 0/1 ya que el pod finaliza apenas termina la ejecución del Script
kubectl get pods -n shared-ops -o wide

# Verificamos que no hayan errores en los logs
kubectl logs -n shared-ops -l job-name=first-sync-vault-cert-manual -f --tail=50

# Validamos que en efecto ya existe el configmap y secret 'vault-ca-cert'
kubectl get configmap -n external-secrets -o wide
kubectl get secret -n vault-secrets-operator -o wide
```

El Script que se ejecuta dentro del pod que crea el job está pensado para actualizar estos recursos (el ConfigMap y el Secret) solo cuando el certificado descargado del servidor de Vault (del LXC) se renueva, por tanto, si ejecutamos un segundo job de prueba podremos ver que no se actualiza el ConfigMap y el Secret ya que actualmente el certificado es el mismo del servidor de Vault:

```sh
# Ejecutamos un segundo job de prueba
kubectl create job second-sync-vault-cert-manual \
  --from=cronjob/sync-vault-cert \
  -n shared-ops

# Validamos el resultado en los logs
kubectl logs -n shared-ops -l job-name=second-sync-vault-cert-manual --tail=50
```

Ahora sí procedemos con la instalación de los operadores de ESO y VSO.

#### Instalación de ESO

Para instalar External Secrets Operator, ejecutamos los siguientes comandos:

```sh
# Agregamos el repositorio
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Instalamos
helm upgrade --install external-secrets external-secrets/external-secrets --version 2.9.0 \
  --namespace external-secrets \
  -f k8s/deployments/eso-values.yaml
```

Para validar la instalación podemos ejecutar lo siguiente:

```sh
# Validamos que se crearon los pods (los pods de webhook y cert-controller suelen tardar
# un poco en quedar en READY=1/1):
kubectl get pods -n external-secrets -o wide

# Podemos validar también los CRDs que se crearon
kubectl get crds | grep external-secrets
```

#### Instalación de VSO

Para instalar Vault Secrets Operator, ejecutamos los siguientes comandos:

```sh
# Agregamos el repositorio
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Instalamos
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator --version 1.5.1 \
   --namespace vault-secrets-operator \
   -f k8s/deployments/vso-values.yaml
```

Para validar la instalación podemos ejecutar lo siguiente:

```sh
# Validamos que se creó el pod:
kubectl get pods -n vault-secrets-operator -o wide

# Podemos validar también los CRDs que se crearon
kubectl get crds | grep secrets.hashicorp.com
```

**Manifiestos Globales de Configuración de VSO**

A diferencia de ESO, en VSO no se usa un certificado global montado dentro del Pod, pero nos da la flexibilidad de usar un `VaultConnection` y `VaultAuthGlobal` que a pesar de que se crean en un namespace específico (como por ejemplo en el que instalamos VSO), actúan como de ámbito global, lo que permite referenciarlos desde recursos `VaultAuth` ubicados en cualquier otro namespace.

De este modo, como el certificado se referencia solo en el `VaultConnection`, podemos tener un único recurso de este tipo y por ende, un solo `Secret` con el certificado TLS de vault (que es el que creamos y actualizamos periódicamente mediante el job), lo cual no se puede hacer con ESO (a menos que use solo `ClusterSecretStore`), ya que el recurso (`SecretStore`) que maneja los datos de conexión (URL del servidor de Vault y certificado TLS para hacer handshake) es el mismo que maneja los datos de autenticación (por eso en ESO cargamos el ConfigMap con el certificado como volumen en el pod, para así evitar crear dicho ConfigMap en cada namespace que se necesite crear un SecretStore).

Por tanto, a continuación crearemos nuestros recursos `VaultConnection` y `VaultAuthGlobal` sobre el mismo namespace de VSO (y no por ejemplo en `external-auth`), ya que no son componentes de infraestructura general de autenticación (como el Token Reviewer), sino la configuración core del motor de VSO, por tanto, toda configuración global que dicta cómo opera una herramienta debe residir dentro del "límite de confianza" (trust boundary) de este operador.

Además, mantenerlos en `vault-secrets-operator` asegura que el plano de control de VSO esté centralizado y sea autocontenido. Por tanto, si necesitamos respaldar, migrar o auditar la configuración de VSO, sabemos que todo está en un único namespace.

Así pues, ejecutamos entonces los siguientes comandos:

```sh
# Creamos la Conexión Global
kubectl apply -f k8s/vso-vault-connection.yaml

# Validamos que se haya creado el recurso 'vault-connection'
# Debe quedar HEALTHY=True y READY=True
kubectl get vaultconnections -n vault-secrets-operator -o wide

# Creamos nuestro Configuración de Autenticación Global
kubectl apply -f k8s/vso-vault-auth-global.yaml

# Validamos que se haya creado el recurso 'vault-auth-global-eljavatar-k8s'
# En este caso no vemos ningún estado, ya que un VaultAuthGlobal como tal no realiza
# ninguna acción de autenticación. Simplemente lo creamos con datos de configuración
# genéricos que podemos heredar después a los recursos VaultAuth.
kubectl get vaultauthglobals -n vault-secrets-operator -o wide

# En caso de que el VaultConnection no se cree correctamente, podemos revisar
# los logs del controlador de VSO para encontrar la causa del error:
kubectl logs -n vault-secrets-operator deployments/vault-secrets-operator-controller-manager -f --tail=50
```


### Reloader

Hay un problema clásico en Kubernetes: si inyectamos secretos o configuraciones como variables de entorno (`env`), el Pod no se enterará del cambio hasta que se reinicie.

Para solucionar esto, y hacer que las aplicaciones en el clúster se enteren instantáneamente de un cambio en un `Secret` o un `ConfigMap` que se está usando sin tener que reiniciar los Pods a mano, se utiliza una herramienta del ecosistema de CNCF llamada **Reloader** (de Stakater).

Para instalar reloader, ejecutamos lo siguiente:

```sh
# Agregamos el repositorio
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

# Instalamos
helm install reloader stakater/reloader --version 2.2.17 \
  --namespace reloader --create-namespace
  -f k8s/deployments/reloader-values.yaml
```

Para verificar la instalación, ejecutamos:

```sh
kubectl get pods -n reloader

kubectl logs -n reloader -l app=reloader-reloader
```

A pesar de que estamos desplegando Reloader con la config `reloader.watchGlobally=true`, la cual hace que Reloader pueda ver los cambios en secretos y configmaps en todos los namespaces, no quiere decir que éste actúe automáticamente sobre todos los pods, ya que para que Reloader pueda lanzar un `rollout restart` se requiere que en el manifiesto del deployment se agregue una anotación (ver la documentación oficial de [How Reloader Works](https://docs.stakater.com/reloader/1.4/architecture/how-it-works.html#step-3-workload-matching)):

```yaml
metadata:
  annotations:
    # Existen varias anotaciones que podríamos usar, sin embargo, aquí muestro algunas de las
    # más comunes. No quiere decir que se deban usar todas, ya que depende de lo que requiramos
    # En la documentación se puede encontrar la lista de anotaciones que podemos usar:
    # https://docs.stakater.com/reloader/1.4/reference/annotations.html#workload-annotations
    # https://docs.stakater.com/reloader/1.4/index.html#annotation-patterns

    # Supervisa todos los ConfigMaps y Secrets a los que hace referencia la carga de trabajo.
    reloader.stakater.com/auto: "true"

    # Observa uno o más Secretos nombrados explícitamente:
    secret.reloader.stakater.com/reload: "database-secret,api-keys"

    # Observa explícitamente uno o más ConfigMaps que coinciden con estos nombres.
    configmap.reloader.stakater.com/reload: "app-config,feature-flags"

    # Habilita el modo de búsqueda. Reloader solo iniciaría un reinicio cuando un ConfigMap o
    # Secret referenciado también tenga la anotación 'reloader.stakater.com/match: "true"'.
    # Se utiliza junto con match para dar a los dueños de Secret/ConfigMap control sobre
    # qué recursos activan las recargas.
    reloader.stakater.com/match: "true"
```


### Descheduler

Al usar `preferredDuringSchedulingIgnoredDuringExecution` (como en nuestro caso con CoreDNS), Kubernetes no rebalancea los Pods por sí solo una vez que las Mini PCs se estabilizan tras un reinicio masivo. Es decir, si por ejemplo se reinicia primero la Mini PC 2 que la Mini PC 1, las tres instancias de CoreDNS caerán en la VM de `ops` que se encuentra en la Mini PC 2, y estas permanecerán ahí a menos que se fuerce un rollout manual.

A este problema se le conoce como afinidad suave (*soft affinity*), donde Kubernetes no rebalancea los Pods por sí solo una vez que las condiciones de quórum se estabilizan tras un reinicio de nodos, y es precisamente lo que Descheduler nos ayuda a solucionar (también podríamos solventarlo haciendo un reinicio usando por ejemplo `kubectl rollout restart deployment coredns -n kube-system`, pero esto habría que hacerlo por cada deployment).

Descheduler se puede ejecutar en 3 modos: *Job*, *CronJob* y *Deployment*. Descartamos la opción de Job o CronJob, debido a que este modo ejecuta el Descheduler de forma intermitente (por ejemplo, cada 15 minutos) como una herramienta CLI. Esto causa que, si un nodo se reinicia y desbalancea los pods (por ejemplo los de CoreDNS), el sistema permanecerá desorganizado hasta el siguiente ciclo del cron.

En contraste, al correr como un Deployment continuo (configurando el intervalo con la directiva `deschedulingInterval`), el Descheduler opera como un controlador activo que audita el estado del clúster continuamente. En el momento exacto en que detecta que un nodo de las Mini PCs volvió a la vida y está disponible para alojar a CoreDNS de forma óptima, calcula la penalización de peso e inicia la desalojación (*eviction*) programada de forma progresiva sin esperar una ventana de tiempo rígida como la de un CronJob.

Sin embargo, por ejempo para el caso de CoreDNS se debe asegurar que los despliegues toleren estos reinicios sin perder conectividad, ya que si el Descheduler decidiera mover los pods de CoreDNS al mismo tiempo sin protección, el clúster se quedaría sin resolución de nombres por unos segundos, rompiendo la comunicación entre las aplicaciones y servicios. Para mitigar esto, al levantar el pod se debería tener en cuenta lo siguiente:

- Configurar el `RollingUpdate` con `maxUnavailable: 0` para garantizar que Kubernetes no pueda matar un pod viejo si no hay uno nuevo listo y `maxSurge: 1` para permitir crear un pod temporal extra en el nodo alterno antes de la limpieza.
  ```yaml
  spec:
    replicas: 2
    strategy:
      type: RollingUpdate
      rollingUpdate:
        maxUnavailable: 0 # Prohibe apagar un pod activo si no hay otro listo
        maxSurge: 1       # Permite crear 1 pod nuevo temporal antes de borrar el viejo
  ```

- Crear un `PodDisruptionBudget` (PDB) el cuál operará como un escudo técnico: Cuando el Descheduler intente enviar una orden de `Evict` a un Pod, por ejemplo de CoreDNS concentrado en el nodo de `ops`, la API de Kubernetes interceptará la petición y consultará el PDB. Si un segundo pod de CoreDNS está iniciándose y solo hay uno sano, Kubernetes rechazará la orden del Descheduler, protegiendo el clúster. El Descheduler esperará al siguiente ciclo (por ejemplo 5 minutos en nuestro caso) para reintentar la operación de forma segura.
  ```yaml
  apiVersion: policy/v1
  kind: PodDisruptionBudget
  metadata:
    name: target-app-pdb
    namespace: my-apps
  spec:
    minAvailable: 1
    selector:
      matchLabels:
        app: target-app
  ```

- Sondas de salud integradas (`livenessProbe` y/o `readinessProbe`) para garantizar que el Pod está listo antes de apagar el anterior.

#### Validaciones en el Servicio que será afectado por Descheduler (CoreDNS)

Hay que tener en cuenta que el Descheduler no afectará a pods que tengan reglas de afinidad estrictas, como puede ser el caso de las que aplicamos en nuestro deployment de `cloudflared`; veamos un ejemplo de las reglas de afinidad que aplicamos en dicho deployment:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: custom-role
              operator: In
              values:
                - ops
                - apps
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app
              operator: In
              values:
                - cloudflared
        topologyKey: "topology.kubernetes.io/zone"
```

Aquí podemos ver el uso de la directiva `requiredDuringSchedulingIgnoredDuringExecution`, la cual es una regla estricta (dura). En este caso, el programador nativo de Kubernetes (`kube-scheduler`) tiene prohibido de forma absoluta colocar dos Pods con esa configuración en la misma zona de topología (`topology.kubernetes.io/zone`).

Como Kubernetes jamás violará esa regla en primer lugar (preferirá dejar un Pod en estado `Pending` antes de ponerlos juntos en la misma zona), el plugin `RemovePodsViolatingInterPodAntiAffinity` del Descheduler auditará el clúster, verá que la regla se está cumpliendo perfectamente y pasará de largo sin tocar a `cloudflared`. Por tanto, el Descheduler solo actúa sobre reglas duras violadas, no sobre reglas cumplidas.

Además, si bien es cierto que el plugin `RemovePodsViolatingInterPodAntiAffinity` que usamos en la configuración del Descheduler puede limpiar Pods si una regla dura (`required`) se rompe a posteriori (por ejemplo, si cambiamos los labels de un nodo en caliente), en este caso particular de `cloudflared` la regla de separación es por Zona de Topología (Mini PC física) (`topologyKey: "topology.kubernetes.io/zone"`), no por VM de Talos (`kubernetes.io/hostname`). Como las zonas de mis Mini PCs no cambian dinámicamente, no hay escenario físico real en este Homelab donde esta regla pueda quedar en un estado de violación posterior al arranque.

Por otro lado, el Descheduler respeta el quórum imposible, es decir, si por alguna razón se reinicia una Mini PC y solo queda viva una zona, los Pods excedentes de `cloudflared` simplemente no podrán encender en ningún otro lado debido al flag `required`. El Descheduler sabe que desahuciar un Pod que no tiene un nodo alternativo que cumpla con sus requisitos obligatorios es inútil, por lo que el motor de desalojo (`DefaultEvictor`) abortará cualquier intento de moverlo para evitar quedarnos sin el servicio de Cloudflare Tunnel.

Teniendo esto claro, podemos confirmar si nuestro pod será afectado por el Descheduler validando si tiene configurada la regla `preferredDuringSchedulingIgnoredDuringExecution`, y para esto, ejecutamos lo siguiente:

```sh
# Reemplazamos coredns-xxxxxxxxx-xxxxx por el nombre real de uno de nuestros pods (ejemplo: coredns-9cc65fd7b-2qcvk)
kubectl get pod coredns-xxxxxxxxx-xxxxx -n kube-system -o yaml | grep -A 30 "affinity:"
```

Lo cual en nuesro caso nos muestra una salida como la siguiente:

```yaml
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: custom-role
            operator: In
            values:
            - ops
            - apps
            - data
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: k8s-app
              operator: In
              values:
              - coredns
          topologyKey: kubernetes.io/hostname
        weight: 100
```

Aquí podemos ver que en efecto tenemos configurada la regla `preferredDuringSchedulingIgnoredDuringExecution`, la cual aplicará a los pods que tengan la etiqueta `k8s-app: coredns`; para validar que los pods tengan dicha etiqueta, podemos ejecutar lo siguiente:

```sh
# Reemplazamos coredns-xxxxxxxxx-xxxxx por el nombre real de uno de nuestros pods (ejemplo: coredns-9cc65fd7b-2qcvk)
kubectl describe pod coredns-xxxxxxxxx-xxxxx -n kube-system
```

Lo cual en nuestro caso nos muestra una salida como la siguiente:

```yaml
Name:             coredns-xxxxxxxxx-xxxxx
Namespace:        kube-system
Priority:         0
Service Account:  default
Node:             worker-apps-01/192.168.0.41
Start Time:       Tue, 04 Aug 2026 23:13:22 -0500
Labels:           app.kubernetes.io/instance=coredns
                  app.kubernetes.io/name=coredns
                  k8s-app=coredns
                  pod-template-hash=xxxxxxxxx
                  topology.kubernetes.io/zone=pmx-01
```

Con estas validaciones, confirmamos que el Descheduler que configuraremos si tendrá efecto sobre nuestros pods de CoreDNS.

#### Instalación de Descheduler

Para instalar el descheduler, ejecutamos los siguientes comandos (en el archivo `descheduler-values.yaml` especifiqué algunas configuraciones según los requerimientos de este homelab, sin embargo en el [repositorio de GitHub](https://github.com/kubernetes-sigs/descheduler) se pueden encontrar más opciones de configuración):

```sh
# Agregamos el repositorio
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler/
helm repo update

# Instalamos
helm upgrade --install descheduler descheduler/descheduler --version 0.36.0 \
  -n kube-system \
  -f k8s/deployments/descheduler-values.yaml
```

Para validar la instalación podemos ejecutar lo siguiente:

```sh
# Validamos que se creó el respectivo pod:
kubectl get -n kube-system deployment/descheduler -o wide
# kubectl get pods -n kube-system -o wide | grep descheduler

# Validar el configmap que se creó
kubectl get configmap -n kube-system descheduler -o yaml
```

Para ver como actúa el descheduler podemos hacer una prueba de reinicio de las PCs y ejecutar un `kubectl get pods -n kube-system -o wide` en distintos momentos para validar cómo se rebalancean los pods para que cumplan con las reglas de afinidad incluso después de estar con estado `Running`:

```sh
# Inmediatamente después del reinicio
NAMESPACE     NAME                      READY   STATUS      RESTARTS      AGE     IP             NODE          
kube-system   coredns-9cc65fd7b-2qcvk   1/1     Running     0             12h     10.244.1.50    worker-apps-01
kube-system   coredns-9cc65fd7b-8zkdz   0/1     Completed   0             15h     <none>         worker-data-01
kube-system   coredns-9cc65fd7b-hj9kk   1/1     Running     1 (12h ago)   15h     10.244.3.177   worker-ops-02 
kube-system   coredns-9cc65fd7b-mk976   1/1     Running     0             12h     10.244.1.119   worker-apps-01

# Después de que el descheduler actuara
NAMESPACE     NAME                      READY   STATUS      RESTARTS      AGE     IP             NODE          
kube-system   coredns-9cc65fd7b-2qcvk   1/1     Running     0             12h     10.244.1.50    worker-apps-01
kube-system   coredns-9cc65fd7b-8zkdz   0/1     Completed   0             15h     <none>         worker-data-01
kube-system   coredns-9cc65fd7b-hj9kk   1/1     Running     1 (12h ago)   15h     10.244.3.177   worker-ops-02 
kube-system   coredns-9cc65fd7b-j4sbv   1/1     Running     0             7m59s   10.244.7.99    worker-data-01
```

Como se puede apreciar, se hizo un `evict` del pod `coredns-9cc65fd7b-mk976`, ya que habían 2 pods corriendo en el nodo `worker-apps-01`, de modo tal que el nuevo pod (`coredns-9cc65fd7b-j4sbv`) quedó ubicado en el nodo `worker-data-01`.

Además, también podemos apreciar que en el nodo `worker-data-01` se aprovisionó el pod `coredns-9cc65fd7b-8zkdz`, el cual quedó con `Ready=0/1` y `status=Completed`, lo cual es completamente normal en clústeres modernos impulsados por Cilium como CNI nativo en modo estricto.

Esto se debe a una condición de carrera tras el reinicio: Cuando la Mini PC 1 (la cual contiene el nodo `worker-data-01`) se reinició y volvió a encender, ocurrió una secuencia de inicialización desincronizada a nivel de milisegundos:

1. **El Kubelet levanta antes que la Red:** El agente de Talos Linux (`kubelet`) arrancó de forma ultra-rápida y procesó de inmediato los Pods estáticos y los despliegues que estaban asignados a ese nodo antes del crash, entre ellos el Pod de CoreDNS (`...-8zkdz`).

2. **Cilium aún no estaba listo:** En ese microsegundo exacto, el agente de Cilium en ese nodo específico todavía estaba inicializando las tablas de enrutamiento eBPF de la tarjeta de red virtual. Por ende, la interfaz de red del pod (`eth0`) no tenía asignada una IP válida del clúster (por eso vemos que quedó con la IP: `<none>`).

3. **El Init-Container de red o el Loop de CoreDNS:** CoreDNS realiza un chequeo interno de sockets en su arranque. Al detectar que no hay interfaces de red activas ni resolución de bucle local (`localhost / loopback`) disponible debido al estado embrionario del CNI de Cilium, el binario de CoreDNS determinó que el entorno de red era inviable y realizó una salida limpia del proceso (Código de salida `0`).

4. **La magia del Deployment:** Como el proceso de CoreDNS terminó limpiamente (`exit 0`), Kubernetes marcó el contenedor viejo en estado `Completed`. Inmediatamente después, el controlador de despliegues (*Deployment Controller*) notó que el nodo de aplicaciones estaba libre, ignoró al Pod colapsado y levantó los nuevos Pods sanos (`-2qcvk` y `-mk976`) en `worker-apps-01`, los cuales sí obtuvieron red de inmediato.

**¿Por qué se queda ahí el Pod en `Completed` y no se borra solo?**

Kubernetes **no elimina automáticamente** los Pods con estado `Completed` o `Failed` de inmediato por una decisión deliberada de diseño llamada **Preservación de Evidencia**. El API-Server mantiene el objeto del Pod huérfano en la base de datos de `etcd` para que uno como administrador pueda ejecutar un `kubectl logs` o un `kubectl describe pod` y auditar exactamente qué código de salida arrojó el contenedor antes de morir.

Eventualmente, un componente nativo de Kubernetes llamado **PodGC (Pod Garbage Collector)** pasará a limpiar ese Pod muerto de forma automática cuando el número de Pods inactivos en el clúster supere el umbral por defecto (que suele ser de 1250 Pods).

#### Consideraciones para usar `preferredDuringSchedulingIgnoredDuringExecution` en otras aplicaciones

Si se planea replicar esta estrategia de anti-afinidad suave en aplicaciones de Java, Go o Python (u otros servicios), hay que tener en cuenta estas tres reglas de oro para evitar problemas de programación de Pods:

- **Consideración 1: Tolerancia a la co-localización temporal:** Se debe entender que durante un despliegue masivo inicial (`kubectl apply`), si un nodo (una VM de Talos) está lleno, Kubernetes ignorará la preferencia y colocará los pods juntos. El Descheduler actuará después, desahuciándolos progresivamente a medida que haya espacio. Las aplicaciones deben estar listas para soportar la co-localización temporal durante unos minutos sin saturar el host.

- **Consideración 2: El uso obligatorio de `PriorityClasses`:** Si una aplicación es menos importante que un servicio DNS o una base de datos, no se le debe asignar prioridades críticas. El Descheduler utiliza el parámetro de prioridad del pod para decidir a quién mover primero si hay escasez de recursos en un nodo.

- **Consideración 3: El balance de `weight` (Peso):** Se debe mantener el peso en `100` (el valor máximo) para las aplicaciones stateless normales. Esto le da una señal clara al algoritmo del Descheduler de que compartir el mismo `hostname` físico de una VM se considera una penalización alta y debe dársele prioridad de rebalanceo en cuanto el hardware alterno (la nueva VM) esté en estado Ready.


### Metrics Server

La función principal de Metrics Server es recopilar y exponer el uso de recursos (CPU y memoria) de los contenedores y nodos del clúster de Kubernetes. Metrics Server recopila métricas de recursos de Kubelets y las expone en el apiServer de Kubernetes a través del [Metrics API](https://github.com/kubernetes/metrics) para que sean utilizadas por los *Horizontal Pod Autoscaler* y *Vertical Pod Autoscaler*. También se puede acceder a la API de métricas mediante `kubectl top`, lo que facilita la depuración de las canalizaciones de autoescalado.

**Nota:** Como lo explica su [documentación oficial en GitHub](https://github.com/kubernetes-sigs/metrics-server), Metrics Server está diseñado exclusivamente para el escalado automático. Es decir, no se debe utilizar para reenviar métricas a soluciones de monitorización ni como fuente de métricas para dichas soluciones. En tales casos, se debería recopilar las métricas directamente desde el endpoint `/metrics/resource` de Kubelet.

**¿Para qué se utiliza exactamente entonces?**

- **Autoescalado automático:** Permite que los componentes *Horizontal Pod Autoscaler (HPA)* y *Vertical Pod Autoscaler (VPA)* ajusten la cantidad de réplicas o el tamaño de pods en tiempo real dependiendo de su consumo.
- **Comando `kubectl top`:** Habilita el uso de comandos como `kubectl top pods` y `kubectl top nodes`, los cuales son herramientas indispensables para depurar y visualizar el consumo inmediato de la infraestructura.
- **Paneles de control:** Nutre de información a plataformas como [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) (aunque ya fue marcada como obsoleto, y se recomienda usar en su lugar [Headlamp](https://headlamp.dev/)) para que puedan mostrar gráficos de rendimiento en vivo.

Para instalarlo ejecutamos lo siguiente:

```sh
# Agregamos el repositorio
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update

# Instalamos
helm upgrade --install metrics-server metrics-server/metrics-server --version 3.13.1 \
  -n kube-system \
  -f k8s/deployments/metrics-server-values.yaml
```

Para verificar que se haya creado correctamente, ejecutamos lo siguiente:

```sh
# Validamos que se crearon los pods
kubectl get -n kube-system deployment/metrics-server -o wide
# kubectl get pods -n kube-system -o wide | grep metrics-server

# Adicionalmente, podemos validar los comandos kubectl top
kubectl top nodes
kubectl top pods -A # O de un namespace en particular: kubectl top pods -n some-namespace
```

#### Discrepancias en la medición entre Proxmox y Metrics Server

Si entramos a la interfaz web de Proxmox, e inspeccinamos cada una de las VMs, es posible que veamos valores de consumo de memoria RAM como los siguientes (entre paréntesis coloco la memoria RAM asignada a cada VM):

- cp-01 (3 GiB): 85.3% (2.5 GiB)
- cp-02 (3 GiB): 79% (2.3 GiB)
- cp-03 (3 GiB): 79.4% (2.3 GiB)
- worker-apps-01 (10 GiB): 22.4% (2.2 GiB)
- worker-data-01 (10 GiB): 20.5% (2.0 GiB)
- worker-heavy-02 (12 GiB): 18.2% (2.1 GiB)
- worker-ops-02 (11 GiB): 26.7% (2.9 GiB)

Sin embargo, al ejecutar `kubectl topo nodes` podríamos ver valores como los siguientes:

```
NAME              CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
cp-01             125m         6%       1915Mi          81%
cp-02             107m         5%       1728Mi          73%
cp-03             96m          4%       1722Mi          73%
worker-apps-01    73m          1%       1422Mi          15%
worker-data-01    60m          1%       1210Mi          12%
worker-heavy-02   69m          1%       1195Mi          10%
worker-ops-02     87m          1%       2083Mi          19%
```

La diferencia se debe a que ambas herramientas miden la memoria desde dos perspectivas matemáticas y de sistema operativo radicalmente distintas:

- **La perspectiva de `metrics-server` (Dentro de Kubernetes):** `metrics-server` le pregunta al Kubelet por el indicador `WorkingSet` de la memoria (a través del cAdvisor que veremos más adelante). Esta métrica calcula **estrictamente la memoria activa que los procesos del clúster no pueden liberar bajo ninguna circunstancia** (binarios en ejecución, hilos activos del kernel, memoria anónima asignada por Cilium, etc.). Ignora por completo los cachés del sistema de archivos.
- **La perspectiva de Proxmox / QEMU (Fuera de la VM):** El hipervisor Proxmox no sabe qué es un Pod ni qué es el API-Server. Él solo ve un proceso de QEMU/KVM en Linux que representa a la VM. Para Proxmox, si una página de memoria RAM de 4KB fue tocada o asignada alguna vez por la VM, **esa página se considera "ocupada"** hasta que el sistema operativo invitado la libere explícitamente a través de un mecanismo llamado *Memory Ballooning*.

#### Consumo de RAM en nodos sin cargas de trabajo

En este momento, tenemos nodos (como por ejemplo `worker-heavy-02`) sobre los cuales no hemos especificado que se ejecute algún servicio (ya que en nuestros archivos `*-values.yaml` solo hemos especificado que se desplieguen sobre nodos con labels `apps`, `data` y `ops`). Aún así, si Talos Linux es un sistema operativo ultra ligero que consume apenas ~350 MiB en frío, ¿por qué Proxmox reporta 2.1 GiB y metrics-server reporta 1.1 GiB en un nodo "vacío"? La culpa la tienen los siguientes factores (que pueden parecer invisibles para nosotros):

**A. El Caché de Páginas de Linux (Page Cache / Buffers)**

Linux tiene la filosofía de que *"RAM no utilizada es RAM desperdiciada"*. Talos Linux corre enteramente en **RAMfs** (se monta en memoria en lugar de leer constantemente del disco virtual). Cuando un nodo arranca (una VM de Talos), descarga imágenes de contenedores del sistema (Cilium, CoreDNS, metrics-server, etc.), genera logs internos y escribe metadata en disco y, el kernel de Talos guarda todas esas lecturas/escrituras en un caché en la memoria RAM para que el nodo vuele en rendimiento.

- Para **metrics-server**, este caché es "liberable" si el nodo se queda sin memoria, por lo que no lo cuenta dentro del porcentaje del nodo.
- Para **Proxmox**, esa RAM ya fue reclamada por la VM, por lo que la cuenta como ocupada.

**B. La "Huella Base" Invisible de los Agentes del Clúster**

Aunque pensemos que el nodo está "vacío", no está 100% vacío. Tiene corriendo los agentes globales en modo `DaemonSet` y los componentes internos de Kubernetes:

- **El Kubelet:** El motor de contenedores base consume entre 200MB y 350MB solo por mantener los sockets y las APIs de red abiertas esperando instrucciones.
- **Cilium (CNI con eBPF):** Cilium compila programas eBPF en C directamente dentro del kernel de Talos Linux y genera mapas de memoria compartida (eBPF Maps) en la RAM para trackear cada paquete de red. Esto tiene un costo base de entre 300MB y 500MB de RAM por nodo desde el segundo uno.

Si sumamos los ~350MB de Talos, los ~300MB del Kubelet y los ~450MB de Cilium, obtenemos exactamente los ~1.1 GiB (1195Mi) reales de memoria activa que `metrics-server` nos reportaría con precisión matemática en este momento. Los 1.0 GiB adicionales que ve Proxmox son puro caché de disco y páginas retenidas por la virtualización de QEMU.

#### El caso crítico de los Control Planes (`cp-01`, `cp-02`, `cp-03`)

Ver a los Control Planes al 85% en Proxmox es perfectamente normal en Kubernetes. El componente **`etcd`** (la base de datos distribuida del clúster donde se guarda la configuración cero, los secrets, los certificados de cert-manager y el estado de la red) es un motor transaccional pesado.

`etcd` mapea de forma agresiva todo su árbol de llaves en la memoria RAM para responderle al API-Server en menos de 1 milisegundo. En máquinas virtuales asignadas con apenas 3GB de RAM, la base de datos de Kubernetes junto con los controladores internos (`kube-controller-manager` y `kube-scheduler`) van a consumir de forma nativa e inmediata entre 1.5GB y 1.9GB de memoria limpia (`WorkingSet`), llevando el hardware al límite saludable que estamos presenciando.

#### Conclusión para el Monitoreo de Infraestructura

- **¿A quién creerle?** Para saber si al clúster le queda espacio para meter algún servicio, debemos creerle siempre a `metrics-server` (o al servicio de observabilidad que configuremos para recolectar métricas de cAdvisor). Ellos nos dicen cuánta RAM física real le queda al sistema operativo para alojar procesos.

- **¿Para qué sirve el dato de Proxmox entonces?** Nos sirve para medir el impacto real en el hardware de una Mini PC física (`pmx-01` y `pmx-02`). Nos dice que, aunque la VM tenga RAM libre por dentro, el hipervisor ya ha bloqueado y asignado esos gigabytes en los sockets de memoria física y no se los puede prestar a otra VM de Proxmox.


### cAdvisor

**cAdvisor** (Container Advisor) es una herramienta integrada de forma nativa en Kubelet dentro de Kubernetes. Su función principal es recopilar, procesar y exportar métricas en tiempo real sobre el uso de recursos (CPU, memoria, red y disco) de todos los contenedores que corren en un nodo.

**Cómo funciona en Kubernetes**

- **Integración nativa:** Viene incrustado dentro del binario de kubelet en cada nodo del clúster.
- **Sin instalación extra:** No se requiere desplegar un agente adicional para obtener las métricas básicas de los contenedores.
- **Descubrimiento automático:** Detecta de manera automática cualquier contenedor nuevo que se cree o se destruya en el nodo.

**Métricas principales que recopila**

- **CPU:** Uso total, tiempo de uso acumulado por usuario y sistema.
- **Memoria:** Memoria trabajada, caché y límites asignados.
- **Red:** Bytes recibidos y transmitidos, además de errores de red.
- **Sistema de archivos:** Espacio usado y operaciones de E/S en disco.

**¿Por qué no hay un Dashboard nativo o comandos `kubectl` para cAdvisor?**

A pesar de que viene integrado de forma nativa dentro del binario de Kubelet en cada nodo de Kubernetes, su filosofía es la de un exportador puro de telemetría, no una interfaz de usuario. Antiguamente (hace muchos años), cAdvisor levantaba un puerto web independiente (el puerto 4194) en cada máquina donde se podían ver gráficas web básicas. Sin embargo, por razones de seguridad y rendimiento, Kubernetes eliminó por completo esa interfaz web interna.

Además, no hay comandos kubectl específicos, ya que los comandos `kubectl top` consumen los datos procesados por `metrics-server` (que extrae una versión muy resumida y digerida de cAdvisor), pero no nos permiten ver el desglose masivo de métricas de red, escrituras en disco (IOPS) o throttling de CPU por contenedor que genera cAdvisor de forma cruda.

**¿Cómo expone cAdvisor sus métricas en Kubernetes?**

cAdvisor expone un endpoint HTTP seguro en formato Prometheus directamente a través del API-Server o del Kubelet de cada nodo. Las rutas nativas en Kubernetes v1.36 son las siguientes (si se intenta acceder a estas rutas no se verá nada, ya que solo se usan para exponer las métricas hacia otros sistemas de observabilidad como por ejemplo Prometheus o Victoria Metrics):

- **Métricas completas del nodo y contenedores:** `https://<IP-DEL-NODO>:10250/metrics/cadvisor`
- **Métricas resumidas del recurso:** `https://<IP-DEL-NODO>:10250/stats/summary`

**¿Cómo se pueden ver y auditar las métricas de cAdvisor en tiempo real?**

Dado que estamos utilizando Talos Linux, el puerto del Kubelet (`10250`) está protegido por certificados TLS y requiere autenticación RBAC estricta. La forma correcta, segura y directa de inspeccionar lo que cAdvisor está transmitiendo sin instalar nada complejo es utilizando el comando `kubectl get --raw`.

Para esto podemos ejecutar el siguiente comando en la terminal para extraer el flujo de texto plano nativo de cAdvisor de cualquiera de los nodos de Kubernetes (VMs de Talos):

```sh
# Cambiamos "worker-apps-01" por el nombre exacto del nodo que queramos ver
kubectl get --raw "/api/v1/nodes/worker-apps-01/proxy/metrics/cadvisor"
```

Lo que nos aparecerá en la terminal será un volcado de miles de líneas en formato de texto plano estructurado para Prometheus. Veremos métricas ultra-detalladas como las siguientes (entre muchas otras) (en [este repositorio](https://github.com/google/cadvisor/blob/master/docs/storage/prometheus.md) podemos ver la lista completa de métricas que expone cAdvisor):

- `container_cpu_usage_seconds_total{container="coredns", pod="..."}` (Consumo de CPU acumulado por contenedor).
- `container_memory_working_set_bytes{...}` (La métrica real de memoria que usa Kubernetes para decidir los OOMKills).
- `container_fs_writes_bytes_total{...}` (Bytes escritos en el NVMe local a través de OpenEBS).
- `container_network_receive_bytes_total{...}` (El recuento acumulado de bytes recibidos a través de la red).

**¿Cómo se consumen estas métricas en entornos de producción?**

Para no tener que usar comandos de terminal y poder visualizar dashboards reales con históricos de los contenedores, se suele utilizar un Agente de Raspado (Scraper) que lee esos endpoints HTTP continuamente, guarda los datos en una base de datos de series temporales y los proyecta en Grafana.

Dependiendo de la herramienta de observabilidad que se desee implementar, la pieza encargada de automatizar esta recolección puede variar, por ejemplo, para el caso del stack de VictoriaMetrics la herramienta sería *VMAgent*, o para el caso del stack LGTMP de grafana (Loki, Grafana, Tempo, Mimir, Pyroscope) la herramienta sería *Alloy*.


### Herramientas de Administración del Clúster de Kubernetes

En esta pequeña sección, no voy a ahondar mucho en el tema, sin embargo, dejaré un breve resumen sobre algunas herramientas sobre las que he indagado.

Existen diversas herramientas de administración como por ejemplo k9s (la cual ya tenemos instalada), OpenLens y Headlamp. Aunque las tres herramientas sirven para visualizar el estado de los pods, volúmenes de OpenEBS o configuraciones del Descheduler, operan bajo arquitecturas y filosofías radicalmente opuestas:

1. **Arquitectura In-Cluster vs. Local:**
   - **OpenLens y K9s:** Corren localmente en la computadora personal y utilizan el archivo `~/.kube/config` para hacer peticiones directas al API-Server de Talos. Si la computadora está apagada o no se tiene la VPN/túnel activa, nadie puede ver el clúster, es decir, nadie podría ejecutar comandos `kubectl` sobre el clúster.
   - **Headlamp:** Se ejecuta dentro del clúster como un servicio web permanente. Esto significa que actúa como una plataforma centralizada a la que se puede acceder desde cualquier navegador web (incluso desde una tablet o teléfono móvil) si se expone de forma segura.

2. **Gobierno de Acceso y Multi-tenancy (RBAC Nativo):**
   **Headlamp** no requiere que se comparta el archivo de configuración de Kubernetes (`kubeconfig`) con nadie, ya que soporta autenticación nativa por OIDC (OpenID Connect). Se puede integrar directamente con sistemas tipo IAM como Keycloak. Así, si un desarrollador o uno mismo iniciamos sesión, Headlamp solo les mostrará los recursos del clúster que sus usuarios de Keycloak tengan permitidos por RBAC, todo gestionado desde la web. En **OpenLens**, se tendría que distribuir archivos `kubeconfig` individuales a cada máquina.

3. **Sistema de Plugins y Extensibilidad Extrema:**
   **Headlamp** fue diseñado por Kinvolk (ahora Microsoft) con una arquitectura basada en plugins de React. A diferencia de **OpenLens** (que limitó sus extensiones en versiones recientes) o **K9s** (basado en terminal), en Headlamp se pueden programar o instalar vistas personalizadas directamente en la interfaz. Por ejemplo, se puede añadir un plugin visual que muestre el estado de salud del clúster de CloudNativePG o gráficos embebidos de los componentes de almacenamiento sin salir del dashboard.

**¿En qué escenarios valdría la pena instalar Headlamp?**

Para tareas cotidianas de depuración (revisar por qué un pod quedó en `Completed`, inspeccionar logs de algún servicio, o validar que un PVC de SeaweedFS se montó), K9s siempre será infinitamente más rápido debido a sus atajos de teclado y latencia cero. Por otro lado, OpenLens, ya nos da la perspectiva gráfica de mapas de calor y consumo de hardware.

Adicionalmente, Headlamp requiere desplegar un Pod de frontend y un backend de traducción de APIs. En un entorno de homelab local donde se busca exprimir cada gigabyte de RAM para bases de datos pesadas como Apache Pulsar o ScyllaDB, añadir otra interfaz web permanente consume recursos que no aportarían nueva información técnica.

El único escenario donde si se debería considerar la instalación de Headlamp es si nuestro Homelab evoluciona hacia alguno de estos dos escenarios:

- **Acceso en Movimiento (SRE Portátil):** Si se quiere poder revisar la salud de las bases de datos desde el teléfono o fuera de la casa sin arrastrar el computador portátil con K9s (en mi caso mi Macbook), Headlamp expuesto tras `cloudflared` (Cloudflare Tunnel) con protección de Cloudflare Access nos daría una consola de administración visual completa desde cualquier navegador.
- **Compartir el Clúster:** Si en algún momento otra persona va a colaborar con uno en el desarrollo de las aplicaciones de Java o Go, o se quisiera mostrar métricas a un tercero, con Headlamp se le podría crear un acceso web en lugar de comprometer la seguridad del clúster dándole un token de administración para su K9s local.





# Pruebas de Componentes y Configuraciones

## Prueba de Tráfico hacia nuestro Clúster

Hasta el momento hemos hecho lo siguiente para configurar la red de nuestro clúster y para permitir tráfico seguro tanto interno como externo, ya sea proveniente de un entorno local o de internet:

1. Instalamos los CRDs de Gateway API.
2. Instalamos el Aprobador automático de certificados.
3. Instalamos Cilium.
4. Instalamos CoreDNS.
5. Configuramos nuestro pool de IPs locales (`CiliumLoadBalancerIPPool`) y configuramos nuestro balanceador (`CiliumL2AnnouncementPolicy`).
6. Instalamos `cert-manager` y `trust-manager`, y establecimos la confianza interna del clúster (`internal-ca-cert`, `internal-ca-issuer`, `cluster-trusted-ca`).
7. Creamos un `ClusterIssuer` para que Let's Encrypt, usando nuestro token de Cloudflare (el cual almacenamos en un secret), pueda emitir un certificado de seguridad para quienes acceden desde internet a nuestras apps mediante nuestro dominio `eljavatar.org` (en realidad creamos 2, uno apuntando al ambiente de staging (`letsencrypt-stage-issuer`) y otro al ambiente de producción (`letsencrypt-prod-issuer`) de Let's Encrypt).
8. Creamos un certificado (`cert-gateway-local`) para tráfico proveniente desde ambientes locales (`eljavatar.home`) usando el emisor local (`internal-ca-issuer`).
9. Creamos un certificado (`cert-letsencrypt-public`) para tráfico proveniente desde internet (`eljavatar.org`) usando el emisor de Let's Encrypt (`letsencrypt-stage-issuer` o `letsencrypt-prod-issuer`).
10. Levantamos nuestro Gateway (`external-gateway`) usando el controlador de cilium y especificando 3 listeners: 1 para tráfico http, uno para tráfico https proveniente desde tráfico local (el cual para su configuración de TLS usa el secreto `cert-gateway-local-secret`) y uno para tráfico https proveniente desde internet (el cual para su configuración de TLS usa el secreto `cert-letsencrypt-public-secret`).
11. Levantamos el agente de `clouflared` para permitir tráfico público desde internet hacia nuestro clúster mediante nuestro dominio `eljavatar.org` y usando un túnel de Cloudflare.
12. Instalamos varias utilidades como como por ejemplo operadores para manejar secretos de Vault, Reloader, Deschduler y Metrics Server.

En cada uno de estos pasos fuimos realizando distintas comprobaciones para verificar que cada servicio que instalamos y cada recurso que levantamos, se hubiera instalado/levantado correctamente.

Sin embargo, la mejor forma de validar que nuestro clúster está listo para recibir tráfico, y que además los Certificados generados son correctos (para evitar que por ejemplo al ingresar desde el navegador nos aparezca el mensaje de *Conexión no segura (Certificado no reconocido)*), es haciendo pruebas de tráfico hacia nuestro clúster.

Con este enfoque, a continuación veremos 3 pruebas distintas que nos ayudarán a validar que todo nos quedó buien configurado.


### 1. Validación del Certificado en Requests hacia el Clúster

A continuación usaremos `curl` y `openssl` desde nuestra máquina local para validar qué tipo de certificado está respondiendo nuestro clúster.

Además, dado que estamos usando dominios locales/públicos apuntando a una IP privada (`192.168.0.70`), usaremos los parámetros de resolución forzada de `curl` y `openssl` para simular la petición web sin necesidad de alterar el archivo `/etc/hosts` local todavía.

#### Script A: Validación con openssl (El más preciso para depurar)

Este script extrae la cadena completa de certificados directamente desde el `handshake TLS` del Envoy. Nos dirá textualmente si el certificado proviene de la CA interna, de Let's Encrypt Staging ("Fake LE") o de Let's Encrypt Producción.

```bash
# Otorgamos permisos al script
chmod +x tests/validate-tls-with-openssl.sh

# Ejecutamos el Script
./tests/validate-tls-with-openssl.sh
```

**¿Qué deberíamos ver en la salida de OpenSSL?**

- **Si estamos en Staging (`.org`):** `issuer=C=US, O=Let's Encrypt, CN=(SAGING)` junto con una advertencia de pruebas o un nombre tipo `Fake LE`, `Baloney Bulgur YE2`, `Artificial Amaranth YE1` o algo por el estilo.
- **Si estamos en Producción (`.org`):** `issuer=C=US, O=Let's Encrypt, CN=YE2` (o la variante de producción activa del año en curso).
- **Si estamos en la Red Local (`.home`):** `issuer=CN=cluster-internal-ca` (el nombre exacto de nuestro `commonName` del `Certificate` raíz (`internal-ca-cert`)).

#### Script B: Validación con curl

Este script realiza una petición HTTP/HTTPS forzando a que resuelva el dominio a la IP de Cilium y analiza el emisor (Issuer) en la salida de error.

```bash
# Otorgamos permisos al script
chmod +x tests/validate-cert-with-curl.sh

# Ejecutamos el Script
./tests/validate-cert-with-curl.sh
```

Al ejecutar este Script, es posible que obtengamos un error de `curl` que diga `SSL certificate problem: unable to get local issuer certificate`; este error no necesariamente significa que el clúster de Kubernetes o CIlium tenga un error, al contrario, confirman que la criptografía está funcionando exactamente como debe. Veamos por qué pasa este error dependiendo el caso.

##### Caso 1: El dominio local (`api.eljavatar.home`)

- **A qué se debe el error de curl:**

  `curl` es una herramienta de transferencia de datos diseñada para ser segura por defecto. Cuando intentamos conectarnos a `https://api.eljavatar.home`, Cilium le entrega a nuestra máquina local un certificado emitido por nuestra Autoridad Certificadora interna (`issuer=CN=cluster-internal-ca`).

  Inmediatamente, `curl` busca en el llavero de nuestro sistema operativo (`/etc/ssl/cert.pem` en mi caso) para ver si la entidad `cluster-internal-ca` está en la lista de autoridades en las que nuestro computador confía globalmente. Como es una CA que nosotros mismos inventamos y creamos dentro del clúster, nuestra máquina local no la conoce, desconfía de ella y aborta la conexión por seguridad.

- **Por qué `openssl` sí funciona:**

  El comando de `openssl` que utilizamos antes solo actúa como un inspector. Su único objetivo es conectarse al puerto, descargar el texto del certificado y formatearlo en la pantalla (`-noout -issuer -subject`). A `openssl` no le importa si el certificado es válido, falso o de confianza; solo muestra la información técnica cruda que el servidor le entregó.

- **¿Cómo solucionarlo?**

  Como el dominio `.home` es puramente nuestro y privado, para que `curl` confíe en él desde nuestra máquina de desarrollo lo ideal es descargar el certificado raíz de nuestra CA interna desde el clúster (el que genera nuestro `trust-manager` Bundle) y decirle a `curl` que confíe explícitamente en él usando el parámetro `--cacert`:

  ```sh
  # Descargamos la CA del clúster a un archivo local
  kubectl get configmap cluster-trusted-ca -n gateway-api-system -o jsonpath='{.data.internal-ca-bundle\.crt}' > certs/my-internal-ca.crt

  # Le pasamos la CA a curl para que confíe en ella
  curl -vI --cacert certs/my-internal-ca.crt --resolve "api.eljavatar.home:443:$IP_CILIUM_GATEWAY" "https://api.eljavatar.home"
  ```

  Al ejecutarlo con `--cacert`, `curl` verá que el certificado del Gateway fue firmado por el archivo `certs/my-internal-ca.crt` que le proporcionamos, la validación criptográfica será exitosa y completará la conexión de forma segura.

##### Caso 2: El dominio público (`api.eljavatar.org`)

Si al ejecutar el comando con el dominio `.org` obtenemos el mismo error, significa que el recurso `Certificate` público todavía está apuntando al emisor de Staging (`letsencrypt-stage-issuer`).

- **A qué se debe el error de `curl` en el `.org`:**

  Los certificados emitidos por el servidor de Staging de Let's Encrypt son firmados por una CA ficticia llamada *Fake LE Intermediate X1*. Let's Encrypt diseñó esto a propósito para que los desarrolladores puedan probar sus automatizaciones sin gastar sus cuotas reales. Dado que ningún computador del mundo confía en la entidad "Fake LE", `curl` bloquea la conexión exactamente con el mismo mensaje.

- **¿Cómo solucionarlo?**

  Debemos modificar el `archivo k8s/cert-letsencrypt-public.yaml` para que use el emisor de producción de Let's Encrypt que en nuestro caso es `letsencrypt-prod-issuer`, y volver a aplicar el manifiesto del certificado:

  ```yaml
  # En el archivo k8s/cert-letsencrypt-public.yaml
    issuerRef:
      name: letsencrypt-prod-issuer # <-- Cambiamos stage por prod
      kind: ClusterIssuer
  ```

  En cuanto ejecutemos `kubectl apply -f k8s/cert-letsencrypt-public.yaml` y `cert-manager` termine de validar el desafío con Cloudflare (entre unos 30 segundos y 2 minutos), Let's Encrypt emitirá un certificado firmado por su entidad oficial confiable (`CN=YE2` en este caso). A partir de ese milisegundo, el curl hacia `https://api.eljavatar.org` funcionará perfectamente sin errores, porque la CA de Let's Encrypt ya viene preinstalada de fábrica en nuestro sistema operativo.

  De esa forma si volvemos a lanzar el curl, debería mostrarnos información del certificado, con un mensaje `SSL certificate verify ok`:

  ```sh
  curl -vI --resolve "api.eljavatar.org:443:$IP_CILIUM_GATEWAY" "https://api.eljavatar.org"
  ```


### 2. Simulación de Fallo (Chaos Engineering) para la IP Flotante

Como lo mencionamos antes, Cilium hace que el acceso a nuestro Gateway sea altamente disponible, haciendo que su IP (`192.168.0.70`) pueda flotar entre todos los Envoys que se encuentran corriendo en cada una de las VMs Talos que componen nuestro clúster de Kubernetes.

Así que con esta prueba vamos a ejecutar un experimento para comprobar que la IP `192.168.0.70` migra correctamente de una VM a otra sin que apenas lo notemos.

#### Paso A: Establecer la Línea Base (Monitoreo en vivo)

Desde nuestra máquina local (fuera del clúster), abrimos tres terminales separadas para monitorear el comportamiento en tiempo real, y en cada una vamos a hacer lo siguiente:

##### Terminal 1 (Ver quién tiene la IP):

Ejecutamos el comando que obtiene los `Leases` de forma continua para ver qué nodo es el líder actual:

```sh
watch -n 1 "kubectl get leases -n kube-system | grep cilium-l2"
```

Debemos fijarnos en el nombre del nodo que aparece, ya que este es el que reiniciaremos después desde nuestra interfaz de Proxmox (ej. `worker-heavy-01`).

##### Terminal 2 (Ping continuo):

Lanzamos un NetCat hacia la IP del Gateway para validar que el Gateway esté saludable y hacemos un ping para validar si estamos llegando a la IP del nodo líder:

```sh
# Validamos que el Gateway está saludable
nc -zv 192.168.0.70 443

# Hacemos ping
ping 192.168.0.70
```

La IP flotante asignada al Cilium Gateway (`192.168.0.70`) no responderá a comandos ping convencionales. Cilium procesa esta IP mediante eBPF a nivel de Capa 4/7 descartando los paquetes ICMP. Por esto, al hacer ping veremos una salida como la siguiente:

```
Request timeout for icmp_seq 0
Request timeout for icmp_seq 1
Request timeout for icmp_seq 2
Request timeout for icmp_seq 3
92 bytes from 192.168.0.42: Destination Host Unreachable
Vr HL TOS  Len   ID Flg  off TTL Pro  cks      Src      Dst
 4  5  00 5400 7440   0 0000  3f  01 8522 192.168.0.176  192.168.0.70
```

**¿Por qué obtenemos Host Unreachable?**

Cuando enviamos un `ping` desde nuestra máquina local (en este caso la `.176`) hacia la IP del Gateway (`.70`), el paquete viaja por el switch físico y llega a la tarjeta de red de la VM de Talos con la IP `.42` (porque ella ganó el `Lease` ARP y es la dueña de la IP flotante).

Una vez que el paquete ICMP entra al sistema operativo Talos del nodo líder pasa lo siguiente:

1. El motor de enrutamiento interno de Talos/Cilium recibe el paquete destinado a la IP `192.168.0.70`.

2. Como explicamos antes, Cilium procesa la IP `.70` mediante eBPF a nivel de sockets TCP/UDP (Capas 4 y 7) para Envoy, pero **no crea una interfaz de red virtual en el kernel de Linux** que tenga asignada la IP `.70` para responder paquetes ICMP (Capa 3).

3. Al no encontrar una interfaz o ruta interna que reclame el paquete ICMP, el propio kernel de Linux del nodo líder (`192.168.0.42`) asume que el destino final no existe dentro de su propia configuración de red.

4. Por lo tanto, por estándar del protocolo IP, el nodo líder se ve obligado a responderle a nuestra laptop (`.176`) con un mensaje de control ICMP de tipo `Destination Host Unreachable` (Host de destino inalcanzable), firmando la respuesta con su IP física `real: 92 bytes from 192.168.0.42...`.

A pesar de este comportamiento que puede parecer erróneo, es la prueba irrefutable de 2 cosas:

- **Prueba 1:** El switch y la red física local están ruteando perfectamente: los paquetes dirigidos a la IP del Gateway `.70` están llegando físicamente a la VM líder correcta (`.42`).

- **Prueba 2:** El aislamiento de Cilium funciona. El nodo líder intercepta y descarta el tráfico no deseado (ICMP), respondiendo de manera correcta según los estándares de redes, mientras mantiene los puertos `80` y `443` abiertos y listos para despachar nuestras peticiones `curl` con éxito.

##### Terminal 3 (Peticiones HTTP continuas):

Simulamos tráfico de usuarios reales haciendo consultas infinitas al dominio local:

```sh
while true; do curl -skI --connect-timeout 1 --resolve "api.eljavatar.home:443:192.168.0.70" "https://api.eljavatar.home" | grep HTTP; sleep 0.2; done
```

#### Paso B: Provocar el Fallo (Inyección de Caos)

Tenemos dos formas de simular la caída del nodo líder que anotamos en el Paso A en la Terminal 1 (en mi caso, suelo probar usando el método duro):

**Método Suave (A nivel de Kubernetes):** Apagamos los componentes de red del nodo drenándolo:

```sh
kubectl drain <nombre-del-nodo-lider> --ignore-daemonsets --delete-emptydir-data
```

**Método Duro (A nivel físico - El más realista):** Vamos a la interfaz de Proxmox y reiniciamos abrubtamente (también la podríamos apagar) la VM de Talos que tiene el liderazgo. Las peticiones HTTP/HTTPS continuarán devolviendo el estado `HTTP/2 200` (o como en este caso no tenemos un servicio en la ruta `api.eljavatar.home`, será un `404`) de nuestras aplicaciones web o gRPC sin interrupción visible, validando que Envoy tomó el control del tráfico en el host secundario.

#### Paso C: Analizar los Resultados del Experimento

Al observar las terminales de monitoreo inmediatamente después del corte, deberíamos ver lo siguiente:

1. **En la Terminal 1**, veremos que en un intervalo menor a 1 segundo, la fila que muestra el valor de `cilium-l2announce...` cambia por cualquier otra VM de Talos (nodo de Kubernetes) que esté activa en cualquiera de las nodos de Proxmox.

2. **En la Terminal 2 (Ping)**, notaremos que la conexión puede perder como máximo 1 o 2 pings (menos de un segundo de interrupción) mientras la tabla ARP del switch de nuestra casa se actualiza con la nueva dirección MAC. Sin embargo, lo importante es verificar que el mensaje de `Destination Host Unreachable` ahora responderá desde la IP del nuevo nodo de Kubernetes que asumió el liderazgo.

3. **En la Terminal 3 (Curl)**, comprobaremos que las peticiones HTTP/HTTPS se recuperan de inmediato y siguen respondiendo `HTTP/2 200` o el código correspondiente (probablemente sea `HTTP/2 404` ya que `api.eljavatar.home` es una ruta que no está asociada a ningún servicio), demostrando que Envoy en la otra VM ya está procesando el tráfico.

#### Paso D: Ejecución mediante un Script

Con los pasos anteriores podemos evidenciar en tiempo real cómo Cilium nos garantiza la alta disponibilidad haciendo flotar la IP del Gateway entre nodos. Sin embargo, también podríamos ejecutar dicha prueba de forma similar mediante el siguiente Script:

```sh
# Otorgamos permisos al script
chmod +x tests/gateway-chaos-test.sh

# Ejecutamos el script
./tests/gateway-chaos-test.sh
```


### 3. Desplegar una App de Prueba con su Service y HTTPRoute

Talos se centra en proporcionarnos un clúster seguro predeterminado listo para usar, por lo que no podemos simplemente usar `kubectl create deployment hello-server --image=gcr.io/google-samples/hello-app:1.0`, ya que Talos requiere que configuremos el `securityContext`.

Aquí tenemos un ejemplo de implementación para nginx que se ejecuta como un usuario sin privilegios de administrador y especifica los requisitos de recursos del pod para cumplir con la configuración de Admisión de Seguridad de Pods que viene con talos (podemos encontrar más información en la [documentación de Talos](https://docs.siderolabs.com/kubernetes-guides/security/pod-security)):

```sh
# Levantamos la aplicación
kubectl apply -f tests/playground-nginx.yaml

# Hacemos un curl (Lo hacemos con el resolve para evitar añadir esta ruta a nuestro archivo /etc/hosts)
curl --insecure --resolve "api.eljavatar.home:443:$IP_CILIUM" "https://api.eljavatar.home"

curl --insecure --resolve "api.eljavatar.org:443:$IP_CILIUM" "https://api.eljavatar.org"


# Al finalizar la prueba, podríamos simplemente eliminar el namespace:
kubectl delete ns playground
```

En ambos casos, deberíamos ver en la terminal el HTML de la página de inicio de la aplicación nginx que se despliega con el manifiesto `tests/playground-nginx.yaml`, lo cual demuestra que nuestro clúster de Kubernetes, Cilium, Let's Encrypt, el Gateway y dicha aplicación de nginx junto con su HTTPRoute están configurados a la perfección. Sin embargo, si intentamos acceder desde el navegador, no nos cargaría nada ya que no hay una red física externa (un DNS) que le diga al navegador cómo resolver las URLs `api.eljavatar.home` y `api.eljavatar.org`.

**¿Por qué funciona en la terminal?**

En este caso al usar el comando `curl`, le estamos aplicando un truco técnico con el parámetro `--resolve`. Ese flag le dice a `curl`: "*Ignora el internet real, no busques en ningún servidor DNS del mundo, asume manualmente que `api.eljavatar.org` (o `api.eljavatar.home`) está en la IP privada de mi casa `192.168.0.70`*".

En cambio nuestro navegador web no tiene ese parámetro `--resolve`. Cuando escribimos `https://api.eljavatar.org` (o `https://api.eljavatar.home`) en la barra de direcciones del computador o el celular, el navegador realiza un flujo estándar de internet para resolución de DNS que actualmente está fallando en nuestra infraestructura por falta de dos configuraciones externas.

A continuación veremos qué necesitamos configurar para que funcione en el navegador según desde dónde intentemos acceder:

#### Escenario A: Acceder desde DENTRO de nuestra red mediante un DNS Local

A pesar de que estemos conectados al mismo Wi-Fi o red que nuestras mini PCs que corren los servidores de Proxmox que contienen las VMs de Talos que componen nuestro clúster de Kubernetes, nuestro navegador no sabe que `api.eljavatar.home` debe apuntar a dicho clúster. Por tanto, intentará buscar la IP en los servidores DNS públicos (como los de Google `8.8.8.8` o los de Cloudflare `1.1.1.1`) y no encontrará nada, debido a que `.home` no es un dominio de nivel superior (TLD) público y válido en el sistema de nombres de dominio de internet (la ICANN bloqueó el uso de este sufijo para registros abiertos en internet debido a posibles confusiones de seguridad).

Para solucionar esto, lo ideal sería tener un servidor DNS local (como Pi-hole, AdGuard Home, o incluso el mismo panel de administración de nuestro router) en el cual podamos crear una regla DNS.

En mi caso, no tengo un servidor DNS local, y el firmware de mi router (el Tp-link Ax55) no incluye una función de resolución DNS local (solo permite configurar servidores DNS externos globales (como los de Google o Cloudflare), pero no tiene una tabla interna editable para emparejar dominios con IPs privadas de mi red).

Por tanto, como alternativa podemos modificar el archivo `hosts`, el cual imitaría el comportamiento del comando `curl --resolve`, pero aplicado a nuestro navegador; sin embargo, hay que tener en cuenta que esto habría que hacerlo en cada computador de nuestra red local (por eso, si es posible, lo ideal sería en algún momento levantar un servicio de DNS local). Para configurar el archivo `hosts`, debemos hacer lo siguiente:

```sh
# Abrimos el archivo /etc/hosts (en Mac y Linux; en Windows, se encuentra en C:\Windows\System32\drivers\etc\hosts)
sudo nano /etc/hosts

# Añadimos esta línea al final y guardamos:
192.168.0.70  api.eljavatar.home
```

Ahora, si accedemos desde el navegador a `api.eljavatar.home`, veremos inicialmente un mensaje de Conexión no segura (esto debido a que recordemos que este dominio usa el certificado interno que no es reconocido por los navegadores); para continuar, solamente debemos hacer clic en <u>Continuar al sitio (no seguro)</u> y veremos la página de bienvenida a Nginx.

#### Escenario B: Acceder desde FUERA de nuestra red con Cloudflare Tunnel

Para acceder a un servicio/aplicación de nuestro clúster desde internet usando Cloudflare Tunnels, se requieren 3 pasos principales:

1. Crear el túnel en Cloudflare y extraer el token.
2. Levantar el agente de `cloudflared` dentro del clúster usando dicho token
3. Indicarle a Cloudflare a dónde debe enviar el tráfico que llega desde internet para ese túnel.

Los 2 primeros pasos son globales, es decir, los realizamos una sola vez. Sin embargo, aún nos falta el paso 3, configurar el enrutamiento en Cloudflare hacia el Gateway de nuestro clúster para decirle a dónde enviar el tráfico que llega desde internet para ese túnel que creamos (este tercer paso lo debemos realizar por cada ruta (subdominio) desde la cual queramos recibir tráfico de Internet hacia nuestros servicios/aplicaciones dentro del clúster).

Para esto, volvemos a la interfaz web de Cloudflare (en **Zero Trust**, y luego en **Networks** -> **Tunnels & Mesh**), y realizamos los siguientes pasos:

1. Entramos a la edición del túnel haciendo clic sobre él (o en los 3 puntos de la derecha y luego en **Configure**).
2. Vamos a la pestaña *Published application routes* (o *Public Hostname*).
3. Aquí nos aparecerá la ruta de prueba que habíamos creado cuando configuramos el túnel (`prueba.eljavatar.org`); la eliminamos ya que vamos a crear la ruta desde cero (clic en los 3 puntos de la derecha -> Delete -> Delete hostname).
4. Hacemos clic en **Add a published application route**.
6. Ingresamos los siguientes datos:
   - En la sección **Hostname**:
     - **Subdomain:** `api` (el subdominio en el que corre la aplicación)
     - **Domain:** seleccionamos nuestro dominio (`eljavatar.org`)
     - **Path**: Lo dejamos vacío
   - En la sección **Service**:
     - **Type:** `HTTPS` (Es crucial que sea HTTPS para que Cilium aplique nuestros listeners y reglas de enrutamiento)
     - **URL:** `192.168.0.70:443` (La IP fija y el puerto seguro de nuestro Cilium Gateway)
   - Desplegamos la sección **Origin request and connection settings**
   - Desplegamos la sección **TLS** y configuramos lo siguiente:
     - **TLS Verify:** Lo activamos para que quede en `On` (Esto es estrictamente obligatorio porque Cloudflare se conectará a nuestro clúster usando el dominio del túnel, e internamente nuestro Cilium Gateway le responderá con el certificado Wildcard. Activar esta opción le indica a Cloudflare que confíe en el handshake TLS interno del Gateway sin validar la cadena pública de la IP privada)
     - **Match SNI to Host:** Lo activamos para que quede en `On` (una alternativa a esta config es escribir en el campo *Origin Server Name* la ruta completa de la aplicación, es decir, `api.eljavatar.org`)
   - Desplegamos la sección **HTTP Settings** y configuramos lo siguiente:
     - **HTTP Host Header:** `api.eljavatar.org`
7. Finalmente damos clic en **Save**.

Ahora, si accedemos desde el navegador a `api.eljavatar.org`, veremos la página de bienvenida a Nginx con un candado verde 100% confiable emitido por Cloudflare de cara al público.

En caso de que al acceder veamos una página de error *Bad Gateway (código 502)* (la cual es una respuesta oficial generada por los servidores perimetrales de Cloudflare), significa que el túnel está perfectamente abierto y saludable desde nuestro clúster hacia internet, pero cuando Cloudflare intenta enviar el tráfico dentro del clúster hacia la IP de nuestro Gateway (`192.168.0.70:443`), la conexión es rechazada.

Las razones principales de este tipo de error podrían ser las siguientes (las cuales ya abordamos al momento de crear la ruta en el túnel de Cloudflare):

- **La directiva "No TLS Verify" en Cloudflare:** La causa más probable, por ende, **TLS Verify** debe estar en `On`.

- **El dominio no coincide con el Certificado del Gateway:** Revisar el manifiesto del Gateway para validar que el listener `https-publico` tiene configurado el hostname en formato comodín: `hostname: "*.eljavatar.org"`.

- **Restricción de red local en los Pods de Cloudflared (Cilium Network Policies):** Validar que no se haya implementado alguna política de red restrictiva (`CiliumNetworkPolicy`) o si el tráfico desde un namespace a otro está bloqueado por defecto (ya que `clouflared` corre en el namespace `cloudflare-tunnel-system` y la aplicación nginx de prueba que levantamos corre en el namespace `playground`), ya que si esto sucede, los Pods del túnel no podrán hablar con la IP del Gateway.
  Para comprobar si es por un bloqueo interno, entramos a los logs y buscamos si hay un error que diga textualmente `Dial to 192.168.0.70:443 failed: connect: connection refused` o `i/o timeout`, ya que esto confirmaría que hay un bloqueo de red interno o que el proxy de Cilium no está escuchando de forma homogénea en ese nodo:
  ```sh
  kubectl logs -l app=cloudflared -n cloudflare-tunnel-system --tail=20
  ```

- **El choque de SNI en el proxy Envoy:** Si en los logs vemos algo como `connection reset by peer` enviado por la IP `192.168.0.70:443`, significa que el pod de `cloudflared` sí logra comunicarse físicamente con el balanceador L2 del clúster y el puerto 443 responde. Sin embargo, en el instante preciso en que se inicia el saludo de seguridad (TLS Handshake), el proxy Envoy de Cilium decide romper la conexión de forma abrupta enviando un paquete TCP RST (Reset). En la arquitectura de Cilium v1.18.0 con el Gateway API, este comportamiento de rechazo inmediato tiene un origen muy específico ligado a los mecanismos de inspección **SNI (Server Name Indication)** de Envoy.
  
  El problema radica en que, por defecto, el cliente TLS interno de `cloudflared` utiliza la dirección IP destino (`192.168.0.70`) como el parámetro de control SNI en el saludo TLS, en lugar del nombre del dominio. Cuando el paquete llega a Envoy:

  - Envoy ve que el cliente intenta negociar un apretón de manos TLS solicitando el host `"192.168.0.70"`.
  - Envoy revisa las reglas del listener `https-publico` del Gateway y encuentra la restricción estricta: `hostname: "*.eljavatar.org"`.
  - Al comparar `"192.168.0.70"` contra `"*.eljavatar.org"`, la coincidencia falla por completo. Como Envoy tiene prohibido servir certificados a hostnames no autorizados en ese listener, aplica la política de seguridad por defecto: corta la conexión de inmediato enviando un Connection Reset.

  La solución es inyectar el parámetro **SNI** durante el saludo criptográfico de la conexión de `cloudflared` hacia nuestro clúster de Kubernetes, lo cual se puede lograr de 2 formas distinta: activando **Match SNI to Host** para que quede en `On` o escribiendo textualmente `api.eljavatar.org` en el campo `Origin Server Name`.

  Al aplicar cualquiera de estas dos opciones, cuando el pod de `cloudflared` intente abrir el socket seguro hacia la IP `192.168.0.70:443`, el saludo TLS incluirá la extensión SNI con el valor `api.eljavatar.org`.

  El proxy Envoy de Cilium validará que este host encaja perfectamente dentro de la regla comodín `*.eljavatar.org` de nuestro listener `https-publico`, completará exitosamente el handshake TLS utilizando el Secret de Let's Encrypt y redirigirá el tráfico sin contratiempos hacia el `HTTPRoute` de la aplicación Nginx de prueba, devolviendo un código HTTP/2 200 en el navegador, y por ende, la respectiva página de bienvenida a Nginx.



## Prueba de Descarga de Secretos Externos

### Crear Secretos y Roles en Vault

Primero, vamos a crear en Vault los secretos que vamos a usar para esta prueba (debemos haber habilitado previamente el [Secret engine de KV-v2](VAULT_README.md#crear-un-secret-de-tipo-key-value-kv-v2)):

```sh
vault kv put secret/eljavatar_k8s/kv-v2/playground/nginx-app NGINX_USERNAME=nginx_user NGINX_PASSWORD=nginx123

vault kv put secret/eljavatar_k8s/kv-v2/demo TEST_USERNAME=test TEST_PASSWORD=test123
```

El rol genérico `global-dynamic-reading-role` que creamos cuando [configuramos los roles en Vault](VAULT_README.md#crear-roles-para-dar-acceso-a-los-secretos-de-vault) nos permitirá acceder al secreto `/playground/nginx-app` que acabamnos de crear debido a la Templated policy `eljavatar_k8s-read-kv_v2_data_by_ns_tmpl` que definimos, pero para el caso del secreto `/demo`, debemos habilitar un rol custom:

```sh
vault write auth/eljavatar_k8s/kubernetes/role/playground-test-role \
    bound_service_account_names="playground-sa" \
    bound_service_account_namespaces="playground" \
    token_policies=eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl \
    audience=vault \
    ttl=1h
```


### Desplegar una App de Prueba con Secretos extraídos con ESO

Para esta prueba, debemos asegurarnos que no exista el namespace `playground`, para lo cual ejecutamos primero `kubectl delete ns plaground`.

Para levantar la aplicación, ejecutamos lo siguiente, lo cual además de levantar el pod, creará los recursos `ServiceAccount`, `SecretStorage` y `ExternalSecrets` requeridos para que ESO pueda descargar los secretos de Vault y genere un `Secret` de Kubernetes:

```sh
# Levantamos la aplicación. Para esto, tenemos 2 opciones:
# A) Montando los secretos en el deployment como Variables de entorno
kubectl apply -f tests/playground-nginx-with-secrets-inside-envs.yaml
# B) Montando los secretos en el deployment como Volumenes
kubectl apply -f tests/playground-nginx-with-secrets-inside-volumes.yaml


# Validamos que se creó el pod
kubectl get pods -n playground -o wide

# Verificamos que se crearon los secrets
kubectl get secrets -n playground -o wide

# Validamos en los logs del pod que se obtuvieron los datos correctos:
kubectl logs -n playground deployment.apps/playground-nginx-app --tail=50

# Al finalizar la prueba, podríamos simplemente eliminar el namespace:
kubectl delete ns playground
```

Al ejecutar la línea que muestra los logs, deberíamos ver un resultado como el siguiente:

```text
=== VERIFICANDO SECRETOS DESDE EL POD ===
Usuario recuperado del secret playground/nginx-app:  nginx_user
Password recuperado del secret playground/nginx-app: nginx123
Usuario recuperado del secret demo:  test
Password recuperado del secret demo: test927
=========================================
```

Las dos opciones de despliegue soportan que el Pod pueda ver cambios en los secretos si un secreto se actualiza en Vault (por ejemplo, si ejecutamos ahora `vault kv put secret/eljavatar_k8s/kv-v2/playground/nginx-app NGINX_USERNAME=nginx_user NGINX_PASSWORD=nginx456`). La diferencia es que la opción A usa Reloader para hacer un reinicio del Pod (lo que crearía un nuevo Pod), mientras que la opción B, al usar volumenes no requiere usar reloader ni hacer reinicios manuales, pero requiere que las aplicaciones soporten *File Watching* (monitoreo de archivos), es decir, deben tener un mecanismo de *hot-reload* (un hilo de ejecución o un cron interno que re-lee el archivo del disco, que en este ejemplo simulamos mediante un ciclo `while` infinito).

En caso de que no se creen los secretos de kubernetes y que el pod no se despliegue correctamente, podemos hacer trobleshooting usando los siguientes comandos:

```sh
# Validamos si se pudieron crear los SecretStores que realizan la autenticación
kubectl get secretstores -n playground -o wide
# Debe quedar en estado Valid con capabilities ReadWrite y Ready=True

# En caso de que el anterior comando nos muestre por ejemplo un status InvalidProviderConfig, podemos
# diagnosticar problemas al momento de crear el SecretStore (mirar los eventos al final del describe):
kubectl describe secretstore vault-auth-eljavatar-k8s-kv-v2-demo -n playground
kubectl describe secretstore vault-auth-eljavatar-k8s-kv-v2-playground -n playground

# Validamos si se pudieron crear los ExternalSecrets que obtienen los secretos
kubectl get externalsecrets -n playground -o wide
# Debe quedar en Status SecretSynced y Ready=True

# También podemos mirar los logs del operador de ESO para encontrar la causa del error:
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets
```


### Obtener Secretos con VSO

Para esta prueba, nos aseguramos que no exista el namespace `playground`, para lo cual ejecutamos primero `kubectl delete ns plaground`.

No es necesario tener que levantar una aplicación para probar que los operadores (tanto ESO como VSO) pueden descargar secretos. En este caso vamos a realizar una prueba aplicando manifiestos que solamente crean los recursos de VSO necesarios para generar un Secret de Kubernetes. Para esto, ejecutamos los siguientes comandos:


```sh
# Creamos el namespace
kubectl create ns playground

# Creamos los recursos VaultAuth que se encargan de la autenticación:
kubectl apply -f tests/vso-auth.yaml
# Validamos que se creen correctamente:
kubectl get vaultauths -n playground -o wide # Debe quedar en HEALTHY=True y READY=True
# Si hay algún error, puede que se demore un poco en actualizar el estado

# Creamos los recursos VaultStaticSecret que se encargan de obtener los secretos:
kubectl apply -f tests/vso-secret.yaml
# Validamos que se creen correctamente:
kubectl get vaultstaticsecrets -n playground -o wide # Debe quedar en HEALTHY=True y READY=True

# Validamos que los Secret de kubernetes se crean correctamente:
kubectl get secrets -n playground -o wide

# Podemos validar los datos con los que se crearon estos secretos:
kubectl get secret -n playground playground-nginx-secret -o jsonpath='{.data.NGINX_USERNAME}' | base64 --decode; echo
kubectl get secret -n playground playground-nginx-secret -o jsonpath='{.data.NGINX_PASSWORD}' | base64 --decode; echo
kubectl get secret -n playground playground-nginx-secret -o jsonpath='{.data._raw}' | base64 --decode; echo

kubectl get secret -n playground demo-secret -o jsonpath='{.data.TEST_USERNAME}' | base64 --decode; echo
kubectl get secret -n playground demo-secret -o jsonpath='{.data.TEST_PASSWORD}' | base64 --decode; echo
kubectl get secret -n playground demo-secret -o jsonpath='{.data._raw}' | base64 --decode; echo

# Al finalizar la prueba, podríamos simplemente eliminar el namespace:
kubectl delete ns playground
```

El `VaultSecertStatic` que obtiene el secreto de `/playground/nginx-app` lo configuramos para que valide secretos cada 2 minutos, por tanto, si por ejemplo ejecutamos ahora `vault kv put secret/eljavatar_k8s/kv-v2/playground/nginx-app NGINX_USERNAME=nginx_user NGINX_PASSWORD=nginx789`, al validar después de un par de minutos el valor de `NGINX_PASSWORD` en el Secret `playground-nginx-secret` veremos que su valor ha cambiado.

En caso de que obtengamos errores al ejecutar los pasos anteriores que no permitan la creación de los secretos de Kubernetes, podemos hacer trobleshooting usando los siguientes comandos:

```sh

# Vemos los eventos asociados a los VaultAuth
kubectl events --types=Warning -n playground --for vaultauths.secrets.hashicorp.com/vault-auth-playground -o json
kubectl events --types=Warning -n playground --for vaultauths.secrets.hashicorp.com/vault-auth-demo -o json

# También podemos mirar los logs del operador de VSO para encontrar la causa del error:
kubectl logs -n vault-secrets-operator deployments/vault-secrets-operator-controller-manager -f --tail=100
```


