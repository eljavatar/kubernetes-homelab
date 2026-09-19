# Variables
AUTO_CONFIG_CLUSTER=true
IS_DEVELOPMENT=true
USE_LOCAL_ISO=false
USE_PROD_DOMAIN=true
USE_LETSENCRYPT_PROD=false

.PHONY: check-deps tf-init tf-validate tf-plan tf-apply tf-destroy

check-deps: # Verifica que las herramientas necesarias estén instaladas
	@echo "Checking dependencies..."
	@command -v terraform >/dev/null 2>&1 || { echo "Error: Terraform no está instalado."; exit 1; }
	@command -v talosctl >/dev/null 2>&1 || { echo "Error: Talosctl no está instalado."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: Kubectl no está instalado."; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: Helm no está instalado."; exit 1; }
	@command -v cilium >/dev/null 2>&1 || { echo "Error: Cilium no está instalado."; exit 1; }
	@command -v vault >/dev/null 2>&1 || { echo "Error: Vault no está instalado."; exit 1; }
	@echo "All dependencies found."

tf-init:
	terraform -chdir=terraform init -upgrade

tf-validate:
	terraform -chdir=terraform validate

tf-plan:
	terraform -chdir=terraform plan \
		-var="auto_config_cluster=$(AUTO_CONFIG_CLUSTER)" \
		-var="is_development=$(IS_DEVELOPMENT)" \
		-var="use_local_iso=$(USE_LOCAL_ISO)" \
		-var="use_prod_domain=$(USE_PROD_DOMAIN)" \
		-var="use_letsencrypt_prod=$(USE_LETSENCRYPT_PROD)"

tf-apply:
	terraform -chdir=terraform apply --auto-approve \
		-var="auto_config_cluster=$(AUTO_CONFIG_CLUSTER)" \
		-var="is_development=$(IS_DEVELOPMENT)" \
		-var="use_local_iso=$(USE_LOCAL_ISO)" \
		-var="use_prod_domain=$(USE_PROD_DOMAIN)" \
		-var="use_letsencrypt_prod=$(USE_LETSENCRYPT_PROD)"

tf-destroy:
	terraform -chdir=terraform destroy
