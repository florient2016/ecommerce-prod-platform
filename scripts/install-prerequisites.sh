#!/bin/bash
# =============================================================================
# INSTALLATION DES PRÉREQUIS
# Tekton, Argo CD, Harbor, namespaces, RBAC
# À lancer AVANT deploy-production.sh
# =============================================================================
set -euo pipefail

HARBOR_HOST="${HARBOR_HOST:-10.0.0.2:8083}"
HARBOR_USER="${HARBOR_USER:-robot\$ecommerce+tekton}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:?ERREUR : export HARBOR_PASSWORD=votre_token}"
DOMAIN="${DOMAIN:-itssolutions.it}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "    ${GREEN}✓${NC} $1"; }
warn() { echo -e "    ${YELLOW}⚠${NC} $1"; }
step() { echo -e "\n${BLUE}▶${NC} $1"; }

if [ ! -f "gitops/namespaces.yaml" ]; then
  echo "ERREUR : lancer depuis la racine du projet ecommerce-production-platform/"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         INSTALLATION PRÉREQUIS — OPENSHIFT               ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ─── 1. NAMESPACES ───────────────────────────────────────────────────────────
step "[1/10] Création des namespaces..."
oc apply -f gitops/namespaces.yaml
ok "Namespaces : ecommerce-prod, ecommerce-dev, cicd"

# ─── 2. TEKTON PIPELINES ─────────────────────────────────────────────────────
step "[2/10] Installation OpenShift Pipelines (Tekton)..."
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "    ⏳ Attente démarrage complet de Tekton (max 10 min)..."
echo "    (controller + webhook + triggers)"

wait_tekton_ready() {
  local TIMEOUT=600
  local ELAPSED=0
  local INTERVAL=15
  while [ $ELAPSED -lt $TIMEOUT ]; do
    CSV_STATUS=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | \
      grep "openshift-pipelines-operator" | awk '{print $NF}' | head -1)
    WEBHOOK_EP=$(oc get endpoints tekton-pipelines-webhook \
      -n tekton-pipelines \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")
    printf "    [%3ds] CSV: %-12s  webhook endpoint: %s\n" \
      "$ELAPSED" "${CSV_STATUS:-en attente}" "${WEBHOOK_EP:-non disponible}"
    if [ "$CSV_STATUS" = "Succeeded" ] && [ -n "$WEBHOOK_EP" ]; then
      return 0
    fi
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
  done
  return 1
}

if wait_tekton_ready; then
  ok "Tekton CSV           : Succeeded"
  ok "Tekton webhook       : endpoint disponible"
  oc wait --for=condition=available \
    deployment/tekton-pipelines-controller \
    deployment/tekton-pipelines-webhook \
    -n tekton-pipelines --timeout=120s 2>/dev/null && \
    ok "Tekton controller    : Available" || \
    warn "Tekton controller pas encore Available — continuer"
  oc wait --for=condition=available \
    deployment/tekton-triggers-controller \
    deployment/tekton-triggers-webhook \
    -n tekton-pipelines --timeout=120s 2>/dev/null && \
    ok "Tekton triggers      : Available" || \
    warn "Tekton triggers pas encore Available — continuer"
  ok "Tekton Pipelines complètement opérationnel"
else
  echo ""
  echo "    ERREUR : Tekton n'est pas prêt après 10 min."
  echo "    Diagnostic :"
  echo "      oc get csv -n openshift-operators | grep pipelines"
  echo "      oc get pods -n tekton-pipelines"
  echo "      oc get endpoints tekton-pipelines-webhook -n tekton-pipelines"
  echo ""
  echo "    Relancer manuellement après que Tekton soit prêt :"
  echo "      oc apply -f tekton/serviceaccount.yaml -n cicd"
  echo "      oc apply -f tekton/rbac.yaml"
  echo "      oc apply -f tekton/tasks/tasks.yaml -n cicd"
  echo "      oc apply -f tekton/pipelines/pipeline.yaml -n cicd"
  echo "      oc apply -f tekton/triggers/triggers.yaml -n cicd"
  exit 1
fi

