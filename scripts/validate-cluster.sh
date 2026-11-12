#!/usr/bin/env bash
#
# Validación integral del clúster tras un bootstrap (Terraform, manual o GitOps).
#
# Objetivo: después de 'make tf-apply' (o de un levantamiento manual), ejecutar
# 'make validate-cluster' y obtener en segundos el estado de cada capa del clúster, con
# un FAIL por cada cosa que no esté como debería. Si algo falla, el propio script
# imprime el ancla del README donde está el troubleshooting de ese componente.
#
# Principios de diseño:
#   - Solo LECTURA por defecto. Nada de crear ni borrar recursos (salvo los flags
#     --with-app, --with-vso-e2e y --with-chaos, que son explícitos).
#   - Sin 'set -e': un check que falla no debe abortar el resto; se contabiliza.
#   - Sin dependencias nuevas: kubectl, curl y openssl. 'cilium', 'nc' y 'jq' solo
#     se usan si existen (si no, el check pasa a SKIP).
#   - Nada hardcodeado: la IP del Gateway y los hostnames se leen del clúster, así
#     el script sigue siendo válido si cambia el pool de IPs o el dominio.
#   - Placement por PREFIJO de nodo (worker-ops*, worker-apps*...), porque el
#     nodeSelector es por label y puede haber varios nodos del mismo rol.
#
# Códigos de salida:
#   0  todo OK (puede haber WARN/SKIP)
#   1  al menos un FAIL
#   2  no se puede hablar con el clúster (kubeconfig/contexto)
#
# Uso:
#   ./scripts/validate-cluster.sh
#   ./scripts/validate-cluster.sh --only=core,tls
#   ./scripts/validate-cluster.sh --skip=workloads
#   ./scripts/validate-cluster.sh --with-connectivity
#   ./scripts/validate-cluster.sh --with-chaos --with-app
#   ./scripts/validate-cluster.sh --json
#   make validate | make validate-slow | make validate-json

set -uo pipefail

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMEOUT="${VALIDATE_TIMEOUT:-30}"
GATEWAY_NS="${GATEWAY_NS:-gateway-api-system}"
GATEWAY_NAME="${GATEWAY_NAME:-external-gateway}"
ARGOCD_NS="${ARGOCD_NS:-argocd}"
APP_PROJECT="${APP_PROJECT:-homelab-platform}"
APPSET_NAME="${APPSET_NAME:-platform-components}"

GROUPS_ALL="core crds net workloads tls secrets storage gitops"
ONLY=""
SKIP=""
WITH_CONNECTIVITY=false
WITH_CHAOS=false
WITH_APP=false
WITH_VSO_E2E=false
JSON=false
VERBOSE=false

GW_ADDR=""
NODE_COUNT=0

# ---------------------------------------------------------------------------
# Estado
# ---------------------------------------------------------------------------
N_OK=0
N_FAIL=0
N_WARN=0
N_SKIP=0
FAILED_IDS=""
JSON_ROWS=""

if [ -t 1 ]; then
  C_OK=$'\033[0;32m'; C_FAIL=$'\033[0;31m'; C_WARN=$'\033[1;33m'
  C_SKIP=$'\033[0;36m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_OK=""; C_FAIL=""; C_WARN=""; C_SKIP=""; C_DIM=""; C_OFF=""
fi

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n'
}

record() {
  # record <OK|FAIL|WARN|SKIP> <id> <detalle> [pista]
  local status="$1" id="$2" detail="$3" hint="${4:-}"
  local tag color
  case "$status" in
    OK)   color="$C_OK";   tag=" OK "; N_OK=$((N_OK + 1)) ;;
    FAIL) color="$C_FAIL"; tag="FAIL"; N_FAIL=$((N_FAIL + 1)); FAILED_IDS="${FAILED_IDS}${id} " ;;
    WARN) color="$C_WARN"; tag="WARN"; N_WARN=$((N_WARN + 1)) ;;
    SKIP) color="$C_SKIP"; tag="SKIP"; N_SKIP=$((N_SKIP + 1)) ;;
  esac

  if [ "$JSON" = true ]; then
    JSON_ROWS="${JSON_ROWS}${JSON_ROWS:+,}{\"status\":\"${status}\",\"id\":\"$(json_escape "$id")\",\"detail\":\"$(json_escape "$detail")\",\"hint\":\"$(json_escape "$hint")\"}"
  else
    printf '%s[%s]%s %-34s %s\n' "$color" "$tag" "$C_OFF" "$id" "$detail"
    if [ -n "$hint" ] && { [ "$status" = "FAIL" ] || [ "$VERBOSE" = true ]; }; then
      printf '       %s↳ %s%s\n' "$C_DIM" "$hint" "$C_OFF"
    fi
  fi
}

ok()   { record OK   "$@"; }
fail() { record FAIL "$@"; }
warn() { record WARN "$@"; }
skip() { record SKIP "$@"; }

k() { kubectl --request-timeout="${TIMEOUT}s" "$@"; }

to_epoch() {
  local d="$1"
  [ -z "$d" ] && { echo ""; return; }
  date -j -f "%Y-%m-%dT%H:%M:%SZ" "$d" +%s 2>/dev/null \
    || date -d "$d" +%s 2>/dev/null \
    || echo ""
}

# Un hostname cae dentro del patrón de un listener (sufijo, uno o más labels).
host_in_listener_pattern() {
  local host="$1" pattern="$2"
  [ -z "$pattern" ] && return 0
  [ "$pattern" = "*" ] && return 0
  case "$pattern" in
    "*."*) case "$host" in *".${pattern#*.}") return 0 ;; *) return 1 ;; esac ;;
    *)     [ "$host" = "$pattern" ] ;;
  esac
}

# Un SAN de certificado cubre un hostname (exacto o wildcard de UN label).
san_covers_host() {
  local san="$1" host="$2"
  [ "$san" = "$host" ] && return 0
  case "$san" in
    "*."*)
      local suffix="${san#*.}" prefix
      case "$host" in
        *".${suffix}")
          prefix="${host%".${suffix}"}"
          case "$prefix" in ""|*.*) return 1 ;; *) return 0 ;; esac
          ;;
        *) return 1 ;;
      esac
      ;;
  esac
  return 1
}

