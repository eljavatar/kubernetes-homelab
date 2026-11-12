#!/usr/bin/env bash
#
# Publica el árbol GitOps en una rama de pruebas, sin acumular historial.
#
# Comportamiento:
#   1. Reescribe la rama de trabajo partiendo del commit actual (git switch -C).
#      Esto NO toca el working tree: los cambios sin commitear se conservan.
#   2. Añade solo las rutas indicadas (por defecto gitops/ y k8s/).
#      Se publica todo 'k8s/' porque Argo CD lee de Git tanto los values del bootstrap
#      (k8s/bootstrap/deployments/) como los de las aplicaciones (k8s/apps/).
#   3. Crea un commit solo si hay cambios.
#   4. Fuerza el push con --force-with-lease, de modo que la rama remota siempre
#      queda "un commit por encima de main" y nunca acumula commits de prueba.
#
# La integración a main se hace con squash (un único commit limpio):
#   git switch main
#   git merge --squash "$GITOPS_BRANCH"
#   git commit -m "feat(gitops): ..."
#
# Variables de entorno:
#   GITOPS_BRANCH   Rama de trabajo (default: test/gitops-bootstrap)
#   GITOPS_PATHS    Rutas a publicar, separadas por espacios
#                   (default: "gitops/ k8s/")
#   GITOPS_SSH_KEY  Clave SSH para el push (default: ~/.ssh/id_ed25519_gitops)
#
# Uso:
#   ./scripts/gitops-publish.sh
#   GITOPS_BRANCH=test/observability ./scripts/gitops-publish.sh
#   make gitops-publish

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANCH="${GITOPS_BRANCH:-test/gitops-bootstrap}"
SSH_KEY="${GITOPS_SSH_KEY:-$HOME/.ssh/id_ed25519_gitops}"
REMOTE="${GITOPS_REMOTE:-gitops}"
read -r -a PATHS <<< "${GITOPS_PATHS:-gitops/ k8s/}"

# echo "BASH_SOURCE: ${BASH_SOURCE[0]}"
# echo "REPO_ROOT: ${REPO_ROOT}"
# echo "GITOPS_BRANCH: ${GITOPS_BRANCH}"
# echo "BRANCH: ${BRANCH}"
# #echo "GITOPS_SSH_KEY: ${GITOPS_SSH_KEY}"
# echo "SSH_KEY: ${SSH_KEY}"
# #echo "GITOPS_PATHS: ${GITOPS_PATHS}"
# echo "REMOTE: ${REMOTE}"
# echo "PATHS @: ${PATHS[@]}"
# echo "PATHS *: ${PATHS[*]}"

export GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
export GIT_TERMINAL_PROMPT=0

cd "$REPO_ROOT"

# Valida si REPO_ROOT es un directorio de trabajo Git válido
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: ${REPO_ROOT} no es un repositorio Git." >&2
  exit 1
fi

# Nunca publicar sobre la rama por defecto (que suele ser main (o master para repositorios antiguos))
DEFAULT_BRANCH="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)"
if [ "$BRANCH" = "$DEFAULT_BRANCH" ]; then
  echo "ERROR: '${BRANCH}' es la rama por defecto; usa una rama test/<tema>." >&2
  exit 1
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
  echo "Aviso: estás en '${CURRENT_BRANCH}'. Se creará/reescribirá '${BRANCH}' desde el estado actual."
fi

# 1. Reescribe el puntero de la rama (no toca archivos sin commitear)
git switch -C "$BRANCH"

# 2. Añade solo las rutas de GitOps (o las que se pasen en el argumento GITOPS_PATHS)
git add -- "${PATHS[@]}"

# 3. Commit únicamente si hay algo staged
if git diff --cached --quiet; then
  echo "Sin cambios en: ${PATHS[*]} (nada que publicar)."
else
  git commit -m "chore(gitops): snapshot de pruebas $(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi

# 3b. Aviso temprano: sin application.yaml, root sincroniza con 0 recursos
if ! git ls-files -- 'gitops/apps/*/application.yaml' | grep -q .; then
  echo "AVISO: no hay ningún 'gitops/apps/*/application.yaml' versionado en esta rama." >&2
  echo "       La Application raíz sincronizará con 0 recursos y NO creará Applications hijas." >&2
fi

# 4. Push forzado con arrendamiento (falla si el remoto cambió por fuera)
# Si falla, la alternativa sería con 'git push --force'
#git push --force-with-lease -u origin "$BRANCH"
git push --force-with-lease -u "$REMOTE" "$BRANCH"

echo "OK: '${BRANCH}' publicada con: ${PATHS[*]}"
echo "Para integrar en ${DEFAULT_BRANCH}: git switch ${DEFAULT_BRANCH} && git merge --squash ${BRANCH} && git commit"