# ─── 3. ARGO CD ──────────────────────────────────────────────────────────────
step "[3/10] Installation OpenShift GitOps (Argo CD)..."
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "    ⏳ Attente déploiement Argo CD (max 5 min)..."
sleep 60
oc wait --for=condition=available deployment/openshift-gitops-server \
  -n openshift-gitops --timeout=300s 2>/dev/null && \
  ok "Argo CD opérationnel" || \
  warn "Argo CD en cours d'installation — continuer"

# ─── 4. HARBOR REGISTRY INSECURE ─────────────────────────────────────────────
step "[4/10] Configuration Harbor comme registry insecure..."
oc patch image.config.openshift.io/cluster --type=merge -p "{
  \"spec\": {
    \"registrySources\": {
      \"insecureRegistries\": [\"${HARBOR_HOST}\"]
    }
  }
}"
ok "Harbor ${HARBOR_HOST} ajouté comme registry insecure"

if oc get mcp/worker &>/dev/null 2>&1; then
  warn "MachineConfigPool détecté — attente nœuds (peut prendre 5 min)..."
  sleep 30
  oc wait mcp/worker --for=condition=Updated --timeout=600s && \
    ok "Nœuds mis à jour" || warn "Timeout MachineConfigPool — continuer"
else
  ok "Pas de MachineConfigPool worker (SNO) — continuer"
fi

# ─── 5. SECRETS HARBOR ───────────────────────────────────────────────────────
step "[5/10] Création des secrets Harbor..."

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
ok "harbor-push-secret dans cicd"

# ─── 6. TEKTON SA + RBAC ─────────────────────────────────────────────────────
step "[6/10] ServiceAccounts et RBAC Tekton..."
oc apply -f tekton/serviceaccount.yaml -n cicd
oc apply -f tekton/rbac.yaml
ok "ServiceAccounts et RBAC configurés"

# ─── 7. TEKTON TASKS + PIPELINE + TRIGGERS ───────────────────────────────────
step "[7/10] Tasks, Pipeline, Triggers Tekton..."
oc apply -f tekton/tasks/tasks.yaml -n cicd
oc apply -f tekton/pipelines/pipeline.yaml -n cicd
oc apply -f tekton/triggers/triggers.yaml -n cicd
ok "Tekton Tasks, Pipeline, Triggers créés"

# ─── 8. ARGO CD PROJECT + APPLICATIONS ───────────────────────────────────────
step "[8/10] Argo CD Project et Applications..."
oc apply -f gitops/argocd/project.yaml
oc apply -f gitops/argocd/application-prod.yaml
oc apply -f gitops/argocd/application-dev.yaml
ok "AppProject 'ecommerce' créé"
ok "Application ecommerce-prod créée"
ok "Application ecommerce-dev créée"

# ─── 9. DÉPLOIEMENT POSTGRESQL ───────────────────────────────────────────────
step "[9/10] Déploiement PostgreSQL..."
oc apply -f gitops/apps/postgres/ -n ecommerce-prod
echo "    ⏳ Attente PostgreSQL Ready (max 3 min)..."
oc rollout status statefulset/postgres -n ecommerce-prod --timeout=180s && \
  ok "PostgreSQL opérationnel" || \
  warn "PostgreSQL non prêt — vérifier : oc get pods -n ecommerce-prod"

# ─── 10. ROUTE ARGO CD ───────────────────────────────────────────────────────
step "[10/10] Informations Argo CD..."
ARGOCD_HOST=$(oc get route openshift-gitops-server -n openshift-gitops \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
ARGOCD_PASS=$(oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d || echo "non disponible")

ok "Argo CD URL      : https://${ARGOCD_HOST}"
ok "Argo CD password : ${ARGOCD_PASS}"

# ─── RÉSUMÉ ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║            ✅  PRÉREQUIS INSTALLÉS                           ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Étape suivante : lancer le déploiement complet              ║"
echo "║                                                              ║"
echo "║  export HARBOR_PASSWORD='...'                                ║"
echo "║  export GITOPS_REPO='ssh://git@gitlab.itssolutions.it:2424/YOUR_GROUP/ecommerce-production-platform.git'            ║"
echo "║  ./scripts/deploy-production.sh                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
