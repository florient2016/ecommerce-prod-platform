# Architecture — E-Commerce Production Platform

## Composants

| Composant | Technologie | Version | Rôle |
|-----------|-------------|---------|------|
| Frontend | React + Vite + TailwindCSS | 18.x | Interface utilisateur SPA |
| Backend | NestJS + Prisma | 10.x | API REST JSON |
| Base de données | PostgreSQL | 16 | Persistence |
| Registry | Harbor | — | Images container |
| CI | Tekton Pipelines | — | Build/Test/Push |
| CD | Argo CD (OpenShift GitOps) | — | Deploy GitOps |
| Platform | OpenShift | 4.12+ | Orchestration container |

## Modèle de données

```
User ──< Order ──< OrderItem >── Product >── Category
User ──< Cart  ──< CartItem  >── Product
```

## Flux CI/CD

```
1. Developer git push main
        ↓
2. Git webhook POST → https://webhook.itssolutions.it
        ↓
3. Tekton EventListener reçoit et valide HMAC
        ↓
4. TriggerTemplate crée un PipelineRun
        ↓
5. Pipeline steps :
   [clone] → [test-backend + test-frontend] → [build-backend + build-frontend]
           → [push Harbor 10.0.0.2:8083]
           → [update gitops manifests (kustomize tag)]
        ↓
6. Argo CD détecte le changement sur la branche main (polling 3min)
        ↓
7. Argo CD applique kustomize overlay prod → ecommerce-prod namespace
        ↓
8. OpenShift RollingUpdate deployment
        ↓
9. Health/Readiness probes valident le déploiement
```

## Sécurité

- Containers non-root (UID 1001, compatible OpenShift arbitrary UID)
- SecurityContext restrictif : `allowPrivilegeEscalation: false`, `capabilities: drop: [ALL]`
- NetworkPolicies : isolation stricte entre les composants
- Secrets : jamais en clair dans Git (créés manuellement ou via SealedSecrets)
- JWT HS256 avec secret 512 bits
- bcrypt cost factor 12 pour les mots de passe
- TLS edge termination sur toutes les Routes
- CORS strict sur le backend
- Rate limiting Tekton (ThrottlerModule) : 20 req/s, 200 req/min

## Ressources

| Pod | CPU Request | CPU Limit | RAM Request | RAM Limit |
|-----|-------------|-----------|-------------|-----------|
| frontend | 50m | 200m | 64Mi | 256Mi |
| backend | 100m | 500m | 256Mi | 512Mi |
| postgres | 250m | 1000m | 256Mi | 1Gi |

## HPA

- Backend : 2→8 replicas, scale à 70% CPU / 80% RAM
- Frontend : 2→6 replicas, scale à 70% CPU
