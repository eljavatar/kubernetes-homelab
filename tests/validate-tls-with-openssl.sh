#!/bin/bash
# debug-tls.sh

IP_CILIUM_GATEWAY="192.168.0.70"

echo "=== DETALLE EMISOR: DOMINIO PÚBLICO ==="
openssl s_client -connect "$IP_CILIUM_GATEWAY:443" -servername "api.eljavatar.org" -showcerts </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates

echo -e "\n=== DETALLE EMISOR: DOMINIO LOCAL ==="
openssl s_client -connect "$IP_CILIUM_GATEWAY:443" -servername "api.eljavatar.home" -showcerts </dev/null 2>/dev/null | openssl x509 -noout -issuer -subject -dates
