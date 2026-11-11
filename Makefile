# Variables
AUTO_CONFIG_CLUSTER=true
SYNC_WITH_TF=false
IS_DEVELOPMENT=true
USE_LOCAL_ISO=false
USE_PROD_DOMAIN=true
USE_LETSENCRYPT_PROD=false
# Rama del repositorio que Argo CD sincroniza. En pruebas: test/<tema>; en producción: main
GITOPS_BRANCH ?= test/gitops-bootstrap
# Applications a revisar por 'make gitops-health' (vacío = lista por defecto del script)
GITOPS_APPS ?=

.PHONY: check-deps gitops-publish gitops-health gitops-health-strict validate-cluster validate-cluster-slow validate-cluster-json tf-init tf-validate tf-plan tf-apply tf-destroy

check-deps: # Verifica que las herramientas necesarias estén instaladas
	@echo "Checking dependencies..."
	@command -v terraform >/dev/null 2>&1 || { echo "Error: Terraform no está instalado."; exit 1; }
	@command -v talosctl >/dev/null 2>&1 || { echo "Error: Talosctl no está instalado."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: Kubectl no está instalado."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: Helm no está instalado."; exit 1; }
	@command -v cilium >/dev/null 2>&1 || { echo "Error: Cilium no está instalado."; exit 1; }
	@command -v vault >/dev/null 2>&1 || { echo "Error: Vault no está instalado."; exit 1; }
	@command -v argocd >/dev/null 2>&1 || { echo "Error: ArgoCD no está instalado."; exit 1; }
	@echo "All dependencies found."

tf-init:
	terraform -chdir=terraform init -upgrade

tf-validate:
	terraform -chdir=terraform validate

# Publica los manifiestos GitOps en la rama de pruebas (reescribe la rama, sin acumular historial)
# Primero creamos la variable de entorno GITOPS_BRANCH ya que el script la necesita
# En caso de que la SSH Key no esté en '$HOME/.ssh/id_ed25519_gitops', se puede pasar la ruta mediante la variable GITOPS_SSH_KEY
# En caso de que los archivos a comitear no estén en las rutas 'gitops/ k8s/deployments/', se pueden pasar mediante la variable GITOPS_PATHS
gitops-publish:
	GITOPS_BRANCH=$(GITOPS_BRANCH) ./scripts/gitops-publish.sh

tf-plan:
	terraform -chdir=terraform plan \
		-var="auto_config_cluster=$(AUTO_CONFIG_CLUSTER)" \
		-var="sync_with_tf=$(SYNC_WITH_TF)" \
		-var="gitops_branch=$(GITOPS_BRANCH)" \
		-var="is_development=$(IS_DEVELOPMENT)" \
		-var="use_local_iso=$(USE_LOCAL_ISO)" \
		-var="use_prod_domain=$(USE_PROD_DOMAIN)" \
		-var="use_letsencrypt_prod=$(USE_LETSENCRYPT_PROD)"

# Publica primero los manifiestos GitOps y luego levanta el clúster
tf-apply: gitops-publish
	terraform -chdir=terraform apply --auto-approve \
		-var="auto_config_cluster=$(AUTO_CONFIG_CLUSTER)" \
		-var="sync_with_tf=$(SYNC_WITH_TF)" \
		-var="gitops_branch=$(GITOPS_BRANCH)" \
		-var="is_development=$(IS_DEVELOPMENT)" \
		-var="use_local_iso=$(USE_LOCAL_ISO)" \
		-var="use_prod_domain=$(USE_PROD_DOMAIN)" \
		-var="use_letsencrypt_prod=$(USE_LETSENCRYPT_PROD)"

# Estado de salud de las Applications de Argo CD (verificación de día 2, sin Terraform).
# No falla por 'OutOfSync'/'Progressing' transitorios: solo por Applications inexistentes.
gitops-health:
	APPS="$(GITOPS_APPS)" ./scripts/gitops-health.sh

# Igual que 'gitops-health', pero falla si alguna Application no está Synced/Healthy.
gitops-health-strict:
	STRICT=true APPS="$(GITOPS_APPS)" ./scripts/gitops-health.sh

# Validación integral del clúster tras el bootstrap (solo lectura, ~segundos).
# Agrupa CRDs, red, workloads, TLS, secretos, almacenamiento y GitOps en una sola pasada,
# con un FAIL por cada cosa fuera de sitio y el ancla del README para el troubleshooting.
validate-cluster:
	./scripts/validate-cluster.sh

# Igual, añadiendo las pruebas lentas: cilium connectivity test, chaos de la IP flotante,
# despliegue temporal de nginx y end-to-end de VSO (estas SÍ crean y borran recursos).
validate-cluster-slow:
	./scripts/validate-cluster.sh --with-connectivity --with-chaos --with-app --with-vso-e2e

# Salida JSON para CI (exit 0 sin FAIL, exit 1 con FAIL, exit 2 sin clúster).
validate-cluster-json:
	./scripts/validate-cluster.sh --json

tf-destroy:
	terraform -chdir=terraform destroy
