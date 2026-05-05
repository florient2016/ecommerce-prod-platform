#!/bin/bash
# =============================================================================
# VALIDATION POST-DÉPLOIEMENT
# =============================================================================
set -euo pipefail

NS="ecommerce-prod"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }

echo ""
echo "═══════════════════════════════════════════"
echo "   VALIDATION DÉPLOIEMENT ECOMMERCE PROD"
echo "═══════════════════════════════════════════"

# ─── Pods ────────────────────────────────────────
echo ""
echo "▶ Pods ($NS) :"

check_pod() {
  local LABEL=$1
  local NAME=$2
  COUNT=$(oc get pods -n $NS -l app=$LABEL \
    --field-selector=status.phase=Running \
    --no-headers 2>/dev/null | wc -l)
  if [ "$COUNT" -gt 0 ]; then
    ok "$NAME : $COUNT pod(s) Running"
  else
    fail "$NAME : aucun pod Running"
    oc get pods -n $NS -l app=$LABEL --no-headers 2>/dev/null | \
      awk '{print "       → "$1" "$3}' || true
  fi
}

check_pod postgres  "PostgreSQL"
check_pod backend   "Backend"
check_pod frontend  "Frontend"

# ─── Routes ──────────────────────────────────────
echo ""
echo "▶ Routes ($NS) :"

FRONTEND_URL=$(oc get route frontend -n $NS \
  -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "")
BACKEND_URL=$(oc get route backend-api -n $NS \
  -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "")

if [ -n "$FRONTEND_URL" ]; then
  ok "Frontend : $FRONTEND_URL"
else
  fail "Route frontend introuvable"
fi

if [ -n "$BACKEND_URL" ]; then
  ok "Backend : $BACKEND_URL"
else
  fail "Route backend-api introuvable"
fi

# ─── Health checks ───────────────────────────────
echo ""
echo "▶ Health checks API :"

if [ -n "$BACKEND_URL" ]; then
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    "${BACKEND_URL}/health" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    ok "GET /health → 200 OK"
  else
    fail "GET /health → $HTTP_CODE"
  fi

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    "${BACKEND_URL}/ready" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    ok "GET /ready → 200 OK (DB connectée)"
  else
    fail "GET /ready → $HTTP_CODE (DB non connectée ?)"
  fi

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    "${BACKEND_URL}/api/v1/products" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "200" ]; then
    ok "GET /api/v1/products → 200 OK"
    PRODUCTS=$(curl -sk "${BACKEND_URL}/api/v1/products" | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('total',0))" \
      2>/dev/null || echo "?")
    ok "Produits en base : $PRODUCTS"
  else
    fail "GET /api/v1/products → $HTTP_CODE"
  fi

  # Test Auth
  echo ""
  echo "▶ Test authentification :"
  AUTH_RESP=$(curl -sk -X POST "${BACKEND_URL}/api/v1/auth/login" \
    -H 'Content-Type: application/json' \
    -d '{"email":"admin@itssolutions.it","password":"Admin@2024!Secure"}' \
    2>/dev/null || echo "{}")
  TOKEN=$(echo "$AUTH_RESP" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('accessToken',''))" \
    2>/dev/null || echo "")
  if [ -n "$TOKEN" ]; then
    ok "Login admin → JWT reçu"
    ME=$(curl -sk "${BACKEND_URL}/api/v1/users/me" \
      -H "Authorization: Bearer $TOKEN" | \
      python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('role','?'))" \
      2>/dev/null || echo "?")
    ok "GET /users/me → role: $ME"
  else
    fail "Login admin échoué → seed non exécuté ?"
    warn "Exécuter : oc exec -n $NS \$(oc get pod -l app=backend -n $NS -o name | head -1) -- npx prisma db seed"
  fi
fi

# ─── Secrets ─────────────────────────────────────
echo ""
echo "▶ Secrets ($NS) :"

for SECRET in postgres-secret backend-secret harbor-pull-secret; do
  if oc get secret $SECRET -n $NS &>/dev/null; then
    ok "$SECRET présent"
  else
    fail "$SECRET MANQUANT"
  fi
done

# ─── PVC PostgreSQL ───────────────────────────────
echo ""
echo "▶ Stockage :"
PVC_STATUS=$(oc get pvc -n $NS -l app=postgres \
  --no-headers 2>/dev/null | awk '{print $2}' | head -1)
if [ "$PVC_STATUS" = "Bound" ]; then
  ok "PVC PostgreSQL : Bound"
else
  fail "PVC PostgreSQL : ${PVC_STATUS:-introuvable}"
fi

# ─── Tekton ──────────────────────────────────────
echo ""
echo "▶ Tekton (cicd) :"
PIPELINE=$(oc get pipeline ecommerce-pipeline -n cicd \
  --no-headers 2>/dev/null | wc -l)
if [ "$PIPELINE" -gt 0 ]; then
  ok "Pipeline ecommerce-pipeline présent"
else
  fail "Pipeline ecommerce-pipeline introuvable"
fi

EL=$(oc get eventlistener ecommerce-event-listener -n cicd \
  --no-headers 2>/dev/null | wc -l)
if [ "$EL" -gt 0 ]; then
  ok "EventListener présent"
  WEBHOOK_URL=$(oc get route ecommerce-webhook -n cicd \
    -o jsonpath='https://{.spec.host}' 2>/dev/null || echo "route introuvable")
  ok "Webhook URL : $WEBHOOK_URL"
else
  fail "EventListener introuvable"
fi

# ─── Argo CD ─────────────────────────────────────
echo ""
echo "▶ Argo CD :"
APP_STATUS=$(oc get application ecommerce-prod -n openshift-gitops \
  -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "introuvable")
HEALTH=$(oc get application ecommerce-prod -n openshift-gitops \
  -o jsonpath='{.status.health.status}' 2>/dev/null || echo "introuvable")

if [ "$APP_STATUS" = "Synced" ]; then
  ok "Application ecommerce-prod : Synced"
else
  warn "Application ecommerce-prod sync : $APP_STATUS"
fi

if [ "$HEALTH" = "Healthy" ]; then
  ok "Application ecommerce-prod health : Healthy"
else
  warn "Application ecommerce-prod health : $HEALTH"
fi

echo ""
echo "═══════════════════════════════════════════"
echo "   FIN VALIDATION"
echo "═══════════════════════════════════════════"
echo ""
