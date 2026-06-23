# Step-by-Step Setup Guide (Beginner Friendly)
# =============================================
# This guide walks you through everything from zero to a running cluster.
# Time estimate: ~2–3 hours

# ══════════════════════════════════════════════════════════════
# PART 1: INSTALL TOOLS ON YOUR MACHINE (WSL / Linux / Mac)
# ══════════════════════════════════════════════════════════════

# --- 1A. Open WSL (Windows) or Terminal (Mac/Linux) ---
# On Windows: Press Win key → type "wsl" → press Enter


# --- 1B. Install Docker (on WSL / Ubuntu) ---
sudo apt-get update
sudo apt-get install -y docker.io
sudo usermod -aG docker $USER
newgrp docker                         # apply group change without logging out
docker --version                      # should print Docker version


# --- 1C. Install kubectl ---
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client              # should print client version


# ══════════════════════════════════════════════════════════════
# PART 2: CREATE A KUBERNETES CLUSTER (CHOOSE ONE CLOUD)
# ══════════════════════════════════════════════════════════════

# ── OPTION A: Google Kubernetes Engine (GKE) — Free Tier Available ────────────
#   1. Go to console.cloud.google.com → Enable Kubernetes Engine API
#   2. Install gcloud CLI:
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
gcloud init                           # follow prompts, log in, choose project

#   3. Create cluster (cheapest possible for assignment):
gcloud container clusters create bookstore-cluster \
  --zone us-central1-a \
  --num-nodes 2 \
  --machine-type e2-medium \
  --disk-size 20GB

#   4. Connect kubectl to your cluster:
gcloud container clusters get-credentials bookstore-cluster --zone us-central1-a

# ── OPTION B: Azure Kubernetes Service (AKS) ─────────────────────────────────
#   (Use if you have Azure credits/subscription)
#   1. Install Azure CLI:
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az login

#   2. Create resource group and cluster:
az group create --name bookstoreRG --location eastus
az aks create --resource-group bookstoreRG --name bookstoreCluster \
  --node-count 2 --node-vm-size Standard_B2s --generate-ssh-keys

#   3. Connect kubectl:
az aks get-credentials --resource-group bookstoreRG --name bookstoreCluster

# ── OPTION C: AWS EKS ────────────────────────────────────────────────────────
#   (Use if you have AWS credits)
#   1. Install eksctl:
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

#   2. Create cluster:
eksctl create cluster --name bookstore-cluster \
  --region us-east-1 --nodegroup-name standard-workers \
  --node-type t3.medium --nodes 2 --managed

# ── Verify cluster connection (all options) ───────────────────────────────────
kubectl cluster-info         # should show cluster URL
kubectl get nodes            # should show your nodes as "Ready"


# ══════════════════════════════════════════════════════════════
# PART 3: INSTALL NGINX INGRESS CONTROLLER
# ══════════════════════════════════════════════════════════════
# This is needed to expose the API externally via an Ingress resource.

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

# Wait for it to be ready (takes ~2 minutes):
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s


# ══════════════════════════════════════════════════════════════
# PART 4: SET UP DOCKER HUB ACCOUNT & PUSH IMAGE
# ══════════════════════════════════════════════════════════════

# 1. Create a free account at https://hub.docker.com (use personal email)
# 2. Create a public repository named "bookstore-api"
# 3. Log in from your terminal:
docker login                          # enter your Docker Hub username + password

# 4. Clone this repository:
git clone https://github.com/YOUR_USERNAME/bookstore-k8s.git
cd bookstore-k8s

# 5. Build and push the Docker image:
export DOCKERHUB_USER=your_dockerhub_username   # ← CHANGE THIS
docker build -t $DOCKERHUB_USER/bookstore-api:latest ./app
docker push $DOCKERHUB_USER/bookstore-api:latest

# 6. Update the deployment file with your username:
sed -i "s|YOUR_DOCKERHUB_USERNAME|$DOCKERHUB_USER|g" k8s/base/api-deployment.yaml


# ══════════════════════════════════════════════════════════════
# PART 5: INSTALL METRICS SERVER (Required for HPA)
# ══════════════════════════════════════════════════════════════
# GKE: already included, skip this step
# EKS / AKS: run this:

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify it's running:
kubectl get deployment metrics-server -n kube-system


# ══════════════════════════════════════════════════════════════
# PART 6: DEPLOY EVERYTHING TO KUBERNETES
# ══════════════════════════════════════════════════════════════

