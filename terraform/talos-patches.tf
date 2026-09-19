# Una nota importante para el "Futuro" (Día 2)
# 
# En este caso, estamos usando talos_machine_configuration para generar la configuración de inicio de las VMs
# con la IP estática y hostname requerido, por lo que no necesitamos de talos_machine_configuration_apply.
# 
# ¿Cuándo necesitarríamos usar talos_machine_configuration_apply?
# 
# Únicamente en el "Día 2" de las operaciones del clúster. Si dentro de 6 meses se requiere cambiar un
# parámetro de Kubernetes, añadir un proxy, o cambiar una configuración del kernel de Talos sin destruir
# la VM, el Snippet de Cloud-Init ya no servirá (porque Cloud-Init solo corre en el primer arranque).
# 
# En ese escenario futuro, se añadiría el talos_machine_configuration_apply apuntando a las IPs ya
# existentes para actualizar los nodos en vivo.
# 
# Con esta configuración, evitamos tener que ejecutar patchs desde la terminal por cada VM:
# resource "talos_machine_configuration_apply" "patch_1" {
#   for_each = local.vms

#   client_configuration        = var.client_configuration
#   machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
#   node                        = each.value.ip
#   # También podríamos usar yamlencode como lo hicimos en talos_machine_configuration
#   config_patches              = [file("${path.module}/talos/patches/${each.key}.yaml")]

#   # Esto asegura que si cambia la seguridad, Talos aplique el parche de inmediato
#   lifecycle {
#     create_before_destroy = false
#   }

#   # REGLA CRÍTICA DE ORDEN: Espera a que el módulo de Proxmox termine por completo
#   depends_on = [
#     module.talos_node
#   ]

# }
