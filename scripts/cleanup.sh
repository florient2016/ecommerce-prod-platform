#!/bin/bash
# =============================================================================
# CLEANUP COMPLET E-COMMERCE — OPENSHIFT
# Supprime TOUT ce qui a été déployé par install-prerequisites.sh
# et deploy-production.sh, SAUF les opérateurs (Tekton, Argo CD).
#
# Usage :
#   ./scripts/cleanup.sh
#   ./scripts/cleanup.sh --force     # sans confirmation
# =============================================================================
set -euo pipefail

# ─── COULEURS ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "    ${GREEN}✓${NC} $1"; }
warn() { echo -e "    ${YELLOW}⚠${NC} $1"; }
step() { echo -e "\n${BLUE}▶${NC} $1"; }
skip() { echo -e "    ${YELLOW}↷${NC} $1 (déjà absent)"; }

FORCE="${1:-}"

# ─── VÉRIFICATION CONNEXION ──────────────────────────────────────────────────
if ! oc whoami &>/dev/null; then
  echo -e "${RED}ERREUR${NC} : oc non connecté. Faire : oc login https://api.cluster:6443"
  exit 1
fi

CURRENT_USER=$(oc whoami)
CURRENT_SERVER=$(oc whoami --show-server)

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           🗑️  CLEANUP E-COMMERCE — OPENSHIFT                 ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Ce script supprime :                                        ║"
echo "║    • Applications Argo CD (ecommerce-prod, ecommerce-dev)    ║"
echo "║    • AppProject Argo CD (ecommerce)                          ║"
echo "║    • Tous les Pods, Deployments, StatefulSets                ║"
echo "║    • Tous les Services, Routes, ConfigMaps                   ║"
echo "║    • Tous les Secrets applicatifs                            ║"
echo "║    • Les PVC PostgreSQL (données perdues définitivement)     ║"
echo "║    • Les Pipelines, Tasks, Triggers Tekton                   ║"
echo "║    • Les ServiceAccounts et RBAC                             ║"
echo "║    • Les Namespaces complets                                 ║"
echo "║    • La config Harbor registry insecure                      ║"
echo "║                                                              ║"
echo "║  Ce script NE supprime PAS :                                 ║"
echo "║    • L'opérateur OpenShift Pipelines (Tekton)                ║"
echo "║    • L'opérateur OpenShift GitOps (Argo CD)                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Cluster     : $CURRENT_SERVER"
echo "  Utilisateur : $CURRENT_USER"
echo ""

if [ "$FORCE" != "--force" ]; then
  read -rp "⚠️  Confirmer la suppression complète ? [oui/N] : " CONFIRM
  if [ "$CONFIRM" != "oui" ]; then
    echo "Annulé."
    exit 0
  fi
  echo ""
  echo -e "${RED}DERNIÈRE CONFIRMATION${NC} — Les données PostgreSQL seront PERDUES définitivement."
  read -rp "Taper 'SUPPRIMER' pour confirmer : " CONFIRM2
  if [ "$CONFIRM2" != "SUPPRIMER" ]; then
    echo "Annulé."
    exit 0
  fi
fi

echo ""
echo "Début du cleanup..."

# ─── 1. ARGO CD — APPLICATIONS ───────────────────────────────────────────────
step "[1/9] Suppression des Applications Argo CD..."

for APP in ecommerce-prod ecommerce-dev; do
  if oc get application "$APP" -n openshift-gitops &>/dev/null 2>&1; then
    # Désactiver le sync auto avant de supprimer pour éviter re-création
    oc patch application "$APP" -n openshift-gitops \
      --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}' 2>/dev/null || true
    oc delete application "$APP" -n openshift-gitops --timeout=60s
    ok "Application Argo CD '$APP' supprimée"
  else
    skip "Application Argo CD '$APP'"
  fi
done

# AppProject
if oc get appproject ecommerce -n openshift-gitops &>/dev/null 2>&1; then
  oc delete appproject ecommerce -n openshift-gitops --timeout=30s
  ok "AppProject 'ecommerce' supprimé"
else
  skip "AppProject 'ecommerce'"
fi

# ─── 2. ECOMMERCE-PROD — WORKLOADS ───────────────────────────────────────────
step "[2/9] Suppression des workloads ecommerce-prod..."

