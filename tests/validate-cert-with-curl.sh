#!/bin/bash
# validar-cert.sh

IP_CILIUM_GATEWAY="192.168.0.70"

echo "=== probando AMBIENTE PÚBLICO (.org) ==="
curl -vI --resolve "api.eljavatar.org:443:$IP_CILIUM_GATEWAY" "https://api.eljavatar.org" 2>&1 | grep -E "SSL connection|issuer|subject|TLS handshake|CAfile|CApath"

echo -e "\n=== probando AMBIENTE LOCAL (.home) ==="
curl -vI --resolve "api.eljavatar.home:443:$IP_CILIUM_GATEWAY" "https://api.eljavatar.home" 2>&1 | grep -E "SSL connection|issuer|subject|TLS handshake|CAfile|CApath"