san_list_from_server() {
  local host="$1"
  openssl s_client -connect "${GW_ADDR}:443" -servername "$host" </dev/null 2>/dev/null \
    | openssl x509 -noout -text 2>/dev/null \
    | awk '/X509v3 Subject Alternative Name/{getline; print; exit}' \
    | sed -e 's/DNS://g' -e 's/,/ /g' -e 's/^ *//' -e 's/ *$//'
}

issuer_from_server() {
  local host="$1"
  openssl s_client -connect "${GW_ADDR}:443" -servername "$host" </dev/null 2>/dev/null \
    | openssl x509 -noout -issuer 2>/dev/null
}

ns_exists() { k get namespace "$1" >/dev/null 2>&1; }

group_enabled() {
  local g="$1"
  if [ -n "$ONLY" ]; then
    case " $ONLY " in *" $g "*) ;; *) return 1 ;; esac
  fi
  case " $SKIP " in *" $g "*) return 1 ;; esac
  return 0
}

# ---------------------------------------------------------------------------
# core
# ---------------------------------------------------------------------------
group_core() {
  [ "$JSON" = true ] || echo "── core ──────────────────────────────────────────────────────────"

  # Nodos Ready y schedulable
  local bad="" line name status
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name="${line%%=*}"; status="${line##*=}"
    [ "$status" = "True" ] || bad="${bad}${name} "
  done <<EOF
$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)
EOF
  NODE_COUNT=$(k get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

  if [ -z "$bad" ] && [ "$NODE_COUNT" -gt 0 ]; then
    ok "core/nodes-ready" "${NODE_COUNT} nodos Ready"
  else
    fail "core/nodes-ready" "nodos no Ready: ${bad:-<ninguno detectado>}" "#comprobar-el-estado-de-los-nodos"
  fi

  local cordoned
  cordoned=$(k get nodes -o jsonpath='{range .items[*]}{.spec.unschedulable}{"\n"}{end}' 2>/dev/null | grep -c true)
  if [ "$cordoned" -eq 0 ]; then
    ok "core/nodes-schedulable" "ningún nodo cordoned"
  else
    warn "core/nodes-schedulable" "${cordoned} nodo(s) cordoned"
  fi

  # CSRs sin aprobar (prueba real de kubelet-csr-approver)
  local csr_total csr_approved
  csr_total=$(k get csr --no-headers 2>/dev/null | wc -l | tr -d ' ')
  csr_approved=$(k get csr -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Approved")].status}{"\n"}{end}' 2>/dev/null | grep -c True)
  if [ "$csr_total" -eq 0 ]; then
    ok "core/csr-approved" "sin CSRs registradas"
  elif [ "$csr_total" -eq "$csr_approved" ]; then
    ok "core/csr-approved" "${csr_approved}/${csr_total} CSRs aprobadas"
  else
    fail "core/csr-approved" "$((csr_total - csr_approved)) de ${csr_total} CSRs sin aprobar (¿kubelet-csr-approver?)" "#aprobar-certificados-autom%C3%A1ticamente"
  fi

  # Pods en mal estado en los namespaces de plataforma
  local ns badpods all="" per_ns
  for ns in kube-system cert-manager argocd openebs external-secrets vault-secrets-operator \
            argo-rollouts reloader open-feature-operator-system cloudflare-tunnel-system \
            gateway-api-system shared-ops; do
    ns_exists "$ns" || continue
    per_ns=$(k get pods -n "$ns" --no-headers 2>/dev/null | awk '
      { split($2, a, "/"); if (a[1] != a[2] && $3 != "Completed" && $3 != "Succeeded") print $1 "(" $3 ")" }' | paste -sd, -)
    [ -n "$per_ns" ] && all="${all}${ns}: ${per_ns}; "
  done
  if [ -z "$all" ]; then
    ok "core/pods-healthy" "todos los pods de plataforma Ready/Completed"
  else
    fail "core/pods-healthy" "$all" "#comprobar-qu%C3%A9-se-violar%C3%ADa-al-endurecer-un-namespace"
  fi

  # Rechazos por Pod Security Admission
  local events psa
  events=$(k get events -A --field-selector reason=FailedCreate -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.message}{"\n"}{end}' 2>/dev/null)
  psa=$(printf '%s\n' "$events" | grep -i podsecurity | head -n 3)
  if [ -n "$psa" ]; then
    fail "core/psa-failedcreate" "eventos FailedCreate por PodSecurity: $(printf '%s' "$psa" | tr '\n' ' ')" "#pod-security-admission-niveles-matriz-por-componente-y-comprobaciones"
  else
    ok "core/psa-failedcreate" "sin FailedCreate por PodSecurity"
  fi

  # Namespace de OpenEBS con el nivel correcto
  local psa_level
  psa_level=$(k get namespace openebs -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null)
  if [ "$psa_level" = "privileged" ]; then
    ok "core/openebs-psa-label" "ns/openebs enforce=privileged"
  elif ns_exists openebs; then
    fail "core/openebs-psa-label" "ns/openebs enforce='${psa_level:-<sin etiqueta>}' (debería ser privileged)" "#qué-hay-que-tocar-en-cada-caso-el-namespace-sí-el-valuesyaml-no"
  else
    skip "core/openebs-psa-label" "el namespace openebs no existe"
  fi
}

# ---------------------------------------------------------------------------
# crds
# ---------------------------------------------------------------------------
check_crd_group() {
  local label="$1"; shift
  local missing="" c total=0
  for c in "$@"; do
    total=$((total + 1))
    k get crd "$c" >/dev/null 2>&1 || missing="${missing}${c} "
  done
  if [ -z "$missing" ]; then
    ok "crds/${label}" "${total}/${total} CRDs presentes"
  else
    fail "crds/${label}" "faltan: ${missing}" "#aplicar-crds-de-gateway-api"
  fi
}

group_crds() {
  [ "$JSON" = true ] || echo "── crds ──────────────────────────────────────────────────────────"
  check_crd_group "gateway-api" \
    backendtlspolicies.gateway.networking.k8s.io \
    gatewayclasses.gateway.networking.k8s.io \
    gateways.gateway.networking.k8s.io \
    grpcroutes.gateway.networking.k8s.io \
    httproutes.gateway.networking.k8s.io \
    referencegrants.gateway.networking.k8s.io \
    tlsroutes.gateway.networking.k8s.io
  check_crd_group "cilium" \
    ciliumloadbalancerippools.cilium.io \
    ciliuml2announcementpolicies.cilium.io \
    ciliumenvoyconfigs.cilium.io \
    ciliumnetworkpolicies.cilium.io
  check_crd_group "cert-manager" \
    certificates.cert-manager.io \
    certificaterequests.cert-manager.io \
    clusterissuers.cert-manager.io \
    issuers.cert-manager.io
  check_crd_group "external-secrets" \
    externalsecrets.external-secrets.io \
    clusterexternalsecrets.external-secrets.io \
    secretstores.external-secrets.io \
    clustersecretstores.external-secrets.io
  check_crd_group "vso" \
    vaultauthglobals.secrets.hashicorp.com \
    vaultauths.secrets.hashicorp.com \
    vaultconnections.secrets.hashicorp.com \
    vaultstaticsecrets.secrets.hashicorp.com
  check_crd_group "openfeature" \
    featureflags.core.openfeature.dev \
    featureflagsources.core.openfeature.dev \
    flagds.core.openfeature.dev \
    inprocessconfigurations.core.openfeature.dev
  check_crd_group "argoproj" \
    applications.argoproj.io \
    applicationsets.argoproj.io \
    appprojects.argoproj.io \
    rollouts.argoproj.io \
    analysistemplates.argoproj.io \
    clusteranalysistemplates.argoproj.io \
    experiments.argoproj.io \
    analysisruns.argoproj.io
}

# ---------------------------------------------------------------------------
# net
# ---------------------------------------------------------------------------
group_net() {
  [ "$JSON" = true ] || echo "── net ───────────────────────────────────────────────────────────"

  local gc_accepted gc_controller
  gc_accepted=$(k get gatewayclass cilium -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
  gc_controller=$(k get gatewayclass cilium -o jsonpath='{.spec.controllerName}' 2>/dev/null)
  if [ "$gc_accepted" = "True" ] && [ "$gc_controller" = "io.cilium/gateway-controller" ]; then
    ok "net/gatewayclass" "cilium ACCEPTED=True ($gc_controller)"
  else
    fail "net/gatewayclass" "ACCEPTED='${gc_accepted:-<vacío>}' controller='${gc_controller:-<vacío>}'" "#levantar-el-gateway-de-cilium"
  fi

  local programmed
  programmed=$(k get gateway -n "$GATEWAY_NS" "$GATEWAY_NAME" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
  GW_ADDR=$(k get gateway -n "$GATEWAY_NS" "$GATEWAY_NAME" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  if [ "$programmed" = "True" ] && [ -n "$GW_ADDR" ]; then
    ok "net/gateway-programmed" "${GATEWAY_NAME} PROGRAMMED=True addr=${GW_ADDR}"
  else
    fail "net/gateway-programmed" "PROGRAMMED='${programmed:-<vacío>}' addr='${GW_ADDR:-<vacía>}'" "#levantar-el-gateway-de-cilium"
  fi

  # Cada listener Programmed (detecta listener inválido o cert inexistente)
  local bad_listeners line lname lprog
  bad_listeners=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lname="${line%%=*}"; lprog="${line##*=}"
    [ "$lprog" = "True" ] || bad_listeners="${bad_listeners}${lname} "
  done <<EOF
$(k get gateway -n "$GATEWAY_NS" "$GATEWAY_NAME" -o jsonpath='{range .status.listeners[*]}{.name}={.conditions[?(@.type=="Programmed")].status}{"\n"}{end}' 2>/dev/null)
EOF
  if [ -z "$bad_listeners" ]; then
    ok "net/gateway-listeners" "todos los listeners Programmed=True"
  else
    fail "net/gateway-listeners" "listeners no programados: ${bad_listeners}" "#certificados-para-tr%C3%A1fico-externo-del-cl%C3%BAster"
  fi

  # IP pool: Cilium publica el estado en condiciones (con el dato en 'message'),
  # no en campos como 'status.ipv4AvailableIPs'.
  local pool_avail pool_total pool_conflict pool_disabled
  if k get ciliumloadbalancerippool homelab-ip-pool >/dev/null 2>&1; then
    pool_conflict=$(k get ciliumloadbalancerippool homelab-ip-pool -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].status}' 2>/dev/null)
    pool_avail=$(k get ciliumloadbalancerippool homelab-ip-pool -o jsonpath='{.status.conditions[?(@.type=="cilium.io/IPsAvailable")].message}' 2>/dev/null)
    pool_total=$(k get ciliumloadbalancerippool homelab-ip-pool -o jsonpath='{.status.conditions[?(@.type=="cilium.io/IPsTotal")].message}' 2>/dev/null)
    pool_disabled=$(k get ciliumloadbalancerippool homelab-ip-pool -o jsonpath='{.spec.disabled}' 2>/dev/null)
    if [ "$pool_conflict" = "True" ]; then
      fail "net/ip-pool" "homelab-ip-pool con PoolConflict=True" "#opci%C3%B3n-a-cilium-l2-announcement-recomendada"
    elif [ "$pool_disabled" = "true" ]; then
      warn "net/ip-pool" "homelab-ip-pool aparece como disabled"
    else
      ok "net/ip-pool" "homelab-ip-pool activo (${pool_avail:-?}/${pool_total:-?} IPs libres)"
    fi
  else
    fail "net/ip-pool" "no existe CiliumLoadBalancerIPPool homelab-ip-pool" "#opci%C3%B3n-a-cilium-l2-announcement-recomendada"
  fi

  if k get ciliuml2announcementpolicy homelab-l2-announcement >/dev/null 2>&1; then
    ok "net/l2-policy" "homelab-l2-announcement presente"
  else
    fail "net/l2-policy" "no existe CiliumL2AnnouncementPolicy homelab-l2-announcement" "#opci%C3%B3n-a-cilium-l2-announcement-recomendada"
  fi

  if have cilium; then
    # Los estados viven en el JSON ('"state": "OK"' por componente); el modo texto
    # imprime un banner ASCII que no sirve para parsear.
    local cstates
    cstates=$(cilium status --wait=false -o json 2>/dev/null \
      | grep -o '"state": "[^"]*"' | sed 's/.*"state": "//; s/"$//' | sort -u | paste -sd, -)
    case "$cstates" in
      "")                 skip "net/cilium-status" "sin salida de 'cilium status -o json'" ;;
      *Failure*|*Warning*) fail "net/cilium-status" "estados: ${cstates}" "#validar-instalaci%C3%B3n-de-cilium-en-el-cl%C3%BAster" ;;
      *)                  ok "net/cilium-status" "estados: ${cstates}" ;;
    esac
  else
    skip "net/cilium-status" "binario 'cilium' no instalado"
  fi
}

# ---------------------------------------------------------------------------
# workloads
# ---------------------------------------------------------------------------
group_workloads() {
  [ "$JSON" = true ] || echo "── workloads ─────────────────────────────────────────────────────"

  # Réplicas ready vs deseadas
  local id ns kind name expect ready desired
  while IFS='|' read -r id ns kind name expect; do
    [ -z "$id" ] && continue
    if ! ns_exists "$ns"; then
      skip "workloads/${id}" "namespace ${ns} no existe"
      continue
    fi
    case "$kind" in
      deploy)
        ready=$(k get deploy "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        desired=$(k get deploy "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        ;;
      sts)
        ready=$(k get sts "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        desired=$(k get sts "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
        ;;
      ds)
        ready=$(k get ds "$name" -n "$ns" -o jsonpath='{.status.numberReady}' 2>/dev/null)
        desired=$(k get ds "$name" -n "$ns" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        expect="$NODE_COUNT"
        ;;
    esac
    ready="${ready:-0}"; desired="${desired:-0}"; expect="${expect:-$desired}"

    if [ "$ready" = "$expect" ] && [ "$desired" = "$expect" ]; then
      ok "workloads/${id}" "${ready}/${expect} ready"
    elif [ "$desired" != "$expect" ]; then
      warn "workloads/${id}" "deseadas ${desired}, esperadas ${expect} (¿cambio intencionado?)"
    else
      fail "workloads/${id}" "${ready}/${desired} ready (esperadas ${expect})" "#instalaci%C3%B3n-de-componentes-utilitarios"
    fi
  done <<'EOF'
replicas-kubelet-csr|kube-system|deploy|kubelet-csr-approver|1
replicas-cilium|kube-system|ds|cilium|-|
replicas-cilium-envoy|kube-system|ds|cilium-envoy|-|
replicas-cilium-operator|kube-system|deploy|cilium-operator|1
replicas-coredns|kube-system|deploy|coredns|3
replicas-hubble-relay|kube-system|deploy|hubble-relay|1
replicas-hubble-ui|kube-system|deploy|hubble-ui|1
replicas-descheduler|kube-system|deploy|descheduler|1
replicas-metrics-server|kube-system|deploy|metrics-server|2
replicas-cert-manager|cert-manager|deploy|cert-manager|1
replicas-cert-cainjector|cert-manager|deploy|cert-manager-cainjector|1
replicas-cert-webhook|cert-manager|deploy|cert-manager-webhook|1
replicas-trust-manager|cert-manager|deploy|trust-manager|1
replicas-openebs|openebs|deploy|openebs-localpv-provisioner|2
replicas-eso|external-secrets|deploy|external-secrets|1
replicas-eso-cert|external-secrets|deploy|external-secrets-cert-controller|1
replicas-eso-webhook|external-secrets|deploy|external-secrets-webhook|1
replicas-vso|vault-secrets-operator|deploy|vault-secrets-operator-controller-manager|1
replicas-argocd-controller|argocd|sts|argo-cd-argocd-application-controller|1
replicas-argocd-appset|argocd|deploy|argo-cd-argocd-applicationset-controller|1
replicas-argocd-redis|argocd|deploy|argo-cd-argocd-redis|1
replicas-argocd-repo|argocd|deploy|argo-cd-argocd-repo-server|1
replicas-argocd-server|argocd|deploy|argo-cd-argocd-server|1
replicas-argo-rollouts|argo-rollouts|deploy|argo-rollouts|2
replicas-argo-rollouts-dash|argo-rollouts|deploy|argo-rollouts-dashboard|1
replicas-reloader|reloader|deploy|reloader-reloader|1
replicas-openfeature|open-feature-operator-system|deploy|open-feature-operator-controller-manager|1
replicas-cloudflared|cloudflare-tunnel-system|deploy|cloudflared|2
EOF

  # Placement por prefijo de nodo
  local id2 ns2 prefix allowed nodes node bad_nodes
  while IFS='|' read -r id2 ns2 prefix allowed; do
    [ -z "$id2" ] && continue
    if ! ns_exists "$ns2"; then
      skip "placement/${id2}" "namespace ${ns2} no existe"
      continue
    fi
    # '-o wide' es imprescindible: sin él la columna 7 no es el nodo.
    nodes=$(k get pods -n "$ns2" -o wide --no-headers 2>/dev/null | awk -v p="$prefix" '$1 ~ "^"p {print $7}' | sort -u)
    if [ -z "$nodes" ]; then
      skip "placement/${id2}" "sin pods '${prefix}*' en ${ns2}"
      continue
    fi
    bad_nodes=""
    for node in $nodes; do
      local match=false p
      # Los valores de 'allowed' son fragmentos glob que se buscan en cualquier parte
      # del nombre del nodo: 'ops*' matchea 'worker-ops-02' y 'worker-ops-03'.
      for p in $(printf '%s' "$allowed" | tr ',' ' '); do
        case "$node" in *$p) match=true ;; esac
      done
      [ "$match" = true ] || bad_nodes="${bad_nodes}${node} "
    done
    if [ -z "$bad_nodes" ]; then
      ok "placement/${id2}" "$(printf '%s' "$nodes" | tr '\n' ' ')"
    else
      fail "placement/${id2}" "en nodos fuera de [${allowed}]: ${bad_nodes}" "#distribuci%C3%B3n-de-vms"
    fi
  done <<'EOF'
kubelet-csr|kube-system|kubelet-csr-approver|ops*
coredns|kube-system|coredns|apps*,data*,ops*
descheduler|kube-system|descheduler|ops*
metrics-server|kube-system|metrics-server|ops*,apps*
cert-manager|cert-manager|cert-manager|ops*
trust-manager|cert-manager|trust-manager|ops*
openebs|openebs|openebs-localpv-provisioner|ops*,apps*
external-secrets|external-secrets|external-secrets|ops*
vso|vault-secrets-operator|vault-secrets-operator-controller-manager|ops*
argocd|argocd|argo-cd-argocd|ops*
argo-rollouts|argo-rollouts|argo-rollouts|ops*,apps*
reloader|reloader|reloader-reloader|ops*
openfeature|open-feature-operator-system|open-feature-operator-controller-manager|ops*,heavy*
cloudflared|cloudflare-tunnel-system|cloudflared|ops*,apps*
shared-ops-jobs|shared-ops|sync-vault-cert|ops*
EOF

  # Prueba real de metrics-server (el pod Running no garantiza que la API responda)
  if k top nodes >/dev/null 2>&1; then
    ok "workloads/metrics-api" "'kubectl top nodes' responde"
  else
    fail "workloads/metrics-api" "'kubectl top nodes' no responde (metrics-server sin métricas)" "#metrics-server"
  fi
}