if oc get namespace ecommerce-prod &>/dev/null 2>&1; then

  # Deployments
  for DEP in frontend backend; do
    if oc get deployment "$DEP" -n ecommerce-prod &>/dev/null 2>&1; then
      oc delete deployment "$DEP" -n ecommerce-prod --timeout=60s
      ok "Deployment '$DEP' supprimé"
    else
      skip "Deployment '$DEP'"
    fi
  done

  # StatefulSet PostgreSQL
  if oc get statefulset postgres -n ecommerce-prod &>/dev/null 2>&1; then
    oc delete statefulset postgres -n ecommerce-prod --timeout=60s
    ok "StatefulSet 'postgres' supprimé"
  else
    skip "StatefulSet 'postgres'"
  fi

  # HPA
  oc delete hpa --all -n ecommerce-prod --timeout=30s 2>/dev/null && \
    ok "HPA supprimés" || skip "HPA"

  # PDB
  oc delete pdb --all -n ecommerce-prod --timeout=30s 2>/dev/null && \
    ok "PodDisruptionBudgets supprimés" || skip "PDB"

else
  skip "Namespace ecommerce-prod (inexistant)"
fi

# ─── 3. ECOMMERCE-PROD — SERVICES ET ROUTES ──────────────────────────────────
step "[3/9] Suppression des Services et Routes ecommerce-prod..."

if oc get namespace ecommerce-prod &>/dev/null 2>&1; then

  for SVC in frontend backend postgres; do
    if oc get service "$SVC" -n ecommerce-prod &>/dev/null 2>&1; then
      oc delete service "$SVC" -n ecommerce-prod --timeout=30s
      ok "Service '$SVC' supprimé"
    else
      skip "Service '$SVC'"
    fi
  done

  for ROUTE in frontend backend-api; do
    if oc get route "$ROUTE" -n ecommerce-prod &>/dev/null 2>&1; then
      oc delete route "$ROUTE" -n ecommerce-prod --timeout=30s
      ok "Route '$ROUTE' supprimée"
    else
      skip "Route '$ROUTE'"
    fi
  done

fi

# ─── 4. ECOMMERCE-PROD — CONFIGMAPS ET SECRETS ───────────────────────────────
step "[4/9] Suppression des ConfigMaps et Secrets ecommerce-prod..."

if oc get namespace ecommerce-prod &>/dev/null 2>&1; then

  for CM in postgres-config backend-config; do
    if oc get configmap "$CM" -n ecommerce-prod &>/dev/null 2>&1; then
      oc delete configmap "$CM" -n ecommerce-prod --timeout=30s
      ok "ConfigMap '$CM' supprimé"
    else
      skip "ConfigMap '$CM'"
    fi
  done

  for SECRET in postgres-secret backend-secret harbor-pull-secret; do
    if oc get secret "$SECRET" -n ecommerce-prod &>/dev/null 2>&1; then
      oc delete secret "$SECRET" -n ecommerce-prod --timeout=30s
      ok "Secret '$SECRET' supprimé"
    else
      skip "Secret '$SECRET'"
    fi
  done

fi

# ─── 5. ECOMMERCE-PROD — PVC (DONNÉES POSTGRESQL) ────────────────────────────
step "[5/9] Suppression des PVC PostgreSQL (données définitivement perdues)..."

if oc get namespace ecommerce-prod &>/dev/null 2>&1; then
  PVCS=$(oc get pvc -n ecommerce-prod -o name 2>/dev/null || echo "")
  if [ -n "$PVCS" ]; then
    echo "$PVCS" | while read -r PVC; do
      oc delete "$PVC" -n ecommerce-prod --timeout=60s
      ok "PVC '$PVC' supprimé"
    done
  else
    skip "Aucun PVC dans ecommerce-prod"
  fi
fi

# ─── 6. ECOMMERCE-DEV — TOUT ─────────────────────────────────────────────────
step "[6/9] Suppression des ressources ecommerce-dev..."

