# HashiCorp Vault

Para inyectar dentro de un servicio o aplicación variables que contienen datos sensibles como por ejemplo tokens o contraseñas, solemos hacerlo a través de secretos. El problema de los secretos nativos de Kubernetes es que se guardan en texto plano codificado en Base64 y por lo tanto debemos procurar evitar subir estos archivos `.yaml` de secretos a nuestro repositorio, ya que cualquiera podría decodificarlos y robar nuestros datos sensibles.

No entraré mucho en detalle ahora (ya que lo veremos más adelante), pero una de las formas que tenemos para evitar subir archivos de secretos nativos con datos sensibles expuestos a nuestro repositorio de Git es a través de operadores externos como *External Secrets Operator (ESO)* o *Vault Secrets Operator (VSO)* combinado con una bóveda como puede ser HashiCorp Vault (ó soluciones en la nube como por ejemplo Doppler (el cual tiene una capa gratuita), 1Password Connect, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, etc.).

En este caso, optaré por usar HashiCorp Vault, ya que cuenta con una opción Community Edition de código abierto que podemos desplegar localmente.

HashiCorp Vault es una herramienta centralizada de gestión diseñada para almacenar, acceder y proteger de forma segura datos confidenciales como contraseñas, tokens, claves API y certificados, controlando estrictamente el acceso mediante una API robusta y políticas de autorización. Entre sus principales características encontramos las siguientes:

- **Secretos Dinámicos:** Genera credenciales bajo demanda (para bases de datos o nubes) que caducan y se revocan de manera automática.
- **Cifrado como Servicio (Encryption as a Service):** Cifra y descifra datos para las aplicaciones sin necesidad de almacenar la información en crudo.
- **Gestión de Revocación y Rotación:** Permite revocar accesos de forma masiva o individual y rotar claves periódicamente.
- **Auditoría Detallada:** Registra cada interacción, acceso o intento fallido en bitácoras de auditoría centralizadas.
- **Múltiples Métodos de Autenticación:** Se conecta con identidades nativas de Kubernetes, JWT, LDAP, AppRole y proveedores de nube.

Entre las ventajas que nos ofrece para usarlo como bóveda de nuestros secretos a los que accederemos desde nuestro clúster de Kubernetes tenemos las siguientes:

- **Protección del almacenamiento `etcd`:** Los secretos nativos de Kubernetes se guardan en texto plano codificado en Base64 dentro de `etcd`. Con Vault, los datos confidenciales no residen de forma estática en el clúster.
- **Autenticación Nativa (Kubernetes Auth Method):** Los Pods pueden autenticarse ante Vault utilizando sus propias cuentas de servicio (*Service Accounts*) sin incrustar credenciales estáticas.
- **Inyección en Tiempo de Ejecución:** Permite que los contenedores obtengan los secretos únicamente cuando arrancan, minimizando el tiempo de exposición.
- **Integración con Gestores Externos:** Gracias a herramientas como el *Secrets Store CSI Driver* o *External Secrets Operator*, los secretos de Vault se pueden sincronizar o montar de forma transparente como volúmenes efímeros en los pods.
- **Gobierno Centralizado Multi-clúster:** Funciona como una fuente única de verdad para múltiples entornos o clústeres geográficamente distribuidos.

