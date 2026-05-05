#!/bin/bash
# =============================================================================
# APPLY TEKTON RESOURCES
# À utiliser quand Tekton n'était pas prêt lors de install-prerequisites.sh
# et que les Tasks/Pipeline/Triggers n'ont pas pu être créés.
#
# Usage : ./scripts/apply-tekton-resources.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { echo -e "    ${GREEN}✓${NC} $1"; }
warn() { echo -e "    ${YELLOW}⚠${NC} $1"; }
step() { echo -e "\n${BLUE}▶${NC} $1"; }
info() { echo -e "    ${BLUE}ℹ${NC} $1"; }

if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERREUR${NC} : oc non connecté."
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        APPLICATION DES RESSOURCES TEKTON                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"

# ─── ÉTAPE 1 : ATTENDRE QUE TEKTON SOIT VRAIMENT PRÊT ────────────────────────
step "Vérification que Tekton est complètement opérationnel..."

TIMEOUT=600
ELAPSED=0
INTERVAL=15

echo ""
while [ $ELAPSED -lt $TIMEOUT ]; do

  # 1. CSV installé et Succeeded ?
  CSV_STATUS=$(oc get csv -n openshift-operators --no-headers 2>/dev/null | \
    grep "openshift-pipelines-operator" | awk '{print $NF}' | head -1)

  # 2. Endpoint du webhook disponible ?
  WEBHOOK_EP=$(oc get endpoints tekton-pipelines-webhook \
    -n tekton-pipelines \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")

  # 3. Endpoint du triggers webhook disponible ?
  TRIGGER_EP=$(oc get endpoints tekton-triggers-webhook \
    -n tekton-pipelines \
    -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")

  printf "    [%3ds]  CSV: %-12s  pipeline-webhook: %-15s  triggers-webhook: %s\n" \
    "$ELAPSED" \
    "${CSV_STATUS:-en attente...}" \
    "${WEBHOOK_EP:-non disponible}" \
    "${TRIGGER_EP:-non disponible}"

  # Tous les composants prêts ?
  if [ "$CSV_STATUS" = "Succeeded" ] && \
     [ -n "$WEBHOOK_EP" ] && \
     [ -n "$TRIGGER_EP" ]; then
    echo ""
    ok "Tekton CSV                : Succeeded"
    ok "tekton-pipelines-webhook  : endpoint $WEBHOOK_EP"
    ok "tekton-triggers-webhook   : endpoint $TRIGGER_EP"
    break
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))

  if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo -e "  ${RED}TIMEOUT${NC} — Tekton n'est pas prêt après ${TIMEOUT}s."
    echo ""
    echo "  Diagnostic :"
    echo "    oc get csv -n openshift-operators | grep pipelines"
    oc get csv -n openshift-operators --no-headers 2>/dev/null | \
      grep "openshift-pipelines" | awk '{printf "    → %s : %s\n", $1, $NF}' || true
    echo ""
    echo "    oc get pods -n tekton-pipelines"
    oc get pods -n tekton-pipelines --no-headers 2>/dev/null | \
      awk '{printf "    → %-50s %s\n", $1, $3}' || true
    echo ""
    echo "    oc get endpoints -n tekton-pipelines"
    oc get endpoints -n tekton-pipelines --no-headers 2>/dev/null | \
      awk '{printf "    → %-40s %s\n", $1, $2}' || true
    exit 1
  fi
done

# Double vérification via oc wait
ok "Double vérification des deployments..."
for DEP in \
  tekton-pipelines-controller \
  tekton-pipelines-webhook \
  tekton-triggers-controller \
  tekton-triggers-webhook; do
  if oc get deployment "$DEP" -n tekton-pipelines &>/dev/null 2>&1; then
    oc wait --for=condition=available "deployment/$DEP" \
      -n tekton-pipelines --timeout=60s 2>/dev/null && \
      ok "$DEP : Available" || \
      warn "$DEP : pas encore Available (on continue)"
  fi
done

# ─── ÉTAPE 2 : APPLIQUER SERVICEACCOUNT + RBAC ───────────────────────────────
step "ServiceAccounts et RBAC..."
oc apply -f tekton/serviceaccount.yaml -n cicd
ok "ServiceAccounts créés"

oc apply -f tekton/rbac.yaml
ok "RBAC configuré"

# ─── ÉTAPE 3 : APPLIQUER LES TASKS ───────────────────────────────────────────
step "Tasks Tekton..."

# Appliquer avec retry en cas de webhook temporairement indisponible
apply_with_retry() {
  local FILE="$1"
  local NS="$2"
  local MAX_RETRIES=5
  local RETRY=0
  local WAIT=10

  while [ $RETRY -lt $MAX_RETRIES ]; do
    if oc apply -f "$FILE" -n "$NS" 2>/dev/null; then
      return 0
    fi
    RETRY=$((RETRY + 1))
    warn "Tentative $RETRY/$MAX_RETRIES échouée pour $FILE — attente ${WAIT}s..."
    sleep $WAIT
    WAIT=$((WAIT * 2))
  done
  echo -e "  ${RED}ERREUR${NC} : Impossible d'appliquer $FILE après $MAX_RETRIES tentatives"
  return 1
}

apply_with_retry tekton/tasks/tasks.yaml cicd
ok "Tasks créées (git-clone, run-tests, buildah-build-push, update-gitops)"

# ─── ÉTAPE 4 : PIPELINE ──────────────────────────────────────────────────────
step "Pipeline Tekton..."
apply_with_retry tekton/pipelines/pipeline.yaml cicd
ok "Pipeline 'ecommerce-pipeline' créé"

# ─── ÉTAPE 5 : TRIGGERS ──────────────────────────────────────────────────────
step "Triggers Tekton (EventListener, TriggerBinding, TriggerTemplate)..."
apply_with_retry tekton/triggers/triggers.yaml cicd
ok "Triggers + EventListener créés"

# ─── VÉRIFICATION FINALE ─────────────────────────────────────────────────────
step "Vérification des ressources créées dans cicd..."

echo ""
echo "  Tasks :"
oc get tasks -n cicd --no-headers 2>/dev/null | \
  awk '{printf "    ✓ %s\n", $1}' || warn "Aucune task trouvée"

echo ""
echo "  Pipeline :"
oc get pipeline -n cicd --no-headers 2>/dev/null | \
  awk '{printf "    ✓ %s\n", $1}' || warn "Aucun pipeline trouvé"

echo ""
echo "  EventListener :"
oc get eventlistener -n cicd --no-headers 2>/dev/null | \
  awk '{printf "    ✓ %s\n", $1}' || warn "Aucun EventListener trouvé"

echo ""
echo "  Route webhook :"
WEBHOOK_ROUTE=$(oc get route ecommerce-webhook -n cicd \
  -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
echo "    ✓ https://$WEBHOOK_ROUTE"

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         ✅  RESSOURCES TEKTON APPLIQUÉES                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Prochaine étape si ce n'est pas déjà fait :"
echo "    ./scripts/deploy-production.sh"
echo ""
