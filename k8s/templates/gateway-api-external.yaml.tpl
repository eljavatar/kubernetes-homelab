# yaml-language-server: $schema=none
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: external-gateway
  namespace: gateway-api-system
  annotations:
    io.cilium/lb-ipam-ips: "192.168.0.70"
spec:
  gatewayClassName: cilium
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
    # --- LISTENER 1: TRÁFICO LOCAL PRIVADO ---
    - name: https-local
      port: 443
      protocol: HTTPS
      hostname: "*.eljavatar.home"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: cert-gateway-local-secret 
    # --- LISTENER 2: TRÁFICO PÚBLICO (Solo si está activo) ---
    %{ if USE_PROD_DOMAIN }
    - name: https-publico
      protocol: HTTPS
      port: 443
      hostname: "*.eljavatar.org"
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: cert-letsencrypt-public-secret
    %{ endif }