# ---------------------------------------------------------------------------
# tls
# ---------------------------------------------------------------------------
group_tls() {
  [ "$JSON" = true ] || echo "── tls ───────────────────────────────────────────────────────────"

  # ClusterIssuers
  local bad="" line iname istatus
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    iname="${line%%=*}"; istatus="${line##*=}"
    [ "$istatus" = "True" ] || bad="${bad}${iname} "
  done <<EOF
$(k get clusterissuer -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)
EOF
  if [ -z "$bad" ]; then
    ok "tls/clusterissuers" "todos los ClusterIssuer Ready=True"
  else
    fail "tls/clusterissuers" "no Ready: ${bad}" "#configurar-el-clusterissuer-de-let-s-encrypt"
  fi

  # Certificados en todos los namespaces
  local cert_bad="" cns cname cstatus
  while IFS='|' read -r cns cname cstatus; do
    [ -z "$cname" ] && continue
    [ "$cstatus" = "True" ] || cert_bad="${cert_bad}${cns}/${cname} "
  done <<EOF
$(k get certificates -A -o jsonpath='{range .items[*]}{.metadata.namespace}|{.metadata.name}|{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null)
EOF
  if [ -z "$cert_bad" ]; then
    ok "tls/certificates-ready" "todos los Certificate Ready=True"
  else
    fail "tls/certificates-ready" "no Ready: ${cert_bad}" "#monitorear-el-progreso-del-certificado"
  fi

  # Expiración
  local soon="" exp_epoch now_epoch days
  now_epoch=$(date +%s)
  while IFS='|' read -r cns cname cuntil; do
    [ -z "$cname" ] && continue
    exp_epoch=$(to_epoch "$cuntil")
    [ -z "$exp_epoch" ] && continue
    days=$(( (exp_epoch - now_epoch) / 86400 ))
    [ "$days" -lt 7 ] && soon="${soon}${cns}/${cname}(${days}d) "
  done <<EOF
$(k get certificates -A -o jsonpath='{range .items[*]}{.metadata.namespace}|{.metadata.name}|{.status.notAfter}{"\n"}{end}' 2>/dev/null)
EOF
  if [ -z "$soon" ]; then
    ok "tls/certificates-expiry" "ningún certificado expira en menos de 7 días"
  else
    warn "tls/certificates-expiry" "expiran pronto: ${soon}"
  fi

  # trust-manager distribuye el bundle
  local bundle_ns missing_bundle="" ns
  local total_ns
  total_ns=$(k get namespace --no-headers 2>/dev/null | wc -l | tr -d ' ')
  bundle_ns=$(k get configmap -A --field-selector metadata.name=cluster-trusted-ca -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' 2>/dev/null)
  for ns in $(k get namespace -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null); do
    case "$ns" in
      kube-system|kube-public|kube-node-lease) continue ;;
    esac
    printf '%s\n' "$bundle_ns" | grep -qx "$ns" || missing_bundle="${missing_bundle}${ns} "
  done
  if [ -z "$missing_bundle" ]; then
    ok "tls/trust-bundle" "cluster-trusted-ca presente en todos los namespaces"
  else
    warn "tls/trust-bundle" "sin cluster-trusted-ca: ${missing_bundle}"
  fi

  # Cobertura ruta -> listener -> SAN del certificado servido
  check_route_san_coverage
}

check_route_san_coverage() {
  local line kind rns rname hosts host lname lpattern matched listener_list san_ok sans total=0 covered=0 bad=""

  # Patrones de listener
  listener_list=$(k get gateway -n "$GATEWAY_NS" "$GATEWAY_NAME" -o jsonpath='{range .spec.listeners[*]}{.name}|{.hostname}{"\n"}{end}' 2>/dev/null)

  while IFS='|' read -r kind rns rname hosts; do
    [ -z "$rname" ] && continue
    [ -z "$hosts" ] && continue
    for host in $hosts; do
      total=$((total + 1))
      matched=""
      # 1) ¿Algún listener del Gateway acepta este hostname?
      while IFS='|' read -r lname lpattern; do
        [ -z "$lname" ] && continue
        if host_in_listener_pattern "$host" "$lpattern"; then
          matched="$lname"
          break
        fi
      done <<EOF
$listener_list
EOF
      if [ -z "$matched" ]; then
        bad="${bad}${host}(sin listener) "
        continue
      fi
      # 2) ¿El certificado servido por SNI cubre el hostname?
      sans=$(san_list_from_server "$host")
      san_ok=false
      for san in $sans; do
        if san_covers_host "$san" "$host"; then san_ok=true; break; fi
      done
      if [ "$san_ok" = true ]; then
        covered=$((covered + 1))
      else
        bad="${bad}${host}(sin SAN; servido: ${sans:-<sin respuesta>}) "
      fi
    done
  done <<EOF
$(k get httproute,grpcroute -A -o jsonpath='{range .items[*]}{.kind}|{.metadata.namespace}|{.metadata.name}|{.spec.hostnames[*]}{"\n"}{end}' 2>/dev/null)
EOF

  if [ "$total" -eq 0 ]; then
    skip "tls/route-san-coverage" "no hay rutas con hostnames"
  elif [ -z "$bad" ]; then
    ok "tls/route-san-coverage" "${covered}/${total} hostnames con listener y SAN válidos"
  else
    fail "tls/route-san-coverage" "${bad}" "#profundidad-de-subdominios-listeners-wildcards-y-certificados"
  fi
}

# ---------------------------------------------------------------------------
# secrets
# ---------------------------------------------------------------------------
group_secrets() {
  [ "$JSON" = true ] || echo "── secrets ───────────────────────────────────────────────────────"

  if ns_exists vault-secrets-operator; then
    local healthy ready
    healthy=$(k get vaultconnections -n vault-secrets-operator -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Healthy")].status}{"\n"}{end}' 2>/dev/null | grep -c True)
    ready=$(k get vaultconnections -n vault-secrets-operator -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c True)
    if [ "$healthy" -ge 1 ] && [ "$ready" -ge 1 ]; then
      ok "secrets/vso-connection" "VaultConnection Healthy/Ready"
    else
      fail "secrets/vso-connection" "VaultConnection healthy=${healthy} ready=${ready}" "#obtener-secretos-con-vso"
    fi

    if [ "$(k get vaultauthglobals -n vault-secrets-operator --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]; then
      ok "secrets/vso-authglobal" "VaultAuthGlobal presente"
    else
      fail "secrets/vso-authglobal" "no hay VaultAuthGlobal" "#obtener-secretos-con-vso"
    fi
  else
    skip "secrets/vso-connection" "namespace vault-secrets-operator no existe"
    skip "secrets/vso-authglobal" "namespace vault-secrets-operator no existe"
  fi

  if [ "$(k get configmap -n external-secrets vault-ca-cert --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]; then
    ok "secrets/eso-ca-configmap" "cm/external-secrets/vault-ca-cert presente"
  else
    fail "secrets/eso-ca-configmap" "falta cm/external-secrets/vault-ca-cert" "#verificar-la-confianza-del-certificado-de-vault"
  fi

  if [ "$(k get secret -n vault-secrets-operator vault-ca-cert --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]; then
    ok "secrets/vso-ca-secret" "secret/vault-secrets-operator/vault-ca-cert presente"
  else
    fail "secrets/vso-ca-secret" "falta secret/vault-secrets-operator/vault-ca-cert" "#verificar-la-confianza-del-certificado-de-vault"
  fi

  if ns_exists shared-ops; then
    local jobs_bad="" jn js
    while IFS='|' read -r jn js; do
      [ -z "$jn" ] && continue
      [ "$js" = "True" ] || jobs_bad="${jobs_bad}${jn} "
    done <<EOF
$(k get jobs -n shared-ops -o jsonpath='{range .items[*]}{.metadata.name}|{.status.conditions[?(@.type=="Complete")].status}{"\n"}{end}' 2>/dev/null)
EOF
    if [ -z "$jobs_bad" ]; then
      ok "secrets/vault-syncer-jobs" "todos los Jobs de shared-ops Complete"
    else
      fail "secrets/vault-syncer-jobs" "Jobs incompletos: ${jobs_bad}" "#sincronizaci%C3%B3n-del-certificado-del-servidor-de-vault"
    fi
  else
    skip "secrets/vault-syncer-jobs" "namespace shared-ops no existe"
  fi
}

# ---------------------------------------------------------------------------
# storage
# ---------------------------------------------------------------------------
group_storage() {
  [ "$JSON" = true ] || echo "── storage ───────────────────────────────────────────────────────"

  local def
  def=$(k get storageclass openebs-hostpath -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
  if [ "$def" = "true" ]; then
    ok "storage/default-class" "openebs-hostpath es la StorageClass por defecto"
  else
    fail "storage/default-class" "openebs-hostpath no es default (valor: '${def:-<vacío>}')" "#usar-openebs-como-storageclass"
  fi

  local pending
  pending=$(k get pvc -A --no-headers 2>/dev/null | awk '$3 == "Pending" {print $1 "/" $2}' | paste -sd, -)
  if [ -z "$pending" ]; then
    ok "storage/pvc-pending" "ninguna PVC en Pending"
  else
    fail "storage/pvc-pending" "PVCs en Pending: ${pending}" "#configuraci%C3%B3n-del-almacenamiento-local-storageclass---csi-container-storage-interface"
  fi
}

# ---------------------------------------------------------------------------
# gitops
# ---------------------------------------------------------------------------
group_gitops() {
  [ "$JSON" = true ] || echo "── gitops ────────────────────────────────────────────────────────"

  if ! ns_exists "$ARGOCD_NS"; then
    skip "gitops/argocd" "namespace ${ARGOCD_NS} no existe"
    return
  fi

  # Argo CD alcanzable por HTTPS y por gRPC (el 404 del CLI)
  local https_host grpc_host code
  https_host=$(k get httproute -n "$ARGOCD_NS" -o jsonpath='{.items[0].spec.hostnames[0]}' 2>/dev/null)
  grpc_host=$(k get grpcroute -n "$ARGOCD_NS" -o jsonpath='{.items[0].spec.hostnames[0]}' 2>/dev/null)

  if [ -n "$https_host" ] && [ -n "$GW_ADDR" ]; then
    code=$(curl -sk --max-time "$TIMEOUT" --resolve "${https_host}:443:${GW_ADDR}" -o /dev/null -w '%{http_code}' "https://${https_host}" 2>/dev/null)
    if [ "$code" = "200" ]; then
      ok "gitops/argocd-https" "${https_host} -> 200"
    else
      fail "gitops/argocd-https" "${https_host} -> ${code}" "#acceso-del-cli-a-trav%C3%A9s-del-gateway-api-grpc"
    fi
  else
    skip "gitops/argocd-https" "sin HTTPRoute o sin IP de Gateway"
  fi

  if [ -n "$grpc_host" ] && [ -n "$GW_ADDR" ]; then
    code=$(curl -sk --http2 --max-time "$TIMEOUT" --resolve "${grpc_host}:443:${GW_ADDR}" -o /dev/null -w '%{http_code}' \
      -X POST "https://${grpc_host}/session.SessionService/Create" -H 'Content-Type: application/grpc' 2>/dev/null)
    if [ "$code" = "200" ]; then
      ok "gitops/argocd-grpc" "${grpc_host} -> 200"
    else
      fail "gitops/argocd-grpc" "${grpc_host} -> ${code} (¿GRPCRoute desprogramada?)" "#acceso-del-cli-a-trav%C3%A9s-del-gateway-api-grpc"
    fi
  else
    skip "gitops/argocd-grpc" "sin GRPCRoute o sin IP de Gateway"
  fi

  if [ "$(k get appproject -n "$ARGOCD_NS" "$APP_PROJECT" --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]; then
    ok "gitops/appproject" "AppProject ${APP_PROJECT} presente"
  else
    fail "gitops/appproject" "falta AppProject ${APP_PROJECT}" "#bootstrap-app-of-apps"
  fi

  if [ "$(k get applicationsets -n "$ARGOCD_NS" "$APPSET_NAME" --no-headers 2>/dev/null | wc -l | tr -d ' ')" -ge 1 ]; then
    local generated
    generated=$(k get application -n "$ARGOCD_NS" -o jsonpath='{range .items[*]}{.metadata.ownerReferences[?(@.kind=="ApplicationSet")].name}{"\n"}{end}' 2>/dev/null | grep -c "$APPSET_NAME")
    if [ "$generated" -ge 1 ]; then
      ok "gitops/appset-generated" "${APPSET_NAME} generó ${generated} Application(s)"
    else
      fail "gitops/appset-generated" "${APPSET_NAME} sin Applications generadas (¿revision o path del generador?)" "#variante-escalable-applicationset"
    fi
  else
    fail "gitops/appset" "falta ApplicationSet ${APPSET_NAME}" "#variante-escalable-applicationset"
  fi

  # Todas las Applications Synced + Healthy (aquí es FAIL, no aviso)
  local apps_bad="" an asyn ahea apps_total=0
  while IFS='|' read -r an asyn ahea; do
    [ -z "$an" ] && continue
    apps_total=$((apps_total + 1))
    if [ "$asyn" != "Synced" ] || [ "$ahea" != "Healthy" ]; then
      apps_bad="${apps_bad}${an}(${asyn:-?}/${ahea:-?}) "
    fi
  done <<EOF
$(k get application -n "$ARGOCD_NS" -o jsonpath='{range .items[*]}{.metadata.name}|{.status.sync.status}|{.status.health.status}{"\n"}{end}' 2>/dev/null)
EOF
  if [ "$apps_total" -eq 0 ]; then
    fail "gitops/applications" "no hay Applications en ${ARGOCD_NS}" "#bootstrap-app-of-apps"
  elif [ -z "$apps_bad" ]; then
    ok "gitops/applications" "${apps_total}/${apps_total} Synced+Healthy"
  else
    fail "gitops/applications" "${apps_bad}" "#la-espera-activa-del-bootstrap-cu%C3%A1ndo-se-ejecuta-y-c%C3%B3mo-verificar-el-estado"
  fi
}

# ---------------------------------------------------------------------------
# slow (opt-in)
# ---------------------------------------------------------------------------
group_slow() {
  [ "$JSON" = true ] || echo "── slow (opt-in) ─────────────────────────────────────────────────"

  if [ "$WITH_CONNECTIVITY" = true ]; then
    if have cilium; then
      echo "   ⏳ cilium connectivity test (puede tardar)"
      if cilium connectivity test --test '!pod-log-errors' \
           --namespace-labels pod-security.kubernetes.io/enforce=privileged >/tmp/validate-connectivity.log 2>&1; then
        ok "slow/connectivity" "cilium connectivity test OK"
      else
        fail "slow/connectivity" "falló (ver /tmp/validate-connectivity.log)" "#troubleshooting-en-caso-de-que-falle-el-connectivity-test-por-dns"
      fi
    else
      skip "slow/connectivity" "binario 'cilium' no instalado"
    fi
  fi

  if [ "$WITH_CHAOS" = true ]; then
    if [ -x "${REPO_ROOT}/tests/gateway-chaos-test.sh" ] && have nc && have jq; then
      echo "   ⏳ gateway-chaos-test (migración de la IP flotante)"
      if "${REPO_ROOT}/tests/gateway-chaos-test.sh" >/tmp/validate-chaos.log 2>&1; then
        ok "slow/gateway-chaos" "la IP flotante migró correctamente"
      else
        fail "slow/gateway-chaos" "falló (ver /tmp/validate-chaos.log)" "#2-simulaci%C3%B3n-de-fallo-chaos-engineering-para-la-ip-flotante"
      fi
    else
      skip "slow/gateway-chaos" "requiere nc, jq y tests/gateway-chaos-test.sh"
    fi
  fi

  # --with-app y --with-vso-e2e comparten el namespace playground, así que este NO se
  # borra al final del primer bloque: se limpia una sola vez al final del grupo.
  if [ "$WITH_APP" = true ]; then
    [ "$JSON" = true ] || echo "   ⏳ playground nginx (aplicar, validar)"
    k apply -f "${REPO_ROOT}/tests/playground-nginx.yaml" >/dev/null 2>&1
    if k wait --for=condition=available deployment/playground-nginx-app -n playground --timeout=180s >/dev/null 2>&1; then
      local h body okc=0 totalc=0 tries code
      for h in playground.eljavatar.home playground.eljavatar.org; do
        # Solo validamos el dominio público si el listener existe (use_prod_domain)
        if [ "$h" = "playground.eljavatar.home" ] || [ -n "$(k get gateway -n "$GATEWAY_NS" "$GATEWAY_NAME" -o jsonpath='{.spec.listeners[?(@.name=="https-publico")].name}' 2>/dev/null)" ]; then
          totalc=$((totalc + 1))
          # La ruta puede tardar unos segundos en programarse en Envoy: reintentamos.
          for tries in 1 2 3 4 5 6; do
            body=$(curl -sk --max-time "$TIMEOUT" --resolve "${h}:443:${GW_ADDR}" "https://${h}" 2>/dev/null)
            case "$body" in *"Welcome to nginx"*) okc=$((okc + 1)); break ;; esac
            sleep 5
          done
        fi
      done
      if [ "$okc" -eq "$totalc" ] && [ "$totalc" -gt 0 ]; then
        ok "slow/app-nginx" "${okc}/${totalc} dominios sirven 'Welcome to nginx'"
      else
        code=$(curl -sk --max-time "$TIMEOUT" --resolve "playground.eljavatar.home:443:${GW_ADDR}" -o /dev/null -w '%{http_code}' "https://playground.eljavatar.home" 2>/dev/null)
        fail "slow/app-nginx" "${okc}/${totalc} dominios correctos (playground.eljavatar.home -> ${code:-sin respuesta})" "#3-desplegar-una-app-de-prueba-con-su-service-y-httproute"
      fi
    else
      local podstate
      podstate=$(k get pods -n playground --no-headers 2>/dev/null | awk '{print $1 "(" $3 ")"}' | paste -sd, -)
      fail "slow/app-nginx" "el Deployment de playground no llegó a available (${podstate:-sin pods})" "#3-desplegar-una-app-de-prueba-con-su-service-y-httproute"
    fi
  fi

  if [ "$WITH_VSO_E2E" = true ]; then
    [ "$JSON" = true ] || echo "   ⏳ VSO end-to-end (namespace, VaultAuth, VaultStaticSecret)"
    # El namespace puede no existir: --with-app es opcional y este bloque se ejecuta solo.
    k create namespace playground --dry-run=client -o yaml 2>/dev/null | k apply -f - >/dev/null 2>&1

    # Los VaultStaticSecret referencian 'vault-auth-playground' y 'vault-auth-demo'
    # (vaultAuthRef), y esos VaultAuth los crea tests/vso-auth.yaml: sin él el VSS
    # nunca pasa a Ready. Orden obligatorio: primero el auth, después el secreto.
    k apply -f "${REPO_ROOT}/tests/vso-auth.yaml" >/dev/null 2>&1
    k apply -f "${REPO_ROOT}/tests/vso-secret.yaml" >/dev/null 2>&1

    local ready=false i vstatus vmsg secrets_n
    for i in $(seq 1 18); do
      vstatus=$(k get vaultstaticsecret vault-static-secret-playground -n playground \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
      [ "$vstatus" = "True" ] && { ready=true; break; }
      sleep 5
    done

    if [ "$ready" = true ]; then
      secrets_n=$(k get secret -n playground playground-nginx-secret --no-headers 2>/dev/null | wc -l | tr -d ' ')
      ok "slow/vso-e2e" "VaultStaticSecret Ready=True y Secret materializado (${secrets_n} secret)"
    else
      vmsg=$(k get vaultstaticsecret vault-static-secret-playground -n playground \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
      fail "slow/vso-e2e" "VaultStaticSecret no Ready (${vmsg:-sin mensaje})" "#obtener-secretos-con-vso"
    fi

    k delete -f "${REPO_ROOT}/tests/vso-secret.yaml" --ignore-not-found >/dev/null 2>&1
    k delete -f "${REPO_ROOT}/tests/vso-auth.yaml" --ignore-not-found >/dev/null 2>&1
  fi

  # Limpieza única del namespace compartido por --with-app y --with-vso-e2e
  if [ "$WITH_APP" = true ] || [ "$WITH_VSO_E2E" = true ]; then
    k delete namespace playground --ignore-not-found >/dev/null 2>&1
  fi

  if [ "$WITH_CONNECTIVITY" = false ] && [ "$WITH_CHAOS" = false ] \
     && [ "$WITH_APP" = false ] && [ "$WITH_VSO_E2E" = false ]; then
    skip "slow/opt-in" "usa --with-connectivity, --with-chaos, --with-app o --with-vso-e2e"
  fi
}

# ---------------------------------------------------------------------------
# Argumentos
# ---------------------------------------------------------------------------
usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

for arg in "$@"; do
  case "$arg" in
    --help|-h)       usage ;;
    --only=*)        ONLY="$(printf '%s' "${arg#*=}" | tr ',' ' ') ";;
    --skip=*)        SKIP="$(printf '%s' "${arg#*=}" | tr ',' ' ') ";;
    --with-connectivity) WITH_CONNECTIVITY=true ;;
    --with-chaos)    WITH_CHAOS=true ;;
    --with-app)      WITH_APP=true ;;
    --with-vso-e2e)  WITH_VSO_E2E=true ;;
    --timeout=*)     TIMEOUT="${arg#*=}" ;;
    --json)          JSON=true ;;
    --verbose|-v)    VERBOSE=true ;;
    *) echo "Opción desconocida: $arg (usa --help)" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
