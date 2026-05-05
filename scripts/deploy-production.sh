#!/bin/bash
# =============================================================================
# DÉPLOIEMENT COMPLET E-COMMERCE — OPENSHIFT
# À lancer UNE SEULE FOIS pour initialiser l'environnement de production.
# Ensuite, Tekton + Argo CD gèrent les mises à jour automatiquement.
#
# Usage :
#   export HARBOR_PASSWORD='mon_token_harbor'
#   export GITOPS_REPO='ssh://git@10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git'
#   ./scripts/deploy-production.sh
#
# Variables optionnelles :
#   HARBOR_HOST   (défaut : 10.0.0.2:8083)
#   HARBOR_USER   (défaut : robot$ecommerce+tekton)
#   DOMAIN        (défaut : itssolutions.it)
#   PG_PASSWORD   (défaut : généré automatiquement)
#   JWT_SECRET    (défaut : généré automatiquement)
# =============================================================================
set -euo pipefail

# ─── COULEURS ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "    ${GREEN}✓${NC} $1"; }
fail() { echo -e "    ${RED}✗${NC} $1"; exit 1; }
warn() { echo -e "    ${YELLOW}⚠${NC} $1"; }
step() { echo -e "\n${BLUE}▶${NC} $1"; }

# ─── CONFIG ──────────────────────────────────────────────────────────────────
HARBOR_HOST="${HARBOR_HOST:-10.0.0.2:8083}"
HARBOR_USER="${HARBOR_USER:-robot\$ecommerce+tekton}"

if [ -z "${HARBOR_PASSWORD:-}" ]; then
  echo -e "${RED}ERREUR${NC} : HARBOR_PASSWORD non défini."
  echo "  export HARBOR_PASSWORD='votre_token_harbor'"
  exit 1
fi

if [ -z "${GITOPS_REPO:-}" ]; then
  echo -e "${RED}ERREUR${NC} : GITOPS_REPO non défini."
  echo "  export GITOPS_REPO='ssh://git@10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git'"
  exit 1
fi

DOMAIN="${DOMAIN:-itssolutions.it}"

# Vérifier qu'on est à la racine du projet
if [ ! -f "gitops/namespaces.yaml" ]; then
  echo -e "${RED}ERREUR${NC} : Lancer depuis la racine du projet."
  echo "  cd ecommerce-production-platform && ./scripts/deploy-production.sh"
  exit 1
fi

# Vérifier connexion OpenShift
if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERREUR${NC} : oc non connecté."
  echo "  oc login https://api.cluster:6443"
  exit 1
fi

CURRENT_USER=$(oc whoami)
CURRENT_SERVER=$(oc whoami --show-server)

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     DÉPLOIEMENT E-COMMERCE PRODUCTION — OPENSHIFT        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Cluster     : $CURRENT_SERVER"
echo "  Utilisateur : $CURRENT_USER"
echo "  Harbor      : $HARBOR_HOST"
echo "  Domaine     : $DOMAIN"
echo "  GitOps repo : $GITOPS_REPO"
echo ""
read -rp "Continuer le déploiement ? [oui/N] : " CONFIRM
if [ "$CONFIRM" != "oui" ]; then
  echo "Annulé."
  exit 0
fi

# ─── 1. NAMESPACES ───────────────────────────────────────────────────────────
step "[1/10] Création des namespaces..."
oc apply -f gitops/namespaces.yaml
for NS in ecommerce-prod ecommerce-dev cicd; do
  oc get namespace "$NS" &>/dev/null && ok "Namespace $NS" || warn "Namespace $NS non créé"
done

# ─── 2. HARBOR REGISTRY INSECURE ─────────────────────────────────────────────
step "[2/10] Configuration Harbor comme registry insecure ($HARBOR_HOST)..."
oc patch image.config.openshift.io/cluster --type=merge -p "{
  \"spec\": {
    \"registrySources\": {
      \"insecureRegistries\": [\"${HARBOR_HOST}\"]
    }
  }
}"
ok "Harbor ajouté comme registry insecure"

if oc get mcp/worker &>/dev/null 2>&1; then
  warn "MachineConfigPool détecté — attente nœuds (peut prendre 5 min)..."
  sleep 30
  oc wait mcp/worker --for=condition=Updated --timeout=600s && \
    ok "Nœuds worker mis à jour" || \
    warn "Timeout MachineConfigPool — on continue"
else
  ok "Pas de MachineConfigPool worker (SNO) — on continue"
fi

# ─── 3. SECRETS HARBOR ───────────────────────────────────────────────────────
step "[3/10] Création des secrets Harbor..."