**NOTA:** Hay que tener en cuenta que HashiCorp (propiedad de IBM) ofrece HashiCorp Vault bajo una licencia **Business Source Licence (BSL)**, por tanto, a pesar de que ofrece una versión comunitaria que puede ser útil para la mayoría de casos de HomeLab, pero si se requiere usar las funciones empresariales, se debe obtener una licencia de pago. En todo caso, existe una alternativa Open Source llamada [OpenBao](https://openbao.org/docs/what-is-openbao/), creado como un fork en 2023 a partir de la versión 1.14 de Vault, por lo cual mantiene una compatibilidad directa con las API de Vault, y el uso a través de la línea de comandos (CLI) y la interfaz de usuario web es prácticamente idéntico en sus funciones base. Además, utiliza el mismo diseño de almacenamiento seguro, mecanismos de sealing/unsealing y motores de secretos que Vault, y también ofrece cifrado en tránsito y en reposo, control de acceso basado en roles (RBAC), auditoría detallada y gestión de identidades. Sin embargo debido a que es un proyecto jóven, tiene menor historial en entornos productivos y, el ecosistema y soporte comercial aún está en desarrollo.




## Formas de usar o desplegar HashiCorp Vault

A continuación revisaremos 3 opciones que tenemos para usar HashiCorp Vault, indicando también cuál sería la opción recomendada en nuestro caso:

- **Opción A (Online / Nube):** Esta opción la descartamos de plano para un escenario de homelab como el nuestro. HashiCorp retiró del mercado su producto SaaS simplificado (*HCP Vault Secrets*). Su oferta en la nube actual (*HCP Vault Dedicated*) no posee una capa gratuita permanente para producción y sus costos mínimos son prohibitivos para un entorno personal (cientos de dólares al mes).

- **Opción B (Dentro del Clúster Kubernetes):** No recomendada para producción real. Si corremos Vault dentro del mismo clúster que consume los secretos, generaríamos una dependencia circular peligrosa (el "problema del huevo y la gallina"). Si el almacenamiento persistente del clúster (que en nuestro caso será OpenEBS) falla o el clúster se corrompe, Vault caerá con él. No podremos recuperar las credenciales ni los tokens necesarios para levantar el clúster desde cero mediante GitOps, rompiendo el principio de independencia.

- **Opción C (LXC (Linux Container) en Proxmox):** Esta es nuestra opción ideal. Desplegar HashiCorp Vault (Community Edition, que es 100% gratuita) en un contenedor LXC independiente en Proxmox es la mejor práctica por las siguientes razones:
  - *Uso de recursos:* Un contenedor LXC corriendo Vault de manera nativa (sin la capa de sobrecarga de Kubernetes) es extremadamente ligero; consume menos de 512 MB de RAM y 1 vCPU en reposo absoluta.
  - *Ventaja de producción:* Al estar fuera del clúster de Kubernetes, actúa como un verdadero proveedor externo de identidad y secretos, tal como lo haría AWS Secrets Manager o un Vault corporativo en una red aislada. Si el clúster de Kubernetes explota por completo, los secretos siguen intactos y seguros en Proxmox, listos para alimentar a un nuevo clúster a través de operadores externos como *External Secrets Operator* (ESO) y *Vault Secrets Operator* (VSO). Además, la migración o el respaldo se reducen a hacer un snapshot estándar de Proxmox.


### ¿En cuál Nodo de Proxmox debemos levantar HashiCorp Vault?

Eventualmente en algún momento tengo pensado agregar una tercera Mini PC a mi homelab; sin embargo, por el momento debo decidir en cuál de mis Mini PCs actuales me conviene desplegar el LXC de HashiCorp Vault, teniendo en cuenta que tenemos una [distribución de VMs](README.md#distribución-de-vms) en cada uno de los nodos de Proxmox con una asignación de recursos prácticamente al límite de capacidad de cada Mini PC.

Así pues, este LXC lo levantaremos sobre `pmx-02` y la razón técnica se basa en que el almacenamiento es nuestro factor crítico. La Mini PC 1 (`pmx-01`) hospedará la VM `worker-data-01` donde correrán las bases de datos transaccionales (Postgres y MongoDB) junto con el volumen maestro de SeaweedFS. Esas aplicaciones generarán ráfagas de escritura constantes (IOPS masivos) sobre el único disco NVMe físico de esa máquina.

Raft (que es el motor de almacenamiento que elegiremos para Vault) es muy sensible a la latencia del disco, por tanto, al levantar Vault en `pmx-02` lo aislamos del "vecino ruidoso" del almacenamiento de datos. Aunque `pmx-02` tendrá cargas pesadas en CPU (Pulsar y ScyllaDB), un contenedor LXC nativo de Vault en reposo consume apenas el 0.5% de CPU y menos de 250 MB de RAM, por lo que encajará perfectamente en el margen libre del hardware sin degradar las bases de datos.


### ¿Qué motor de almacenamiento elegir para Vault?

La mejor opción para nuestro caso es **[Integrated Storage (Raft)](https://developer.hashicorp.com/vault/docs/internals/integrated-storage)**. Antiguamente se usaba el sistema de archivos plano (`file backend`), pero este carece de capacidades de consistencia empresarial si quisiéramos expandirnos. El motor **Raft** es el estándar oficial de producción de HashiCorp. Nos permite guardar los secretos de forma encriptada directamente dentro del disco del LXC, ofrece un rendimiento de lectura/escritura en memoria ultrarrápido y cuenta con la ventaja de que, si en el futuro agregamos una tercera Mini PC (`pmx-03`), podremos crear un clúster de Vault de Alta Disponibilidad simplemente levantando otro LXC y uniendo los nodos mediante Raft, sin depender de bases de datos externas como Consul.


### Consideraciones al usar Raft

HashiCorp Vault utiliza **BoltDB** internamente para manejar el estado del almacenamiento Raft. BoltDB funciona mapeando archivos directamente en la memoria del sistema (Memory-Mapped Files o `mmap`).

Si dejamos `mlock` activado en la configuración (`disable_mlock = false`), el sistema operativo intentará bloquear forzosamente en la memoria RAM física todo el archivo de base de datos mapeado. Esto genera un conflicto severo en el Kernel que degrada drásticamente el rendimiento de BoltDB, corrompe datos o causa bloqueos (`panic`) en Vault.

Por esta razón, la [documentación oficial de HashiCorp](https://developer.hashicorp.com/vault/docs/configuration#disable_mlock) indica lo siguiente:

> "Se recomienda encarecidamente deshabilitar `mlock` (`disable_mlock = true`) si se utiliza almacenamiento integrado, debido a que `mlock` no interactúa bien con archivos mapeados en memoria, como los creados por BoltDB, que Raft utiliza para realizar un seguimiento del estado".

Recapitulando, `mlock` evita el intercambio de datos sensibles (como por ejemplo secretos o llaves criptográficas) entre la memoria y el disco (`swap`). Por tanto, al levantar el LXC sobre el cual se ejecutará Hahsicorp Vault tendríamos las siguientes opciones de configuración:

1. **Permitir el intercambio de datos sensibles entre la memoria y el disco (`swap > 0`):** Para esto, al configurar el LXC debemos asignar algo de capacidad para la memoria `swap`, lo que causaría que en caso que la memoria RAM del contenedor se llene, los datos de Vault se escribirían en el espacio de intercambio (`swap`) del disco virtual del contenedor; Sin embargo, aunque los datos dentro de BoltDB permanecen cifrados en reposo, para evitar que otros datos confidenciales de Vault que se encuentran en memoria se guarden en el disco, además de habilitar `mlock` (`disable_mlock = false`) se deberían configurar capacidades del Kernel como por ejemplo `IPC_LOCK` (`echo "lxc.cap.keep: ipc_lock" >> /etc/pve/lxc/{lxc_id}.conf`), lo cual obligaría a que se tenga que crear el LXC con privilegios (desmarcando la casilla *Unpriviligied*).

2. **Restringir el intercambio de datos sensibles entre la memoria y el disco (`swap = 0`):** Para esto, al configurar el LXC debemos asignar `0` de capacidad para la memoria `swap`, y adicionalmente endurecer el host de Proxmox (el nodo de Proxmox sobre el cual corre el LXC (`pmx-02`)) para que en caso que se llegue a quedar sin memoria RAM, se evite intentar enviar páginas del LXC al Swap del propio host (`echo "lxc.cgroup2.memory.swap.max: 0" >> /etc/pve/lxc/{lxc_id}.conf`); de este modo, podemos deshabilitar `mlock` (`disable_mlock = true`) con tranquilidad, ya que como hemos deshabilitado el `swap`, ningún dato (ya sea confidencial o no confidencial) se escribirá en el espacio de intercambio del disco virtual del contenedor; así pues, podríamos crear nuestro LXC sin privilegios (marcando la casilla *Unpriviligied*) debido a que el contenedor no requiere la capacidad especial `ipc_lock`, ya que Valult ya no le pedirá al Kernel que bloquee la RAM física.

**¿Cuál opción elegir?**

En términos generales deberíamos optar por la segunda opción, no solo porque la documentación nos lo recomiende al querer usar Raft, sino por el hecho de que a menos que sea estrictamente necesario, deberíamos evitar tener un LXC con privilegios, ya que en caso de que la seguridad de dicho LXC sea vulnerada, el atacante podría acceder también a nuestro host principal y afectar otros LXCs u otras VMs.

En ese orden de ideas, algo importante a tener en cuenta es asignar la cantidad de recursos suficientes que necesitará nuestro LXC de Hashicorp Vault, los cuáles serán los siguientes (teniendo en cuenta que correrá sobre Debian 12):

- **RAM:** `1 GB`. El consumo en reposo de Debian 12 + Vault es de entre ~150 MB y 300 MB. Esto es suficiente en nuestro caso ya que Vault es muy ligero en memoria si se manejan pocos secretos (entre 50.000 y 100.000).
- **vCPU:** `1 vCPU`. El consumo promedio ronda entre el ~0% al 5%, teniendo unos picos mínimos al cifrar. Esto es suficiente en nuestro caso ya que el procesador solo trabajará cuando hagamos peticiones a la API o al momento de leer/escribir secretos.
- **Disco:** `15 GB`. El consumo estimado son de ~2 GB (SO) + ~1 GB (datos de Raft y archivos de la aplicación de Vault). Esto nos deja uns 12 GB libres, lo cual alcanza para miles de secretos en texto plano.

**Nota:** En un entorno de producción exigente, esta configuración podría quedarse corta, incluso, HashiCorp recomienda un mínimo de 2 vCPUs y 4 GB de RAM para entornos corporativos debido a:

- **Cifrado en tránsito constante:** Si cientos de microservicios consultan credenciales dinámicas por segundo.
- **Motores de secretos pesados:** El uso del motor *Transit* (cifrado como servicio) consume mucha CPU.
- **Logs de auditoría:** Si se activa el guardado de logs en archivos dentro del mismo disco, los 15 GB se llenarán rápidamente si hay mucho tráfico.




## Instalar HashiCorp Vault sobre un LXC en Proxmox


### Paso 1: Descargar la plantilla (Template) de Debian 12 en Proxmox

1. Ingresar a la interfaz web de Proxmox de `pmx-02` (`https://192.168.0.11:8006`).
2. En el árbol de la izquierda, hacer clic en el almacenamiento **local (pmx-02)**.
3. Ir a la sección **CT Templates** y hacer clic en el botón **Templates**.
4. Buscar **debian-12-standard (Bookworm)** en la lista, seleccionarlo y hacer clic en **Download** (si bien a la fecha ya existe Debian 13 (que fue lanzado en 2025), para minimizar riesgos de indisponibilidad de Vault, es mejor usar una versión que tenga más tiempo en el mercado como lo es el caso de Debian 12 (que fue lanzado en 2023 y este tutorial lo estoy escribiendo en 2026) ya que sus paquetes y librerías están completamente depurados).
5. Esperar a que finalice con un `TASK OK`.


### Paso 2: Crear el Contenedor LXC

Hacemos clic en el botón **Create CT** (esquina superior derecha de Proxmox) y completamos las pestañas del asistente técnico con los siguientes valores:

- **General:**
  - **Node:** pmx-02
  - **CT ID:** 1001 (o el que tengamos libre).
  - **Hostname:** hashicorp-vault (vault-homelab.eljavatar.local)
  - **Password:** Definir una contraseña segura para el usuario root del contenedor.
  - *Asegurar* que la opción **Unprivileged container** esté marcada.
- **Template:** Seleccionar el almacenamiento `local` y la plantilla de debian-12 descargada.
- **Disks:** Seleccionar el almacenamiento `local-lvm` y Asignarle 15 GiB (los secretos en texto plano ocupan muy pocos kilobytes).
- **CPU:** Asignar 1 Core (más que suficiente para nuestro homelab).
- **Memory:** Asignar 1024 MiB de RAM y 0 MiB de Swap.
- **Network:**
  - **Name:** eth0
  - **Bridge:** vmbr0
  - **IPv4:** Seleccionar **Static**. Siguiendo nuestra matriz de infraestructura, le asignamos la IP: `192.168.0.20/24`.
  - **Gateway:** `192.168.0.1`
- **DNS:** Dejarlo por defecto (heredará los DNS `1.1.1.1` / `8.8.8.8` que configuramos en el host de Proxmox).
- *Desmarcar* la casilla **Start after created**, ya que debemos configurar algunos privilegios antes de encender el LXC.
- Hacer clic en **Finish** para crear el contenedor y esperar a que finalice con un `TASK OK`.

Hay que tener en cuenta que con esta configuración, nuestro LXC no va a arrancar automáticamente después de un reinicio de la máquina física (por ejemplo, después de un corte de energía). Por tanto, para habilitar el Auto-boot de nuestro LXC, desde la interfaz web de Proxmox, vamos a la **Shell** de nuestro nodo `pmx-02` y ejecutamos lo siguiente:

```sh
pct set 1001 -onboot 1
```


### Paso 3: Configuración para No enviar páginas del LXC al Swap del host de Proxmox

Antes de encender el LXC por primera vez, debemos agregar una configuración en el host de Proxmox (el nodo de Proxmox sobre el que corre el LXC) para que en caso de que el host se llegue a quedar sin memoria RAM, se evite intentar enviar páginas del LXC al Swap del propio host:

1. En la interfaz de Proxmox, hacer clic en el nodo `pmx-02`, entrar a la **Shell**, y ejecutar lo siguiente para restringir los límites de memoria del kernel y asegurar que el aislamiento de memoria sea estricto (`1001` es el CT ID que asignamos a nuestro LXC en el paso 2):
   ```sh
   echo "lxc.cgroup2.memory.swap.max: 0" >> /etc/pve/lxc/1001.conf
   ```
2. (*Opcional*) En caso que nuestro nodo Proxmox requiera Swap por arquitectura, debemos asegurarnos de que esa partición de Swap esté cifrada (por ejemplo, usando `dm-crypt`). De esta forma, si el host vuelca memoria de Vault al disco, los datos seguirán siendo ilegibles; en nuestro caso no requerimos hacer esta configuración.
3. Ahora sí, iniciar el contenedor desde la interfaz web o ejecutando en la Shell `pct start 1001`.


### Paso 4: Instalar el binario oficial de HashiCorp Vault

Entramos a la **Console** del contenedor LXC recién encendido, iniciamos sesión como `root` (usando la contraseña que especificamos en el paso 2) y ejecutamos los siguientes comandos para agregar los repositorios oficiales y realizamos la instalación de Vault:

```sh
# Actualizar el sistema e instalar dependencias base
apt update && apt upgrade -y
apt install wget gpg coreutils curl lsb-release -y

# Descargar la llave GPG oficial de HashiCorp y agregarla al sistema:
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Agregar el repositorio de producción de HashiCorp correspondiente a nuestra versión de Debian
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list

# Instalar HashiCorp Vault (Community Edition)
apt update && apt install -y vault

# Verificar la instalación
vault -v
# Vault v2.0.4
```


### Paso 5. Habilitar el Acceso SSH

Por defecto, Debian 12 bloquea el acceso SSH al usuario `root` mediante contraseña por razones de seguridad. Si intentamos conectarnos, el servidor SSH rechazará la contraseña directamente, lo que generaría un error `Permission denied (publickey,password)`. Lo mismo pasaría si intentamos ejecutar `scp` por ejemplo para copiar algún archivo del LXC, ya que este utiliza el protocolo SSH por debajo y por ende sufriría exactamente el mismo bloqueo.

Para permitir el acceso de `root` en la configuración de SSH del contenedor seguimos los siguientes pasos (debemos estar dentro de la **Console** del contenedor LXC en Proxmox y haber iniciado sesión con el usuario `root`):

1. Abrir el archivo de configuración del servidor SSH con el editor `nano`:
```sh
nano /etc/ssh/sshd_config
```

2. Para modificar la directiva de permisos, buscar la línea que dice `#PermitRootLogin prohibit-password` o `PermitRootLogin no` (Si tiene un símbolo `#` al principio, desmarcarlo borrando el `#`). Se debe cambiar esa línea para que quede exactamente así:
```text
PermitRootLogin yes
```

3. Guardar los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Reiniciar el servicio SSH para que se apliquen los cambios:
```sh
systemctl restart ssh
```

Adicionalmente, habilitaremos el acceso mediante llaves SSH (por ejemplo para entrar de forma segura y sin escribir contraseñas), y para eso ejecutar los siguientes pasos:

1. Desde una terminal en la máquina local (en mi caso mi Macbook Pro), ejecutar lo siguiente para generar una llave solo para este contenedor:

```sh
ssh-keygen -t ed25519 -C "correo@email.com" -f ~/.ssh/id_proxmox_lxc_vault
# Contraseña: Al pedir una passphrase, presionar Enter dos veces para dejarla en blanco ya que queremos que
# Terraform automatice las conexiones sin pedir claves interactivamente.

# Podemos verificar la lista de llaves que tenemos ejecutando:
ls -l ~/.ssh/id_*.pub
```

2. Configurar el archivo SSH Config para que la máquina local sepa exactamente qué clave usar cuando se conecte al LXC. Para esto, se debe editar el archivo de configuración:
   ```sh
   # Abrimos el archivo
   nano ~/.ssh/config
   ```

   Y en el archivo que se abre agregar las siguientes líneas (al finalizar, guardar los cambios con la combinación: `Ctrl+O`, `Enter`, `Ctrl+X`):

   ```text
   Host 192.168.0.20
       User root
       IdentityFile ~/.ssh/id_proxmox_lxc_vault
       IdentitiesOnly yes
   ```

   `IdentitiesOnly yes` evita que la máquina local intente usar otras llaves, previniendo bloqueos por demasiados intentos fallidos.

3. Copiar la llave pública al LXC de Vault para autorizar el acceso:

```sh
# Al intentar copiar la llave en el LXC, debemos ingresar la contraseña del usuario root
ssh-copy-id -i ~/.ssh/id_proxmox_lxc_vault.pub root@192.168.0.20
```

4. Validar que la llave funciona, por lo cual, al ejecutar el siguiente comando no debería solicitar contraseña:

```sh
ssh -i /Users/andres/.ssh/id_proxmox_lxc_vault 'root@192.168.0.20'
```

Adicionalmente, como ya se tiene habilitado el acceso mediante llave SSH, si se desea se puede volver a desactivar el acceso mediante contraseña, para lo cual tendríamos que volver a editar el archivo `/etc/ssh/sshd_config` dentro del contenedor LXC en Proxmox y cambiar la línea que modificamos antes para que quede con el valor `PermitRootLogin prohibit-password`.


### Paso 6: Configurar Certificados SSL/TLS dentro del LXC

Vault maneja información extremadamente sensible (contraseñas, llaves API, certificados raíz), y por seguridad, nunca se deben transmitir estos datos en texto plano (HTTP). Por tanto, debemos configurar certificados SSL/TLS dentro del LXC, los cuales tienen el siguiente propósito:

- Sirven para activar peticiones HTTPS.
- Garantizan que la comunicación entre el navegador (o las aplicaciones) y Vault viaje cifrada.
- Evitan que alguien en la misma red local pueda interceptar los secretos usando técnicas como *Man-in-the-Middle*.

Durante el proceso de instalación de los paquetes oficiales de HashiCorp, dentro de `/opt/vault/tls/` se crean automáticamente certificados autofirmados (self-signed) (`/opt/vault/tls/tls.crt` y `/opt/vault/tls/tls.key`). Estos certificados pueden servirnos para pruebas rápidas locales o entornos tipo HomeLab, sin embargo, el navegador o comandos como `curl` nos lanzarán un error de advertencia diciendo que el certificado no es confiable porque no lo firmó una entidad conocida, por ende, tendremos que ignorar la advertencia en el navegador o usar el parámetro `-k` o `VAULT_SKIP_VERIFY=1` en la terminal.

Para el caso de nuestro Homelab (al menos en principio), usaremos este tipo de certificados autofirmados, pero es mejor generar nuestros propios certificados. Si usamos los que vienen por defecto, no tendremos control sobre la fecha de expiración, el nombre de dominio (o IP) válido, ni la autoridad de certificación (CA) que los respalda.

Antes de generar el certificado, hay que tener en cuenta que vamos a necesitar compartirlo (el archivo `.crt`) para que los clientes (como ESO y VSO) lo puedan usar. Así que vamos a ver primero una forma segura de disponibilizar nuestro certificado a los clientes.

#### Exponer el certificado vía HTTP (dentro del LXC)

Como se explica en la documentación del [Modelo de seguridad de Vault](https://developer.hashicorp.com/vault/docs/internals/security#external-threat-overview), *No existe confianza mutua entre los clientes (como por ejemplo los operadores ESO y VSO) y el servidor de Vault*, por lo tanto, como vamos a habilitar el uso de TLS para permitir el acceso a Vault a través de HTTPS, los clientes deberían usar TLS para verificar la identidad del servidor y establecer un canal de comunicación seguro.

Algunos clientes como por ejemplo la CLI y el operador de VSO permiten usar banderas para saltar esta verificación que se hace mediante el certificado TLS (lo cual puede ser útil en entornos de desarrollo), sin embargo, operadores como ESO no lo permiten (y además los mantenedores del proyecto [no están dispuestos a cambiar esto](https://github.com/external-secrets/external-secrets/issues/3927)).

Ahora bien, como tenemos una llave SSH que podemos usar desde nuestra máquina local para conectarnos al LXC con el usuario `root` sin tener que proporcionar una contraseña, bien podríamos copiar esa llave en nuestro clúster de Kubernetes para por ejemplo hacer que descargue el certificado usando `scp`. No obstante, por razones de seguridad una llave SSH con permisos `root` no debería compartirse a los clientes, nisiquiera a nuestro clúster.

Existen formas para hacer que una llave que subamos al LXC le permita acceder vía SSH solo a ciertos usuarios, e incluso podemos restringirla para que solo pueda acceder al certificado y nada más, pero para nuestro caso, creo que la forma más limpia, sencilla y estándar es instalar un servidor web ultra-ligero en el LXC que sirva el archivo estático y así, cualquier cliente podría acceder al certificado sin tener que estar configurando usuarios y permisos por cada uno.

Así que ejecutamos el siguiente comando en la **Console** de nuestro LXC para instalar Nginx:

```sh
apt update && apt install nginx -y
```

Esto instalará y levantará un servidor web ultra-ligero en el puerto `80`, lo cual podemos verificar ejecutando `ss -tuln`, o si queremos ver el nombre del programa/proceso podemos ejecutar `lsof -i -P -n | grep LISTEN`, donde en efecto podremos apreciar que `nginx` es quien está escuchando por ese puerto.

Nginx por defecto servirá lo que esté en `/var/www/html`, así que lo que haremos por el momento será crear aquí la carpeta donde copiaremos el certificado:

```sh
mkdir -p /var/www/html/certs
```

De esta forma, cuando creemos nuestro certificado, éste estará disponible a través de la URL estática `http://192.168.0.20/certs/vault.crt`. Eventualmente podríamos hacer las configuraciones para se pueda acceder a él mediante `https`, pero por el momento lo dejaremos así.

Ahora sí, veamos 3 de las opciones principales que tenemos para generar el certificado, aunque en este caso ahondaré más en detalle en la opción 1 ya que es la que usaremos por el momento.

#### Opción 1: Certificados Autofirmados Propios (Ideal para empezar en nuestro laboratorio)

Podemos generar nuestros propios certificados válidos para la IP de nuestro contenedor usando `openssl`. Para esto, ejecutamos los siguientes pasos dentro de la terminal de nuestro LXC:

```sh
# 1. Crear carpeta (si se desea cambiar de ruta o asegurar la actual) y otorgar permisos a la carpeta
mkdir -p /opt/vault/own-tls
chown -R vault:vault /opt/vault/own-tls
chmod 700 /opt/vault/own-tls

# 2. Generar llave privada y certificado autofirmado válido por 365 días
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/vault/own-tls/tls.key \
  -out /opt/vault/own-tls/tls.crt \
  -subj "/CN=192.168.0.20" \
  -addext "subjectAltName = IP:192.168.0.20,DNS:vault.eljavatar.home"

# 3. Asignar permisos correctos para que el usuario 'vault' pueda leerlos
chown -R vault:vault /opt/vault/own-tls/*
chmod 600 /opt/vault/own-tls/tls.key
chmod 644 /opt/vault/own-tls/tls.crt

# 4. Exponer el certificado público (El .crt es seguro de compartir, la .key JAMÁS)
# Usamos la carpeta accesible para el servidor web Nginx que creamos previamente
cp /opt/vault/own-tls/tls.crt /var/www/html/certs/vault.crt
chmod 644 /var/www/html/certs/vault.crt
```

##### Renovación Automática del Certificado

Hay que tener en cuenta que este certificado expiraría en `365` días (o el tiempo que le indiquemos), por lo tanto, si queremos quedarnos con esta opción, lo ideal sería crear un Script y un Cron Job dentro del LXC que automatice la creación del certificado antes de que expire.

Podríamos tener formas más sofisticadas de hacer que los clientes puedan obtener el nuevo certificado cada vez que se renueva, como por ejemplo publicar un mensaje en algún tópico después de la renovación y que los clientes reciban la notificación para que puedan descargar el certificado lo más in-real time posible, sin embargo, para nuestro homelab bastará con que los clientes corran periódicamente sus propios jobs para que lo descarguen de la ruta expuesta.

Para automatizar la renovación del certificado seguimos entonces los siguientes pasos:

**Creación del Script**

_**Opcional:** En caso de querer notificar por Telegram un fallo en la renovación, podemos ejecutar lo siguiente (para esto, habría que crear previamente el bot en Telegram y el respectivo chat para obtener el Token del bot y el Chat ID):_

```sh
cat << 'EOF' > /opt/vault/.env_telegram
TELEGRAM_TOKEN="telegram_token_aquí"
TELEGRAM_CHAT_ID="telegram_chat_id_aquí"
EOF

chmod 600 /opt/vault/.env_telegram
chown root:root /opt/vault/.env_telegram
```

1. Crear el archivo del script:
```sh
nano /usr/local/bin/renew-vault-cert.sh
```

2. Pegar el siguiente código (como vemos incluye los mismos comando que ejecutamos antes):
```bash
#!/bin/bash

# EN CASO DE QUE LA RENOVACIÓN FALLE PODEMOS NOTIFICAR POR TELEGRAM SI QUEREMOS
# 1. Cargar credenciales de Telegram de forma segura
# if [ -f /opt/vault/.env_telegram ]; then
#   source /opt/vault/.env_telegram
# fi

# # 2. Función de notificación en caso de error
# enviar_alerta_telegram() {
#   if [ "$?" -ne 0 ]; then
#     echo "🚨 Ejecución fallida. Enviando alerta a Telegram..."
    
#     # En Bash de Debian/Ubuntu, hostname -I nos da la IP privada directamente
#     IP_LXC=$(hostname -I | awk '{print $1}')
    
#     MENSAJE="❌ *Homelab Alert: Renovación TLS falló en LXC*%0A%0A"
#     MENSAJE="${MENSAJE}• *Host:* $(hostname) (${IP_LXC})%0A"
#     MENSAJE="${MENSAJE}• *Servicio:* HashiCorp Vault%0A"
#     MENSAJE="${MENSAJE}• *Error:* Revisar logs en el LXC con \`cat /var/log/vault-cert-renew.log\`"
    
#     # Enviar solo si las variables existen
#     if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
#       curl -s -X POST "https://telegram.org{TELEGRAM_TOKEN}/sendMessage" \
#         -d "chat_id=${TELEGRAM_CHAT_ID}" \
#         -d "text=${MENSAJE}" \
#         -d "parse_mode=Markdown" > /dev/null
#     fi
#   fi
# }

# # Activar el capturador de errores para todo el ciclo de vida del script
# trap enviar_alerta_telegram EXIT


# 1. Regenerar el certificado (Dura 365 días, pero lo correremos cada 3 meses)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /opt/vault/own-tls/tls.key \
  -out /opt/vault/own-tls/tls.crt \
  -subj "/CN=192.168.0.20" \
  -addext "subjectAltName = IP:192.168.0.20,DNS:vault.eljavatar.home"

# 2. Corregir permisos para que Vault pueda leer los certificados
# Vault corre bajo su propio usuario (vault), por lo que al generar los archivos como root
# (vía Anacron), Vault perderá el acceso de lectura a la llave privada y el comando 'reload'
# fallará. Por eso se tienen que volver a asignar los permisos.
chown -R vault:vault /opt/vault/own-tls/
chmod 600 /opt/vault/own-tls/tls.key
chmod 644 /opt/vault/own-tls/tls.crt

# 3. Exponer el certificado público en el servidor web
cp /opt/vault/own-tls/tls.crt /var/www/html/certs/vault.crt
chmod 644 /var/www/html/certs/vault.crt

# 4. Recargar Vault en caliente sin desellarlo
# No hacemos 'restart' porque esto haría que Vault vuelva a quedar Sellado hasta el próximo
# reinicio del LXC y haga el UnSeal automático, o hasta que lo hagamos manualmente
systemctl reload vault
```

3. Guardar los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Darle permisos de ejecución al script:
```sh
chmod +x /usr/local/bin/renew-vault-cert.sh
```

**Creación de la Tarea Programada**

Ahora solo nos queda programar un **Cron Job** en el LXC ejecutando por ejemplo `crontab -e` para que se ejecute, por ejemplo, el día 1 de cada mes a las 3:00 AM (así siempre estará renovado mucho antes de los 365 días).

Sin embargo, puede pasar que el día y hora en que se tiene que hacer la renovación del certificado la máquina esté apagada (depronto por un corte de energía), y en tal caso, si se usa `cron` el certificado no se renovaría sino hasta el siguiente mes, ya que `cron` no guarda un estado de si el `job` se ejecutó o no. Para mitigar esta situación usamos `anacron`, el cual sí lleva un registro en disco de cuándo se ejecutó la tarea por última vez. Si detecta que el sistema estuvo apagado el día programado, dispara el script inmediatamente unos minutos después de que el LXC arranca.

Para esto, debemos asegurarnos primero de que `anacron` esté instalado ejecutando lo siguiente en el LXC:

```sh
apt-get update && apt-get install -y anacron

# Para validar que quedó instalado:
anacron -h
```

Anacron ya trae unas carpetas preconfiguradas en las cuales podemos copiar scripts dentro para que se ejecuten una vez al mes (`/etc/cron.monthly`), a la semana (`/etc/cron.weekly`) o al día (`/etc/cron.daily`), y la configuración que indica cuándo se ejecutarían se encuentra en el archivo `/etc/anacrontab`. En caso de que queramos copiar un archivo en esas carpetas, habría que tener en cuenta que la copia en dicha carpeta debería quedar sin la extensión `sh` ni cualquier otra extensión.

Sin embargo, dado que nuestro script ya está en `/usr/local/bin/renew-vault-cert.sh`, la forma más limpia, ordenada y donde mantenemos el control de los logs, es configurarlo directamente en el archivo `/etc/anacrontab` con un retraso corto. Así pues, seguiremos los siguientes pasos:

1. Abrir el archivo de configuración:
```sh
nano /etc/anacrontab
```

2. Ir al final del archivo y pegar esta línea (esta línea dice que se ejecutará una vez cada 90 días, y que si el equipo estaba apagado a la hora programada, anacron esperará 2 minutos desde que se encienda el sistema antes de lanzar el script):
```
90      2       renew_vault_cert        /usr/local/bin/renew-vault-cert.sh > /var/log/vault-cert-renew.log 2>&1
```

3. Guardar los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Asegurar que Anacron esté activo ya que en Debian 12, anacron usualmente se gestiona a través de un temporizador de Systemd:
```sh
systemctl enable anacron
systemctl start anacron
```

Como podemos apreciar, a diferencia de Cron Jobs tradicionales, con Anacron no se especifica un día y hora exacta, sino que gracias a que guarda un registro de cuando fue la última vez que se ejecutó con éxito el script, va calculando a partir de esa fecha cuando es la próxima vez que tiene que ejecutarlo según el periodo indicado (que en este ejemplo son 90 días).

Este mecanismo es lo que le permite que en caso del LXC estar apagado cuando le correspondería ejecutarse, que al encenderse de nuevo, pueda detectar que el tiempo transcurrido desde la última ejecución es mayor al tiempo configurado. Adicionalmente, el temporizador interno de Debian despierta a anacron una vez al día (por defecto suele ser a las 6:25 AM), lo cual le permite calcular todos los días si se debe ejecutar el Script o no, por ejemplo, para los casos en los que el LXC no se ha apagado en más de 90 días.

#### Opción 2: Usar Let's Encrypt (Certificados gratuitos y válidos en todo el mundo)

Si tenemos un dominio propio apuntando a nuestra red (o usando DNS local con Split-Brain), podemos instalar **Certbot** en el LXC y obtener certificados válidos que el navegador reconocerá sin errores. Una vez generados, configuramos el `vault.hcl` para que apunte a las rutas de Certbot (normalmente en `/etc/letsencrypt/live/...`). Hay que tener en cuenta que los certificados de Let's Encrypt expiran cada 90 días, por lo tanto, al igual que hicimos con nuestros certificados autofirmados, lo ideal también sería implementar un método que permita automatizar al 100% la creación y renovación de los certificados (por ejemplo mediante la API de Cloudflare o el proveeedor de DNS que administre nuestro dominio).

Si bien es cierto que en este caso poseo el dominio `eljavatar.org`, por el momento voy a omitir la creación del certificado para Vault a través de Let's Encrypt.

#### Opción 3: Un Proxy Inverso en Proxmox (La opción más limpia para LXC)

En muchos casos se prefiere **desactivar TLS directamente en Vault** (`tls_disable = "true"`) dentro del archivo `vault.hcl`. En su lugar, se monta otro contenedor LXC muy ligero con Nginx, Caddy o Nginx Proxy Manager que actúe como proxy inverso:

- El proxy se encarga de recibir las conexiones HTTPS desde afuera (con certificados automáticos de Let's Encrypt).
- El proxy se comunica internamente con Vault usando HTTP plano (`http://127.0.0.1:8200` o la IP privada del LXC).
- Esto ahorra el tener que configurar certificados dentro de Vault y facilita la renovación de los mismos.

#### ¿Qué opción elegir?

Lo ideal sería escoger la Opción 2 o la Opción 3, sin embargo, por el momento, por rapidez y practicidad para pruebas, me inclinaré por la opción 1. En un futuro, cuando agregue una tercera Mini PC al homelab, probablemente implemente la Opción 3.

#### Descargar el Certificado en nuestra máquina local (Opcional)

Previamente disponibilizamos el certificado a través de un servidor web con Nginx, por lo cual los clientes que necesiten obtener dicho certificado para realizar la verificación de identidad del servidor de Vault para establecer un canal de comunicación seguro, podrían simplemente usar un CURL para descargarlo.

Del mismo modo, si por alguna razón necesitamos descargar el certificado en nuestra máquina local, tenemos 2 formas de hacerlo: por SSH (usando `scp`) o por CURL:

```sh
# Opción 1: Vía SSH
# Nos pedirá la contraseña del usuario 'root' del LXC
scp root@192.168.0.20:/opt/vault/own-tls/tls.crt certs/vault-ca.crt
# O uando nuestra llave SSH para que no nos pida contraseña
scp -i /Users/andres/.ssh/id_proxmox_lxc_vault 'root@192.168.0.20:/opt/vault/own-tls/tls.crt certs/vault-ca.crt'

# Opción 2: Mediante CURL como lo harían los clientes
curl -s -f -o certs/vault-remote.crt http://192.168.0.20/certs/vault.crt

# Por razones de seguridad, la carpeta 'cert/' debe ser agregada al archivo .gitignore
```


### Paso 7: Configurar el archivo de Vault con motor Raft

Editamos el archivo de configuración principal de Vault dentro del LXC:

```sh
nano /etc/vault.d/vault.hcl
```

Borramos todo su contenido y pegamos la siguiente configuración limpia y adaptada para nuestra red local, habilitando el almacenamiento integrado Raft ([guía de configuración](https://inventivehq.com/blog/hashicorp-vault-cli-install-and-gui-setup-guide)):

```hcl
# Configuración del almacenamiento Raft
storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-node-01"
}

# Listener para escuchar peticiones del clúster de Kubernetes con TLS
listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = "false"
  tls_cert_file   = "/opt/vault/own-tls/tls.crt"
  tls_key_file    = "/opt/vault/own-tls/tls.key"
}

# Habilitar la UI para entornos de Homelab (en entornos estrictos a veces se suele deshabilitar la UI)
ui = true

# Desactivar mlock, obligatorio para evitar conflictos con Raft (BoltDB)
disable_mlock = true

# API Address (for client communication)
api_addr     = "https://192.168.0.20:8200"
cluster_addr = "https://192.168.0.20:8201"
```

Al finalizar la edición del archivo, lo guardamos (`Ctrl+O`, `Enter`, `Ctrl+X`).

Adicionalmente, debemos asegurarnos de crear la carpeta donde Raft persistirá los datos y, le otorgamos permisos al usuario nativo de Vault sobre dicha carpeta:

```sh
mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault
chown -R vault:vault /opt/vault/data
```


### Paso 8: Iniciar el Servicio

Habilitamos e iniciamos el demonio del sistema para que Vault corra 24/7 de forma automática:

```sh
systemctl enable vault
systemctl start vault
```


### Paso 9: Crear Variables de Entorno

Para usar la CLI de Vault desde la terminal del LXC, debemos agregar algunas variables de entorno para que el comando `vault` sepa a dónde apuntar. Podríamos hacerlo rápidamente con `export`, pero cada vez que se reinicie el LXC, tendríamos que volver a configurarlas. Para evitar esto, vamos a agregarlas directamente al perfil del sistema. Para esto, seguiremos los siguientes pasos:

1. Abrimos primero el archivo de configuración de entorno global con un editor:

```sh
nano /etc/environment
```

2. Añadimos las siguientes líneas al final del archivo (Como usamos un certificado autofirmado, añadimos también temporalmente la variable `VAULT_SKIP_VERIFY=true` para que el comando local no rechace su propio certificado):

```text
VAULT_ADDR="https://127.0.0.1:8200"
VAULT_SKIP_VERIFY=true
```

3. Guardamos los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Para que se aplique de inmediato en la sesión actual sin reiniciar, ejecutamos lo siguiente:

```sh
source /etc/environment
```

A partir de ahora, tanto el sistema, como los servicios automáticos y cualquier usuario que inicie sesión, reconocerán estas variables de forma nativa y podrán ejecutar los comandos de `vault` sin inconvenientes.


### Paso 10: Inicializar Vault (The Unseal Process)

Tenemos 2 formas de inicializar el operador de Vault: desde el Navegador o desde la terminal del LXC:

#### Opción A: Desde el Navegador

Abrimos el navegador en nuestra máquina local (en mi caso, mi Macbook Pro), ingresamos a la interfaz web de Vault: `https://192.168.0.20:8200` (como usamos un certificado auto firmado, nos aparecerá una pantalla de Conexión insegura, a lo cual haremos caso omiso y le indicamos que continúe al sitio), y seguimos los siguientes pasos:

1. El sistema nos indica que Vault se encuentra en estado **Sealed**, además de confirmarnos que este servidor está configurado para usar Raft Storage y nos pregunta cómo queremos empezar. Seleccionamos la opción **Create a new Raft cluster** ya que es la configuración e inicialización por primera vez, y este nodo será el primer integrante (el líder inicial) de nuestra infraestructura de Vault. Luego damos clic en **Next**.

2. En la siguiente pantalla, especificamos **5 Key shares** y **3 Key threshold** (Significa que generará 5 llaves maestras y necesitaremos al menos 3 de ellas para abrir la bóveda cada vez que se reinicie el LXC (en laboratorios domésticos suele ser común que solo se usen 3 Key shares y 2 Key threshold, o incluso 1 y 1, sin embargo, en este caso lo configuro con 5 y 3 ya que quiero que sea similar a un entorno realista de producción)) y hacemos clic en **Initialize**.

3. **⚠️ MANDATORIO:** Descargamos el JSON con las llaves criptográficas y el `Initial Root Token`. Si perdemos este archivo, nuestros secretos guardados en el NVMe se volverán basura matemática ilegible para siempre.

4. Hacemos clic en **Continue to Unseal**.

5. Introducimos tres de las llaves descargadas para hacer el **Unseal** (apertura) de la boveda (Si las extraemos del archivo JSON que se descargó, debemos usar las que están en formato de base64).

6. Iniciamos sesión en la UI usando nuestro `Root Token`.

#### Opción B: Desde la Terminal

1. **Configurar la variable de entorno del cliente:** Las variables de entorno las definimos de forma global en el paso 9, sin embargo, en caso de que lo hayamos omitido, deberíamos crearlas mediante `export VAULT_ADDR="https://127.0.0.1:8200"` y `export VAULT_SKIP_VERIFY=true`.

2. **Ejecutar la inicialización:** Para entornos de producción con almacenamiento Raft, se recomienda usar el método tradicional de **Shamir's Shares** (por defecto 5 llaves, requiriendo 3 para desbloquear). Para esto, ejecutamos el siguiente comando:
   ```sh
   vault operator init
   ```

3. **⚠️ Guardar los secretos (MANDATORIO):** Al ejecutar el anterior comando, se nos mostrará en pantalla un output similar a este:
   ```
   Unseal Key 1: oX...
   Unseal Key 2: pY...
   Unseal Key 3: qZ...
   Unseal Key 4: aA...
   Unseal Key 5: bB...

   Initial Root Token: hvs.blahblahblah...
   ```

   En un entorno real, estas 5 llaves se distribuyen a 5 personas distintas de la organización corporativa, por tanto, en un entorno empresarial lo ideal sería guardar estas **Unseal Keys** por separado. Sin embargo, en nuestro caso de Homelab lo importante es guardarlas en un lugar seguro y evitar que se pierdan.

   Por otro lado, el `Initial Root Token` es nuestra contraseña maestra inicial, por tanto, lo ideal sería ponerla en un lugar seguro tipo KeePass, Bitwarden, etc.

4. **Desbloquear (Unseal) el Vault:** Cada vez que el contenedor LXC se reinicie, Vault iniciará en estado **Sellado (Sealed)** por seguridad y no responderá peticiones. Para abrirlo debemos introducir 3 de las 5 llaves generadas, para lo cual ejecutaríamos el siguiente comando 3 veces, introduciendo una *Unseal Key* distinta cada vez:
   ```sh
   # Al ejecutar este comando, nos solicita que ingresemos un Unseal Key
   vault operator unseal
   # Debemos repetir la ejecución de este comando hasta que la línea Sealed cambie a false
   ```

5. **Probar el acceso:** Para esto, verificamos el estado final de nuestro Vault mediante los siguientes comandos:
   ```sh
   vault status
   ```




## Configurar un Auto-Unseal (Opcional, pero Recomendado)

En el paso anterior realizamos el proceso de desbloqueo de la bóveda usando las respectivas Unseal keys. Sin embargo, si se reinicia el contenedor LXC, Vault iniciará en estado **Sellado (Sealed)**, y por tanto, si ejecutamos `vault status` obtendríamos algo como lo siguiente:

```
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  true
Total Shares            5
Threshold               3
Unseal Progress         0/3
Unseal Nonce            n/a
Version                 2.0.4
Build Date              2026-08-03T16:14:36Z
Storage Type            raft
Removed From Cluster    false
HA Enabled              true
```

En esta salida podemos apreciar que `Sealed` está en `true`, lo que significa que nuestra bóveda está sellada, lo cual implica que nuestras aplicaciones y servicios no podrán leer las contraseñas o secretos hasta que entremos a Vault y lo **desbloqueemos (Unseal)** con las `Unseal Key` que obtuvimos al momento de inicializar Vault.

Hacer este proceso de Unseal manualmente cada vez que hay un reinicio de la máquina física sería algo tedioso, por tanto, podríamos automatizar la apertura de Vault para no tener que intervenir en absoluto tras un reinicio (por ejemplo después de un apagón) implementando algún método de **Auto-Unseal**, ya sea utilizando servicios en la nube (como AWS KMS, Azure Key Vault, Google Cloud KMS, etc.) o mediante un script local seguro con una herramienta de tránsito de Vault.

En este caso usaremos una alternativa local robusta que consistirá en crear un script automatizado por un servicio de Systemd que se ejecute solo un momento después de que Vault arranque, lea las llaves de un archivo con permisos ultra-restringidos y realice el proceso de desbloqueo.

**Nota:** En entornos productivos, lo ideal sería usar servicios en la nube para automatizar el **Unseal**, ya que usar un método local implica tener en texto plano las *Unseal_Keys* como lo veremos a continuación; aunque igual podríamos usar también algo como *SOPS* para que este archivo esté cifrado y que sea el Script quien se encargue de descifrarlo, pero por el momento lo dejaremos así.


### Paso 1: Crear el archivo con las llaves de unseal

Vamos a guardar las llaves en un archivo oculto donde ***solo el usuario root*** (o el usuario que maneje el servicio) pueda leerlo.

1. Crear el archivo de credenciales:
```sh
nano /etc/vault.d/.unseal_keys
```

2. Pegar las llaves de desbloqueo, una por línea (se necesita ingresar tantas líneas como el umbral/threshold que se configuró al inicializar Vault, que en nuestro caso fueron 3):
```text
UNSEAL_KEY_1
UNSEAL_KEY_2
UNSEAL_KEY_3
```

3. Guardamos los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. **Crucial por seguridad:** Restringir los permisos del archivo para que nadie más en el contenedor pueda verlo:
```sh
chmod 600 /etc/vault.d/.unseal_keys
chown root:root /etc/vault.d/.unseal_keys
```


### Paso 2: Crear el Script de Unseal

1. Crear el archivo del script:
```sh
nano /usr/local/bin/vault-autounseal.sh
```

2. Pegar el siguiente código (este script lee el archivo anterior línea por línea y ejecuta el comando de desbloqueo):
```bash
#!/bin/bash

# Importar variables de entorno
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY="true"

# Esperar a que el servicio de Vault responda antes de intentar el unseal
until vault status 2>&1 | grep -q "Key"; do
    sleep 2
done

# Verificar si ya está desbloqueado
if vault status | grep -q "Sealed.*true"; then
    echo "Vault está sellado. Iniciando proceso de unseal..."

    # Leer las llaves del archivo seguro y ejecutar unseal por cada una
    while IFS= read -r key || [ -n "$key" ]; do
        vault operator unseal "$key" > /dev/null
    done < /etc/vault.d/.unseal_keys

    echo "Proceso de unseal finalizado."
else
    echo "Vault ya se encuentra desbloqueado."
fi
```

3. Guardamos los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Darle permisos de ejecución al script:
```sh
chmod +x /usr/local/bin/vault-autounseal.sh
```


### Paso 3: Crear el servicio de Systemd para automatizarlo

Crearemos un servicio que se dispare automáticamente justo después de que el servicio principal de Vault se inicie.

1. Crear el archivo del servicio:
```sh
nano /etc/systemd/system/vault-autounseal.service
```

2. Pegar la siguiente configuración:
```ìni
[Unit]
Description=Auto Unseal para HashiCorp Vault
After=vault.service
Requires=vault.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/vault-autounseal.sh
RemainAfterExit=true
User=root

[Install]
WantedBy=multi-user.target
```

3. Recargar Systemd para que reconozca el nuevo servicio y activarlo para que arranque en el boot:
```sh
systemctl daemon-reload
systemctl enable vault-autounseal.service
```


### Paso 4: Probar el funcionamiento del Script

La forma más directa de probar este Auto-Unseal es reiniciando el LXC, así que reiniciamos el contenedor desde la interfaz de Proxmox, vamos a la **Console** y nos logueamos con el usuario `root`. Ahora, al ejecutar `vault status` obtendremos algo como lo siguiente:

```
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
Total Shares            5
Threshold               3
Version                 2.0.4
Build Date              2026-08-03T16:14:36Z
Storage Type            raft
Cluster Name            vault-cluster-82de41a3
Cluster ID              df2b2b72-7af7-3aba-8003-acad26bb7637
Removed From Cluster    false
HA Enabled              true
HA Cluster              https://192.168.0.20:8201
HA Mode                 active
Active Since            2026-08-29T11:32:48.261673315Z
Raft Committed Index    5046
Raft Applied Index      5046
```

En esta salida podemos ver que `Sealed` ya aparece con valor `false`, ya que después de encender el LXC, el LXC inició Vault y Systemd lo desbloqueó de inmediato.

Además, si hemos seguido todos los pasos hasta aquí, al ejecutar `printenv` también veremos que tenemos configuradas las variables de entorno `VAULT_ADDR` y `VAULT_SKIP_VERIFY`, con lo cual ya tenemos listo el ambiente de nuestro LXC para poder usar la CLI de `vault` sin preocuparnos por el unseal de la bóveda o por tener que agregar variables de entorno.




## Configuraciones de Vault

En términos generales, podríamos usar la interfaz web (en `https://192.168.0.20:8200`) para crear secretos, gestionar métodos de autenticación, roles, políticas, etc., sin embargo, en el mundo empresarial se suele usar la CLI para realizar todas estas tareas de administración y configuración. Por lo tanto, las configuraciones a continuación las realizaremos usando la CLI (aunque eventualmente podríamos usar también la UI si quisiéramos).


### Configurar la CLI en la máquina local

En las anteriores secciones estuvimos usando la CLI de vault directamente desde la **Console** del LXC en la interfaz de Proxmox. Sin embargo, en muchas ocasiones vamos a necesitar ejecutar comandos del clúster de Kubernetes (`kubectl`) y comandos para administrar secretos de Vault (`vault`), y estar saltando entre la terminal de la máquina local y la interfaz de Proxmox puede ser cansón.

Por tanto, seguiremos los pasos a continuación para no tener que entrar a la consola de Proxmox ni al LXC para interactuar con Vault, sino que podamos hacerlo directamente desde la terminal de la máquina local (en mi caso, mi Macbook pro) (Para esto hemos de haber instalado previamente la dependencia de vault como se indicó en el [README principal](README.md#dependencias-en-macbook-pro) de este repositorio):

1. Configurar las variables de entorno. Al igual que hicimos dentro del LXC, necesitamos decirle a la CLI de la máquina local a dónde debe apuntar y que ignore el certificado autofirmado. Para esto, ejecutamos los siguientes comandos (recordemos que la IP de nuestro LXC es la `192.168.0.20`):

```sh
export VAULT_ADDR="https://192.168.0.20:8200"
export VAULT_SKIP_VERIFY="true"
```

2. Ahora, para hacerlo permanente y no tener que escribir estos `export` cada vez que abrimos una nueva pestaña de la terminal, los agregamos al archivo de configuración de la shell (generalmente Zsh en macOS moderno).

```sh
# Abrir el archivo .zshrc
nano ~/.zshrc

# Agregar las dos líneas al final del archivo:
export VAULT_ADDR="https://192.168.0.20:8200"
export VAULT_SKIP_VERIFY="true"

# Guardar (Ctrl + O, Enter, Ctrl + X) y aplicar los cambios:
source ~/.zshrc
```


### Iniciar Sesión en la CLI

Para poder realizar todas estas configuraciones, debemos iniciar sesión en Vault. Para esto, podríamos hacerlo a través de la **Console** de nuestro LXC de **hashicorp-vault** (`1001`) en la interfaz de Proxmox, pero gracias a que en el paso anterior configuramos la CLI de Vault en nuestra máquina local, tanto el inicio de sesión, así como las configuraciones posteriores podemos realizarlas desde la terminal de nuestra máquina.

Ahora, ejecutamos el siguiente comando, el cual nos pedirá después que ingresemos un token, y como aún no hemos configurado ningún otro método de acceso, debemos ingresar el `Initial Root Token`:

```sh
vault login
#   Token (will be hidden):
```

Al iniciar sesión, obtendremos una salida como la siguiente:

```
Key                  Value
---                  -----
token                <token_usado_para_iniciar_sesion>
token_accessor       <token_accessor>
token_duration       ∞
token_renewable      false
token_policies       ["root"]
identity_policies    []
policies             ["root"]
```


### Crear Nuevo Token de Administrador

En entornos de producción (e incluso de desarrollo serio), lo ideal sería que configuráramos otra forma de iniciar sesión, ya sea mediante LDAP, con usuario y contraseña, con otro token, etc., ya que como bien lo indica la frase `Initial Root Token`, este es un token con permisos de super usuario para ser usado solo al iniciar sesión por primera vez, y por tanto, nunca se debería usar para el día a día.

Para crear un token de administrador que tenga control total y no expire, el proceso se divide en dos pasos: **crear una política de superusuario (admin)** y luego generar un **token huérfano (orphan) sin expiración** asociado a esa política.

Para esto, seguiremos los siguientes pasos desde la terminal :

#### 1: Crear la política de superusuario

Vault maneja los permisos mediante políticas escritas en formato HCL. Necesitamos una política que otorgue todos los privilegios (`sudo`, `read`, `create`, etc.) sobre absolutamente todas las rutas (`*`).

En el archivo `vault/policies/admin-policy.hcl` hemos definido una política para permitir todo en cualquier ruta; este archivo tiene el siguiente contenido:

```hcl
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
```

Para instalar esta política, ejecutamos lo siguiente (debemos asegurarnos de haber iniciado sesión antes con el root token actual):

```sh
vault policy write administrator vault/policies/admin-policy.hcl
```

#### 2: Crear el Token de Administrador sin expiración

Por defecto, en Vault todos los tokens tienen un "padre" y expiran después de cierto tiempo (TTL). Si el token padre se revoca, los hijos también.

Para crear un token que **no expire** y que **no dependa del root token** (para que podamos revocar el root token después), debemos crearlo con las siguientes condiciones:

- **`no-default-policy`:** Para que no arrastre políticas básicas innecesarias.
- **`period`:** Al asignarle un periodo, el token no tiene una fecha de muerte definitiva, siempre y cuando se renueve automáticamente (los clientes como la CLI de que usamos en nuestra Macbook manejan esto en segundo plano al usarlo).
- **`orphan`:** Para que no tenga padre.

Para esto, ejecutamos lo siguiente en la terminal:

```sh
vault token create \
  -policy="administrator" \
  -no-default-policy \
  -period="768h" \
  -orphan
```

*Nota: El parámetro `-period="768h"` le dice a Vault que el token es renovable indefinidamente cada 32 días. 768h es el tiempo máximo de TTL que podemos asignar (si colocamos un valor mayor veremos un mensaje de advertencia indicando que el valor se limitará a 768h), sin embargo, más adelante veremos cómo automatizar la renovación de este token.*

Al ejecutar el anterior comando, en la terminal obtendremos una salida como la siguiente, de la cual debemos extraer y guardar el valor que dice `token` (que empieza por `hvs.` o similar):

```
Key                  Value
---                  -----
token                <nuevo_token_generado>
token_accessor       <token_accessor>
token_duration       768h
token_renewable      true
token_policies       ["administrator"]
identity_policies    []
policies             ["administrator"]
```

#### 3: Probar el nuevo Token

Para asegurarnos de que todo funciona antes de guardar el root token (en algún gestor de contraseñas seguro fuera de vault, como por ejemplo 1Password, Bitwarden, KeePass, etc.), cerramos sesión e iniciamos con el nuevo:

```sh
# Limpiar la sesión actual en la máquina local:
vault token revoke -self
# (O simplemente borrar el archivo temporal con rm ~/.vault-token)

# Iniciar sesión con el nuevo token:
vault login
# Pegamos el token de administrador que acabamos de generar

# Ver la información de nuestro token
vault token lookup
```

Finalmente ejecutamos `vault secrets list` o `vault policy list` para verificar que tenemos acceso total.

Así que de ahora en adelante, todo lo que hagamos, y cada vez que iniciemos sesión (ya sea desde la CLI o a través de la interfaz web), debemos hacerlo con este nuevo token que hemos creado.


### Renovación Automática del Token de Administrador

Al usar el flag `-period="768h"`, hemos creado un **Periodic Token**, y su comportamiento es el siguiente:

- Su tiempo de vida máximo (`explicit_max_ttl`) es `0s`, lo que significa que **no tiene un límite de días absoluto** para morir (a diferencia de un token normal, que expira por completo al tiempo que se le configure sin importar cuántas veces lo renovemos).
- **La regla de oro:** El token vivirá indefinidamente **siempre y cuando lo renovemos activamente antes de que su ttl llegue a `0`**.
- Si ejecutamos `vault token lookup`, el campo `ttl` nos mostrará cuanto tiempo de vida le queda al token. Si no ejecutamos un comando de renovación antes de que pase ese tiempo, el token morirá de forma definitiva.

Por tanto, debemos implementar una estrategia para que el token se renueve solo, que puede ser mediante un CronJob que ejecute un script, o mediante herramientas como *Vault Agent*. Vault Agent es una herramienta excelente para servidores de producción o Kubernetes donde múltiples microservicios que usan el método de autenticación por *token* necesitan credenciales constantemente (lo cual no aplica en nuestro caso ya que usaremos el método de autenticación de *kubernetes con Service Accounts*).

Así pues, crearemos un Script directamente en el LXC de Vault para que se ejecute todos los días, aunque en esta ocasión, nos bastará hacerlo con Crontab (en vez de con Anacron), ya que si en un día no se puede ejecutar, igual puede hacerlo en los siguientes días (incluso podemos hacer que corra unas 2 o 3 veces al día).

Así pues, lo primero será entrar en la **Console** de nuestro LXC en Proxmox, loggearnos con el usuario `root`, y seguir los siguientes pasos:

1. Crear el archivo del script:
```sh
nano /usr/local/bin/vault-token-renewer.sh
```

2. Pegar el siguiente código:
```bash
#!/bin/bash

# Importamos variables de entorno
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY="true"
# Pasamos el TOKEN REAL a la variable de entorno que la CLI lee automáticamente
# Nuestro token tiene permiso para todo, incluso para renovarse a sí mismo
export VAULT_TOKEN="TOKEN_ADMINISTRADOR_AQUI"

# Al ejecutar 'renew' sin argumentos, Vault renueva automáticamente el token de $VAULT_TOKEN
vault token renew > /dev/null 2>&1

# Alternativa:
# Si no queremos poner el token administrador en este Script, una alternativa sería mediante el accesor,
# el cual podemos obtener a través de 'vault token lookup' (estando loggeado como administrador) pero
# para eso deberíamos crear un nuevo token (como lo hicimos con el administrador) y aplicarle una nueva
# política con permisos de "read" sobre el path "auth/token/lookup-self" y permisos de "update" sobre el
# path "auth/token/create", y asignar dicho nuevo token a la variable VAULT_TOKEN.
#VAULT_ACCESSOR="ACCESSOR_ADMINISTRADOR_AQUI"
#vault token renew -accessor "$VAULT_ACCESSOR" > /dev/null 2>&1
```

3. Guardar los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

4. Darle permisos de ejecución al script:
```sh
chmod +x /usr/local/bin/vault-token-renewer.sh
```

5. Como el script contiene el token real en texto plano, es crítico asegurar que nadie más que el usuario `root` del LXC pueda leer este archivo:
```sh
# Esto asegura que solo el propietario pueda leer, escribir y ejecutar el script).
chmod 700 /usr/local/bin/vault-token-renewer.sh
```

6. Agregarlo al Cron del LXC para que corra 3 veces por día. Primero se abre el editor de cron del sistema:
```sh
crontab -e
# Este comando nos pedirá elegir con qué editor queremos abrirlo, para lo cual
# escogemos 1, que corresponde a 'nano', ya que es el que venimos usando
```

7. Añadir la siguiente línea al final para que se ejecute todos los días a las 0, 8 y 16 horas:
```
0 0,8,16 * * * /usr/local/bin/vault-token-renewer.sh
```

8. Guardar los cambios (`Ctrl+O`, `Enter`, `Ctrl+X`).

De este modo, el LXC mantendrá el token vivo indefinidamente en segundo plano, y podemos usar la CLI en nuestra máquina local o en la consola del LXC en cualquier momento sin preocuparnos de que expire.


### Estructura de paths en Vault

Antes de continuar con los siguientes pasos, consideré pertinente dedicar una pequeña sección al manejo de paths dentro de Vault, lo cual casi nadie menciona pero creo que es importante tenerlo en cuenta antes de empezar a crear secretos, ya que nos ayudará a tener todo organizado desde el principio.

En general, hay tres tipos de elementos principales de Vault con los que siempre vamos a estar trabajando: Motores de Secretos (o Secret engines en inglés) (los cuales contienen secretos), Métodos de autenticación y Políticas. Las políticas las identificamos a través de un nombre, mientras que los motores de secretos y los métodos de autenticación los identificamos a través de un path. Para verlo más en detalle, si ejecutamos `vault secrets list`, `vault auth list` y `vault policy list`, veremos algo como lo siguiente:

```text
==> Resultado de 'vault secrets list'
Path               Type              Accessor                   Description
----               ----              --------                   -----------
agent-registry/    agent_registry    agent-registry_28ece387    agent registry
cubbyhole/         cubbyhole         cubbyhole_51607e5f         per-token private secret storage
identity/          identity          identity_7b8a7db5          identity store
sys/               system            system_a8a1c6bd            system endpoints used for control, policy and debugging

==> Resultado de 'vault auth list'
Path      Type     Accessor               Description                Version
----      ----     --------               -----------                -------
token/    token    auth_token_1ee38c99    token based credentials    n/a

==> Resultado de 'vault policy list'
administrator
default
default-ceiling
root
```

Al momento de crear estos elementos, tenemos comandos específicos para cada uno de ellos:

- **Motores de secretos:** `vault secrets enable [SECRET_ENGINE_TYPE] -path=SOME_PATH` (Si no se indica el path, se creará con el valor por default dependiendo del tipo de motor de secretos escogido).
- **Métodos de autenticación:** `vault auth enable [AUTH_METHOD_TYPE] -path=SOME_PATH` (Si no se indica el path, se creará con el valor por default dependiendo del método de autenticación escogido).
- **Políticas:** `vault policy write [POLICY_NAME] [POLICY_DEFINITION]`.

Sin embargo, para el caso de los secretos y los métodos de autenticación solemos usar también los comandos `vault write [PATH]` y `vault read [PATH]` para escribir y leer configuraciones. Entonces, si creamos un motor de secretos por ejemplo en el path `cluster_demo`, y un método de autenticación en ese mismo path, ¿cómo hace Vault para identificar si en un comando `vault write [PATH]` esa configuración se le debe aplicar a un motor de secretos o a un método de autenticación?

La respuesta la podemos encontrar si entramos a la interfaz web de Vault, específicamente en la URL `https://192.168.0.20:8200/ui/vault/tools/api-explorer` (en caso de que no tengamos habilitada la interfaz de usuario podemos obtener la lista de paths ejecutando `vault read -format=yaml sys/internal/specs/openapi | grep "    /"`).

Aquí podemos ver que Vault coloca los Motores de secretos (por ejemplo `cubbyhole`) en la raíz `/`, mientras que los métodos de autenticación (por ejemplo `token`) los ubica bajo el path `/auth`. Esto quiere decir que para nuestro caso de ejemplo `cluster_demo`, aunque al listarlos los veamos con el mismo nombre, para escribir por ejemplo una config, deberíamos usar `vault write cluster_demo/config` para el caso del motor de secretos y `vault write auth/cluster_demo` para el caso del método de autenticación.

Teniendo esto claro, ahora vamos a definir cómo va a ser la estructura de paths que en nuestro caso usaremos en Vault:

- **Motores de secretos:** Estos se crean en la raíz (`/`), así que para que tengan una estructura similar a los métodos de autenticación, a la hora de crearlos lo haremos en un path con el formato `secret/{TARGET_ENVIRONMENT}/{SECRET_ENGINE_TYPE}/`. De ese modo, si queremos crear un Motor de secretos de tipo Key Value (versión 2) el cual requerimos usar desde nuestro clúster de kubernetes, el path sería `secret/eljavatar_k8s/kv-v2` (si por ejemplo necesitamos crear un motor de tipo database para rotar automáticamente un usuario y contraseña cada X tiempo, el path sería por ejemplo `secret/eljavatar_k8s/database`).

- **Métodos de autenticación:** Estos se crean automáticamente bajo el path `auth/`, así que a la hora de crearlos lo haremos en un path con el formato `{TARGET_ENVIRONMENT}/{AUTH_METHOD_TYPE}`. De ese modo, si queremos crear un Método de autenticación de tipo kubernetes el cual requerimos usar desde nuestro clúster, el path sería `auth/eljavatar_k8s/kubernetes` (aquí puede parecer que tenemos redundancia en el path ya que la palabra `kubernetes` y la palabra `k8s` hacen alusión a lo mismo, sin embargo, es posible que queramos habilitar otro método de autenticación desde nuestro como por ejemplo AppAuth, en cuyo caso el path sería por ejemplo `auth/eljavatar_k8s/app-auth`).

- **Políticas:** Las políticas no se identifican mediante un path, sino con un nombre, así que para identificar fácilmente las políticas que se aplican a un ambiente en particular, al momento de crearlas lo haremos siguiendo el formato `{TARGET_ENVIRONMENT}-{PERMISSION}-{POLICY_NAME}`. De este modo, si queremos crear una Política de lectura global podríamos asignar un nombre como por ejemplo `eljavatar_k8s-read-global`.

No quiere decir que siempre se deba usar una estructura como ésta, ya que todo va a depender del propósito que le queremos dar a Vault (ya que no necesariamente sirve solo para proveer secretos a un clúster de kubernetes), así como posibles políticas empresariales. Sin embargo en mi caso esta estructura me va bien dentro de este Homelab, ya que si por ejemplo quisiera montar un Home Assistant para manejar domótica en mi casa, podría crear un motor de secretos por ejemplo en el path `secret/domotica/kv-v2`, o si quiero tener algo más genérico y que no sea para algún `TARGET_ENVIRONMENT` en específico, podría tener algo como `secret/global/kv-v2`.

#### Estructura de paths para los Secretos

Ya definimos cómo va a ser la estructura de paths que usaremos al momento de crear los Motores de secretos; ahora definiremos la estructura para los secretos en sí. No existen reglas estrictas que nos digan cómo debemos especificar los paths para los secretos, sin embargo, tener una estructura bien definida desde el principio nos ayudará no solo a darle un orden a nuestros secretos, sino que como veremos más adelante, nos será de gran utilidad al momento de crear las políticas en Vault.

Lo primero que tuve en cuenta fue definir el tipo de aplicaciones y servicios que voy a desplegar en mi clúster de Kubernetes:

- **Aplicaciones/Servicios globales:** Aplicaciones como por ejemplo Grafana, SeaweedFS, Keycloack, etc.
- **APlicaciones/Servicios por dominio:** Aplicaciones de backend en diversos lenguajes, las cuales tendrán cada una su propia DB.

Esto me permite organizar mis aplicaciones y servicios por dominio, donde cada dominio tendrá su correpondiente namespace. De este modo, en mi clúster podré tener namespaces como los siguientes:

- **`observability`:** Contendría los despliegues de Grafana, OpenObserve, VictoriaMetrics.
- **`storage`:** Contendría los despliegues de SeaweedFS.
- **`iam`:** Contendría los despliegues de Keycloack.
- **`domain-a`:** Contendría los despliegues de la aplicación A (por ejemplo en Go), las bases de datos correspondientes a la apliación A (postgres, mongo, etc.) y demás elementos relacionados solo con la aplicación A.
- **`domain-b`:** Contendría los despliegues de la aplicación B (por ejemplo en Java), las bases de datos correspondientes a la apliación B (postgres, mongo, etc.) y demás elementos relacionados solo con la aplicación B.

De este modo, puedo darle la misma estructura a los paths de secretos en Vault de tipo *KV-v2* siguiendo el formato `{NAMESPACE}/{APP_OR_SERVICE}`:

- **Secret Engine `secret/eljavatar_k8s/kv-v2/`:** Como es KV versión 2, la forma de acceder a estos secretos es mediante `secret/eljavatar_k8s/kv-v2/data/{SUBPATH_SECRET}`, donde `{SUBPATH_SECRET}` podría tener valores como los siguientes:
  - `observability/grafana`
  - `observability/open-observe`
  - `iam/keycloack`
  - `domain-a/golang-app`
  - `domain-b/java-app`

Para el caso de los secretos en Vault de tipo *database* cambia un poco el enfoque, ya que a estos se les debe configurar primero la conexión a la respectiva base de datos usando un path tipo `secret/eljavatar_k8s/database/config/{DB_CONFIG_NAME}` y luego un rol que define qué permisos tendrá el usuario temporal que Vault creará dentro de la base de datos usando un path tipo `secret/eljavatar_k8s/database/roles/{ROLE_CONFIG_NAME}` (no confundir con el rol con el que nos autenticamos en Vault).

Así pues, para el caso de `DB_CONFIG_NAME` seguiré el formato `{NAMESPACE}-{DB_NAME}` (donde `DB_NAME` podría ser el nombre de la base de datos o el nombre del Pod con el que se despliega dicha base de datos), y para el caso de `ROLE_CONFIG_NAME` seguiré el formato `{NAMESPACE}-{SA_NAME}` (donde `SA_NAME` sería la ServiceAccount que se usaría para la autenticación ante Vault).

De este modo, como la forma de acceder a un secreto dentro de un Motor Engine de tipo *database* es mediante el path `secret/eljavatar_k8s/database/creds/{ROLE_CONFIG_NAME}`, gracias al formato que definimos, dicho path terminaría siendo `secret/eljavatar_k8s/database/creds/{NAMESPACE}-{SA_NAME}`.


### Crear un Secret Engine de tipo Key-Value (KV-v2)

Por lo general, los secretos que vamos a utilizar van a ser contraseñas, API keys o tokens que no cambian con mucha frecuencia, y cuando lo hacen, cambian con una periodicidad relativamente larga (3 meses, 6 meses, 1 año, etc.), lo cual hace que actualizarlos sea relativamente fácil. Por tanto, para la mayoría de casos vamos a querer usar secretos de tipo clave-valor.

Para crear este tipo de secretos, en primer lugar debemos habilitar el respectivo **Secret engine** de tipo KV en su versión 2 (que es la que nos permite almacenar varias versiones para un mismo conjunto de pares clave-valor).

Por defecto, cuando instalamos HashiCorp Vault, el **Secret engine** de KV v2 no viene habilitado, ya que si ejecutamos `vault secrets list` obtendremos algo como lo siguiente:

```
Path               Type              Accessor                   Description
----               ----              --------                   -----------
agent-registry/    agent_registry    agent-registry_28ece387    agent registry
cubbyhole/         cubbyhole         cubbyhole_51607e5f         per-token private secret storage
identity/          identity          identity_7b8a7db5          identity store
sys/               system            system_a8a1c6bd            system endpoints used for control, policy and debugging
```

Así que lo que hacemos es crear un nuevo almacen habilitando el motor de KV v2 mediante el siguiente comando:

```sh
# Con este comando indicamos que se cree el almacén 'secret/eljavatar_k8s/kv-v2' usando el motor 'kv-v2'
# Si no especificamos el parámetro '-path', el almacén se crearía en la ruta predeterminada 'kv-v2'
vault secrets enable -path=secret/eljavatar_k8s/kv-v2 kv-v2
```

Ahora, si ejecutamos de nuevo `vault secrets list`, obtendremos algo como lo siguiente:

```
Path                           Type              Accessor                   Description
----                           ----              --------                   -----------
agent-registry/                agent_registry    agent-registry_28ece387    agent registry
cubbyhole/                     cubbyhole         cubbyhole_51607e5f         per-token private secret storage
identity/                      identity          identity_7b8a7db5          identity store
secret/eljavatar_k8s/kv-v2/    kv                kv_f5c6dfbc                n/a
sys/                           system            system_a8a1c6bd            system endpoints used for control, policy and debugging
```

Podríamos tener varios Secrets engine de tipo KV v2, lo cual sería útil en escenarios como los siguientes:

- Si tenemos varios clústeres de Kubernetes y no queremos que se mezclen entre sí; más adelante veremos que usaremos las Service Accounts nativas de Kubernetes para autenticarnos desde el clúster hacia nuestras bóvedas de Vault y que a través de las policies podemos restringir qué secretos específico puede leer una aplicación, sin embargo, pueden haber casos donde tenemos varios clústeres heterogéneos (con propósitos totalmente distintos) y por tanto quisiéramos evitar que las aplicaciones puedan llegar a acceder a secretos que no les competen. 

- Si por ejemplo queremos tener contenedores que gestionan domótica en nuestra casa y no queremos que los secretos del clúster de kubernetes se mezclen con secretos del Home Assitant.

- Si por políticas estrictas de seguridad empresarial hay secretos a los que no todos los clústeres o aplicaciones pueden acceder.

- Si necesitamos tener secretos con configuraciones heterogéneas, por ejemplo, secretos que puedan tener un historial de máximo 3 versiones, y otros con 10 versiones de historial.


### Configurar Cantidad Máxima de Versiones y TTL de Versiones Viejas

Como veremos más adelante, cada vez que se agrega, modifica o elimina un par clave-valor de un secreto, se crea una copia que representa la nueva versión. De este modo, eventualmente podríamos llegar a tener muchas versiones de un mismo secreto, lo cual consume recursos.

Además, es posible que por políticas de seguridad necesitemos restringir la cantidad de versiones a una cantidad determinada, o que incluso queramos que las versiones anteriores tengan un tiempo máximo de vida después de que dejaron de ser la "current version".

Antes de proceder a realizar estos ajustes, veamos la configuración actual, y para esto ejecutamos `vault read secret/eljavatar_k8s/kv-v2/config`, lo cual nos arrojará algo como lo siguiente:

```
Key                     Value
---                     -----
cas_required            false
delete_version_after    0s
max_versions            0
```

Como se puede apreciar, el valor `delete_version_after` es `0s`, lo que significa que todas las versiones vivirán infinitamente, y por otro lado, el valor de `max_versions` es `0`, lo cual indica que se guardarán la cantidad de versiones por defecto que son `10`.

Estas configuraciones por defecto podrían estar bien en la mayoría de los casos, sin embargo, en nuestro caso vamos a querer que la cantidad máxima de versiones sea `5`, y que el tiempo máximo de vida de las versiones anteriores sea por ejemplo de 6 meses (`4380h`).

**¿Cómo funciona el TTL de la config `delete_version_after`?:** La versión actual (más reciente) tiene un TTL infinito, pero en cuanto es superada por una nueva versión (convirtiéndose en una "versión anterior"), comienza a correr un cronómetro con el tiempo que se le configure. Al cumplirse ese plazo, Vault le aplica un *soft-delete* (borrado suave) automático. Tenemos dos opciones para aplicar esta configuración:

- **Aplicarla a TODO el Secret Engine (Global):** En nuestro caso, si quisieramos aplicársela por ejemplo al motor `secret/eljavatar_k8s/kv-v2`, tendríamos que ejecutar `vault write secret/eljavatar_k8s/kv-v2/config delete_version_after="4380h"`.
- **Aplicarla solo a un secreto en específico (Por Metadata):** En este caso, si quisiéramos aplicársela por ejemplo al secreto `demo`, tendríamos que ejecutar `vault kv metadata put -delete-version-after="4380h" secret/eljavatar_k8s/kv-v2/demo`.

Una consideración importante a tener en cuenta es que como se hace un borrado suave (soft-delete), Vault no destruye los datos de inmediato de forma física, sino que los marca con una propiedad `deletion_time`, lo cual hace que la versión vieja ya no sea accesible para las aplicaciones mediante un comando regular de lectura. Aún así, en los registros de auditoría y metadatos seguirá constando que la versión existió y cuándo fue eliminada.

Si por políticas estrictas de cumplimiento se requiere que los datos de versiones anteriores desaparezcan por completo del almacenamiento físico (nuestra base de datos de Raft) después de cumplir el TTL, la purga automática por TTL no bastará (ya que permite un `undelete`). En ese escenario necesitaríamos programar un script externo (por ejemplo un CronJob) que consulte las versiones viejas y ejecute un `vault kv destroy -versions=X` para eliminarlas permanentemente.

En nuestro caso, queremos aplicar la configuración a todo el Secret Engine, y por el momento, no nos interesa que se haga una eliminación destructiva y permanente, así que simplemente ejecutamos lo siguiente:

```sh
vault write secret/eljavatar_k8s/kv-v2/config \
    max_versions=5 \
    delete_version_after="4380h"
```

Ahora, si ejecutamos de nuevo `vault read secret/eljavatar_k8s/kv-v2/config`, tendremos una salida como la siguiente:

```
Key                     Value
---                     -----
cas_required            false
delete_version_after    4380h0m0s
max_versions            5
```


### Crear un Secret de tipo Key-Value (KV-v2)

En el paso anterior habilitamos un motor de secretos de tipo Key-Value versión 2, ahora veremos un ejemplo de cómo crear un secreto.

Antes de proceder a crearlo, hay que entender que para Vault un secreto de tipo KV-v2 es un conjunto de pares clave-valor (key-values) que pueden tener varias versiones, es decir, el versionado no se aplica a un único par, sino a todo el conjunto que componen dicho secreto. Para tenerlo más claro, veamos el siguiente ejemplo.

Supongamos que dentro del Secret engine `secret/eljavatar_k8s/kv-v2` vamos a crear el secreto `demo` (aquí no voy a seguir la estructura de paths que definí anteriormente ya que es solo un ejemplo de demostración), y a éste le vamos a agregar inicialmente el par clave-valor `username=test`:

- Entonces, la versión 1 del secreto `secret/eljavatar_k8s/kv-v2/demo` será `[username=test]`.
- Ahora, si le agregamos el par clave-valor `password=test123` la versión 2 del secreto `secret/eljavatar_k8s/kv-v2/demo` será `[username=test, password=test123]`.
- Ahora, si modificamos el par `password=test987` la versión 3 del secreto `secret/eljavatar_k8s/kv-v2/demo` será `[username=test, password=test987]`.

Esto quiere decir que cada cambio de pares clave-valor que hagamos dentro de un secreto (ya sean creaciones, modificaciones o eliminaciones), se creará una nueva versión del secreto que no es más que una copia que se crea a partir de la versión anterior y mezclando los nuevos cambios.

Ahora, veamos entonces cómo configurar un secreto (por ejemplo `demo`) dentro de nuestro secret engine `secret/eljavatar_k8s/kv-v2`, agregándole un par clave-valor:

```sh
# La forma de crear el secret dento del secret engine es concatenándolo al path del respectivo secret engine:
vault kv put secret/eljavatar_k8s/kv-v2/demo TEST_USERNAME=test
```

Y si ejecutamos `vault kv get secret/eljavatar_k8s/kv-v2/demo` obtendremos algo como lo siguiente, donde se evidencia la versión de nuestro secreto y el par clave-valor que hemos configurado:

```
============ Secret Path ============
secret/eljavatar_k8s/kv-v2/data/demo

======= Metadata =======
Key                Value
---                -----
created_time       2026-09-08T12:22:55.007488108Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1

======== Data ========
Key              Value
---              -----
TEST_USERNAME    test
```

Ahora agreguemos un nuevo par clave-valor a nuestro secreto:

```sh
vault kv patch secret/eljavatar_k8s/kv-v2/demo TEST_PASSWORD=test123
```

Como se puede apreciar, en este caso usamos `vault kv patch` en vez de `vault kv put`, y esto se debe a que si usamos `put`, Vault crearía una nueva versión únicamente con los pares clave-valor que le indiquemos, es decir, en este caso por ejemplo, la versión 2 solo hubiera quedado con la key `TEST_PASSWORD`. Para que la nueva versión contuviera también los pares de la versión 1 usando `put`, hubiéramos tenido que pasárselos además de los nuevos de la versión 2 (`vault kv put secret/eljavatar_k8s/kv-v2/demo TEST_USERNAME=test TEST_PASSWORD=test123`), lo cual se vuelve inmanejable a medida que la cantidad de keys aumenta. Por esta razón, después de crear el secreto con su primer par clave-valor lo ideal es seguir usando `patch`.

Ahora, si ejecutamos de nuevo `vault kv get secret/eljavatar_k8s/kv-v2/demo` podemos evidenciar el cambio de versión y el nuevo par clave-valor que agregamos:

```
============ Secret Path ============
secret/eljavatar_k8s/kv-v2/data/demo

======= Metadata =======
Key                Value
---                -----
created_time       2026-09-08T12:23:40.039329594Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            2

======== Data ========
Key              Value
---              -----
TEST_PASSWORD    test123
TEST_USERNAME    test
```

Ahora hagamos un cambio a una de las keys:

```sh
vault kv patch secret/eljavatar_k8s/kv-v2/demo TEST_PASSWORD=test927
```

Y si ejecutamos de nuevo `vault kv get secret/eljavatar_k8s/kv-v2/demo` podemos evidenciar el cambio de versión y el cambio de valor para la key `TEST_PASSWORD`:

```
============ Secret Path ============
secret/eljavatar_k8s/kv-v2/data/demo

======= Metadata =======
Key                Value
---                -----
created_time       2026-09-08T12:24:06.576016078Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            3

======== Data ========
Key              Value
---              -----
TEST_PASSWORD    test927
TEST_USERNAME    test
```

Podríamos ver también un histórico de las versiones a través de la metadata al ejecutar `vault kv metadata get -mount="secret/eljavatar_k8s/kv-v2" "demo"`. Existen otras varias acciones que podemos ejecutar sobre nuestros secretos las cuales podemos consultar ejecutando `vault kv --help` o directamente en la [documentación](https://developer.hashicorp.com/vault/docs/commands/kv) de Vault.


### Crear un Secret Engine de tipo Database

Los motores de secretos de tipo *database* los usaremos eventualmente para configurar credenciales de bases de datos que roten dinámicamente cada vez que se solicitan, así que crearemos este tipo de almacén de una vez ejecutando lo siguiente:

```sh
vault secrets enable -path=secret/eljavatar_k8s/database database
```

Ahora, si ejecutamos de nuevo `vault secrets list`, obtendremos algo como lo siguiente donde se evidencia que se creó el nuevo motor de secretos:

```
Path                              Type              Accessor                   Description
----                              ----              --------                   -----------
agent-registry/                   agent_registry    agent-registry_28ece387    agent registry
cubbyhole/                        cubbyhole         cubbyhole_51607e5f         per-token private secret storage
identity/                         identity          identity_7b8a7db5          identity store
secret/eljavatar_k8s/database/    database          database_8b35fb0b          n/a
secret/eljavatar_k8s/kv-v2/       kv                kv_f5c6dfbc                n/a
sys/                              system            system_a8a1c6bd            system endpoints used for control, policy and debugging
```


### Configurar la Autenticación para nuestro Clúster de Kubernetes

En pasos anteriores ejecutamos comandos como por ejemplo `vault kv put` y `vault kv get` (entre otros) que nos permiten gestionar secretos (listar, crear, obtener, actualizar, etc.), pero para eso, previamente tuvimos que loguearnos (en este caso, usando un token).

Para que nuestras aplicaciones y servicios puedan leer secretos de nuestra bóveda (más específicamente nuestros operadores de ESO y VSO), también tienen que autenticarse ante Vault, y para esto contamos con varios métodos, como por ejemplo con *Token* (diferente al `root token`), con *AppRole* y con *Kubernetes* (solo por mencionar algunos).

En nuestro caso tenemos planeado que todo corra dentro del clúster de Kubernetes, por tanto usaremos dicho método ya que aprovecha la identidad nativa de Kubernetes de modo tal que cada aplicación utiliza su propia `ServiceAccount` como control de acceso; de esta manera, Vault se comunica con la API de Kubernetes para verificar que el token de esa `ServiceAccount` sea válido y perteneza al Pod correcto. Además, la gestión de identidad se da de forma automática y nativa, lo que nos exime de tener que gestionar o distribuir credenciales adicionales como sí tendríamos que hacerlo en el caso por ejemplo de los métodos Token y AppRole (`Token` / `RoleID` - `SecretID`); por otro lado, es Kubernetes quien se encarga de rotar y entregar los tokens a los Pods.

_**Nota:** Si en algún momento llegamos a requerir que una aplicación o servicio corra por fuera del clúster de Kubernetes (AWS EC2, Azure VMs, VMs ó LXC sobre Proxmox, servidores on-premise, etc.) o requerimos usar herramientas de CI/CD (como Jenkins o GitLab CI) fuera de Kubernetes que necesiten autenticarse contra Vault, ahí sí sería conveniente contemplar el uso del método AppRole.*_

Para configurar la autenticación mediante el método de kubernetes, debemos seguir los siguientes pasos:

#### 1. Habilitar el método de autenticación `kubernetes`

Lo primero que haremos será habilitar el método de autenticación `kubernetes`, y al igual que hicimos cuando habilitamos el secret engine, le indicaremos el `path`, que en este caso será `eljavatar_k8s/kubernetes`, ya que en caso de no hacerlo se crearía en la ruta por defecto que sería 'kubernetes'.

```sh
vault auth enable -path=eljavatar_k8s/kubernetes kubernetes
```

Ahora, si ejecutamos de nuevo `vault auth list`, obtendremos algo como lo siguiente:

```
Path                         Type          Accessor                    Description                Version
----                         ----          --------                    -----------                -------
eljavatar_k8s/kubernetes/    kubernetes    auth_kubernetes_e9ae8723    n/a                        n/a
token/                       token         auth_token_1ee38c99         token based credentials    n/a
```

#### 2. Crear la `ServiceAccount` del Revisor de Tokens en el clúster de Kubernetes

En el modelo tradicional de Vault, cada aplicación dentro de nuesro clúster (PostgreSQL, MongoDB, Keycloak Grafana, apps, etc.) debe tener su propia `ServiceAccount`, la cual se suele crear en el mismo namespace en el que va a correr su aplicación correspondiente. Esto se suele hacer por el *Principio de Menor Privilegio* ya que si usaramos la misma cuenta para todo, la app del Frontend podría pedir las contraseñas de la base de datos de PostgreSQL, o Keycloak podría leer los secretos de observabilidad. Al separar las cuentas, limitamos estrictamente qué secretos puede pedir cada Pod (aunque debido a que vamos a usar ESO y VSO, la arquitectura cambia y son los operadores quienes solicitan los secretos, así que por lo general, vamos a requerir una ServiceAccount por cada namespace (en lugar de una por cada aplicación)).

De este modo, cuando los operadores se autentican ante Vault lo hacen enviando un token JWT que contiene información de una ServiceAccount y el namespace al que pertenece (más adelante veremos cómo se da este flujo de autenticación tanto en ESO como en VSO). Pero, ¿cómo sabe Vault que ese JWT con el que se está intentando autenticar el operador es correcto?

Para esto debemos crear una `ServiceAccount` (en un namespace genérico, como por ejemplo uno dedicado a la gestión de identidad/autenticación con el mundo exterior) que actuará como Revisor del Token (el cual es de larga duración y debemos setear en la configuración en Vault en los próximos pasos), y su único trabajo es permitir que Vault le pregunte a la API de Kubernetes: "*Oye, ¿este token que me acaba de llegar es válido?*".

Este proceso lo realizamos en la [configuración de nuestro clúster de Kubernetes](README.md#creaci%C3%B3n-de-la-serviceaccount-para-el-revisor-de-tokens-en-vault), sin embargo, a continuación muestro el manifiesto que usamos para crear la `ServiceAccount` del revisor y su respectivo token:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-token-reviewer-sa
  namespace: external-auth
---
# Este binding (con el rol system:auth-delegator) le permite a Vault delegar la autenticación mediante un POST
# al recurso 'tokenreviews.authentication.k8s.io' para validar si el token es real y está activo.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer-auth-binding
subjects:
  - kind: ServiceAccount
    name: vault-token-reviewer-sa
    namespace: external-auth
roleRef:
  kind: ClusterRole
  name: system:auth-delegator # Apunta al rol que permite validar Tokens
  apiGroup: rbac.authorization.k8s.io
---
# En la configuración del método de autenticación de Vault podemos configurar el flag 'use_annotations_as_alias_metadata=true',
# lo cual nos permite usar el parámetro {{identity.entity.aliases.<mount accessor>.metadata.<metadata key>}},
# de modo tal que el valor de '<metadata key>' lo extraería de la anotación 'vault.hashicorp.com/alias-metadata-<metadata key>'
# que configuremos en la ServiceAccount que usemos para autenticarnos (no confundir con la ServiceAccount del
# revisor 'vault-token-reviewer-sa').
# https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies
# 
# Sin embargo, como se menciona en la documentación, al activar 'use_annotations_as_alias_metadata=true',
# Vault necesita permiso explícito para leer (hacer get) las Service Accounts del clúster de Kubernetes.
# De lo contrario, no podrá extraer las anotaciones cuando el Pod intente autenticarse.
# 
# Para resolver esto, creamos un ClusterRole (o Role) que estará dedicado a la lectura de metadatos, y lo
# enlazamos a la misma cuenta de servicio que usará el revisor de tokens (vault-auth-reviewer-sa) mediante
# un ClusterRoleBinding adicional.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-token-reviewer-metadata-role
rules:
  - apiGroups: [""]
    resources: ["serviceaccounts"]
    # Vault necesita obligatoriamente 'get' y 'list' para inspeccionar las anotaciones
    verbs: ["get", "list"]
---
# Este binding (con el rol vault-auth-reviewer-metadata-role) le permite a Vault preguntar por las anotaciones
# 'vault.hashicorp.com/alias-metadata-<metadata key>' de la ServiceAccount usada para la autenticación.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-token-reviewer-metadata-binding
subjects:
  - kind: ServiceAccount
    name: vault-token-reviewer-sa
    namespace: external-auth
roleRef:
  kind: ClusterRole
  name: vault-token-reviewer-metadata-role # Apunta al rol de lectura de SA
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-token-reviewer-secret
  namespace: external-auth
  annotations:
    # Dado que desde Kubernetes 1.24+ las Service Accounts ya no generan automáticamente un secreto con su token,
    # crearlo explícitamente con la anotación kubernetes.io/service-account.name es el paso exacto requerido en
    # clústeres modernos como Talos.
    kubernetes.io/service-account.name: vault-token-reviewer-sa
type: kubernetes.io/service-account-token
```

#### 3. Extraer datos para configurar la autenticación en Vault

Desde nuestra máquina local, ejecutamos los siguientes comandos usando `kubectl` para extraer los datos necesarios para configurar el endpoint de Kubernetes en Vault (estos pasos requieren que previamente ya hayamos levantado y configurado nuestro clúster de Kubernetes):

```sh
# Obtener la URL de la API de Kubernetes (En nuestro caso: https://192.168.0.30:6443)
K8S_HOST=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Obtener el token del revisor
K8S_TOKEN=$(kubectl get secret vault-token-reviewer-secret -n external-auth -o jsonpath='{.data.token}' | base64 --decode)

# Obtener el certificado CA del clúster
K8S_CA=$(kubectl get secret vault-token-reviewer-secret -n external-auth -o jsonpath='{.data.ca\.crt}' | base64 --decode)
```

Aquí cobra un poco más de sentido el paso anterior que realizamos cuando [configuramos la CLI de Vault en nuestra máquina local](#configurar-la-cli-en-la-m%C3%A1quina-local), ya que de lo contrario tendríamos que ejecutar un `echo` por cada uno de estos valores (`K8S_HOST`, `K8S_TOKEN`, `K8S_CA`), copiar las salidas, y luego pegarlas en el comando del siguiente paso para posteriormente ejecutarlo en la Console del LXC desde la interfaz de Proxmox. En contraste, en nuestro caso podemos seguir ejecutando todo desde la misma terminal de nuestra máquina local.

#### 4. Escribir la configuración de autenticación en Vault

Ahora que tenemos los datos almacenados en las variables `K8S_HOST`, `K8S_TOKEN` y `K8S_CA` dentro de la sesión de nuestra terminal, podemos configurar el endpoint de nuestro método de autenticación de tipo *kubernetes* en Vault ejecutando el siguiente comando:

```sh
vault write auth/eljavatar_k8s/kubernetes/config \
    use_annotations_as_alias_metadata=true \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CA" \
    token_reviewer_jwt="$K8S_TOKEN"
```

Si ejecutamos `vault read auth/eljavatar_k8s/kubernetes/config` podemos ver que nuestro método de autenticación ya quedó configurado con los datos de nuestro clúster de kubernetes.

En muchos tutoriales no se suele mencionar el uso del parámetro `use_annotations_as_alias_metadata=true` al hacer esta configuración, sin embargo, en nuestro caso probablemente crearemos Service Accounts con anotaciones `vault.hashicorp.com/alias-metadata-<metadata key>` que nos permitirán definir [templated policies](https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies) usando parámetros personalizados, por eso habilitamos también este parámetro.

En próximos pasos veremos que a las Service Accounts que creemos para nuestras aplicaciones o servicios debemos crearles un rol en Vault y asignarle políticas de permisos. Sin embargo, antes de continuar creo que es pertinente hacer una aclaración. Para el caso de la ServiceAccount `vault-auth-reviewer-sa` que vimos en el paso anterior, no debemos crearle ninguna política (`policy`) ni ningún rol (`role`) dentro de Vault por las siguientes razones:

- **Su único propósito es la validación técnica:** El token de esta ServiceAccount (`token_reviewer_jwt`) solo se usa en el paso `vault write auth/eljavatar_k8s/kubernetes/config`. Vault guarda este token de manera interna y lo utiliza exclusivamente como una "llave maestra de lectura" para comunicarse con la API de Kubernetes (`TokenReview`).

- **No inicia sesión en Vault:** Esta cuenta jamás ejecutará un comando `vault login` ni pedirá un token de Vault.

- **Las políticas son para los clientes:** En Vault, las políticas se asignan a las entidades que **consumen** secretos (como el Pod de una aplicación o el Pod de ESO, o el de VSO). Como el revisor no consume secretos, no necesita permisos en los paths de datos (por ejemplo `secret/*` o el que hayamos definido).


### Relación entre Service Accounts (de Kubernetes), Policies y Roles (de Vault)

Antes de continuar con las siguientes secciones, creo que es pertinente entender cómo se relacionan las Service Accounts que debemos crear en nuestro clúster de Kubernetes, con las políticas y roles que definimos en Vault, ya que estos son los elementos que usaremos para llevar a cabo el proceso de autenticación (desde el clúster hacia Vault) y de autorización a recursos en Vault:

- Una `ServiceAccount` se crea en el clúster de Kubernetes para autenticarse ante Vault, ya sea mediante un `ClusterSecretStore` o un `SecretStore` (usando el bloque `serviceAccountRef` y también indicando el rol que usará en Vault) para el caso de ESO, o un `VaultAuth` para el caso de VSO.

- Una `policy` en Vault se crea para especificar permisos sobre un recurso (por lo general, las creamos para dar permisos de lectura a Secretos, pero no se limitan solo a este tipo de permisos).

- Un `role` se crea dentro de un método de autenticación (en nuestro caso, uno de tipo *kubernetes*), y a través de este es que asociamos las Service Accounts de Kubernetes con las políticas de Vault, es decir, los roles son los que hacen el engranaje que nos indican a qué recursos puede acceder una ServiceAccount.

Veamos un ejemplo (aquí solo mencionaré la secuencia de pasos, ya que en las siguientes secciones entraré más en detalle sobre cómo se crean/configuran cada uno de estos elementos):

Supongamos que tenemos un secreto `wallet-service/wallet-java-app` dentro del Motor de secretos `secret/eljavatar_k8s/kv-v2/`, y queremos que una ServiceAccount llamada `wallet-java-app-sa` dentro del namespace `wallet-service`, al autenticarse pueda leer este secreto. Para esto, seguiríamos el siguiente proceso (que ejemplificaremos usando ESO):

1. En el clúster de Kubernetes, creamos una ServiceAccount sencilla con nombre `wallet-java-app-sa` dentro del namespace `wallet-service`.

2. En el clúster de Kubernetes, definimos un recurso de tipo `SecretStore` que se llamará por ejemplo `vault-auth-eljavatar-k8s-kv-v2-wallet-java-app` también dentro del namespace `wallet-service` (ya que por diseño y por razones de seguridad en ESO, un SecretStore es un recurso de alcance de namespace (namespaced) y solo puede hacer referencia a una ServiceAccount que se encuentre en su mismo namespace) y, configuramos el bloque `serviceAccountRef` para que apunte a la ServiceAccount `wallet-java-app-sa` (el namespace no se configuraría en este caso ya que sería el mismo donde se crea el `SecretStore`). Además, en el `SecretStore` indicamos también el nombre del rol que se le asignará en Vault (supongamos que será `wallet-java-app-role`) y la audiencia (`vault`).

3. En Vault, creamos una política llamada `eljavatar_k8s-read-wallet_java_app`, en la cual definimos permisos de lectura (`read`) sobre el path `secret/eljavatar_k8s/kv-v2/data/wallet-service/wallet-java-app`.

4. En Vault, creamos el role `wallet-java-app-role` (el cual debe ser el mismo que indicamos en el `SecretStore`) dentro del método de autenticación `eljavatar_k8s/kubernetes` (`auth/eljavatar_k8s/kubernetes/role/wallet-java-app-role`) con las propiedades `bound_service_account_names=wallet-java-app-sa` (el nombre de la ServiceAccount que creamos previamente), `bound_service_account_namespaces=wallet-service` (el nombre del namespace dentro del cual se creó la ServiceAccount), `token_policies=eljavatar_k8s-read-wallet_java_app` (la política que definimos y creamos en el paso anterior) y `audience=vault` (debe ser la misma que indicamos en el en `SecretStore`).

De este modo, cuando configuremos por ejemplo un recurso `ExternalSecret` (de ESO) apuntando al `SecretStore` llamado `vault-auth-eljavatar-k8s-kv-v2-wallet-java-app`, el flujo de autenticación y autorización se da dería de la siguiente forma:

1. Para autenticarse, ESO usará el JWT generado para la ServiceAccount `wallet-java-app-sa` ([aquí](#autenticación-desde-kubernetes-usando-eso) explicamos el flujo que permite la generación de este token en ESO), y el Revisor en Vault que configuramos para el método de autenticación `eljavatar_k8s/kubernetes` se encargará de validar que es un token de acceso correcto.

2. Estando autenticado, en Vault se busca que el rol `wallet-java-app-role` que definimos en el `SecretStore` exista en la lista de roles configurados para el método de autenticación `eljavatar_k8s/kubernetes`.

3. Al corroborar que el rol existe, Vault valida si en su lista de Service Accounts y de namespaces permitidos, se encuentra la ServiceAccount `wallet-java-app-sa` y el namespace `wallet-service`.

4. Finalmente, Vault valida en la lista de políticas del rol si existe una que permite el acceso al secreto (o secretos) que se indique en los campos `remoteRef.key` del `ExternalSecret` (que para este ejemplo sería `wallet-service/wallet-java-app`).


### Configurar Políticas de Permisos

Las políticas en Vault definen a qué paths de secretos se tiene acceso y qué acciones se pueden hacer (`read`, `write`, etc.), y como pudimos apreciar anteriormente cuando creamos la política del usuario administrador, se escriben en formato HCL (HashiCorp Configuration Language).

Definir políticas es sencillo ya que por lo general, solo necesitamos especificar 2 cosas: el recurso (`path`) al cual se le aplicará la política y la lista de permisos que se habilitarán sobre dicho recurso. Los permisos que podríamos asignar son los siguientes: `create`, `read`, `update`, `delete`, `list`, `patch`. Además, en una misma política podríamos definir permisos para más de un recurso.

Veamos un ejemplo sobre cómo definir una política (en [este enlace](https://developer.hashicorp.com/vault/docs/concepts/policies#fine-grained-control) podemos ver más ejemplos de la sintaxis para definir políticas):

```hcl
# No he creado el secreto 'secret/eljavatar_k8s/kv-v2/wallet-service/wallet-java-app', solo lo pongo aquí como ejemplo
path "secret/eljavatar_k8s/kv-v2/data/wallet-service/wallet-java-app" {
  capabilities = ["read"]
}

# Opcional: Permitir listar el contenido de la raíz de ese secret engine (por ejemplo para debugging de ESO)
path "secret/eljavatar_k8s/kv-v2/metadata/wallet-service/wallet-java-app" {
  capabilities = ["list"]
}
```

Ahora, para escribir nuestra política en vault podríamos hacerlo utilizando un bloque `EOF` en la terminal, sin embargo, en lo personal prefiero crear un archivo `.hcl` y posteriormente invocarlo. Supongamos entonces que guardamos la anterior política en el archivo `vault/policies/eljavatar_k8s-read-wallet_java_app.yaml`, así pues, para escribir esta política en vault lo haríamos ejecutando por ejemplo lo siguiente:

```sh
vault policy write eljavatar_k8s-read-wallet_java_app vault/policies/eljavatar_k8s-read-wallet_java_app.yaml
```

**El problema de la Proliferación de Políticas**

Como acabamos de ver, las políticas se definen por cada recurso al cual le queremos otorgar determinados permisos. Sin embargo, esto puede llevar a que eventualmente tengamos que estar creando muchas políticas (por lo general, una por cada rol).

Sin embargo, recordemos que previamente habíamos definido una [estructura de paths estandarizada](#estructura-de-paths-para-los-secretos) para nuestros secretos, los cuales tendrán el formato `{NAMESPACE}/{APP_OR_SERVICE}` (incluso en la [documentación de Vault](https://developer.hashicorp.com/vault/tutorials/policies/policy-templates-kubernetes#establish-naming-conventions) recomiendan establecer convenciones de nombres para simplificar la gestión de políticas).

De este modo, podremos hacer uso de las [Templated policies](https://developer.hashicorp.com/vault/docs/concepts/policies#templated-policies) de Vault para definir políticas dinámicas que podamos reutilizar en cada rol que creemos. Para esto podemos usar diversos parámeros en el path de la política (`{{<parameter>}}`), los cuales serían reemplazados dinámicamente por valores extraídos del token de autenticación.

Vault nos dispone de varios parámetros, sin embargo, hay principalmente 2 de ellos que se alinean perfectamente con las convenciones de nomenclatura que especificamos anteriormente:

- **`{{identity.entity.aliases.<mount accessor>.metadata.service_account_namespace}}`:** Se reemplaza dinámicamente por el namespace de Kubernetes donde se encuentra la ServiceAccount que se especifica en el `SecretStore` (o `ClusterSecretStore`) para el caso de ESO, o en el `VaultAuth` (o `VaultAuthGlobal`) para el caso de VSO.
- **`{{identity.entity.aliases.<mount accessor>.metadata.service_account_name}}`:** Se reemplaza dinámicamente por el nombre de la ServiceAccount que se especifica en el `SecretStore` (o `ClusterSecretStore`) para el caso de ESO, o en el `VaultAuth` (o `VaultAuthGlobal`) para el caso de VSO.

En ese orden de ideas, debemos seguir algunos pasos para poder definir políticas dinámicas.

#### 1. Obtener el Accessor del método de autenticación

Cada método de autenticación en Vault tiene un identificador único llamado accessor (si destruimos y recreamos el método de autenticación de Kubernetes en Vault, ese ID cambiará). Necesitamos este ID para construir la política dinámica, ya que ese es el valor que deberíamos reemplazar por `<mount accessor>` en los parámetros que vimos antes. En nuestro caso, el método de autenticación es `eljavatar_k8s/kubernetes/`, así que ejecutamos lo siguiente para obtener el accesor:

```sh
vault auth list -format=json | jq -r '.["eljavatar_k8s/kubernetes/"].accessor'
```

Supongamos que la salida arroja el valor `auth_kubernetes_1a2b3c4d`, de este modo, los parámetros a usar serían por ejemplo `{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_namespace}}` y `{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_name}}`.

#### 2. Crear las Políticas Dinámicas (Templates)

Para el caso de los secretos de tipo *kv-v2*, crearemos un archivo llamado `eljavatar_k8s-read-kv_v2_data_by_ns_tmpl.hcl` con el siguiente contenido (Esta política le dice a Vault: *"El portador de este token solo puede LEER secretos en el path que coincida exactamente con su namespace de Kubernetes"*):

```hcl
path "secret/eljavatar_k8s/kv-v2/data/{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_namespace}}/*" {
  capabilities = ["read"]
}
```

Y para escribirla en Vault, lo haríamos ejecutando lo siguiente:

```sh
vault policy write eljavatar_k8s-read-kv_v2_data_by_ns_tmpl vault/policies/eljavatar_k8s-read-kv_v2_data_by_ns_tmpl.hcl
```

Para el caso de las credenciales de un secreto de tipo *database*, crearemos un archivo llamado `eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl.hcl` con el siguiente contenido (también podría tener el formato `secret/eljavatar_k8s/database/creds/{NAMESPACE}-*` si no queremos que esté amarrada a la ServiceAccount):

```hcl
path "secret/eljavatar_k8s/database/creds/{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_namespace}}-{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_name}}" {
  capabilities = ["read"]
}
```

Y para escribirla en Vault, lo haríamos ejecutando lo siguiente:

```sh
vault policy write eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl vault/policies/eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl.hcl
```

Estas políticas deberían servirnos para la mayoría de los casos según la estructura de paths que definimos, sin embargo, si por alguna eventual razón necesitamos crear un secreto con una estructura de path distinta, podríamos crearle una política personalizada, o bien podríamos hacer uso de la anotación `vault.hashicorp.com/alias-metadata-<metadata key>` dentro de la ServiceAccount que usemos para hacer la autenticación.

En mi caso particular, voy a definir para `<metadata key>` el valor `env` (pero puede ser cualquiera), de modo tal que la anotación que tendría que usar sería `vault.hashicorp.com/alias-metadata-env`, con lo cual podría definir las siguientes políticas dinámicas (en la [documentación de Vault](https://developer.hashicorp.com/vault/docs/auth/kubernetes#working-with-templated-policies) podemos ver un ejemplo de cómo se debería crear la ServiceAccount):

- En el archivo `eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl.hcl`:
  ```hcl
  path "secret/eljavatar_k8s/kv-v2/data/{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.env}}" {
    capabilities = ["read"]
  }
  ```

- En el archivo `eljavatar_k8s-read-db_creds_by_custom_env_tmpl.hcl`:
  ```hcl
  path "secret/eljavatar_k8s/database/creds/{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.env}}" {
    capabilities = ["read"]
  }
  ```

Y para aplicarlas, ejecutaríamos:

```sh
vault policy write eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl vault/policies/eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl.hcl

vault policy write eljavatar_k8s-read-db_creds_by_custom_env_tmpl vault/policies/eljavatar_k8s-read-db_creds_by_custom_env_tmpl.hcl
```

Con esto ya tendríamos políticas con permisos de lectura para casi cualquier secreto de tipo `kv-v2` o `database`. Sin embargo, si se requiere, también podríamos crear políticas más específicas dependiendo el caso de uso. Además, si necesitamos usar otro tipo de Motor de secretos, podemos seguir estos mismos lineamientos para definir sus respectivas *templated policies*.


### Crear Roles para dar Acceso a los Secretos de Vault

Los roles son el componente que cierra el círculo de la autorización, ya que como mencionamos antes, es el que relaciona las Service Accounts de Kubernetes con las políticas qué definen a qué secretos puede acceder una ServiceAccount (las políticas definen también permisos sobre otros tipos de recursos en Vault, pero por lo general, las usamos para definir el acceso a secretos).

Para que ESO y VSO puedan pedir secretos, debemos crear el respectivo rol en Vault que vincule la ServiceAccount de Kubernetes que usamos para la autenticación, con una política de Vault.

La forma en que creamos un rol es ejecutando un código como el siguiente:

```sh
# En muchos tutoriales, las políticas las suelen especificar mediante el parámetro 'policies',
# sin embargo, la documentación indica que este parámetro está marcado como obsoleto y por ende
# se recomienda usar en su lugar 'token_policies'.
vault write auth/eljavatar_k8s/role/name-role \
    bound_service_account_names=app-sa \
    bound_service_account_namespaces=prod \
    token_policies=app-policy \
    audience=vault \
    ttl=1h
```

Por lo general, se suele crear un rol en Vault por cada ServiceAccount de Kubernetes, sin embargo, al igual que con las políticas, podemos definir roles dinámicos genéricos que nos puedan servir para todas nuestras Service Accounts de todos nuestros namespaces (esto debido a que las restricciones ya vendrán definidas mediante las políticas con plantillas).

Sin embargo, para que quede más claro el cómo se comportarían nuestras políticas dinámicas con estos roles genéricos, imaginemos que en nuestro clúster tenemos lo siguiente (para extraer secretos de almacenes tipo *database*, usaré el operador de VSO, por eso planeo tener una ServiceAccount por cada operador en cada namespace):

| Namespace | Aplicación | SA (by Namespace) | SA (by App) |
|-----------|------------|-------------------|-------------|
| **wallet-service** | wallet-java-app | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `wallet-java-app-sa`, `pg-wallet-db-creds-sa`  |
| **wallet-service** | pg-wallet-db    | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `pg-wallet-db-sa`                              |
| **report-service** | report-go-app   | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `report-go-app-sa`, `mongo-report-db-creds-sa` |
| **report-service** | mongo-report-db | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `mongo-report-db-sa`                           |

Ahora sí veamos cómo podríamos crear nuestros roles dinámicos en Vault, para lo cual veremos 2 opciones y a continuación analizaremos cómo impacta cada una según el escenario anterior (en mi caso optaré por la Opción 2 y en el análisis veremos el por qué):

```sh
# Opción 1: Todas las Service Accounts de todos los namespaces podrán leer los secretos definidos
# en las políticas indicadas en el parámetro 'token_policies'
vault write auth/eljavatar_k8s/kubernetes/role/global-dynamic-reading-role \
    bound_service_account_names="*" \
    bound_service_account_namespaces="*" \
    token_policies=eljavatar_k8s-read-kv_v2_data_by_ns_tmpl,eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl \
    audience=vault \
    ttl=1h

# Opción 2: Solo las Service Accounts vault-eso-auth-sa y vault-vso-auth-sa de cualquier namespace
# podrán leer los secretos definidos en las políticas indicadas en el parámetro 'token_policies'
vault write auth/eljavatar_k8s/kubernetes/role/global-dynamic-reading-role \
    bound_service_account_names="vault-eso-auth-sa,vault-vso-auth-sa" \
    bound_service_account_namespaces="*" \
    token_policies=eljavatar_k8s-read-kv_v2_data_by_ns_tmpl,eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl \
    audience=vault \
    ttl=1h
```

Al crear el rol con cualquiera de estas 2 opciones, si el operador ESO o el operador VSO se autentica usando la identidad ya sea de la ServiceAccount `vault-eso-auth-sa` o `vault-vso-auth-sa`, al hacerse efectiva la política y reemplazarsen los parámeros (`{{parameter}}`), tendríamos que los secretos a los que se puede acceder según el namespace donde se encuentre la ServiceAccount son los siguientes:

| Namespace Orígen | ServiceAccount | Secretos Permitidos |
|------------------|----------------|---------------------|
| **wallet-service** | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `secret/eljavatar_k8s/kv-v2/data/wallet-service/*`, `secret/eljavatar_k8s/database/creds/wallet-service-*` |
| **report-service** | `vault-eso-auth-sa`, `vault-vso-auth-sa` | `secret/eljavatar_k8s/kv-v2/data/report-service/*`, `secret/eljavatar_k8s/database/creds/report-service-*` |

Con esto vemos que las Templated Policies terminan siendo nuestro control de acceso y aislamiento, ya que según la forma en la que las definimos, si por ejemplo el operador de ESO intenta descargar datos del secreto `wallet-service/wallet-java-app` desde el namespace `report-service`, no podrá hacerlo, ya que el template le restringiría el acceso a sólo lo que coincida con el path `report-service/*`.

Sin embargo, como podemos apreciar, las Templated Policies que definimos restringen el acceso solo a nivel de namespace, y por lo general, esto va a ser suficiente para la mayoría de los casos, pero, ¿qué pasaría si por ejemplo no queremos que un secreto esté disponible si el operador (ya sea el de ESO o el de VSO) se autentica tomando la identidad de la ServiceAccount `wallet-java-app-sa` que se encuentra en el namespace `wallet-service`?

Aquí es donde la configuración del rol nos brindaría un segundo control de acceso, pero esta vez, a nivel de ServiceAccount; y es en este escenario en donde difieren las dos formas de crear el rol que vimos anteriormente.

Si bien gracias a la forma en que definimos las Templated Policies, al autenticarnos con cualquier ServiceAccount, por ejemplo del namespace `wallet-service`, podemos acceder a cualquier secreto con la estructura `wallet-service/*` (para KV-v2) y `wallet-service-*` (para database), es posible que no queramos permitir el acceso a dichos secretos si la autenticación no se hace tomando la identidad de una ServiceAccount creada sólo para ese propósito.

Con la opción 1, no podríamos segmentar el control de acceso por ServiceAccount, ya que la propiedad `bound_service_account_names="*"` indica que si se hace la autenticación con cualquiera de las Service Accounts del namespace `wallet-service` (`vault-eso-auth-sa`, `vault-vso-auth-sa`, `wallet-java-app-sa`, `pg-wallet-db-creds-sa`), se puede acceder sin problema a todos los secretos.

Así, que si queremos que el acceso esté permitido solo si la autenticación se hace por ejemplo con las Service Accounts `vault-eso-auth-sa` y `vault-vso-auth-sa` (siguiendo el principio de Menor Privilegio), deberíamos usar la opción 2. En caso de que tengamos otra ServiceAccount a la cual le queramos permitir el acceso, podríamos crear o bien otro rol o modificar este agregándole el nuevo valor en la propiedad `bound_service_account_names`.

Aún así, en todo caso tenemos la posibilidad de crear roles dedicados, ya que estos roles dinámicos no es que se apliquen automáticamente a todas las peticiones que se reciban apuntando a un secreto con el formato `{namespace}/*` (para los de tipo KV-v2) o `{namespace}-{serviceaccount}` (para los de tipo database), ya que como lo veremos más adelante, el modelo de autenticación de Vault exige que se envíe el rol, por tanto, las peticiones que hacen los operadores (tanto ESO como VSO) siempre deben indicar el rol que se usará para extraer un secreto de Vault.

Finalmente, en caso de que creemos secretos con un formato distinto, por ejemplo `secret/eljavatar_k8s/kv-v2/data/{CUSTOM_SECRET_NAME}` y `secret/eljavatar_k8s/database/creds/{CUSTOM_CREEDS_NAME}`, deberíamos crear roles asociando las políticas `eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl` o `eljavatar_k8s-read-db_creds_by_custom_env_tmpl` según sea el caso, pero al ser roles que permitirían el acceso a Service Accounts muy específicas, no creo que tenga sentido usar el wildcard `"*"`:

```sh
vault write auth/eljavatar_k8s/kubernetes/role/some-custom-role \
    bound_service_account_names="some-sa" \
    bound_service_account_namespaces="some-namespace" \
    token_policies=eljavatar_k8s-read-kv_v2_data_by_custom_env_tmpl \
    audience=vault \
    ttl=1h

vault write auth/eljavatar_k8s/kubernetes/role/some-custom-role \
    bound_service_account_names="some-sa" \
    bound_service_account_namespaces="some-namespace" \
    token_policies=eljavatar_k8s-read-db_creds_by_custom_env_tmpl \
    audience=vault \
    ttl=1h
```


### Configurar un Secreto (Credenciales) de tipo `database`

El motor de bases de datos de Vault funciona de manera muy distinta a un KV-v2:

- En *KV-v2*, nosotros guardamos un secreto estático y lo leemos en un path fijo.
- En el *Database Engine*, Vault se conecta directamente a la base de datos (por ejemplo PostgreSQL) como administrador y crea un usuario único y temporal en la base de datos cada vez que una aplicación lo solicita, destruyéndolo automáticamente cuando expira el tiempo de vida (TTL).

Estas confifuraciones se realizan por cada base de datos (no a nivel de motor de base de datos), por tanto, eventualmente deberíamos tener una forma de automatizar este proceso. Por el momento, a continuación dejo la secuencia de pasos de cómo se haría la configuración por ejemplo para una base de datos llamada `pg-wallet-db` que tendríamos levantada en el namespace `wallet-service` en nuestro clúster de Kubernetes con su ServiceAccount `pg-wallet-db-sa`.

Para esto, previamente debimos de haber [habilitado un Secret Engine de tipo *database*](#crear-un-secret-engine-de-tipo-database).

#### 1. Configurar la conexión de Vault a PostgreSQL

Primero, Vault necesita un usuario con permisos para administrar credenciales en la DB de PostgreSQL para así poder crear y borrar usuarios dinámicamente, así que ejecutamos este comando para registrar la conexión (deberíamos ajusta la URL de conexión a nuestro entorno):

```sh
vault write secret/eljavatar_k8s/database/config/wallet-service-pg-wallet-db \
    plugin_name="postgresql-database-plugin" \
    allowed_roles="wallet-service-pg-wallet-db-sa" \
    connection_url="postgresql://{{username}}:{{password}}@postgres-host:5432/pg-wallet-db?sslmode=disable" \
    username="vault_admin_user" \
    password="password_seguro_de_admin"
```

- **`allowed_roles`:** Restringe qué roles del motor de secretos (*database*) pueden usar esta conexión (en este caso, mapeado al namespace y a la ServiceAccount); este rol lo definiremos en el paso 2.

- **`username` y `password`:** Es un usuario y contraseña con permisos de administración de credenciales (`pg_create_role`) que ya debe existir previamente en la DB de Postgres. No necesita ser superusuario y por el principio de menor privilegio tampoco se recomienda usar el superusuario principal (`postgres`). Para crear este usuario podemos ejecutar lo siguiente en nuestra DB de Postgres (deberíamos crearlo antes de configurar la conexión en Vault):

  ```sql
  CREATE USER vault_admin_user WITH PASSWORD 'password_seguro_de_admin';

  -- Le otorgamos permisos para crear, modificar y borrar otros roles/usuarios
  GRANT pg_create_role TO vault_admin_user;

  -- Darle permiso para otorgar nuestros roles compartidos a los usuarios dinámicos
  -- Por ejemplo, si tenemos el rol 'role_app_rw':
  GRANT role_app_rw TO vault_admin_user WITH ADMIN OPTION;
  ```

#### 2. Crear el Rol de la Base de Datos en Vault

El "Rol" en este motor de secretos define qué permisos tendrá el usuario temporal que Vault creará dentro de Postgres y cuánto tiempo durará esa credencial; esto lo hacemos mediante la propiedad `creation_statements`, a la cual le pasamos las instrucciones SQL que ejecutará Postgres (NO confundir con el rol que usamos para autenticarnos con Vault (aunque sí se relaciona con el namespace y la ServiceAccount que usamos para autenticarnos con Vault)).

```sh
# En este ejemplo, en el creation_statements además de crear el usuario, también le asignamos los respectivos
# permisos para que pueda realizar todas las operaciones DML sobre todas las tablas del esquema 'public'.
# Sin embargo, si en nuestra DB de Postgres ya tenemos definido un rol con los permisos que tendrá este
# usuario, el creation_statements lo podríamos definir así:
# creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}' IN ROLE role_app_rw;"
# También podríamos tener un Script SQL e invocar dicho Script:
# creation_statements=@script.sql
# 
# El tiempo default_ttl y max_ttl dependen de las políticas de rotación de credenciales e incluso de las
# ventanas de despliegue de una empresa. Veamos unos ejemplos comunes dependiendo el tipo de aplicación:
# - Microservicios y Cloud -> default_ttl: entre 1h y 12h; max_ttl: entre 24h y 7d
# - Legacy o Monolitos -> default_ttl: entre 12h y 24h; max_ttl: entre 7d y 30d
# - CronJobs y Pipelines de CI/CD -> default_ttl: entre 5m y 15m; max_ttl: entre 30m y 1h
#
# Si bien es cierto que no se recomienda configurar TTLs infinitos o de meses (ya que se perdería el
# principal beneficio de rotación frecuente que brinda Vault), para casos de HomeLabs como el nuestro
# donde a veces suele ser normal apagarlo (por ejemplo para ahorro de energía), la comodidad supera
# la seguridad estricta, por tanto estaría bien si configuramos TTLs más largos, ya que después de un
# apagado, al encender de nuevo, si ya se ha cumplido el max_ttl, Vault procederá a rotar las
# credenciales, pero como el LXC arranca más rápido que el clúster, por un lado Vault tardará un poco
# en poder comunicarse con la DB, y por el otro, las apps intentarán conectarse con las credenciales
# antiguas, causando que fallen al intentar arrancar (CrashLoopBackOff).
#
# En todo caso, después de apagados largos, lo ideal es que al encender el HomeLab, limpiemos el
# estado de Kubernetes si notamos comportamientos erráticos, forzando el reinicio de las aplicaciones
# para que soliciten credenciales nuevas a Vault desde el inicio:
# kubectl rollout restart deployment -n some-namespace
vault write secret/eljavatar_k8s/database/roles/wallet-service-pg-wallet-db-sa \
    db_name="wallet-service-pg-wallet-db" \
    default_ttl="1h" \
    max_ttl="24h" \
    username_template="v_{{.RoleName}}_{{random 6}}_{{unix_time}}" \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";"
```

- **`db_name`:** Este es el nombre de la configuración que definimos en el paso 1, y no debe confundirse con el nombre real de la base de datos.
- **`default_ttl`:** Este es el tiempo que indica cada cuanto se rotarán las credenciales y depende de las políticas de seguridad que definamos. Hay que tener en cuenta que lo ideal es que el operador de VSO solicite la generación de nuevas credenciales antes de que se cumpla el TTL.
- **`username_template`:** Por defecto, Vault genera un string largo aleatorio tanto para el nombre del usuario (`{{name}}`) como para la contraseña (`{{password}}`) que tendrá el nuevo usuario que se creará en la DB de Postgres; sin embargo, para el caso del nombre de usuario le definimos un formato específico de tal modo que se vería algo tipo `v_wallet-service-pg-wallet-db-sa_a1b2c3_1700000000`.
- **Nota importante de nombres:** Hemos nombrado al rol `wallet-service-pg-wallet-db-sa` siguiendo el patrón `{namespace}-{serviceaccount}`. Esto es vital para que la política dinámica funcione, ya que cuando se crea un rol, se habilita también el respectivo path que debemos usar para leer las credenciales: `secret/eljavatar_k8s/database/creds/wallet-service-pg-wallet-db-sa`, y es a este path al que le configuramos dicha política dinámica.

#### 3. Crear la Política Dinámica Global

Previamente ya habíamos creado una política dinámica llamada `eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl` con la siguiente estructura:

```hcl
path "secret/eljavatar_k8s/database/creds/{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_namespace}}-{{identity.entity.aliases.auth_kubernetes_1a2b3c4d.metadata.service_account_name}}" {
  capabilities = ["read"]
}
```

Así pues, no necesitamos crear más políticas, ya que esta la podremos asociar a cualquier rol de autenticación de Vault que creemos posteriormente.

Podríamos tener una política más genérica tipo `secret/eljavatar_k8s/database/creds/{NAMESPACE}-*`, lo cual haría que podamos descargar secretos usando cualquier ServiceAccount del namespace (como por ejemplo `vault-vso-auth-sa`), pero para el caso de las bases de datos, esta vez preferimos ser más restrictivos (principio de menor privilegio).

En todo caso, si necesitamos tener más flexibilidad con el nombre del rol del motor de secretos, y por ende, con el path de las credenciales, podemos usar también la política `eljavatar_k8s-read-db_creds_by_custom_env_tmpl`, pero esto requeriría que la ServiceAccount tenga configurada la anotación `vault.hashicorp.com/alias-metadata-env` como lo vimos previamente.

#### 4. Vincular el Auth Method de Kubernetes con la Política (Rol de autenticación de Vault)

Debemos asegurarnos de que cuando el Pod de VSO se autentique en Vault usando la respectiva ServiceAccount (referenciada a través del recurso `VaultAuth` o `VaultAuthGlobal`), reciba esta política que vimos en el paso anterior. Como ya lo vimos previamente, esto lo hacemos creando un rol mediante la configuración del sub-path `/roles` del método de autenticación de Kubernetes:

```sh
vault write auth/eljavatar_k8s/kubernetes/role/wallet-service-pg-wallet-db-sa-role \
    bound_service_account_names="pg-wallet-db-sa" \
    bound_service_account_namespaces="wallet-service" \
    token_policies=eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl \
    audience=vault \
    ttl=1h
```

#### 5. Aplicar manifiestos en Kubernetes para extraer las credenciales

Más adelante veremos los manifiestos que necesitamos para [autenticarnos desde Kubernetes usando el operador VSO](#autenticación-desde-kubernetes-usando-vso), sin embargo, por ahora veamos un ejemplo de cómo configuraríamos el `VaultDynamicSecret` para obtener estas credenciales de base de datos:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: pg-wallet-db-credentials
  namespace: wallet-service
# https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultdynamicsecretspec
spec:
  # 1. Referencia al método de autenticación configurado para este namespace
  # Más adelante veremos un ejemplo de cómo se crea un recurso VaultAuth
  vaultAuthRef: vault-auth-pg-wallet-db

  # 2. Path del Secret Engine de tipo database
  mount: secret/eljavatar_k8s/database

  # 3. Path relativo (al 'mount') del rol que creamos en Vault sobre el Database Engine
  # Apunta exactamente al rol dinámico. VSO se encargará de hacer la petición GET
  # a este path en Vault.
  path: creds/wallet-service-pg-wallet-db-sa

  # 4. Nombre del Secret nativo de Kubernetes que creará VSO
  # Tendrá dos llaves automáticas: username y password
  destination:
    create: true
    name: pg-wallet-db-secret

  # 5. Configuración del ciclo de vida y rotación
  # Renovación automática antes de que expire el TTL de Vault
  # Como definimos un default_ttl="1h" en Vault, el operador renovará las credenciales y creará
  # el nuevo usuario en Postgres cuando pasen 40 minutos (el 67% del tiempo). Esto asegura el
  # solapamiento de usuarios, es decir, de este modo el anterior usuario seguirá existiendo unos
  # minutos después de que se cree el nuevo usuario, para así evitar cortes de conexión
  renewalPercent: 67  # Rota el secreto al consumir aprox. 40 minutos del TTL de 1 hora
  
  # 6. Estrategia de actualización para la aplicación (Elegimos una, en este ejemplo, 'rollout')
  # Como Postgres no permite cambiar la contraseña de una conexión viva de forma transparente
  # para la app, cuando VSO actualice el Secret de Kubernetes, reiniciará automáticamente los
  # pods del Deployment de forma progresiva (Rolling Update) para que tomen las nuevas
  # credenciales sin tirar el servicio.
  # Esto es en caso de que usemos variables de entorno.
  # Si montamos los secretos como volumen no necesitaremos hacer un rollout del pod
  # Otra alternativa sería usar Reloader
  rolloutRestartTargets:
    - kind: Deployment
      name: wallet-java-app
```

**¿Cómo lo consume la aplicación?**

En el YAML del Deployment, solo debemos mapear el secreto generado por VSO a las variables de entorno que use el microservicio para conectarse a Postgres:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wallet-java-app
  namespace: wallet-service
spec:
  template:
    spec:
      serviceAccountName: pg-wallet-db-sa  # Esencial para la autenticación
      containers:
        - name: app
          image: nuestro-registro/wallet-service-java:latest
          env:
            - name: DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: pg-wallet-db-secret  # El nombre que pusimos en 'destination'
                  key: username
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: pg-wallet-db-secret
                  key: password
```

#### 🔄 ¿Cómo consume los secretos el Pod de VSO en la práctica?

Cuando el Pod de VSO se autentique contra Vault, obtendrá un token con la política `eljavatar_k8s-read-db_creds_by_ns_and_sa_tmpl`. Internamente, para Vault, las variables del template se resolverán de la siguiente manera:

- `{{...metadata.service_account_namespace}}` ➔ `wallet-service`
- `{{...metadata.service_account_name}}` ➔ `pg-wallet-db-sa`

Por lo tanto, el Pod estará autorizado únicamente a realizar un `GET` (read) al siguiente path:

```sh
vault read secret/eljavatar_k8s/database/creds/wallet-service-pg-wallet-db-sa
```

Y cada vez que el operador consulte ese path, Vault le devolverá un usuario y contraseña únicos generados en Postgres en ese instante:

```json
{
  "username": "v-kubernetes-wallet-se-r3f8...",
  "password": "A1b2C3d4E5f6G7h8..."
}
```


### Configurar el Inicio de sesión desde el clúster de Kubernetes

Como mencionamos anteriormente, las aplicaciones de nuestro clúster de Kubernetes deben autenticarse ante Vault para poder leer los secretos de los almacenes (los Secret engines). Sin embargo, con los operadores como ESO y VSO el enfoque cambia, ya que es el operador quien actúa como intermediario centralizado que extrae los secretos de Vault y los inyecta como Secretos nativos de Kubernetes en cada namespace. Por lo tanto, las aplicaciones nunca se autentican ante Vault en este modelo, es siempre ESO o VSO quien va a Vault, descarga el secreto, y lo escribe como un `Secret` nativo de Kubernetes en el namespace.

De este modo, es el Pod del operador (`external-secrets` para el caso de ESO y `vault-secrets-operator-controller-manager` para el caso de VSO) el único que se autentica contra Vault usando una `ServiceAccount` válida. A continuación veremos cómo realizan este proceso de autenticación cada uno de estos operadores:

#### Autenticación desde Kubernetes usando ESO

Para realizar este proceso, el operador ESO cuenta con dos tipos de recursos: `SecretStore` y `ClusterSecretStore`. Los dos realizan el mismo proceso de autenticación, así que, ¿Cuál de los dos deberíamos usar? Para responder a esto, primero veamos una comparación entre ambos:

| Característica | `ClusterSecretStore` | `SecretStore` |
|----------------|----------------------|---------------|
| **Alcance del recuros** | Global (*Cluster-wide*): Lo ideal es crear un único recurso `ClusterSecretStore` por cada almacén en Vault (por cada Secret Engine) | Por Namespace (*Namespaced*): Para un mismo almacén en Vault se pueden crear varios recursos `SecretStore` (por lo general, se crea uno por cada namespace, sin embargo, dependiendo de nuestras requerimientos de seguridad y aislamiento podríamos incluso crear uno por aplicación) |
| **Ubicación de la SA** | Centralizada (por ejemplo, en un namespace llamado `vault-auth`) | Distribuida (en el mismo namespace de la aplicación) |
| **Configuración en Vault** | Solo 1 rol de Vault configurado (lo ideal también sería definir una política que otorgue acceso a todos los secretos del almacén) | 1 rol de Vault por cada namespace/app (este nivel de granularidad permite definir políticas de acceso por cada secreto por separado dentro del almacén) |
| **Mantenimiento** | Muy bajo (una sola conexión central) | Medio (repetir el store por namespace o aplicación) |
| **Aislamiento/Seguridad** | Menor aislamiento entre namespaces | Máximo aislamiento (Principio de menor privilegio) |

Los secretos son datos sensibles, por lo tanto, la decisión de qué opción escoger debería basarse en cuál nos brinda mayor nivel de aislamiento y seguridad (por ejemplo, que en el namespace donde corre el frontend no se puedan crear secretos que contengan credenciales de acceso a la base de datos). Sin embargo, si lo analizamos detenidamente, con `ClusterSecretStore` también podríamos lograr un nivel de aislamiento similar al de `SecretStore`, ya que podríamos tener varios `ClusterSecretStore` apuntando al mismo almacén en Vault, pero con diferentes Service Accounts y distintos roles.

En ese orden de ideas, los criterios que suelo seguir para decidir si debería usar un `ClusterSecretStore` son los siguientes:

- Si es un almacén global que va a tener datos que pueden ser compartidos para todos (o varios) los namespaces (como por ejemplo datos de un repositorio tipo docker del cual se obtienen las imagenes de los contenedores).
- Si por políticas corporativas no se quiere permitir que desde los namespaces a los que tienen acceso los desarrolladores se puedan crear los manifiestos de autenticación hacia Vault (e incluso, los manifiestos que generan los secretos en cada namespace, en cuyo caso se usarían `ClusterExternalSecret`).

Si no se cumplen estas condiciones, lo ideal sería usar un `SecretStore`, el cual como ya mencionamos, deberíamos crear por cada namespace (o aplicación) para el cual queramos generar un `Secret`. Además, aunque la propiedad `spec.conditions` dentro de `ClusterExternalSecret` mitiga el riesgo de que el Namespace "A" use un almacén del Namespace "B" pudiendo así incluso tener "un `ClusterExternalSecret` por namespace" (como simulando el comportamiento de un `SecretStore`), se suele preferir múltiples SecretStores locales debido a que la seguridad basada en RBAC nativo de namespaces es mucho más robusta y menos propensa a errores humanos de etiquetado que las condiciones personalizadas de un operador de terceros.

A continuación, veamos un ejempo de cómo crear en nuestro clúster de Kubernetes tanto un manifiesto de tipo `ClusterSecretStore`, así como uno de tipo `SecretStore`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eljavatar-k8s-kv-v2-sa
  namespace: vault-auth
---
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: vault-eljavatar-k8s-kv-v2
spec:
  # ClusterSecretStore es de acceso global, por tanto podemos restringir su uso para que solo
  # se pueda invocar desde namespaces específicos
  conditions:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: some-ns # Solo el namespace some-ns lo podría usar
    # O mediante una lista en caso de varios namespaces:
    # - namespaces:
    #   - "namespace-a"
    #   - "namespace-b"
  provider:
    vault:
      # La IP y puerto del contenedor LXC de Proxmox de HashiCorp Vault
      # También podríamos usar "https://vault.eljavatar.home:8200" ya que en
      # el hosts del CoreDNS del clúster configuramos esa URL
      server: "https://192.168.0.20:8200"
      # La ruta raíz en Vault del Secret Engine (sin el path del secreto interno)
      path: "secret/eljavatar_k8s/kv-v2"
      version: "v2" # Usamos la versión 2 de KV
      auth:
        kubernetes:
          # El path del método de autenticación en Vault
          mountPath: "eljavatar_k8s/kubernetes"
          # El rol en Vault que permite a ESO validar identidades
          role: "eso-global-role"
          serviceAccountRef:
            # También podríamos usar el ServiceAccount real que usa el Pod de ESO (external-secrets)
            name: eljavatar-k8s-kv-v2-sa
            namespace: vault-auth # El namespace donde creamos la ServiceAccount 'eljavatar-k8s-kv-v2-sa'
            audiences:
              # La audiencia es requerida a partir de Vault 1.21
              # Podríamos usar cualquier valor, sin embargo, por convención se suele usar la palabra 'vault'
              - vault
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: wallet-java-app-sa
  namespace: wallet-service
---
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: vault-auth-eljavatar-k8s-kv-v2-wallet-java-app
  namespace: wallet-service
spec:
  provider:
    vault:
      # La IP y puerto del contenedor LXC de Proxmox de HashiCorp Vault
      # También podríamos usar "https://vault.eljavatar.home:8200" ya que en
      # el hosts del CoreDNS del clúster configuramos esa URL
      server: "https://192.168.0.20:8200"
      # La ruta raíz en Vault del Secret Engine (sin el path del secreto interno)
      path: "secret/eljavatar_k8s/kv-v2"
      version: "v2" # Usamos la versión 2 de KV
      auth:
        kubernetes:
          # El path del método de autenticación en Vault
          mountPath: "eljavatar_k8s/kubernetes"
          # El rol en Vault que permite a ESO validar identidades
          role: "wallet-java-app-role"
          serviceAccountRef:
            name: wallet-java-app-sa # Esta ServiceAccount debe existir en el namespace 'wallet-service'
            audiences:
              # La audiencia es requerida a partir de Vault 1.21
              # Podríamos usar cualquier valor, sin embargo, por convención se suele usar la palabra 'vault'
              - vault
```

Como podemos apreciar, los 2 recursos son muy similares en el hecho de que se autentican usando el método de autenticación configurado en Vault de tal modo que les permite obtener todos los secretos de un almacén completo en Vault (un Secret Engine). He ahí la importancia de definir bien las políticas de permisos para cada rol en Vault y las Service Accounts permitidas para dicho rol, ya que de lo contrario podríamos llegar a tener un `SecretStore` mediante el cual se puedan obtener todos los secretos de un almacén independientemente del namespace en el que se encuentre.

Con esto, el operador de ESO ya tendría la configuración requerida para poder autenticarse ante Vault. No obstante, antes de ver qué es lo que pasa tras bambalinas al momento de hacer la autenticación, creo que es pertinente entender varias cosas: A partir de Kubernetes 1.24+, las Service Accounts ya no generan automáticamente tokens de larga duración y que almacenaban en un `Secret`.

Aún así, los Pods siguen teniendo un token, ya que cuando un Pod (como el de ESO) se levanta, el `kubelet` de Kubernetes genera un **token JWT dinámico y temporal (Projected Volume Token)** y lo inyecta automáticamente dentro del contenedor en la ruta `/var/run/secrets/kubernetes.io/serviceaccount/token`. Así pues, debido a que el operador de ESO corre como un Pod en el clúster, Kubernetes inyecta el token de su propia `ServiceAccount` en el disco del Pod (esto lo podemos ver si ejecutamos `kubectl describe pod -n external-secrets <NOMBRE_DEL_POD_DE_ESO>`, en la sección Mounts del container `external-secrets`).

Sin embargo, lo que se envía a Vault no es el token propio de ESO (el de esa ruta que acabamos de mencionar), es decir, cuando se usa `serviceAccountRef`, el token NO se lee desde el disco del Pod de ESO (`/var/run/secrets/...`). Tampoco se usa un "token genérico inventado" o "maquillado" con metadatos adjuntos, ya que un token JWT de Kubernetes no se puede falsificar; está firmado criptográficamente por el servidor de la API (`kube-apiserver`). Por lo tanto, para que Vault lo acepte, tiene que ser un token auténtico y legítimo emitido por el clúster para esa ServiceAccount específica.

En este orden de ideas, para obtener un token JWT legítimo con el cual autenticarnos ante Vault, lo que ocurre internamente con un `ClusterSecretStore` o `SecretStore` es lo siguiente:

1. El controlador de ESO corre con una ServiceAccount propia llamada `external-secrets`. Esta cuenta tiene varios permisos de clúster a nivel de RBAC (ClusterRole), entre ellos, el permiso `create` sobre el recurso `serviceaccounts/tokens`, el cual le permite realizar una llamada `POST` al endpoint especial `/api/v1/namespaces/<namespace>/serviceaccounts/<nombre>/token` (el API `TokenRequest`).

2. Cuando el código de ESO lee el bloque `serviceAccountRef: { name: "mi-sa", namespace: "mi-ns", audiences: ["vault"] }`, ESO llama a la API de Kubernetes realizando un `TokenRequest`: `POST /api/v1/namespaces/mi-ns/serviceaccounts/mi-sa/token` incluyendo un JSON que especifica explícitamente: `"audiences": ["vault"]`.

3. El `kube-apiserver` valida si ESO tiene permiso para suplantar o solicitar tokens de otros. Como el RBAC de ESO lo permite, el clúster genera un JWT legítimo, temporal y firmado por la propia clave del clúster, pero con los claims de identidad de la ServiceAccount que le especificamos en el manifest y para una audiencia en específica (por ejemplo a nombre de "`mi-sa`" en el namespace "`mi-ns`" y para la audiencia "`vault`"). Posteriormente, el clúster le devuelve este nuevo JWT a ESO.

4. ESO toma ese JWT recién nacido y se lo envía a Vault mediante la petición `POST /v1/auth/eljavatar_k8s/kubernetes/login` junto con el rol (supongamos `dev-role`) con el que se intenta acceder a Vault (extraído también del `ClusterSecretStore` o `SecretStore`).

5. Cuando Vault recibe ese token, lee el payload de dicho token y a partir de él obtiene la ServiceAccount (`mi-sa`), el namesapece (`mi-ns`) y la audiencia (`vault`). En primer lugar, Vault revisa la configuración del rol `dev-role` (el cual debería existir en `auth/eljavatar_k8s/kubernetes/role/dev-role`) y valida si su audiencia esperada correponde con la que viene del token para continuar (en caso de que no, Vault cancela la operación de inmediato y devuelve un error de autenticación).

6. Posteriormente, Vault llama al API `TokenReview` de Kubernetes (usando nuestra cuenta Revisor) para validarlo (preguntándole a Kubernetes: *"¿Este token dinámico es válido y pertenece a la ServiceAccount `mi-sa` del namespace `mi-ns`?"*) y Kubernetes le responderá: *"Sí, este token es 100% real, está vigente y le pertenece a la ServiceAccount `mi-sa` del namespace `mi-ns`"*.

7. Al pasar la validación del revisor, Vault le devuelve un payload a ESO que contiene el `X-Vault-Token` y con el cual ESO podrá hacer llamadas a Vault, como por ejemplo, leer un secreto (`GET /v1/secret/eljavatar_k8s/data/my-secret`).

Por lo tanto, Vault recibe la verdadera identidad criptográfica de la ServiceAccount del desarrollador, no la identidad de ESO. Cuando decimos *ServiceAccount del desarrollador*, nos referimos a Service Accounts que se pueden crear por cada namespace, e incluso por cada aplicación individual, de modo tal que podríamos ser lo más granulares posibles en cuanto a qué Secretos en Vault tiene acceso cada ServiceAccount. Pueden haber escenarios en los que si se configura un acceso global mediante un `ClusterSecretStore`, se suela usar la misma identidad de ESO (`serviceAccountRef: { name: "external-secrets", namespace: "external-secrets" }`), sin embargo, aunque sea un acceso global, no es obligatorio que sea la misma identidad de ESO, ya que como vimos en los pasos anteriores, lo único que se requiere es que sea una ServiceAccount real perteneciente a un namespace real dentro del clúster.

#### Autenticación desde Kubernetes usando VSO

Para realizar la autenticación con VSO necesitamos principalmente de dos recursos: `VaultConnection` y `VaultAuth`, aunque en muchos casos también se suele usar un `VaultAuthGlobal`, el cual nos permite definir una especie de plantilla global para ser usada en los `VaultAuth` haciendo que tengamos que escribir menos configuraciones en estos últimos.

A diferencia de ESO, donde los datos para hacer handshake al servidor de Vault (url y certificado) y la autenticación están mezclados en un mismo recurso, en VSO se separa esta lógica, de tal forma que estos recursos se verían de la siguiente forma (estos manifiestos los creamos después de [instalar VSO](README.md#instalación-de-vso) en nuesro clúster de Kubernetes, pero los pongo aquí como referencia):

- **`VaultConnection`**: Se define uno solo en todo el clúster. Por lo general, solemos crearlo en el mismo namespace donde instalmos VSO.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: vault-secrets-operator
# https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultconnectionspec
spec:
  # La IP y puerto del contenedor LXC de Proxmox de HashiCorp Vault
  # También podríamos usar "https://vault.eljavatar.home:8200" ya que en
  # el hosts del CoreDNS del clúster configuramos esa URL
  address: https://192.168.0.20:8200
  # the trusted PEM encoded CA certificate chain stored in a Kubernetes Secret
  caCertSecretRef: vault-ca-cert
  # Para pruebas rápidas podríamos omitir la verificación TLS, pero no se recomienda
  # para entornos productivos. En este caso no necesitamos skipearla ya que le estamos
  # pasando el certificado a través de caCertSecretRef
  # skipTLSVerify: true
```

- **`VaultAuthGlobal`**: Son plantillas, así que podemos crear las plantillas que necesitemos, aunque normalmente solemos necesitar pocas (entre 1 y 3). Por lo general, solemos crearlo en el mismo namespace donde instalmos VSO.

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuthGlobal
metadata:
  name: vault-auth-global-eljavatar-k8s
  namespace: vault-secrets-operator
# https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultauthglobalspec
spec:
  # El nombre de la conexión se puede indicar anteponiendo el nombre del namespace, como
  # por ejemplo namespaceA/vaultConnectionRefB. Si no se le indica el namespace a través
  # de este prefijo, lo buscará en el mismo namespace de este VaultAuthGlobal.
  # En caso de que no especifique el valor de vaultConnectionRef, VSO buscará en el mismo
  # namespace donde se instaló VSO un VaultAuthGlobal con nombre 'default'.
  vaultConnectionRef: vault-secrets-operator/vault-connection
  # Como es un recurso 'global' que el operador de VSO podría invocar desde cualquier
  # namespace, podemos indicarle desde qué namespaces queremos permitir que se llame.
  # Si no le especificamos nada, se deshabilitarán todos los namespaces, excepto donde
  # está instalado el operador de VSO y el del VaultAuthMethod de referencia especificado
  # en este mismo VaultAuthGlobal (por ejemplo, spec.kubernetes.namespace)
  allowedNamespaces:
    # En un entorno productivo, lo ideal sería especificar la lista de namespaces permitidos,
    # sin embargo, en nuestro caso lo permitiremos para todos los namespaces
    - "*"
  defaultAuthMethod: kubernetes
  # https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultauthglobalconfigkubernetes
  kubernetes:
    audiences:
      - vault
    # El path del método de autenticación en Vault
    mount: eljavatar_k8s/kubernetes
    role: global-dynamic-reading-role
    serviceAccount: vault-vso-auth-sa # El namespace se obtiene de cada VaultAuth
    tokenExpirationSeconds: 600
```

- **`VaultAuth`**: Estos son los que realizan el proceso de autenticación, y son los que creamos por cada namespace o cada ServiceAccount según sea el caso.

```yaml
# Ejemplo en el que usamos la misma ServiceAccount definida en el VaultAuthGlobal
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-vso-auth-sa
  namespace: playground
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth-demo
  namespace: playground
# https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultauthspec
spec:
  vaultAuthGlobalRef:
    name: vault-auth-global-eljavatar-k8s
    namespace: vault-secrets-operator

  # Method to use when authenticating to Vault.
  # Lo heredamos del VaultAuthGlobal
  # method: kubernetes

  # Lo heredamos del VaultAuthGlobal
  # mount: eljavatar_k8s/kubernetes


# Ejemplo en el que sobreescribimos la ServiceAccount que viene del VaultAuthGlobal
apiVersion: v1
kind: ServiceAccount
metadata:
  name: playground-sa
  namespace: playground
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth-demo
  namespace: playground
# https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultauthspec
spec:
  vaultAuthGlobalRef:
    name: vault-auth-global-eljavatar-k8s
    namespace: vault-secrets-operator

  # Method to use when authenticating to Vault.
  # Lo heredamos del VaultAuthGlobal
  # method: kubernetes

  # Lo heredamos del VaultAuthGlobal
  # mount: eljavatar_k8s/kubernetes

  # Para este caso la SA y el rol son distintos, por lo tanto los definimos para que sobreescriban
  # los valores heredados de 'vault-auth-global'. EL resto de valores se mantienen
  # https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/api-reference#vaultauthconfigkubernetes
  kubernetes:
    # role to use when authenticating to Vault
    role: playground-test-role
    # ServiceAccount to use when authenticating to Vault
    # El namespace se obtiene de metadata.namespace
    serviceAccount: playground-sa
```

Como podemos apreciar, este esquema permite asbtraer muchas cosas para que los recurso `VaultAuth` sean lo menos verbosos posible, además, podemos apreciar que a pesar de que los recursos `VaultConnection` y `VaultAuthGlobal` se crean en un namespace específico, tienen un comportamiento de ámbito global que les permite ser referenciados desde cualquier namespace:

- En el `VaultConnection` especificamos la URL del servidor de Vault, y al usar `HTTPS` referenciamos también el secreto con el certificado TLS (en entornos de desarrollo o pruebas rápidas podríamos también omitir temporalmente la validación del certificado a través de la propiedad `skipTLSVerify: true`).

- En el `VaultAuthGlobal` definimos una configuración global que heredarán todos los `VaultAuth` que lo referencien. De esta forma, aquí referenciamos la conexión que se va a usar, el método de autenticación por defecto, y los datos que por lo general usarán todos los `VaultAuth`. Cabe recalcar que debemos definir también los `allowedNamespaces`, ya que de lo contrario tendremos problemas al referenciarlo desde los recursos `VaultAuth` que se encuentren en otros namespaces; en nuestro caso, le daremos una configuración rápida permitiendo ser referenciado desde todos los namespaces (`"*"`).

- En el `VaultAuth`, solo nos quedaría referenciar el template `VaultAuthGlobal` que vamos a usar y el namespace, ya que según nuestro modelo de políticas y roles en Vault, los secretos se definen y se acceden según los namespaces. Adicionalmente, como vemos en este ejemplo, si requerimos sobreescribir alguna configuración, lo podemos hacer, de este modo, en el ejemplo tenemos un `VaultAuth` que tendrá un `kubernetes.role` y un `kubernetes.serviceAccount` distinto, pero el resto de configuraciones será igual al del `VaultAuthGlobal` que se referenció (`audiences`, `mount`, etc.).

Ahora que ya sabemos cómo configurar la autenticación con VSO, veamos qué es lo que pasa tras bambalinas al momento del operador intentar autenticarse ante el servidor de Vault, quien al igual que ESO, se ve obligado a "impersonar" y realizar llamadas programáticas a la API de Kubernetes, ya que en el modo de operador puro, es completamente imposible que use la proyección física de volúmenes en disco para el flujo de nuestras aplicaciones (`ServiceAccountTokenVolumeProjection`), porque el Pod de VSO vive estático en `vault-secrets-operator` y no puede adivinar ni montar en caliente volúmenes de Service Accounts de otros namespaces que van apareciendo dinámicamente en el clúster.

Para que VSO se pueda "impersonar" a nombre de otras Service Accounts, el RBAC por defecto de VSO que instalamos vía Heml crea su propia ServiceAccount `vault-secrets-operator-controller-manager` la cual también incluye el permiso `create` sobre `serviceaccounts/token` a nivel de clúster (ClusterRole). Veamos el flujo detallado por ejemplo para el `VaultAuth` `vault-auth-demo` que vimos previamente (al igual que en ESO, omito la parte del handshake usando el certificado TLS ya que esto se hace antes de siquiera intentar obtener el token JWT para la autenticación):

1. **El Origen de los datos (Lectura del Manifiesto):** Cuando creamos o actualizamos un recurso (por ejemplo, un `VaultStaticSecret` también en el namespace `playground`), el controlador de VSO intercepta el evento:
   - VSO busca el `VaultAuth` en ese mismo namespace `playground`, es decir, buscaría a `vault-auth-demo` (o hereda los datos del `VaultAuthGlobal` referenciado, en este caso `vault-auth-global-eljavatar-k8s`).
   - **De dónde extrae los datos:** VSO lee directamente del manifiesto (`VaultAuth`) los campos `spec.kubernetes.serviceAccount` (que en nuestro caso es `playground-sa`) y la audiencia `spec.kubernetes.audiences` (que es `vault`, aunque en este ejemplo la heredaría del `VaultAuthGlobal`). El namespace origen lo extrae del metadato del propio recurso (`metadata.namespace` del `VaultAuth`, es decir, `playground`).

2. **La llamada programática a Kubernetes (`TokenRequest`):** Al igual que ESO, el código en Go de VSO utiliza el cliente oficial de Kubernetes (`client-go`) para disparar una petición HTTPS directa al clúster:
   - **La Petición:** `POST /api/v1/namespaces/playground/serviceaccounts/playground-sa/token`.
   - **El Payload de la petición:** En el cuerpo del POST, VSO envía un JSON estructurado de tipo `TokenRequest` especificando explícitamente: `"audiences": ["vault"]`.

3. **El Nacimiento del JWT en el kube-apiserver:** El `kube-apiserver` recibe la petición firmada por el operador de VSO:
   - El clúster valida si la ServiceAccount del operador (`vault-secrets-operator-controller-manager`) tiene permisos RBAC para pedir tokens de terceros en el namespace `playground`, y al validar que sí, el clúster **construye el JWT desde cero**.
   - **Cómo se inyectan los datos:** El API Server junta la identidad de la ruta consultada (`playground` y `playground-sa`) junto con el payload enviado por VSO (`vault`). El clúster genera el JSON del payload, aplica su firma criptográfica y le devuelve el string `header.payload.signature` final a VSO. Nadie decodifica ni altera nada en el camino; el token nace ya estructurado directamente en el núcleo de Kubernetes.

4. **El Login ante Vault:** VSO toma ese string JWT en texto plano que le devolvió el clúster y procesa la solicitud de autenticación hacia la API de Vault:
   - **La Petición:** `POST/v1/auth/eljavatar_k8s/kubernetes/login` (`eljavatar_k8s/kubernetes` lo obtenemos del campo `spec.kubernetes.mount` del `VaultAuthGlobal`).
   - **El Payload:** Envía el JWT obtenido en el paso anterior y el nombre del rol (`playground-test-role`) extraído del manifiesto `VaultAuth` (del campo `spec.kubernetes.role`).

5. **La primera validación en Vault (Audiencia y Rol):** Vault recibe el JWT y el nombre del rol:
   - Vault va a su base de datos interna y busca la configuración en `auth/eljavatar_k8s/kubernetes/role/playground-test-role`.
   - Vault abre el JWT (sin verificar la firma todavía, solo lee el payload que es texto expuesto) y busca el claim "aud". Valida si coincide con lo que el administrador de seguridad (en este caso, nosotros mismos) configuró en el rol de Vault. Si no coincide, aborta y devuelve un error `400` o `403` de inmediato.

6. **El `TokenReview` (Validación de Firma):** Vault no confía ciegamente en lo que dice el string, y por tanto necesita asegurarse de que el token no sea falso y siga vigente:
   - Vault realiza una llamada HTTP `POST` al clúster de Kubernetes usando el endpoint de la API: `/apis/authentication.k8s.io/v1/tokenreviews`.
   - Para hacer esta llamada, Vault utiliza sus propias credenciales de "Revisor" que configuramos previamente.
   - En el cuerpo del `TokenReview`, Vault le envía el JWT completo que le dio VSO y le pregunta a Kubernetes: *¿Este token es válido y vigente para `system:serviceaccount:playground:playground-sa`?*
   - El `kube-apiserver` valida la firma criptográfica usando las llaves públicas del clúster (`service-account-key-file`) y verifica que no haya expirado. Si todo está en orden, responde a Vault con un JSON que contiene `status.authenticated: true`, confirmando la identidad exacta de la ServiceAccount.

7. **Verificación de Límites del Rol (Bound Check):** Una vez que Kubernetes le confirma a Vault que el token es 100% legítimo, Vault hace una última validación interna de seguridad basada en las restricciones del rol (`playground-test-role`):
   - Compara que la ServiceAccount verificada (`playground-sa`) y el namespace verificado (`playground-sa`) coincidan exactamente con los parámetros `bound_service_account_names` y `bound_service_account_namespaces` configurados en el rol de Vault.
   - Si el token pertenece a otra ServiceAccount o a otro namespace no autorizado en ese rol específico, la autenticación falla.

8. **Generación del Token de Vault (X-Vault-Token):** Si todas las reglas de negocio y de infraestructura se cumplen:
   - Vault genera un token interno de Vault (`X-Vault-Token`) con las políticas de acceso (ACLs) asociadas a ese rol `playground-test-role`.
   - Este token de Vault tiene un tiempo de vida limitado (TTL) y propiedades de renovación.
   - Vault responde a la petición HTTP original de VSO devolviendo un payload JSON que contiene este token de Vault en la propiedad `auth.client_token`.

9. **Consumo de Secretos por parte de VSO:** VSO recibe el token de Vault exitosamente:
   - VSO almacena este token de Vault de forma segura en su memoria (y opcionalmente puede persistirlo en un Secreto de Kubernetes si se configuró para almacenar el token de sesión).
   - A partir de este momento, VSO utiliza este `X-Vault-Token` incluyéndolo en los Headers HTTP (`X-Vault-Token: <token>`) para realizar las llamadas de lectura a las APIs de Vault (por ejemplo, GET `/v1/secret/eljavatar_k8s/kv-v2/data/demo`).
   - VSO se encarga de monitorear el TTL de este token de Vault y de realizar llamadas a `/v1/auth/token/renew-self` periódicamente para mantenerlo vivo mientras el operador siga corriendo. Si el token expira, VSO repite el flujo completo de autenticación.


### Configurar un Motor PKI en Vault (Opcional)

Esta pequeña sección pensaba no incluirla, pero la dejo ya que debido a algunas pruebas y configuraciones que estaba haciendo, terminé creando este tipo de secretos, el cual permitiría que nuestro servidor de HashiCorp Vault pueda asumir un rol de Autoridad de Certificación (CA) (como lo es por ejemplo Let's Encrypt). Sin embargo, por el momento no voy a ahondar mucho en explicaciones sobre este tipo de secretos. Solo dejaré algunas instrucciones para crealos y cómo usarlos desde el clúster de Kubernetes:

1. Configurar un secreto de tipo PKI en Vault:

```sh
# 1. Habilitar PKI
vault secrets enable -path=secret/eljavatar_k8s/pki pki

# 2. Configurar TTL de la CA (10 años)
vault secrets tune -max-lease-ttl=87600h secret/eljavatar_k8s/pki

# 3. Generar la Root CA interna
vault write -format=json secret/eljavatar_k8s/pki/root/generate/internal \
    common_name="eljavatar.home" \
    ttl=87600h > certs/vault_ca_root.json

# 4. Configurar endpoints de emisión
vault write secret/eljavatar_k8s/pki/config/urls \
    issuing_certificates="https://192.168.0.20:8200/v1/secret/eljavatar_k8s/pki/ca" \
    crl_distribution_points="https://192.168.0.20:8200/v1/secret/eljavatar_k8s/pki/crl"

# 5. Crear el rol que pueda procesar las solicitudes de firma de certificado
# El nombre de este rol es con el que se define el nombre del recurso al que
# se tendrá acceso desde nuestro clúster de Kubernetes
vault write secret/eljavatar_k8s/pki/roles/eljavatar-home-cert-issuer \
    allowed_domains="eljavatar.home,192.168.0.20" \
    allow_subdomains=true \
    allow_any_name=true \
    allow_ip_sans=true \
    max_ttl=720h
```

2. Definir la política en un archivo `.hcl` y escribirla en Vault:

```hcl
path "secret/eljavatar_k8s/pki/sign/eljavatar-home-cert-issuer" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
```

```sh
vault policy write eljavatar_k8s-all-pki_home_cert_issuer vault/policies/eljavatar_k8s-all-pki_home_cert_issuer.hcl
```

3. Crear el rol asignando asignando esta política y otorgando permisos a una `ServiceAccount` ubicada en el namespace `cert-manager`. A diferencia de los otros tipos de secretos que hemos visto los cuales son accedidos a través de los operadores externos, este tipo de secretos genera certificados TLS que son descargados dentro de Secrets en nuestro clúster a través de recursos tipo `Certificate` usando el operador `cert-manager` (aunque con VSO también los podríamos descargar):

```sh
vault write auth/eljavatar_k8s/kubernetes/role/cert-manager-ca-role \
    bound_service_account_names=cert-manager \
    bound_service_account_namespaces=cert-manager \
    token_policies=eljavatar_k8s-all-pki_home_cert_issuer \
    audience=vault-cert-manager
    ttl=1h
```

4. Configuración en nuestro clúster de Kubernetes:

```sh
# Crear el secret con el certificado del servidor de Vault para que cert-manager
# pueda hacer login en Vault
kubectl create secret generic vault-ca-bootstrap \
  --from-file=ca.crt=<(curl -s http://192.168.0.20/certs/vault.crt) \
  -n cert-manager

# Crear la `ServiceAccount` con los permisos que necista el operador de cert-manager
# para crear el token temporal con el que se autenticará ante Vault
kubectl apply -f k8s/optional/vault-cert-manager-sa-rbac.yaml

# Crear el recurso Issuer (el emisor) con los datos para autenticarse ante la entidad
# emisora de certificados, que en este caso es nuestro servidor de Vault
kubectl apply -f k8s/optional/vault-server-ca-issuer.yaml

# Crear recurso Certificate que es el que obtiene el certificado desde la entidad
# emisora y lo guarda en un Secret dentro del namespace que se le indique. En el
# manifiesto pusimos de ejemplo 'playground' pero puede ser cualquier otro.
kubectl apply -f k8s/optional/vault-server-ca-cert.yaml

# Para validar que todo está bien, se hace después de solicitar un certificado
# Como mencionamos, lo hicimos de ejemplo en el namespace playground
kubectl get certificaterequests -n playground -o wide

# En caso de que el anterior comando nos muestre un error en la descripción, podemos
# usar los siguientes comandos para hacer troubleshooting y encontrar la causa raíz:
kubectl describe certificaterequest -n playground vault-server-cert-<ID_ALEATORIO>
```















