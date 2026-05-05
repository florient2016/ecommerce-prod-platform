#!/bin/bash
# =============================================================================
# SCRIPT D'INSTALLATION DES PRÉREQUIS
# E-Commerce Production Platform - OpenShift
# =============================================================================
set -euo pipefail

HARBOR_HOST="10.0.0.2:8083"
HARBOR_PROJECT="ecommerce"
DOMAIN="itssolutions.it"

echo "=== [1/10] Création des namespaces ==="
oc apply -f gitops/namespaces.yaml

echo "=== [2/10] Installation Tekton Pipelines ==="
# Option A : OpenShift Pipelines Operator (recommandé on-premise)
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

echo "Attente déploiement Tekton..."
oc wait --for=condition=ready pod -l app=tekton-pipelines-controller -n tekton-pipelines --timeout=300s 2>/dev/null || \
oc rollout status deployment/tekton-pipelines-controller -n tekton-pipelines --timeout=300s || true

echo "=== [3/10] Installation Argo CD (OpenShift GitOps) ==="
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

echo "Attente déploiement Argo CD..."
sleep 60
oc wait --for=condition=available deployment/openshift-gitops-server -n openshift-gitops --timeout=300s || true

echo "=== [4/10] Configuration Harbor - Certificat auto-signé ==="
# Récupérer le certificat Harbor si auto-signé
echo "Récupération certificat Harbor..."
openssl s_client -connect ${HARBOR_HOST} -showcerts </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > /tmp/harbor-ca.crt 2>/dev/null || \
  echo "Harbor HTTP ou certificat non récupérable automatiquement"

# Ajouter Harbor comme registry insecure dans OpenShift (si HTTP)
oc patch image.config.openshift.io/cluster --type=merge -p "{
  \"spec\": {
    \"registrySources\": {
      \"insecureRegistries\": [\"${HARBOR_HOST}\"],
      \"allowedRegistries\": [
        \"${HARBOR_HOST}\",
        \"registry.redhat.io\",
        \"registry.access.redhat.com\",
        \"quay.io\",
        \"docker.io\"
      ]
    }
  }
}"

echo "=== [5/10] Création Secret Harbor (ImagePull + Push) ==="
# Remplacer HARBOR_USER et HARBOR_PASSWORD par les vraies valeurs
HARBOR_USER="${HARBOR_USER:-robot\$ecommerce+tekton}"
HARBOR_PASSWORD="${HARBOR_PASSWORD:-CHANGEME}"

# Secret pour pull dans ecommerce-prod
oc create secret docker-registry harbor-pull-secret \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASSWORD}" \
  -n ecommerce-prod --dry-run=client -o yaml | oc apply -f -

# Secret pour pull dans ecommerce-dev
oc create secret docker-registry harbor-pull-secret \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASSWORD}" \
  -n ecommerce-dev --dry-run=client -o yaml | oc apply -f -

# Secret pour push dans cicd (Tekton)
oc create secret docker-registry harbor-push-secret \
  --docker-server="${HARBOR_HOST}" \
  --docker-username="${HARBOR_USER}" \
  --docker-password="${HARBOR_PASSWORD}" \
  -n cicd --dry-run=client -o yaml | oc apply -f -

echo "=== [6/10] Link ImagePullSecrets aux ServiceAccounts ==="
oc secrets link default harbor-pull-secret --for=pull -n ecommerce-prod
oc secrets link default harbor-pull-secret --for=pull -n ecommerce-dev

echo "=== [7/10] Application manifests Tekton ==="
oc apply -f tekton/serviceaccount.yaml
oc apply -f tekton/rbac.yaml
oc apply -f tekton/tasks/
oc apply -f tekton/pipelines/
oc apply -f tekton/triggers/

echo "=== [8/10] Application manifests GitOps ==="
oc apply -f gitops/argocd/project.yaml
oc apply -f gitops/argocd/application-prod.yaml

echo "=== [9/10] Déploiement PostgreSQL ==="
oc apply -f gitops/apps/postgres/ -n ecommerce-prod

echo "=== [10/10] Route Argo CD ==="
ARGOCD_ROUTE=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "non disponible")
echo "Argo CD URL: https://${ARGOCD_ROUTE}"
ARGOCD_PASSWORD=$(oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d)
echo "Argo CD admin password: ${ARGOCD_PASSWORD}"

echo ""
echo "=== INSTALLATION TERMINÉE ==="
echo "Frontend: https://frontend.${DOMAIN}"
echo "API:      https://api.${DOMAIN}"
echo "Argo CD:  https://${ARGOCD_ROUTE}"