if oc get namespace ecommerce-dev &>/dev/null 2>&1; then
  # Workloads
  oc delete deployment --all -n ecommerce-dev --timeout=60s 2>/dev/null && \
    ok "Deployments ecommerce-dev supprimés" || skip "Deployments ecommerce-dev"

  oc delete statefulset --all -n ecommerce-dev --timeout=60s 2>/dev/null && \
    ok "StatefulSets ecommerce-dev supprimés" || skip "StatefulSets ecommerce-dev"

  oc delete service --all -n ecommerce-dev --timeout=30s 2>/dev/null && \
    ok "Services ecommerce-dev supprimés" || skip "Services ecommerce-dev"

  oc delete route --all -n ecommerce-dev --timeout=30s 2>/dev/null && \
    ok "Routes ecommerce-dev supprimées" || skip "Routes ecommerce-dev"

  for SECRET in postgres-secret backend-secret harbor-pull-secret; do
    oc delete secret "$SECRET" -n ecommerce-dev --timeout=30s 2>/dev/null && \
      ok "Secret '$SECRET' ecommerce-dev supprimé" || skip "Secret '$SECRET' ecommerce-dev"
  done

  PVCS_DEV=$(oc get pvc -n ecommerce-dev -o name 2>/dev/null || echo "")
  if [ -n "$PVCS_DEV" ]; then
    echo "$PVCS_DEV" | while read -r PVC; do
      oc delete "$PVC" -n ecommerce-dev --timeout=60s
      ok "PVC '$PVC' ecommerce-dev supprimé"
    done
  fi
else
  skip "Namespace ecommerce-dev (inexistant)"
fi

# ─── 7. CICD — TEKTON RESOURCES ──────────────────────────────────────────────
step "[7/9] Suppression des ressources Tekton (cicd)..."

if oc get namespace cicd &>/dev/null 2>&1; then

  # PipelineRuns en cours — annuler proprement
  RUNNING_PR=$(oc get pipelinerun -n cicd \
    --field-selector=status.conditions[0].reason=Running \
    -o name 2>/dev/null || echo "")
  if [ -n "$RUNNING_PR" ]; then
    echo "$RUNNING_PR" | while read -r PR; do
      tkn pipelinerun cancel "${PR#pipelinerun/}" -n cicd 2>/dev/null || true
      warn "PipelineRun '${PR}' annulé"
    done
    sleep 5
  fi

  # Supprimer tous les PipelineRuns
  oc delete pipelinerun --all -n cicd --timeout=60s 2>/dev/null && \
    ok "PipelineRuns supprimés" || skip "PipelineRuns"

  # Supprimer tous les TaskRuns
  oc delete taskrun --all -n cicd --timeout=60s 2>/dev/null && \
    ok "TaskRuns supprimés" || skip "TaskRuns"

  # Triggers
  for RES in eventlistener triggerbinding triggertemplate; do
    oc delete "$RES" --all -n cicd --timeout=30s 2>/dev/null && \
      ok "${RES} supprimés" || skip "${RES}"
  done

  # Pipeline + Tasks
  oc delete pipeline --all -n cicd --timeout=30s 2>/dev/null && \
    ok "Pipelines supprimés" || skip "Pipelines"

  oc delete task --all -n cicd --timeout=30s 2>/dev/null && \
    ok "Tasks supprimées" || skip "Tasks"

  # Routes webhook
  if oc get route ecommerce-webhook -n cicd &>/dev/null 2>&1; then
    oc delete route ecommerce-webhook -n cicd --timeout=30s
    ok "Route webhook supprimée"
  else
    skip "Route webhook"
  fi

  # Secrets Tekton
  for SECRET in harbor-push-secret git-ssh-secret webhook-secret; do
    if oc get secret "$SECRET" -n cicd &>/dev/null 2>&1; then
      oc delete secret "$SECRET" -n cicd --timeout=30s
      ok "Secret '$SECRET' supprimé"
    else
      skip "Secret '$SECRET'"
    fi
  done

  # ServiceAccounts
  for SA in tekton-pipeline-sa tekton-triggers-sa; do
    if oc get serviceaccount "$SA" -n cicd &>/dev/null 2>&1; then
      oc delete serviceaccount "$SA" -n cicd --timeout=30s
      ok "ServiceAccount '$SA' supprimé"
    else
      skip "ServiceAccount '$SA'"
    fi
  done

  # RBAC
  for ROLE in tekton-pipeline-role tekton-triggers-role; do
    oc delete role "$ROLE" -n cicd --timeout=30s 2>/dev/null && \
      ok "Role '$ROLE' supprimé" || skip "Role '$ROLE'"
  done

  for RB in tekton-pipeline-rolebinding tekton-triggers-rolebinding; do
    oc delete rolebinding "$RB" -n cicd --timeout=30s 2>/dev/null && \
      ok "RoleBinding '$RB' supprimé" || skip "RoleBinding '$RB'"
  done

  # PVC workspace Tekton
  PVCS_CICD=$(oc get pvc -n cicd -o name 2>/dev/null || echo "")
  if [ -n "$PVCS_CICD" ]; then
    echo "$PVCS_CICD" | while read -r PVC; do
      oc delete "$PVC" -n cicd --timeout=60s
      ok "PVC Tekton '$PVC' supprimé"
    done
  else
    skip "Aucun PVC dans cicd"
  fi