# Apply all manifests in order:
kubectl apply -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/secret.yaml
kubectl apply -f k8s/base/api-configmap.yaml
kubectl apply -f k8s/base/db-init-sql-configmap.yaml
kubectl apply -f k8s/base/postgres-pvc.yaml
kubectl apply -f k8s/base/postgres-statefulset.yaml
kubectl apply -f k8s/base/api-service.yaml
kubectl apply -f k8s/base/api-deployment.yaml
kubectl apply -f k8s/ingress/ingress.yaml
kubectl apply -f k8s/hpa/hpa.yaml
kubectl apply -f k8s/finops/resource-quota.yaml

# Check everything is running:
kubectl get all -n bookstore

# Wait for pods to be Ready (takes ~1-2 minutes):
kubectl get pods -n bookstore -w
# Press Ctrl+C when all pods show Running


# ══════════════════════════════════════════════════════════════
# PART 7: GET YOUR EXTERNAL IP AND TEST THE API
# ══════════════════════════════════════════════════════════════

# Get external IP (may take 2-3 minutes after ingress creation):
kubectl get ingress -n bookstore
# Look for EXTERNAL-IP column

# Store it in a variable:
export EXTERNAL_IP=$(kubectl get ingress bookstore-ingress -n bookstore \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Your API is at: http://$EXTERNAL_IP"

# Test the endpoints:
curl http://$EXTERNAL_IP/            # {"status":"ok","message":"Book Catalog API is running"}
curl http://$EXTERNAL_IP/health      # {"status":"healthy"}
curl http://$EXTERNAL_IP/books       # Returns all 8 books
curl http://$EXTERNAL_IP/books/1     # Returns book with id=1


# ══════════════════════════════════════════════════════════════
# PART 8: SCREEN RECORDING DEMO STEPS
# ══════════════════════════════════════════════════════════════
# Start recording now. Run the following commands one by one.

# Step A: Show all deployed objects
kubectl get all -n bookstore
kubectl get ingress -n bookstore
kubectl get hpa -n bookstore
kubectl get pvc -n bookstore
kubectl get configmap -n bookstore
kubectl get secret -n bookstore

# Step B: Show API call retrieving data from DB
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool

# Step C: Kill an API pod → show it regenerates (self-healing)
API_POD=$(kubectl get pods -n bookstore -l app=bookstore-api -o jsonpath='{.items[0].metadata.name}')
echo "Killing pod: $API_POD"
kubectl delete pod $API_POD -n bookstore
# Immediately watch:
kubectl get pods -n bookstore -w
# You'll see the pod Terminating and a new one starting — press Ctrl+C after new pod is Running

# Step D: Kill DB pod → show data persists
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool   # show data BEFORE
DB_POD=$(kubectl get pods -n bookstore -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $DB_POD -n bookstore
kubectl get pods -n bookstore -w    # wait for postgres to restart (Ctrl+C when Running)
curl -s http://$EXTERNAL_IP/books | python3 -m json.tool   # show SAME data AFTER ✓

# Step E: Rolling update
kubectl set image deployment/bookstore-api bookstore-api=$DOCKERHUB_USER/bookstore-api:latest -n bookstore
kubectl rollout status deployment/bookstore-api -n bookstore

# Step F: HPA
kubectl get hpa -n bookstore
kubectl describe hpa bookstore-api-hpa -n bookstore

# Step G: FinOps
kubectl describe resourcequota bookstore-quota -n bookstore
kubectl describe limitrange bookstore-limitrange -n bookstore


# ══════════════════════════════════════════════════════════════
# PART 9: PUSH CODE TO GITHUB
# ══════════════════════════════════════════════════════════════

# 1. Create a new PUBLIC repository on github.com (use personal account)
#    Name it: bookstore-k8s
#    Do NOT initialise with README (we already have one)

# 2. From your local machine:
git init
git add .
git commit -m "Initial commit: Kubernetes multi-tier bookstore assignment"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/bookstore-k8s.git
git push -u origin main


# ══════════════════════════════════════════════════════════════
# PART 10: TEARDOWN (after demo is recorded and submitted)
# ══════════════════════════════════════════════════════════════

kubectl delete namespace bookstore   # removes all resources in namespace

# Delete the cluster itself to stop cloud billing:
# GKE:  gcloud container clusters delete bookstore-cluster --zone us-central1-a
# AKS:  az aks delete --resource-group bookstoreRG --name bookstoreCluster --yes
# EKS:  eksctl delete cluster --name bookstore-cluster --region us-east-1