for NS in ecommerce-prod ecommerce-dev; do
  oc create secret docker-registry harbor-pull-secret \
    --docker-server="${HARBOR_HOST}" \
    --docker-username="${HARBOR_USER}" \
    --docker-password="${HARBOR_PASSWORD}" \
    -n "${NS}" --dry-run=client -o yaml | oc apply -f -
  oc secrets link default harbor-pull-secret --for=pull -n "${NS}" 2>/dev/null || true
  ok "harbor-pull-secret dans ${NS}"
done

oc create secret docker-registry harbor-push-secret \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASSWORD}" \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "harbor-push-secret dans cicd (pour Tekton)"

# ─── 4. SECRETS POSTGRESQL ET BACKEND ────────────────────────────────────────
step "[4/10] Création des secrets PostgreSQL et Backend..."

PG_PASSWORD="${PG_PASSWORD:-$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)}"
JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 64)}"

# PROD
oc create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=ecommerce \
  --from-literal=POSTGRES_PASSWORD="${PG_PASSWORD}" \
  -n ecommerce-prod --dry-run=client -o yaml | oc apply -f -
ok "postgres-secret dans ecommerce-prod"

DATABASE_URL="postgresql://ecommerce:${PG_PASSWORD}@postgres:5432/ecommerce_prod"
oc create secret generic backend-secret \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=JWT_SECRET="${JWT_SECRET}" \
  -n ecommerce-prod --dry-run=client -o yaml | oc apply -f -
ok "backend-secret dans ecommerce-prod"

# DEV
PG_PASSWORD_DEV="$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)"
JWT_SECRET_DEV="$(openssl rand -base64 64)"

oc create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=ecommerce \
  --from-literal=POSTGRES_PASSWORD="${PG_PASSWORD_DEV}" \
  -n ecommerce-dev --dry-run=client -o yaml | oc apply -f -

oc create secret generic backend-secret \
  --from-literal=DATABASE_URL="postgresql://ecommerce:${PG_PASSWORD_DEV}@postgres:5432/ecommerce_dev" \
  --from-literal=JWT_SECRET="${JWT_SECRET_DEV}" \
  -n ecommerce-dev --dry-run=client -o yaml | oc apply -f -
ok "Secrets créés dans ecommerce-dev"

# ─── 5. SECRETS GIT SSH + WEBHOOK ────────────────────────────────────────────
step "[5/10] Secrets Git SSH et Webhook Tekton..."

if [ ! -f /tmp/tekton-git ]; then
  ssh-keygen -t ed25519 -C "tekton@${DOMAIN}" -f /tmp/tekton-git -N "" -q
fi

echo ""
echo "  ┌──────────────────────────────────────────────────────────┐"
echo "  │  Clé publique SSH — à ajouter dans votre Git :           │"
echo "  │  Settings → Deploy Keys → Add Key (avec WRITE access)    │"
echo "  └──────────────────────────────────────────────────────────┘"
echo ""
cat /tmp/tekton-git.pub
echo ""
read -rp "  Appuyez sur ENTRÉE après avoir ajouté la clé dans Git... "

oc create secret generic git-ssh-secret \
  --from-file=ssh-privatekey=/tmp/tekton-git \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "git-ssh-secret dans cicd"

WEBHOOK_SECRET="$(openssl rand -hex 32)"
oc create secret generic webhook-secret \
  --from-literal=secret="${WEBHOOK_SECRET}" \
  -n cicd --dry-run=client -o yaml | oc apply -f -
ok "webhook-secret dans cicd"

# ─── 6. TEKTON ───────────────────────────────────────────────────────────────
step "[6/10] Déploiement Tekton (SA, RBAC, Tasks, Pipeline, Triggers)..."

oc apply -f tekton/serviceaccount.yaml -n cicd
ok "ServiceAccounts créés"

oc apply -f tekton/rbac.yaml
ok "RBAC configuré"

oc apply -f tekton/tasks/tasks.yaml -n cicd
ok "Tasks créées"

oc apply -f tekton/pipelines/pipeline.yaml -n cicd
ok "Pipeline créé"

oc apply -f tekton/triggers/triggers.yaml -n cicd
ok "Triggers + EventListener créés"

# ─── 7. DÉPLOIEMENT APPLICATIF PROD ──────────────────────────────────────────
step "[7/10] Déploiement PostgreSQL → Backend → Frontend (prod)..."

oc apply -f gitops/kustomize/base/configmap.yaml -n ecommerce-prod
ok "ConfigMaps appliqués"

# PostgreSQL
oc apply -f gitops/kustomize/base/postgres-statefulset.yaml -n ecommerce-prod
echo "    ⏳ Attente PostgreSQL Ready (max 3 min)..."
oc rollout status statefulset/postgres -n ecommerce-prod --timeout=180s
ok "PostgreSQL opérationnel"

