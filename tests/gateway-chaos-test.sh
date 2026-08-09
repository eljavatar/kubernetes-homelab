#!/bin/bash

# Configuración del Laboratorio
IP_GATEWAY="192.168.0.70"
DOMINIO_PRUEBA="api.eljavatar.home"
NAMESPACE_RED="kube-system"
DURACION_MONITOREO=15 # Segundos para validar estabilidad inicial

# Colores para la terminal
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}[1/5] Iniciando validación del entorno...${NC}"

# Si hacemos PING fallará, por tanto usaremos Netcat (nc -zv "$IP_GATEWAY" 443)
# if ! ping -c 1 -W 1 "$IP_GATEWAY" > /dev/null 2>&1; then
#     echo -e "${RED}ERROR: No hay conectividad ping con la IP del Gateway ($IP_GATEWAY).${NC}"
#     exit 1
# fi

# 1. Verificar conectividad base mediante puerto TCP (NUEVO - CORRECTO)
if ! nc -z -w 1 "$IP_GATEWAY" 443 > /dev/null 2>&1; then
    echo -e "${RED}ERROR: El puerto 443 del Gateway ($IP_GATEWAY) no responde. Verifica que el Gateway esté levantado.${NC}"
    exit 1
fi


# 2. Identificar al Líder ARP Actual
NODO_LIDER=$(kubectl get leases -n "$NAMESPACE_RED" -o json | jq -r '.items[] | select(.metadata.name | contains("cilium-l2")) | .spec.holderIdentity' | head -n 1)

if [ -z "$NODO_LIDER" ] || [ "$NODO_LIDER" == "null" ]; then
    echo -e "${RED}ERROR: No se pudo determinar el nodo Líder ARP actual desde los Leases de K8s.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Entorno saludable.${NC}"
echo -e "${YELLOW}-> Nodo Líder ARP actual detectado: ${GREEN}$NODO_LIDER${NC}"
echo "--------------------------------------------------------"
echo -e "${YELLOW}[2/5] Monitoreando tráfico en estado normal por $DURACION_MONITOREO segundos...${NC}"


# Bucle corto para verificar que curl responde (esperamos el 404 o 200 que viste)
for i in $(seq 1 "$DURACION_MONITOREO"); do
    RESPUESTA=$(curl -skI --connect-timeout 1 --resolve "$DOMINIO_PRUEBA:443:$IP_GATEWAY" "https://$DOMINIO_PRUEBA" | grep HTTP | awk '{print $2}')
    echo -e "Petición HTTP #$i: Código de respuesta -> ${GREEN}$RESPUESTA${NC}"
    sleep 1
done

echo "--------------------------------------------------------"
echo -e "${RED}[3/5] ¡INJECTANDO CAOS! Evacuando tráfico del nodo líder: $NODO_LIDER...${NC}"


# Simulamos la falla aislando el nodo en Kubernetes (Cordon) 
# NOTA: Si prefieres un apagado físico real en Proxmox desde aquí, puedes reemplazar estas 2 líneas por un comando de la API de Proxmox
kubectl cordon "$NODO_LIDER" > /dev/null
# Reiniciamos el agente de Cilium de ese nodo específico para forzar la pérdida instantánea del Lease L2
POD_CILIUM=$(kubectl get pods -n "$NAMESPACE_RED" -l k8s-app=cilium --field-selector spec.nodeName="$NODO_LIDER" -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$POD_CILIUM" -n "$NAMESPACE_RED" --grace-period=0 > /dev/null

echo -e "${YELLOW}-> Ataque de caos ejecutado. Midiendo tiempo de recuperación del tráfico...${NC}"
echo "--------------------------------------------------------"
echo -e "${YELLOW}[4/5] Verificando Failover de la IP flotante...${NC}"

CONTADOR_FALLOS=0
NUEVO_LIDER=""

# Monitorear por 20 segundos el comportamiento del tráfico durante el fallo
for i in {1..40}; do
    # Hacemos el curl (0.5 segundos por ciclo)
    RESPUESTA=$(curl -skI --connect-timeout 0.5 --resolve "$DOMINIO_PRUEBA:443:$IP_GATEWAY" "https://$DOMINIO_PRUEBA" | grep HTTP | awk '{print $2}')
    
    if [ -z "$RESPUESTA" ]; then
        CONTADOR_FALLOS=$((CONTADOR_FALLOS + 1))
        echo -e "Tiempo $((i*5))00ms: ${RED}Pérdida temporal de conexión web...${NC}"
    else
        echo -e "Tiempo $((i*5))00ms: Tráfico Activo -> Código ${GREEN}$RESPUESTA${NC}"
    fi
    sleep 0.5
done

# Obtener el nuevo dueño de la IP
NUEVO_LIDER=$(kubectl get leases -n "$NAMESPACE_RED" -o json | jq -r '.items[] | select(.metadata.name | contains("cilium-l2")) | .spec.holderIdentity' | head -n 1)

echo "--------------------------------------------------------"
echo -e "${YELLOW}[5/5] Analizando resultados del reporte de caos...${NC}"
echo -e "-> Nodo Líder Original: ${RED}$NODO_LIDER${NC}"
echo -e "-> Nuevo Nodo Líder Detectado: ${GREEN}$NUEVO_LIDER${NC}"
echo -e "-> Cantidad de requests fallidas: ${YELLOW}$CONTADOR_FALLOS${NC}"

if [ "$NODO_LIDER" != "$NUEVO_LIDER" ] && [ "$CONTADOR_FALLOS" -le 3 ]; then
    echo -e "${GREEN}============= TEST EXITOSO ============="
    echo -e "La IP flotante migró correctamente de máquina física."
    echo -e "El tráfico web sufrió una interrupción despreciable de menos de 1.5 segundos."
    echo -e "========================================${NC}"
else
    echo -e "${RED}============= TEST FALLIDO ============="
    echo -e "La IP no migró de nodo o el tiempo de caída de la red fue demasiado alto."
    echo -e "========================================${NC}"
fi

# Restaurar el nodo para dejar el laboratorio limpio
echo -e "${YELLOW}Limpiando entorno del laboratorio (Uncordon del nodo)...${NC}"
kubectl uncordon "$NODO_LIDER" > /dev/null
