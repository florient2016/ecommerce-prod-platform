# 🛒 E-Commerce Production Platform

**Stack : NestJS · React/Vite · PostgreSQL · OpenShift · Tekton · Argo CD · Harbor**

---

## Table des matières

1. [Architecture](#architecture)
2. [Prérequis](#prérequis)
3. [Installation rapide](#installation-rapide)
4. [Déploiement complet pas à pas](#déploiement-complet)
5. [Pipeline CI/CD](#cicd)
6. [Commandes de validation](#validation)
7. [Troubleshooting](#troubleshooting)
8. [Rollback](#rollback)
9. [Backup PostgreSQL](#backup)

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                         │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌──────────────────────┐   │
│  │  cicd ns │   │ argocd ns│   │   ecommerce-prod ns   │   │
│  │          │   │          │   │                       │   │
│  │  Tekton  │   │  Argo CD │   │  Frontend (React)     │   │
│  │  Pipeline│──▶│  GitOps  │──▶│  Backend (NestJS)     │   │
│  │  Triggers│   │  Sync    │   │  PostgreSQL            │   │
│  └──────────┘   └──────────┘   └──────────────────────┘   │
│       ▲                                                     │
│       │ webhook                                             │
└───────┼─────────────────────────────────────────────────────┘
        │
   Git Push ──▶ Harbor Registry (10.0.0.2:8083)
                 ecommerce/backend:<sha>
                 ecommerce/frontend:<sha>

URLs exposées :
  https://frontend.itssolutions.it  →  Frontend (React/Nginx)
  https://api.itssolutions.it       →  Backend API (NestJS)
  https://webhook.itssolutions.it   →  Tekton EventListener
```

---

## Prérequis

- OpenShift 4.12+
- `oc` CLI configuré avec droits cluster-admin
- Accès Harbor sur `10.0.0.2:8083`
- Git repo accessible depuis le cluster

---

## Installation rapide

```bash
# 1. Cloner ce repo
git clone <REPO_URL> ecommerce-production-platform
cd ecommerce-production-platform

# 2. Exporter les variables
export HARBOR_USER="robot\$ecommerce+tekton"
export HARBOR_PASSWORD="<TOKEN_HARBOR>"
export HARBOR_HOST="10.0.0.2:8083"

# 3. Lancer le script d'installation
chmod +x scripts/install-prerequisites.sh
./scripts/install-prerequisites.sh
```

---

## Déploiement complet

### Étape 1 — Namespaces

```bash
oc apply -f gitops/namespaces.yaml
```

### Étape 2 — Harbor : Registry insecure (si HTTP ou cert auto-signé)

```bash
# Autoriser Harbor comme registry insecure
oc patch image.config.openshift.io/cluster --type=merge -p '{
  "spec": {
    "registrySources": {
      "insecureRegistries": ["10.0.0.2:8083"]
    }
  }
}'

# Attendre le redémarrage des nœuds (MachineConfig)
oc wait mcp/worker --for=condition=Updated --timeout=600s
```

### Étape 3 — Secrets Harbor

```bash
# Robot account Harbor (créer dans Harbor UI : Projects > ecommerce > Robot Accounts)
HARBOR_USER="robot\$ecommerce+tekton"
HARBOR_PASSWORD="<TOKEN>"

# Pull secrets (prod + dev)
for NS in ecommerce-prod ecommerce-dev; do
  oc create secret docker-registry harbor-pull-secret \
    --docker-server=10.0.0.2:8083 \
    --docker-username="$HARBOR_USER" \
    --docker-password="$HARBOR_PASSWORD" \
    -n $NS --dry-run=client -o yaml | oc apply -f -
  oc secrets link default harbor-pull-secret --for=pull -n $NS
done

# Push secret (cicd)
oc create secret docker-registry harbor-push-secret \
  --docker-server=10.0.0.2:8083 \
  --docker-username="$HARBOR_USER" \
  --docker-password="$HARBOR_PASSWORD" \
  -n cicd --dry-run=client -o yaml | oc apply -f -
```

### Étape 4 — Secrets applicatifs

```bash
# Générer mot de passe PostgreSQL
PG_PASSWORD=$(openssl rand -base64 32 | tr -dc 'A-Za-z0-9' | head -c 32)
JWT_SECRET=$(openssl rand -base64 64)

oc create secret generic postgres-secret \
  --from-literal=POSTGRES_USER=ecommerce \
  --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
  -n ecommerce-prod

oc create secret generic backend-secret \
  --from-literal=DATABASE_URL="postgresql://ecommerce:${PG_PASSWORD}@postgres:5432/ecommerce_prod" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  -n ecommerce-prod

# SSH key pour git (push manifests GitOps)
ssh-keygen -t ed25519 -C "tekton@itssolutions.it" -f /tmp/tekton-git -N ""
# AJOUTER la clé publique (/tmp/tekton-git.pub) dans votre Git en Deploy Key (avec write)

oc create secret generic git-ssh-secret \
  --from-file=ssh-privatekey=/tmp/tekton-git \
  -n cicd

# Webhook secret (HMAC)
oc create secret generic webhook-secret \
  --from-literal=secret=$(openssl rand -hex 32) \
  -n cicd
```

### Étape 5 — Tekton

```bash
oc apply -f tekton/serviceaccount.yaml
oc apply -f tekton/rbac.yaml
oc apply -f tekton/tasks/tasks.yaml
oc apply -f tekton/pipelines/pipeline.yaml
oc apply -f tekton/triggers/triggers.yaml

# Vérifier
oc get tasks,pipelines,eventlisteners -n cicd
```

### Étape 6 — Argo CD

```bash
# Modifier l'URL du repo Git dans applications.yaml
sed -i 's|YOUR_ORG|votre-org|g' gitops/argocd/applications.yaml

oc apply -f gitops/argocd/applications.yaml -n openshift-gitops

# Récupérer le mot de passe admin
oc get secret openshift-gitops-cluster -n openshift-gitops \
  -o jsonpath='{.data.admin\.password}' | base64 -d && echo
```

### Étape 7 — Configurer le webhook Git

```bash
# Récupérer l'URL du webhook
WEBHOOK_URL=$(oc get route ecommerce-webhook -n cicd -o jsonpath='{.spec.host}')
WEBHOOK_SECRET=$(oc get secret webhook-secret -n cicd -o jsonpath='{.data.secret}' | base64 -d)

echo "URL webhook: https://$WEBHOOK_URL"
echo "Secret:      $WEBHOOK_SECRET"

# Dans GitLab/GitHub : Settings > Webhooks
# URL: https://$WEBHOOK_URL
# Secret: $WEBHOOK_SECRET
# Events: Push events, branch: main
```

### Étape 8 — Seed initial de la base de données

```bash
# Après le premier déploiement backend
BACKEND_POD=$(oc get pod -n ecommerce-prod -l app=backend -o name | head -1)
oc exec -n ecommerce-prod $BACKEND_POD -- npx prisma db seed
```

---

## CI/CD

### Déclencher manuellement un PipelineRun

```bash
cat <<EOF | oc apply -f -
apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  generateName: ecommerce-manual-run-
  namespace: cicd
spec:
  serviceAccountName: tekton-pipeline-sa
  pipelineRef:
    name: ecommerce-pipeline
  params:
    - name: git-url
      value: http://10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git
    - name: git-revision
      value: main
    - name: gitops-url
      value: ssh://git@10.0.0.2:8929/YOUR_GROUP/ecommerce-production-platform.git
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: [ReadWriteMany]
          storageClassName: nfs-storage
          resources:
            requests:
              storage: 2Gi
    - name: dockerconfig-workspace
      secret:
        secretName: harbor-push-secret
    - name: ssh-workspace
      secret:
        secretName: git-ssh-secret
EOF

# Suivre les logs
tkn pipelinerun logs -f -n cicd --last
```

---

## Validation

```bash
# === Infrastructure ===
oc get nodes
oc get namespaces | grep -E "ecommerce|cicd|argocd"

# === Pods prod ===
oc get pods -n ecommerce-prod
oc get pods -n cicd

# === Routes ===
oc get routes -n ecommerce-prod
oc get routes -n cicd

# === Test API ===
curl -k https://api.itssolutions.it/health
curl -k https://api.itssolutions.it/ready
curl -k https://api.itssolutions.it/api/v1/products

# === Test Auth ===
TOKEN=$(curl -sk -X POST https://api.itssolutions.it/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"admin@itssolutions.it","password":"Admin@2024!Secure"}' \
  | jq -r '.accessToken')
echo "Token: $TOKEN"

curl -sk https://api.itssolutions.it/api/v1/users/me \
  -H "Authorization: Bearer $TOKEN" | jq

# === Argo CD ===
oc get application -n openshift-gitops
argocd app get ecommerce-prod  # si CLI argocd installé

# === Tekton ===
tkn pipeline list -n cicd
tkn pipelinerun list -n cicd
```

---

## Rollback

### Option A — Rollback Argo CD (recommandé)

```bash
# Lister les révisions
argocd app history ecommerce-prod

# Rollback vers révision précédente
argocd app rollback ecommerce-prod <REVISION_ID>
```

### Option B — Rollback Git (GitOps)

```bash
# Identifier le commit à restaurer
git log --oneline gitops/kustomize/overlays/prod/kustomization.yaml

# Revenir à l'état précédent
git revert HEAD
git push origin main

# Argo CD détecte et sync automatiquement
```

### Option C — Rollback OpenShift direct (urgence)

```bash
# Lister l'historique des déploiements
oc rollout history deployment/backend -n ecommerce-prod
oc rollout history deployment/frontend -n ecommerce-prod

# Rollback vers la version précédente
oc rollout undo deployment/backend -n ecommerce-prod
oc rollout undo deployment/frontend -n ecommerce-prod

# Ou vers une révision spécifique
oc rollout undo deployment/backend --to-revision=2 -n ecommerce-prod

# Vérifier
oc rollout status deployment/backend -n ecommerce-prod
```

---

## Backup PostgreSQL

### Backup manuel

```bash
POSTGRES_POD=$(oc get pod -n ecommerce-prod -l app=postgres -o name | head -1)
PG_PASSWORD=$(oc get secret postgres-secret -n ecommerce-prod \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)

# Dump complet
oc exec -n ecommerce-prod $POSTGRES_POD -- \
  pg_dump -U ecommerce -d ecommerce_prod --format=custom \
  > backup-$(date +%Y%m%d-%H%M%S).dump

echo "Backup créé : backup-$(date +%Y%m%d).dump"
```

### Restore

```bash
DUMP_FILE="backup-20240101-120000.dump"
POSTGRES_POD=$(oc get pod -n ecommerce-prod -l app=postgres -o name | head -1)

# Copier le dump dans le pod
oc cp $DUMP_FILE ecommerce-prod/$POSTGRES_POD:/tmp/restore.dump

# Restore
oc exec -n ecommerce-prod $POSTGRES_POD -- \
  pg_restore -U ecommerce -d ecommerce_prod --clean /tmp/restore.dump
```

### CronJob Backup automatique

```bash
cat <<EOF | oc apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: ecommerce-prod
spec:
  schedule: "0 2 * * *"   # Chaque nuit à 2h
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: postgres:16-alpine
              env:
                - name: PGPASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: postgres-secret
                      key: POSTGRES_PASSWORD
              command:
                - /bin/sh
                - -c
                - |
                  DATE=\$(date +%Y%m%d-%H%M%S)
                  pg_dump -h postgres -U ecommerce -d ecommerce_prod \
                    --format=custom > /backup/dump-\${DATE}.dump
                  # Garder seulement les 7 derniers backups
                  ls -t /backup/dump-*.dump | tail -n +8 | xargs -r rm
                  echo "Backup terminé: dump-\${DATE}.dump"
              volumeMounts:
                - name: backup-storage
                  mountPath: /backup
          volumes:
            - name: backup-storage
              persistentVolumeClaim:
                claimName: postgres-backup-pvc
EOF
```

---

## Troubleshooting

```bash
# === Pods en erreur ===
oc get pods -n ecommerce-prod --field-selector=status.phase!=Running
oc describe pod <POD_NAME> -n ecommerce-prod
oc logs <POD_NAME> -n ecommerce-prod --previous

# === ImagePullBackOff ===
oc describe pod <POD_NAME> -n ecommerce-prod | grep -A5 Events
# Vérifier ImagePullSecret
oc get secret harbor-pull-secret -n ecommerce-prod -o yaml
# Tester le pull manuellement
oc debug node/<NODE_NAME> -- chroot /host crictl pull \
  --creds "user:pass" 10.0.0.2:8083/ecommerce/backend:latest

# === Backend ne démarre pas ===
oc logs -l app=backend -n ecommerce-prod --tail=100
# Vérifier la connexion DB
BACKEND_POD=$(oc get pod -l app=backend -n ecommerce-prod -o name | head -1)
oc exec -n ecommerce-prod $BACKEND_POD -- npx prisma db push --accept-data-loss

# === Pipeline Tekton échoue ===
tkn pipelinerun describe --last -n cicd
tkn taskrun logs --last -n cicd
oc get events -n cicd --sort-by='.lastTimestamp'

# === Argo CD OutOfSync ===
argocd app diff ecommerce-prod
argocd app sync ecommerce-prod --force

# === Route 503 ===
oc get endpoints -n ecommerce-prod
oc get route frontend -n ecommerce-prod -o yaml

# === Postgres connexion ===
oc exec -n ecommerce-prod \
  $(oc get pod -l app=postgres -n ecommerce-prod -o name | head -1) -- \
  psql -U ecommerce -d ecommerce_prod -c "SELECT version();"

# === Ressources ===
oc top pods -n ecommerce-prod
oc top nodes
oc describe resourcequota -n ecommerce-prod
```