# Backend
oc apply -f gitops/kustomize/base/backend-deployment.yaml -n ecommerce-prod
echo "    ⏳ Attente Backend Ready (max 5 min)..."
oc rollout status deployment/backend -n ecommerce-prod --timeout=300s
ok "Backend opérationnel"

# Seed
echo "    ⏳ Seed base de données..."
BACKEND_POD=$(oc get pod -n ecommerce-prod -l app=backend \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$BACKEND_POD" ]; then
  oc exec -n ecommerce-prod "$BACKEND_POD" -- \
    sh -c "cd /app && npx prisma db seed" 2>&1 | tail -3 && \
    ok "Base de données seedée (8 produits + comptes demo)" || \
    warn "Seed échoué ou déjà exécuté"
else
  warn "Pod backend non trouvé — seed à lancer manuellement :"
  warn "  oc exec -n ecommerce-prod \$(oc get pod -l app=backend -n ecommerce-prod -o name | head -1) -- npx prisma db seed"
fi

# Frontend
oc apply -f gitops/kustomize/base/frontend-deployment.yaml -n ecommerce-prod
echo "    ⏳ Attente Frontend Ready (max 3 min)..."
oc rollout status deployment/frontend -n ecommerce-prod --timeout=180s
ok "Frontend opérationnel"

oc apply -f gitops/kustomize/base/networkpolicy.yaml -n ecommerce-prod
ok "NetworkPolicies appliquées"

oc apply -f gitops/kustomize/base/hpa.yaml -n ecommerce-prod
ok "HPA configuré"

# ─── 8. ROUTES OPENSHIFT ─────────────────────────────────────────────────────
step "[8/10] Création des Routes OpenShift (TLS edge)..."
oc apply -f gitops/kustomize/overlays/prod/routes.yaml -n ecommerce-prod

FRONTEND_ROUTE=$(oc get route frontend -n ecommerce-prod \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
BACKEND_ROUTE=$(oc get route backend-api -n ecommerce-prod \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")

ok "Frontend : https://${FRONTEND_ROUTE}"
ok "Backend  : https://${BACKEND_ROUTE}"

# ─── 9. ARGO CD ──────────────────────────────────────────────────────────────
step "[9/10] Configuration Argo CD..."

sed "s|http://10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git|${GITOPS_REPO}|g;
     s|ssh://git@10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git|${GITOPS_REPO}|g" \
  gitops/argocd/applications.yaml | oc apply -f -

ARGOCD_HOST=$(oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
ARGOCD_PASS=$(oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d || echo "non disponible")

ok "Argo CD URL      : https://${ARGOCD_HOST}"
ok "Argo CD password : ${ARGOCD_PASS}"

# ─── 10. WEBHOOK ─────────────────────────────────────────────────────────────
step "[10/10] URL Webhook Git..."
WEBHOOK_HOST=$(oc get route ecommerce-webhook -n cicd \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
ok "Webhook : https://${WEBHOOK_HOST}"

# ─── RÉSUMÉ ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                 ✅  DÉPLOIEMENT TERMINÉ                      ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  %-60s║\n" "Frontend  : https://${FRONTEND_ROUTE}"
printf "║  %-60s║\n" "API       : https://${BACKEND_ROUTE}"
printf "║  %-60s║\n" "Argo CD   : https://${ARGOCD_HOST}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Webhook Git (à configurer dans GitLab / GitHub) :          ║"
printf "║    %-58s║\n" "URL    : https://${WEBHOOK_HOST}"
printf "║    %-58s║\n" "Secret : ${WEBHOOK_SECRET}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Comptes de démo :                                           ║"
echo "║    Admin    : admin@itssolutions.it / Admin@2024!Secure      ║"
echo "║    Customer : customer@example.com  / Customer@2024!         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Vérifications rapides :"
echo "    curl -k https://${BACKEND_ROUTE}/health"
echo "    curl -k https://${BACKEND_ROUTE}/api/v1/products"
echo "    ./scripts/validate.sh"
echo ""

# Sauvegarder les infos localement (ne jamais commiter ce fichier)
cat > /tmp/ecommerce-deploy-info.txt <<EOF
=== DÉPLOIEMENT E-COMMERCE $(date) ===
Frontend     : https://${FRONTEND_ROUTE}
API          : https://${BACKEND_ROUTE}
Argo CD      : https://${ARGOCD_HOST}
  password   : ${ARGOCD_PASS}
Webhook URL  : https://${WEBHOOK_HOST}
  secret     : ${WEBHOOK_SECRET}
PG_PASSWORD     (prod) : ${PG_PASSWORD}
PG_PASSWORD_DEV (dev)  : ${PG_PASSWORD_DEV}
JWT_SECRET      (prod) : ${JWT_SECRET}
EOF
echo "  ℹ Informations sauvegardées dans /tmp/ecommerce-deploy-info.txt"
