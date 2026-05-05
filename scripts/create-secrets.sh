#!/bin/bash
# =============================================================================
# CRÉATION DE TOUS LES SECRETS
# À lancer AVANT tout déploiement de pods.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "    ${GREEN}✓${NC} $1"; }
warn() { echo -e "    ${YELLOW}⚠${NC} $1"; }
step() { echo -e "\n${BLUE}▶${NC} $1"; }

# ─── VÉRIFICATION ────────────────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERREUR${NC} : oc non connecté."
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            CRÉATION DES SECRETS — E-COMMERCE                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ─── NAMESPACES ──────────────────────────────────────────────────────────────
step "Vérification des namespaces..."
for NS in ecommerce-prod ecommerce-dev cicd; do
  if ! oc get namespace "$NS" &>/dev/null; then
    oc create namespace "$NS"
    ok "Namespace $NS créé"
  else
    ok "Namespace $NS existe déjà"
  fi
done

# =============================================================================
# SECRETS POSTGRESQL
# =============================================================================
step "Secrets PostgreSQL (ecommerce-prod)..."

# Générer ou utiliser les valeurs fournies
PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 64)}"

oc create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=ecommerce \
  --from-literal=POSTGRES_PASSWORD="${PG_PASSWORD}" \
  -n ecommerce-prod --dry-run=client -o yaml | oc apply -f -
ok "postgres-secret créé dans ecommerce-prod"
ok "  POSTGRES_USER     : ecommerce"
ok "  POSTGRES_PASSWORD : ${PG_PASSWORD:0:8}... (tronqué)"

DATABASE_URL="postgresql://ecommerce:${PG_PASSWORD}@postgres:5432/ecommerce_prod"
oc create secret generic backend-secret \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  -n ecommerce-prod --dry-run=client -o yaml | oc apply -f -
ok "backend-secret créé dans ecommerce-prod"
ok "  DATABASE_URL : postgresql://ecommerce:***@postgres:5432/ecommerce_prod"
ok "  JWT_SECRET   : ${JWT_SECRET:0:8}... (tronqué)"

# ─── MÊME CHOSE POUR DEV ─────────────────────────────────────────────────────
step "Secrets PostgreSQL (ecommerce-dev)..."

PG_PASSWORD_DEV="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
JWT_SECRET_DEV="$(openssl rand -base64 64)"

oc create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=ecommerce \
  --from-literal=POSTGRES_PASSWORD="${PG_PASSWORD_DEV}" \
  -n ecommerce-dev --dry-run=client -o yaml | oc apply -f -
ok "postgres-secret créé dans ecommerce-dev"

oc create secret generic backend-secret \
  --from-literal=DATABASE_URL="postgresql://ecommerce:${PG_PASSWORD_DEV}@postgres:5432/ecommerce_dev" \
  --from-literal=JWT_SECRET="${JWT_SECRET_DEV}" \
  -n ecommerce-dev --dry-run=client -o yaml | oc apply -f -
ok "backend-secret créé dans ecommerce-dev"

# =============================================================================
# SECRETS HARBOR
# =============================================================================
step "Secrets Harbor..."

if [ -z "${HARBOR_PASSWORD:-}" ]; then
  echo ""
  read -rsp "    Token Harbor (robot\$ecommerce+tekton) : " HARBOR_PASSWORD
  echo ""
fi

HARBOR_HOST="${HARBOR_HOST:-10.0.0.2:8083}"
HARBOR_USER="${HARBOR_USER:-robot\$ecommerce+tekton}"

# Pull secrets (namespaces applicatifs)
for NS in ecommerce-prod ecommerce-dev; do
  oc create secret docker-registry harbor-pull-secret \
    --docker-server="${HARBOR_HOST}" \
    --docker-username="${HARBOR_USER}" \
    --docker-password="${HARBOR_PASSWORD}" \
    -n "${NS}" --dry-run=client -o yaml | oc apply -f -
  oc secrets link default harbor-pull-secret --for=pull -n "${NS}" 2>/dev/null || true
  ok "harbor-pull-secret dans ${NS}"
done

# Push secret (Tekton)
oc create secret docker-registry harbor-push-secret \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASSWORD}" \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "harbor-push-secret dans cicd"

# =============================================================================
# SECRETS GIT SSH (GitLab 10.0.0.2:8929)
# =============================================================================
step "Secret Git SSH (GitLab on-premise 10.0.0.2:8929)..."

