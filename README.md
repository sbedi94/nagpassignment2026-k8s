# Bookstore API — Kubernetes Multi-Tier Assignment

## Links

| Resource | URL |
|---|---|
| **GitHub Repository** | `https://github.com/YOUR_USERNAME/bookstore-k8s` |
| **Docker Hub Image** | `https://hub.docker.com/r/YOUR_DOCKERHUB_USERNAME/bookstore-api` |
| **Live API Endpoint** | `http://EXTERNAL_IP/books` |

> Replace `YOUR_USERNAME`, `YOUR_DOCKERHUB_USERNAME`, and `EXTERNAL_IP` with actual values after deployment.

---

## Architecture Overview

```
Internet
   │
   ▼
[Ingress Controller]  ← External IP (LoadBalancer)
   │
   ▼
[bookstore-api-service]  ClusterIP :80
   │
   ├── [bookstore-api Pod 1]
   ├── [bookstore-api Pod 2]   ← Deployment (4 replicas)
   ├── [bookstore-api Pod 3]      Rolling Update | Self-healing | HPA
   └── [bookstore-api Pod 4]
             │
             │  ClusterIP (postgres-service:5432)
             ▼
        [postgres Pod]  ← StatefulSet (1 replica)
             │
             ▼
        [PersistentVolumeClaim]  ← Data persists across pod restarts
```

---

## Project Structure

```
.
├── app/
│   ├── app.py               # Flask API microservice
│   ├── wsgi.py              # Gunicorn entry point
│   ├── requirements.txt     # Python dependencies
│   └── Dockerfile           # Multi-stage Docker build
├── k8s/
│   ├── base/
│   │   ├── namespace.yaml
│   │   ├── secret.yaml              # DB credentials (base64)
│   │   ├── api-configmap.yaml       # Non-secret DB config
│   │   ├── db-init-sql-configmap.yaml  # SQL init script
│   │   ├── postgres-pvc.yaml        # Persistent Volume Claim
│   │   ├── postgres-statefulset.yaml   # DB StatefulSet + Service
│   │   ├── api-deployment.yaml      # API Deployment (4 replicas)
│   │   └── api-service.yaml         # API ClusterIP Service
│   ├── ingress/
│   │   └── ingress.yaml             # External Ingress
│   ├── hpa/
│   │   └── hpa.yaml                 # HorizontalPodAutoscaler
│   └── finops/
│       └── resource-quota.yaml      # ResourceQuota + LimitRange
├── deploy.sh                # One-command deployment script
├── demo-commands.sh         # Screen recording demo commands
└── README.md
```

---

## Prerequisites

- Docker installed (or Docker on WSL)
- `kubectl` configured pointing to your cluster (GKE / EKS / AKS)
- Nginx Ingress Controller installed in cluster (see below)
- Docker Hub account

---

## Step-by-Step Deployment

### 1. Clone the repository
```bash
git clone https://github.com/YOUR_USERNAME/bookstore-k8s.git
cd bookstore-k8s
```

### 2. Install Nginx Ingress Controller (if not already installed)
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml
```

### 3. Log in to Docker Hub
```bash
docker login
```

### 4. Set your Docker Hub username and deploy
```bash
export DOCKERHUB_USER=your_dockerhub_username
chmod +x deploy.sh
./deploy.sh
```

### 5. Get the external IP
```bash
kubectl get ingress -n bookstore
# Wait ~2 minutes for EXTERNAL-IP to appear
```

### 6. Test the API
```bash
curl http://EXTERNAL_IP/books
curl http://EXTERNAL_IP/books/1
curl http://EXTERNAL_IP/health
```

---

## API Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/` | API status check |
| GET | `/health` | Liveness probe |
| GET | `/ready` | Readiness probe (checks DB) |
| GET | `/books` | List all books |
| GET | `/books/{id}` | Get book by ID |

---

## Kubernetes Features Demonstrated

| Feature | How |
|---|---|
| External access | Nginx Ingress → ClusterIP Service |
| Internal-only DB | postgres-service is ClusterIP only |
| 4 API pods | `replicas: 4` in Deployment |
| Rolling updates | `RollingUpdate` strategy, maxUnavailable:1 |
| Self-healing | Liveness + readiness probes; K8s restarts failed pods |
| Data persistence | PVC mounted to StatefulSet |
| No pod IPs | All communication via Service DNS names |
| ConfigMap | DB host/port/name injected via `envFrom` |
| Secrets | DB password injected via `secretKeyRef` |
| HPA | CPU 60% / Memory 70% triggers, min 2 max 8 pods |
| Resource limits | requests+limits on all containers |

---

## FinOps Cost Optimisation Opportunities

1. **Right-sized resource requests** — CPU/memory requests set to observed usage, not arbitrary defaults. Prevents over-provisioning on node auto-scaler.

2. **HPA scale-down** — API tier scales down to 2 replicas during low traffic (off-peak hours), reducing compute cost automatically.

3. **LimitRange + ResourceQuota** — Namespace-level caps prevent runaway pods from consuming costly node resources.

4. **Spot/Preemptible nodes** — API pods are stateless and tolerant to interruption; run them on spot/preemptible nodes for 60–80% node cost reduction.

5. **Single small DB instance** — StatefulSet uses 1 replica with a small PVC (1Gi), avoiding unnecessary storage cost.

---

## Updating the Image (Rolling Update)

```bash
# Build new version
docker build -t YOUR_DOCKERHUB_USERNAME/bookstore-api:v2 ./app
docker push YOUR_DOCKERHUB_USERNAME/bookstore-api:v2

# Trigger rolling update — zero downtime
kubectl set image deployment/bookstore-api \
  bookstore-api=YOUR_DOCKERHUB_USERNAME/bookstore-api:v2 \
  -n bookstore

# Watch the rollout
kubectl rollout status deployment/bookstore-api -n bookstore
```

---

## Teardown (after recording)

```bash
kubectl delete namespace bookstore
# Then delete your cloud cluster to stop billing
```