else
  skip "Namespace cicd (inexistant)"
fi

# ─── 8. RBAC CLUSTER ─────────────────────────────────────────────────────────
step "[8/9] Suppression RBAC cluster..."

for CRB in tekton-gitops-updater-binding tekton-pipeline-privileged; do
  if oc get clusterrolebinding "$CRB" &>/dev/null 2>&1; then
    oc delete clusterrolebinding "$CRB" --timeout=30s
    ok "ClusterRoleBinding '$CRB' supprimé"
  else
    skip "ClusterRoleBinding '$CRB'"
  fi
done

if oc get clusterrole tekton-gitops-updater &>/dev/null 2>&1; then
  oc delete clusterrole tekton-gitops-updater --timeout=30s
  ok "ClusterRole 'tekton-gitops-updater' supprimé"
else
  skip "ClusterRole 'tekton-gitops-updater'"
fi

# ─── 9. NAMESPACES + HARBOR CONFIG ───────────────────────────────────────────
step "[9/9] Suppression des namespaces et config Harbor..."

for NS in ecommerce-prod ecommerce-dev cicd; do
  if oc get namespace "$NS" &>/dev/null 2>&1; then
    oc delete namespace "$NS" --timeout=120s
    ok "Namespace '$NS' supprimé"
  else
    skip "Namespace '$NS'"
  fi
done

# Retirer Harbor de la liste insecureRegistries
echo "    Suppression Harbor de la config registry insecure..."
CURRENT_INSECURE=$(oc get image.config.openshift.io/cluster \
  -o jsonpath='{.spec.registrySources.insecureRegistries}' 2>/dev/null || echo "[]")

if echo "$CURRENT_INSECURE" | grep -q "10.0.0.2:8083"; then
  oc patch image.config.openshift.io/cluster --type=json \
    -p '[{"op":"remove","path":"/spec/registrySources/insecureRegistries"}]' \
    2>/dev/null || \
  oc patch image.config.openshift.io/cluster --type=merge \
    -p '{"spec":{"registrySources":{"insecureRegistries":[]}}}' \
    2>/dev/null || true
  ok "Harbor retiré des registries insecures"
else
  skip "Harbor n'était pas dans insecureRegistries"
fi

# ─── RÉSUMÉ ──────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                  ✅  CLEANUP TERMINÉ                         ║"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  Supprimé :                                                  ║"
echo "║    ✓ Applications et AppProject Argo CD                      ║"
echo "║    ✓ Deployments, StatefulSets, Services, Routes             ║"
echo "║    ✓ Secrets, ConfigMaps, PVC                                ║"
echo "║    ✓ Pipelines, Tasks, Triggers, PipelineRuns Tekton         ║"
echo "║    ✓ ServiceAccounts, RBAC cluster                           ║"
echo "║    ✓ Namespaces : ecommerce-prod, ecommerce-dev, cicd        ║"
echo "║    ✓ Config Harbor registry insecure                         ║"
echo "║                                                              ║"
echo "║  Non supprimé (opérateurs) :                                 ║"
echo "║    • OpenShift Pipelines (Tekton)                            ║"
echo "║    • OpenShift GitOps (Argo CD)                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Pour redéployer depuis zéro :"
echo "    export HARBOR_PASSWORD='...' GITOPS_REPO='...'"
echo "    ./scripts/install-prerequisites.sh"
echo "    ./scripts/deploy-production.sh"
echo ""
