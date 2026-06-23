# Kubernetes Multi-Tier Architecture — Comprehensive Documentation

---

## 1. Requirement Understanding

The assignment requires building and deploying a **multi-tier application on Kubernetes** consisting of:

**Service API Tier (microservice):**
- Exposes HTTP API endpoints that fetch data from the database
- 4 replicas running at all times
- Externally accessible via Ingress
- Supports rolling updates (zero-downtime deployments)
- Self-healing via Kubernetes probes
- HorizontalPodAutoscaler (HPA) to scale based on CPU/memory
- Configuration injected from outside the pod (ConfigMap + Secrets)

**Database Tier (PostgreSQL):**
- 1 replica StatefulSet
- Contains a `books` table with 8 seed records
- Data must persist across pod restarts (PersistentVolumeClaim)
- Accessible only within the cluster (ClusterIP service)
- Self-healing via StatefulSet restart policy

**Kubernetes Requirements:**
- ConfigMap for non-secret DB connection config in the API tier
- Kubernetes Secrets for database password — never visible in plain text in YAML
- Communication between tiers via Service DNS names (never pod IPs)
- Ingress for external exposure of the API tier

**FinOps Requirements:**
- CPU and memory requests/limits defined on API tier
- Minimum 3 cost optimisation opportunities identified
- Resource optimisation implemented with quotas

---

## 2. Assumptions

| # | Assumption |
|---|---|
| 1 | A Kubernetes cluster (GKE / EKS / AKS) is available and `kubectl` is configured to point to it. |
| 2 | The Nginx Ingress Controller is installed in the cluster. The assignment does not mandate a specific ingress class; Nginx was chosen as it is cloud-agnostic. |
| 3 | An IP address (without DNS mapping) is sufficient to demonstrate external access, per Q&A guidance. |
| 4 | PostgreSQL 16 is an acceptable database engine. No specific RDBMS was mandated. |
| 5 | Python (Flask + Gunicorn) is an acceptable framework for the API tier. |
| 6 | Docker is available on WSL (Windows Subsystem for Linux) on the developer's machine, per Q&A guidance. |
| 7 | A personal Docker Hub account (public repository) is acceptable for image hosting, per Q&A guidance. |
| 8 | A personal GitHub account is acceptable for the repository, per Q&A guidance. |
| 9 | The cluster can be deleted after the demo recording is captured, per Q&A guidance. |
| 10 | The `metrics-server` add-on is installed in the cluster (required for HPA CPU/memory metrics). |

---

## 3. Solution Overview

### 3.1 Technology Stack

| Component | Technology | Reason |
|---|---|---|
| API Language | Python 3.12 | Lightweight, minimal boilerplate, excellent Kubernetes ecosystem |
| API Framework | Flask 3.0 | Lightweight REST framework, easy to containerise |
| API Server | Gunicorn | Production-grade WSGI server; multi-worker support |
| Database | PostgreSQL 16 | Robust, widely used, excellent Kubernetes support |
| DB Driver | psycopg2 | Standard Python PostgreSQL driver with connection pooling |
| Container Registry | Docker Hub | Free public registry; no cluster configuration needed |
| Source Control | GitHub | Free public repository hosting |
| Ingress | Nginx Ingress | Cloud-agnostic; works on GKE, EKS, AKS |

---

### 3.2 Application: Bookstore API

A simple Book Catalogue API that stores 8 books in a PostgreSQL database. The API exposes:

- `GET /books` — returns all books as JSON
- `GET /books/{id}` — returns a single book
- `GET /health` — liveness probe endpoint
- `GET /ready` — readiness probe endpoint (verifies DB connectivity)

**Connection Pooling:** `psycopg2.pool.SimpleConnectionPool` is used with `minconn=1, maxconn=10`. This means connections to PostgreSQL are reused across requests rather than opened/closed per request — a production best practice that reduces latency and DB load.

**Config Separation:** Database host, port, name, and user are injected via environment variables from a Kubernetes ConfigMap. The password is injected separately from a Kubernetes Secret. The application code contains no hardcoded credentials.

---

### 3.3 Docker Image

The Dockerfile uses a **multi-stage build**:

1. **Builder stage** — installs Python dependencies into `/install` using pip
2. **Runtime stage** — copies only the installed packages and source into a minimal `python:3.12-slim` image

This produces a lean image (~120 MB) rather than a bloated one with build tools included. A **non-root user** (`appuser`) is used for security.

---

### 3.4 Kubernetes Objects Summary

| Object | Name | Namespace | Purpose |
|---|---|---|---|
| Namespace | bookstore | — | Isolates all assignment resources |
| ConfigMap | api-config | bookstore | DB_HOST, DB_PORT, DB_NAME, DB_USER for API |
| ConfigMap | db-init-sql | bookstore | SQL script to create table + seed data |
| Secret | db-secret | bookstore | POSTGRES_PASSWORD, DB_PASSWORD, POSTGRES_USER, POSTGRES_DB |
| PersistentVolumeClaim | postgres-pvc | bookstore | 1Gi volume for PostgreSQL data directory |
| StatefulSet | postgres | bookstore | 1-replica PostgreSQL with PVC mount |
| Service | postgres-service | bookstore | ClusterIP :5432 — internal access only |
| Deployment | bookstore-api | bookstore | 4-replica Flask API with rolling update |
| Service | bookstore-api-service | bookstore | ClusterIP :80 → pod :5000 |
| Ingress | bookstore-ingress | bookstore | Routes external HTTP to bookstore-api-service |
| HPA | bookstore-api-hpa | bookstore | Scales API pods based on CPU/memory |
| ResourceQuota | bookstore-quota | bookstore | Namespace-level CPU/memory/pod cap |
| LimitRange | bookstore-limitrange | bookstore | Per-container default + max limits |

