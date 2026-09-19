# Permitir absolutamente todo en cualquier ruta de Vault
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "patch", "sudo"]
}
