#!/usr/bin/env bash
# =============================================================================
# demo-commands.sh  — Commands to run during screen recording
# Run each section as a separate demo step
# =============================================================================

NAMESPACE="bookstore"

# ─── SECTION 1: Show all running objects ─────────────────────────────────────
echo "===== ALL PODS ====="
kubectl get pods -n $NAMESPACE -o wide

echo "===== ALL SERVICES ====="
kubectl get svc -n $NAMESPACE

echo "===== DEPLOYMENTS ====="
kubectl get deployments -n $NAMESPACE

echo "===== STATEFULSETS ====="
kubectl get statefulsets -n $NAMESPACE

echo "===== INGRESS ====="
kubectl get ingress -n $NAMESPACE

echo "===== HPA ====="
kubectl get hpa -n $NAMESPACE

echo "===== PVC ====="
kubectl get pvc -n $NAMESPACE

echo "===== CONFIGMAPS ====="
kubectl get configmap -n $NAMESPACE

echo "===== SECRETS ====="
kubectl get secrets -n $NAMESPACE


# ─── SECTION 2: API Call to fetch books ──────────────────────────────────────
# Get the external IP first:
EXTERNAL_IP=$(kubectl get ingress bookstore-ingress -n $NAMESPACE \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "External IP: $EXTERNAL_IP"

# Fetch all books
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool

# Fetch single book
curl -s http://$EXTERNAL_IP/books/1 | python3 -m json.tool


# ─── SECTION 3: Self-healing demo — kill an API pod ──────────────────────────
echo "===== Current API pods ====="
kubectl get pods -n $NAMESPACE -l app=bookstore-api

# Pick the first pod name and delete it
API_POD=$(kubectl get pods -n $NAMESPACE -l app=bookstore-api \
  -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod: $API_POD"
kubectl delete pod $API_POD -n $NAMESPACE

echo "Watch Kubernetes recreate it automatically:"
kubectl get pods -n $NAMESPACE -l app=bookstore-api -w


# ─── SECTION 4: Self-healing demo — kill DB pod ──────────────────────────────
echo "===== Books BEFORE pod deletion ====="
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool

DB_POD=$(kubectl get pods -n $NAMESPACE -l app=postgres \
  -o jsonpath='{.items[0].metadata.name}')
echo "Deleting DB pod: $DB_POD"
kubectl delete pod $DB_POD -n $NAMESPACE

echo "Waiting for DB to restart..."
kubectl rollout status statefulset/postgres -n $NAMESPACE --timeout=120s

echo "===== Books AFTER pod deletion (data persisted!) ====="
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool


# ─── SECTION 5: Rolling update demo ──────────────────────────────────────────
# Update the image tag to trigger a rolling update
kubectl set image deployment/bookstore-api \
  bookstore-api=YOUR_DOCKERHUB_USERNAME/bookstore-api:v2 \
  -n $NAMESPACE

kubectl rollout status deployment/bookstore-api -n $NAMESPACE


# ─── SECTION 6: HPA demo ─────────────────────────────────────────────────────
# Install stress tool in a test pod to generate load
kubectl run load-test --image=busybox -n $NAMESPACE --rm -it -- \
  /bin/sh -c "while true; do wget -q -O- http://bookstore-api-service/books; done"

# In another terminal, watch HPA scale up:
kubectl get hpa -n $NAMESPACE -w


# ─── SECTION 7: FinOps — Show resource usage ─────────────────────────────────
kubectl top pods -n $NAMESPACE
kubectl describe resourcequota bookstore-quota -n $NAMESPACE
kubectl describe limitrange bookstore-limitrange -n $NAMESPACE
