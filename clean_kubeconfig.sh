#!/usr/bin/env bash

# Configurar el script para que se detenga si ocurre un error
set -euo pipefail

echo "=== 1. Estado inicial de los contextos ==="
kubectl config get-contexts

# Verificar si se pasó un argumento, si no, usar el contexto actual
if [ -n "${1:-}" ]; then
    TARGET_CONTEXT="$1"
    echo -e "\nContexto objetivo recibido por parámetro: ${TARGET_CONTEXT}"
else
    TARGET_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
    if [ -z "$TARGET_CONTEXT" ]; then
        echo "❌ Error: No se especificó contexto y no hay un contexto activo."
        exit 1
    fi
    echo -e "\nNo se recibió parámetro. Contexto actual detectado: ${TARGET_CONTEXT}"
fi

# Validar que el contexto realmente exista en el kubeconfig
if ! kubectl config get-contexts "$TARGET_CONTEXT" >/dev/null 2>&1; then
    echo "❌ Error: El contexto '${TARGET_CONTEXT}' no existe."
    exit 1
fi

# # Obtener el contexto actual automáticamente
# CURRENT_CONTEXT=$(kubectl config current-context 2>/dev/null || true)

# if [ -z "$CURRENT_CONTEXT" ]; then
#     echo "❌ Error: No hay ningún contexto activo configurado."
#     exit 1
# fi

echo -e "\nContexto a eliminar: ${TARGET_CONTEXT}"




# Obtener el cluster y usuario asociados al contexto objetivo
CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${TARGET_CONTEXT}')].context.cluster}")
USER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${TARGET_CONTEXT}')].context.user}")

echo "Cluster asociado: ${CLUSTER}"
echo "Usuario asociado: ${USER}"



# --- Bloque de Confirmación ---
echo -e "\n⚠️  ATENCIÓN: Se eliminarán de forma permanente los 3 elementos anteriores."
read -p "¿Estás seguro de que deseas continuar? (y/N): " CONFIRMATION

# Convertir la respuesta a minúsculas y validar
CONFIRMATION=$(echo "$CONFIRMATION" | tr '[:upper:]' '[:lower:]')
if [[ "$CONFIRMATION" != "y" && "$CONFIRMATION" != "yes" ]]; then
    echo "❌ Operación cancelada por el usuario."
    exit 0
fi
# ------------------------------




# # Obtener el cluster y usuario asociados al contexto actual
# CLUSTER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CURRENT_CONTEXT}')].context.cluster}")
# USER=$(kubectl config view -o jsonpath="{.contexts[?(@.name=='${CURRENT_CONTEXT}')].context.user}")

# echo "Cluster asociado: ${CLUSTER}"
# echo "Usuario asociado: ${USER}"

echo -e "\n=== 2. Eliminando componentes del contexto actual ==="

# Si el contexto a borrar es el actual, lo desconfiguramos primero
CURRENT_ACTIVE=$(kubectl config current-context 2>/dev/null || true)
if [ "$TARGET_CONTEXT" = "$CURRENT_ACTIVE" ]; then
    kubectl config unset current-context
fi

# # Desconfigurar el contexto actual
# kubectl config unset current-context




# Eliminar contexto, cluster y usuario
kubectl config delete-context "${TARGET_CONTEXT}"
[ -n "$CLUSTER" ] && kubectl config delete-cluster "${CLUSTER}"
[ -n "$USER" ] && kubectl config delete-user "${USER}"

# # Eliminar contexto, cluster y usuario
# kubectl config delete-context "${CURRENT_CONTEXT}"
# kubectl config delete-cluster "${CLUSTER}"
# kubectl config delete-user "${USER}"



# Asegurar la limpieza del contexto actual por si acaso
kubectl config unset current-context

echo -e "\n=== 3. Estado final de los contextos ==="
kubectl config get-contexts

echo -e "\n✅ ¡Proceso completado con éxito!"