if [ ! -f /tmp/tekton-git ]; then
  ssh-keygen -t ed25519 -C "tekton@itssolutions.it" -f /tmp/tekton-git -N "" -q
  echo ""
  echo "  ┌──────────────────────────────────────────────────────────────┐"
  echo "  │  Clé publique à ajouter dans GitLab :                        │"
  echo "  │  http://10.0.0.2:8929 → projet                               │"
  echo "  │  → Settings → Repository → Deploy Keys → Add new deploy key  │"
  echo "  │  → Cocher 'Grant write permissions to this key'              │"
  echo "  └──────────────────────────────────────────────────────────────┘"
  echo ""
  cat /tmp/tekton-git.pub
  echo ""
  read -rp "  Appuyez sur ENTRÉE après avoir ajouté la clé dans GitLab... "
else
  warn "Clé /tmp/tekton-git déjà existante — réutilisation"
fi

oc create secret generic git-ssh-secret \
  --from-file=ssh-privatekey=/tmp/tekton-git \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "git-ssh-secret créé dans cicd"

# Test connexion GitLab
echo "    Test connexion GitLab..."
SSH_TEST=$(ssh -T git@10.0.0.2 -p 8929 -i /tmp/tekton-git \
  -o StrictHostKeyChecking=no \
  -o ConnectTimeout=5 2>&1 || true)
if echo "$SSH_TEST" | grep -qi "welcome\|authenticated"; then
  ok "Connexion GitLab SSH : OK"
else
  warn "Connexion GitLab SSH : $SSH_TEST"
  warn "Vérifier que la clé publique est bien ajoutée dans GitLab"
fi

# =============================================================================
# SECRET WEBHOOK HMAC
# =============================================================================
step "Secret Webhook (GitLab → Tekton EventListener)..."

WEBHOOK_SECRET="$(openssl rand -hex 32)"

oc create secret generic webhook-secret \
  --from-literal=secret="${WEBHOOK_SECRET}" \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "webhook-secret créé dans cicd"

echo ""
echo "  ┌──────────────────────────────────────────────────────────────┐"
echo "  │  Configurer le webhook dans GitLab :                         │"
echo "  │  http://10.0.0.2:8929 → projet                               │"
echo "  │  → Settings → Webhooks → Add new webhook                     │"
printf "  │    URL    : https://webhook.itssolutions.it%-18s│\n" ""
printf "  │    Secret : %-49s│\n" "${WEBHOOK_SECRET}"
echo "  │    Trigger: Push events → branche : main                     │"
echo "  │    SSL    : décocher si pas de certificat signé              │"
echo "  └──────────────────────────────────────────────────────────────┘"

# =============================================================================
# VÉRIFICATION FINALE
# =============================================================================
step "Vérification de tous les secrets créés..."

echo ""
echo "  ecommerce-prod :"
oc get secrets -n ecommerce-prod \
  --no-headers 2>/dev/null | \
  grep -E "postgres-secret|backend-secret|harbor-pull-secret" | \
  awk '{printf "    ✓ %-35s %s\n", $1, $2}'

echo ""
echo "  ecommerce-dev :"
oc get secrets -n ecommerce-dev \
  --no-headers 2>/dev/null | \
  grep -E "postgres-secret|backend-secret|harbor-pull-secret" | \
  awk '{printf "    ✓ %-35s %s\n", $1, $2}'

echo ""
echo "  cicd :"
oc get secrets -n cicd \
  --no-headers 2>/dev/null | \
  grep -E "harbor-push-secret|git-ssh-secret|webhook-secret" | \
  awk '{printf "    ✓ %-35s %s\n", $1, $2}'

# Sauvegarder les valeurs générées (jamais dans Git)
cat > /tmp/ecommerce-secrets.txt << EOF
=== SECRETS GÉNÉRÉS $(date) ===

[ecommerce-prod]
POSTGRES_USER     : ecommerce
POSTGRES_PASSWORD : ${PG_PASSWORD}
DATABASE_URL      : postgresql://ecommerce:${PG_PASSWORD}@postgres:5432/ecommerce_prod
JWT_SECRET        : ${JWT_SECRET}

[ecommerce-dev]
POSTGRES_PASSWORD : ${PG_PASSWORD_DEV}
JWT_SECRET        : ${JWT_SECRET_DEV}

[cicd]
WEBHOOK_SECRET    : ${WEBHOOK_SECRET}
SSH_KEY_PRIVÉE    : /tmp/tekton-git
SSH_KEY_PUBLIQUE  : /tmp/tekton-git.pub
EOF

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              ✅  SECRETS CRÉÉS AVEC SUCCÈS                   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Valeurs sauvegardées dans /tmp/ecommerce-secrets.txt        ║"
echo "║  (fichier local uniquement — NE PAS commiter)                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
