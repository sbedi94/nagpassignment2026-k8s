#!/usr/bin/env bash
# =============================================================================
# deploy.sh  —  Full deployment script for the Bookstore K8s Assignment
# Run this from the repository root after setting DOCKERHUB_USER below.
# =============================================================================
set -euo pipefail

# ── CONFIGURE THESE ──────────────────────────────────────────────────────────
DOCKERHUB_USER="${DOCKERHUB_USER:-YOUR_DOCKERHUB_USERNAME}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
IMAGE_NAME="${DOCKERHUB_USER}/bookstore-api:${IMAGE_TAG}"
# ─────────────────────────────────────────────────────────────────────────────

echo "============================================================"
echo "  Bookstore Kubernetes Deployment"
echo "  Image: ${IMAGE_NAME}"
echo "============================================================"

# ── Step 1: Build and push Docker image ──────────────────────────────────────
echo ""
echo "[1/6] Building Docker image..."
docker build -t "${IMAGE_NAME}" ./app

echo "[1/6] Pushing image to Docker Hub..."
docker push "${IMAGE_NAME}"

# ── Step 2: Update image reference in deployment YAML ────────────────────────
echo ""
echo "[2/6] Patching image reference in api-deployment.yaml..."
sed -i "s|YOUR_DOCKERHUB_USERNAME/bookstore-api:latest|${IMAGE_NAME}|g" \
    k8s/base/api-deployment.yaml

# ── Step 3: Create namespace ──────────────────────────────────────────────────
echo ""
echo "[3/6] Creating namespace..."
kubectl apply -f k8s/base/namespace.yaml

# ── Step 4: Apply base manifests ─────────────────────────────────────────────
echo ""
echo "[4/6] Applying base Kubernetes manifests..."
kubectl apply -f k8s/base/secret.yaml
kubectl apply -f k8s/base/api-configmap.yaml
kubectl apply -f k8s/base/db-init-sql-configmap.yaml
kubectl apply -f k8s/base/postgres-pvc.yaml
kubectl apply -f k8s/base/postgres-statefulset.yaml
kubectl apply -f k8s/base/api-deployment.yaml
kubectl apply -f k8s/base/api-service.yaml

# ── Step 5: Apply ingress and HPA ─────────────────────────────────────────────
echo ""
echo "[5/6] Applying Ingress and HPA..."
kubectl apply -f k8s/ingress/ingress.yaml
kubectl apply -f k8s/hpa/hpa.yaml

# ── Step 6: Apply FinOps quota ───────────────────────────────────────────────
echo ""
echo "[6/6] Applying FinOps ResourceQuota and LimitRange..."
kubectl apply -f k8s/finops/resource-quota.yaml

# ── Wait for pods ─────────────────────────────────────────────────────────────
echo ""
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/bookstore-api -n bookstore --timeout=120s
kubectl rollout status statefulset/postgres -n bookstore --timeout=120s

# ── Print external access info ────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  Deployment complete!"
echo "============================================================"
echo ""
echo "All pods:"
kubectl get pods -n bookstore

echo ""
echo "Services:"
kubectl get svc -n bookstore

echo ""
echo "Ingress (wait ~2 min for external IP to be assigned):"
kubectl get ingress -n bookstore

echo ""
echo "HPA:"
kubectl get hpa -n bookstore
