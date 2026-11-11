#!/usr/bin/env bash
#
# Estado de salud de las Applications gestionadas por Argo CD (verificación de día 2).
#
# ¿Por qué existe este script?
#   La espera activa de Terraform (terraform_data.argocd_wait_gitops) usa un provisioner
#   'local-exec', y los provisioners SOLO se ejecutan al crear (o reemplazar) el recurso.
#   Eso es deliberado: esa espera existe para que el bootstrap falle ruidosamente si la
#   plataforma no quedó en pie, no para auditar el clúster en cada 'terraform apply'.
#   Un 'Progressing' transitorio (un rollout en curso, un pod reiniciando, un HPA
#   escalando) no debe hacer fallar un apply de infraestructura. Para eso está este script.
#
# Comportamiento:
#   - Siempre imprime una tabla con SYNC y HEALTH de cada Application.
#   - Sale con 1 si alguna Application NO EXISTE (bootstrap incompleto: siempre fatal).
#   - Sale con 0 aunque haya Applications OutOfSync/Degraded, salvo STRICT=true.
#
# Variables de entorno:
#   APPS       Applications a revisar (default: las del bootstrap)
#   STRICT     true -> también falla si alguna no está Synced/Healthy
#   NAMESPACE  Namespace de Argo CD (default: argocd)
#   KUBECONFIG Contexto y credenciales a usar (los hereda kubectl)
#
# Uso:
#   ./scripts/gitops-health.sh
#   STRICT=true ./scripts/gitops-health.sh
#   APPS="root reloader" ./scripts/gitops-health.sh
#   make gitops-health
#   make gitops-health-strict

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAMESPACE="${NAMESPACE:-argocd}"
STRICT="${STRICT:-false}"
read -r -a APP_LIST <<< "${APPS:-root descheduler metrics-server open-feature-operator argo-rollouts reloader}"

# Si no hay KUBECONFIG en el entorno, usamos el que genera Terraform (talos/kubeconfig),
# que es el mismo que inyectan los provisioners de terraform/k8s-bootstrap.tf.
if [ -z "${KUBECONFIG:-}" ] && [ -f "${REPO_ROOT}/talos/kubeconfig" ]; then
  export KUBECONFIG="${REPO_ROOT}/talos/kubeconfig"
fi

command -v kubectl >/dev/null 2>&1 || {
  echo "ERROR: kubectl no está instalado." >&2
  exit 1
}

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: no se puede contactar el clúster o el namespace '${NAMESPACE}' no existe." >&2
  echo "       KUBECONFIG actual: ${KUBECONFIG:-<sin definir>}" >&2
  echo "       Revisa KUBECONFIG y el contexto actual: kubectl config current-context" >&2
  exit 1
fi

missing=0
unhealthy=0

printf '%-30s %-12s %-12s\n' "APPLICATION" "SYNC" "HEALTH"
printf '%-30s %-12s %-12s\n' "------------------------------" "------------" "------------"

for app in "${APP_LIST[@]}"; do
  if ! kubectl get application "$app" -n "$NAMESPACE" >/dev/null 2>&1; then
    printf '%-30s %-12s %-12s\n' "$app" "MISSING" "-"
    missing=$((missing + 1))
    continue
  fi

  sync=$(kubectl get application "$app" -n "$NAMESPACE" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)
  health=$(kubectl get application "$app" -n "$NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || true)

  printf '%-30s %-12s %-12s\n' "$app" "${sync:-Unknown}" "${health:-Unknown}"

  if [ "${sync:-Unknown}" != "Synced" ] || [ "${health:-Unknown}" != "Healthy" ]; then
    unhealthy=$((unhealthy + 1))
  fi
done

echo
echo "Resumen: ${#APP_LIST[@]} Applications | ${missing} inexistentes | ${unhealthy} fuera de Synced/Healthy"

# 1) Existencia: siempre fatal. Una Application que no existe significa que el árbol de
#    GitOps está incompleto, no que esté "temporalmente desincronizado".
if [ "$missing" -gt 0 ]; then
  echo "ERROR: hay Applications que no existen. El árbol de GitOps está incompleto." >&2
  echo "       Causas típicas:" >&2
  echo "         1. 'make gitops-publish' no publicó el manifiesto en la rama que Argo CD lee." >&2
  echo "         2. Root sincronizó con 0 recursos: revisa 'directory.include' ('*/application.yaml')." >&2
  echo "         3. El ApplicationSet apunta a otra rama y genera 0 Applications." >&2
  exit 1
fi

# 2) Salud: informativa por defecto; solo fatal con STRICT=true.
if [ "$unhealthy" -gt 0 ] && [ "$STRICT" = "true" ]; then
  echo "ERROR: hay Applications fuera de Synced/Healthy y STRICT=true." >&2
  echo "       Diagnóstico: argocd app get <app> -n ${NAMESPACE}" >&2
  exit 1
fi

if [ "$unhealthy" -gt 0 ]; then
  echo "Aviso: hay Applications fuera de Synced/Healthy. No es fatal sin STRICT=true."
fi

exit 0