have kubectl || { echo "ERROR: kubectl no está instalado." >&2; exit 2; }

# KUBECONFIG del entorno o el que genera Terraform
if [ -z "${KUBECONFIG:-}" ] && [ -f "${REPO_ROOT}/talos/kubeconfig" ]; then
  export KUBECONFIG="${REPO_ROOT}/talos/kubeconfig"
fi

if ! k get --raw='/readyz' >/dev/null 2>&1; then
  echo "ERROR: no se puede contactar el clúster." >&2
  echo "       KUBECONFIG actual: ${KUBECONFIG:-<sin definir>}" >&2
  echo "       Revisa el contexto: kubectl config current-context" >&2
  exit 2
fi

if [ "$JSON" = false ]; then
  echo "Validación del clúster · $(date '+%Y-%m-%d %H:%M:%S') · contexto: $(kubectl config current-context 2>/dev/null)"
  echo
fi

# ---------------------------------------------------------------------------
# Ejecución
# ---------------------------------------------------------------------------
for g in $GROUPS_ALL; do
  group_enabled "$g" || continue
  "group_${g}"
  echo
done
if [ "$WITH_CONNECTIVITY" = true ] || [ "$WITH_CHAOS" = true ] || [ "$WITH_APP" = true ] || [ "$WITH_VSO_E2E" = true ]; then
  group_slow
  echo
fi

# ---------------------------------------------------------------------------
# Resumen
# ---------------------------------------------------------------------------
if [ "$JSON" = true ]; then
  printf '{"ok":%d,"fail":%d,"warn":%d,"skip":%d,"failed":["%s"],"checks":[%s]}\n' \
    "$N_OK" "$N_FAIL" "$N_WARN" "$N_SKIP" \
    "$(printf '%s' "$FAILED_IDS" | sed 's/ *$//' | sed 's/ /","/g')" "$JSON_ROWS"
else
  echo "══════════════════════════════════════════════════════════════════"
  printf 'Resumen: %s%d OK%s · %s%d FAIL%s · %s%d WARN%s · %s%d SKIP%s\n' \
    "$C_OK" "$N_OK" "$C_OFF" "$C_FAIL" "$N_FAIL" "$C_OFF" \
    "$C_WARN" "$N_WARN" "$C_OFF" "$C_SKIP" "$N_SKIP" "$C_OFF"
  if [ "$N_FAIL" -gt 0 ]; then
    echo
    echo "Fallos: ${FAILED_IDS}"
    echo "Cada FAIL imprime arriba el ancla del README con su troubleshooting."
  fi
fi

[ "$N_FAIL" -gt 0 ] && exit 1
exit 0