---

### 3.5 Key Kubernetes Features

#### Rolling Updates
The `bookstore-api` Deployment uses `strategy: RollingUpdate` with `maxUnavailable: 1` and `maxSurge: 1`. This means during any update:
- At most 1 pod is taken down (3 remain serving traffic)
- At most 1 extra pod is started (briefly 5 pods during transition)
- Zero downtime is maintained

#### Self-Healing

**API Tier:** The Deployment controller continuously reconciles the desired state (4 replicas). If a pod crashes or is deleted, it is automatically recreated. The liveness probe (`/health`) restarts a pod if it stops responding. The readiness probe (`/ready`) removes a pod from load balancing if it cannot reach the DB.

**Database Tier:** The StatefulSet controller ensures the postgres pod is always restarted if it fails. Since the data is on a PVC (not inside the pod), restarting the pod does not lose data.

#### Data Persistence
PostgreSQL stores data at `/var/lib/postgresql/data/pgdata`. This path is mounted from the PVC (`postgres-pvc`). The PVC is backed by the cluster's default StorageClass (e.g., `gp2` on EKS, `standard` on GKE). Even if the pod is deleted and rescheduled on a different node, the PVC re-attaches and data is preserved.

#### No Pod IP Usage
All inter-tier communication uses **Kubernetes Service DNS names**:
- The API connects to `postgres-service` (resolves to the ClusterIP of the postgres service)
- Pod IPs are ephemeral and change on every restart; Service DNS is stable

#### ConfigMap and Secret Injection
```
api-config (ConfigMap)           db-secret (Secret)
 DB_HOST=postgres-service         DB_PASSWORD=<base64>
 DB_PORT=5432            →  Injected as env vars into API pod
 DB_NAME=appdb
 DB_USER=appuser
```
The ConfigMap values are loaded via `envFrom: configMapRef`. The Secret password is loaded separately via `secretKeyRef`. Neither the ConfigMap nor Secret contains plain-text passwords in the source YAML (values are base64-encoded in the Secret).

#### HPA
The HPA monitors the average CPU and memory utilisation across all `bookstore-api` pods. When either exceeds the threshold (60% CPU or 70% memory), new pods are added up to the maximum of 8. A 5-minute cool-down window prevents rapid scale-down (flapping).

---

### 3.6 FinOps: Cost Optimisation

Three opportunities (and implementations) to reduce Kubernetes costs:

**Opportunity 1 — Right-sized resource requests**
Without explicit requests, the scheduler may place pods on over-provisioned nodes or fail to pack pods efficiently. The API pods are given:
- CPU request: 100m (0.1 vCPU) — matches observed idle usage
- Memory request: 128Mi — matches observed Flask + gunicorn baseline
This allows the cluster autoscaler to provision smaller nodes and pack pods tightly.

**Opportunity 2 — HPA scale-down during off-peak hours**
The HPA's `minReplicas: 2` means during quiet periods the API drops from 4 to 2 pods, halving compute cost for the API tier. The 300-second `scaleDown.stabilizationWindowSeconds` prevents expensive oscillation.

**Opportunity 3 — Namespace ResourceQuota hard caps**
The `ResourceQuota` limits the entire namespace to 1 vCPU request and 1 GiB memory request. This prevents accidental runaway pod counts from inflating the cluster node count and incurring unexpected costs.

**Opportunity 4 (bonus) — Spot/Preemptible nodes for the API tier**
Since Flask API pods are stateless and can restart instantly (liveness/readiness probes handle transient failures), they are ideal candidates for spot instances (AWS) or preemptible VMs (GCP), which cost 60–90% less than on-demand instances.

**Opportunity 5 (bonus) — Minimal PVC size**
The PostgreSQL PVC is 1Gi — sufficient for the 8-record dataset used in this assignment. Cloud storage costs are proportional to provisioned size; using the minimum reduces storage billing.

---

## 4. Justification for Resources Utilised

### Why Python / Flask?
Python with Flask is lightweight and has minimal container image overhead. Flask's simplicity keeps the application code focused on demonstrating Kubernetes concepts rather than framework boilerplate. Gunicorn provides production-grade request handling with minimal configuration.

### Why PostgreSQL?
PostgreSQL is the most widely used open-source relational database in Kubernetes environments. The official Docker image supports init scripts via `/docker-entrypoint-initdb.d/`, making seed data injection straightforward via a ConfigMap. It has excellent support for connection pooling and health checks.

### Why StatefulSet for the database?
StatefulSets are the correct Kubernetes primitive for databases because they provide: stable network identity (pod DNS name is predictable), ordered pod creation/deletion, and native PVC template support. A plain Deployment could work for a stateless app but is not appropriate for a database where startup order and volume attachment matter.

### Why Nginx Ingress over LoadBalancer service?
A LoadBalancer service provisions one cloud load balancer per service (costly). An Ingress uses a single load balancer and routes multiple paths to different services via rules. For this assignment (single service), both work — but Ingress is the industry-standard approach and is explicitly required by the assignment.

### Why Connection Pooling in the Application?
Opening a new TCP connection to PostgreSQL for every HTTP request is expensive (each connection spawns a process on the DB server). `psycopg2.pool.SimpleConnectionPool` maintains a pool of open connections that are leased per request and returned when done. This is the standard best practice for database-backed web services.

### Why Multi-Stage Docker Build?
A single-stage Dockerfile that installs gcc and libpq-dev for compilation would produce an image of ~400MB. The multi-stage build discards all build-time tooling and produces a ~120MB runtime image. Smaller images: pull faster, reduce attack surface, and lower container registry storage costs.

---

*End of Documentation*
