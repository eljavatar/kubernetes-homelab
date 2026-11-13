---
name: bootstrap-component
description: Flujo de trabajo obligatorio de 5 pasos para instalar, documentar, validar y automatizar con Terraform o ArgoCD un nuevo componente en la fase de bootstrap del clúster. Usar SIEMPRE que el usuario pida agregar o instalar un componente core/utilitario en el bootstrap del homelab (sección "Instalación de Componentes utilitarios" del README.md).
---

# Flujo de Instalación de Componentes en Fase Bootstrap

Cuando el usuario solicite agregar un nuevo componente a la fase de bootstrap del clúster, sigue estrictamente estas 5 fases en orden, pidiendo confirmación entre etapas críticas (como destrucciones o despliegues):

## Fase 1: Prueba Manual y Documentación Base
1. Busca la versión más reciente y compatible del componente usando la herramienta MCP de búsqueda web (`tavily_search`); puedes revisar inicialmente en la página de Artifacthub (si el componente se encuentra listado ahí, priorizando el componente oficial) y en caso de que no esté listado ahí, puedes validar en su repositorio de GitHub y/o en su página de documentación oficial (un ejemplo es el componente de ArgoCD que se encuentra en Artifacthub en la página 'https://artifacthub.io/packages/helm/argo/argo-cd'). En caso de que no sea posible identificar la página oficial del componente y por ende su versión, pregúntale al usuario de donde se debería obtener la información para validar la versión.
2. Genera un archivo de configuración "k8s/bootstrap/deployments/{componente}-values.yaml" (por ejemplo "k8s/bootstrap/deployments/argo-cd-values.yaml") con los parámetros recomendados para producción/HomeLab (ej. si requiere algún dashboard, si requiere activar alta disponibilidad o réplicas si aplica, instalación automática de CRDs, uso de métricas, otros componentes, etc.); ten en cuenta que para métricas el usuario planea usar en el futuro VictoriaMetrics y OpenObserve, por lo cual no es posible usar los CRDs de Prometheus. Puedes ver de referencia otros values que el usuario tiene en la carpeta "k8s/deployments/bootstrap", y para los values, para evitar alucinaciones, ten presente los valores que encuentres en la documentación según la versión recomendada (si encontraste la versión en Artifacthub, la página sería algo como "https://artifacthub.io/packages/helm/{organizacion}/{componente}/{VERSION}?modal=values" (por ejemplo para ArgoCD era algo como "https://artifacthub.io/packages/helm/argo/argo-cd/{VERSION}?modal=values"), si no está en Artifacthub, busca el archivo de values por defecto en su repositorio de Github o en su documentación oficial, pero que sean los de la versión recomendada, ya que un values puede cambiar drásticamente entre versiones). Si no te es posible encontrar el archivo de values por defecto para la versión recomendada, validalo con el usuario antes de intentar generar el values.yaml para el componente. Si el componente requiere de datos sensibles que se almacenan en secretos, prioriza el uso de Secretos de Vault, ya que datos como contraseñas, tokens o api keys no deben quedar quemados en el código (como se hace por ejemplo con la contraseña del componente de ArgoCD).
3. Proporciona los comandos exactos de `helm` y/o `kubectl` para que el usuario lo pruebe manualmente.
4. Genera el texto técnico en Markdown correspondiente a la documentación de este nuevo componente para añadirlo bajo la sección "Instalación de Componentes utilitarios" del `README.md`, siguiendo el estilo explicativo paso a paso del repositorio para usuarios que no usan Terraform (puedes ver otras subsecciones de dicha sección para ver como el usuario suele estructurar la documentación (como por ejemplo la subsección "Operadores Para Manejar Secretos Externos", "Argo CD (GitOps)", "Argo Rollouts", "Descheduler" y "Reloader", donde no solo se brinda una explicación sobre el uso del componente y su proceso de instalación, sino que también se explican cosas que pueden ser útiles respecto a la herramienta)).

## Fase 2: Automatización de Validaciones
1. Analiza el script `scripts/validate-cluster.sh`.
2. Agrega las comprobaciones necesarias (pods, CRDs, servicios o endpoints) para verificar automáticamente que el nuevo componente quedó sano y listo.

## Fase 3: Definición de Responsabilidades y Docs Secundarias
1. Consulta o define con el usuario si el componente será gestionado por Terraform (`sync_with_tf = true`) o por ArgoCD (`sync_with_tf = false`).
2. Actualiza la tabla/sección **"Modelo de responsabilidades: Bootstrap con Terraform vs. GitOps con Argo CD"** en el `README.md`.
3. Revisa otras secciones del repositorio (como `VAULT_README.md` o el `Makefile`) por si requieren ajustes relacionados.

## Fase 4: Infraestructura como Código (IaC) y GitOps
1. Recuerda al usuario ejecutar `make tf-destroy` para limpiar el estado manual antes de automatizar.
2. Agrega el recurso correspondiente en los archivos de `terraform/` (ej. `terraform/k8s-bootstrap.tf`).
3. Si `sync_with_tf = false`, crea o actualiza los manifiestos correspondientes dentro de `gitops/` (ubicándolo correctamente bajo App-of-Apps o ApplicationSet según corresponda).

## Fase 5: Recreación y Verificación End-to-End
1. Indica al usuario ejecutar la secuencia de validación y despliegue (`tf-validate`, `tf-plan` y `tf-apply`).
2. Solicita ejecutar `scripts/validate-cluster.sh` tras el despliegue para certificar que el clúster alcanza el estado *Ready-to-work* desde cero de forma 100% automatizada.

En caso de que no sea posible identificar la versión o encontrar el archivo values base por defecto para esa versión, pregúntale primero al usuario para que él te provea esa información ANTES de siquiera intentar generar un plan. Después de que tengas esta información (ya sea que la hayas encontrado tú o que el usuario te la haya proveido), Preséntale al usuario primero el plan de acción, las versiones seleccionadas, y los bloques de código para su aprobación antes de proceder a escribir en el sistema de archivos.
