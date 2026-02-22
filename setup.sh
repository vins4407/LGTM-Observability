#!/bin/bash

# =============================================================================
# MLTP-STACK ONE-CLICK SETUP SCRIPT (Local Development)
# =============================================================================

set -e

# --- Configuration ---
CLUSTER_NAME="mltp-local-cluster"
NAMESPACE="grafana-monitoring"
CHART_DIR="."
VALUES_FILE="values/values-local.yaml"

# --- Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting MLTP-Stack Local Setup...${NC}"

# 1. Check Prerequisites
echo -e "${YELLOW}🔍 Checking prerequisites...${NC}"
command -v kind >/dev/null 2>&1 || { echo -e >&2 "❌ kind is required but not installed. Aborting."; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e >&2 "❌ helm is required but not installed. Aborting."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo -e >&2 "❌ kubectl is required but not installed. Aborting."; exit 1; }

# 2. Create Kind Cluster (if not exists)
if kind get clusters | grep -q "^$CLUSTER_NAME$"; then
    echo -e "${GREEN}✅ Kind cluster '$CLUSTER_NAME' already exists.${NC}"
else
    echo -e "${YELLOW}🏗️ Creating Kind cluster '$CLUSTER_NAME'...${NC}"
    kind create cluster --name "$CLUSTER_NAME"
fi

# 3. Add Helm Repositories
echo -e "${YELLOW}📦 Adding Helm repositories...${NC}"
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# 4. Install MLTP-Stack
echo -e "${YELLOW}📥 Installing MLTP-Stack in namespace '$NAMESPACE'...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Build dependencies
echo -e "${YELLOW}🔗 Building chart dependencies...${NC}"
helm dependency build "$CHART_DIR"

# Install/Upgrade
echo -e "${YELLOW}⚡ Deploying Helm chart...${NC}"
helm upgrade --install mltp-stack "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --wait --timeout 15m

echo -e "${GREEN}✅ MLTP-Stack successfully deployed!${NC}"

# 5. Access Information
echo -e "\n${BLUE}📊 Access Information:${NC}"
echo -e "--------------------------------------------------"
echo -e "Grafana UI:  http://localhost:3000"
echo -e "Username:    admin"
echo -e "Password:    admin"
echo -e "\nTo access Grafana, run:"
echo -e "${GREEN}kubectl port-forward svc/mltp-stack-grafana -n $NAMESPACE 3000:80${NC}"
echo -e "--------------------------------------------------"

echo -e "\n${BLUE}📝 Next Steps:${NC}"
echo -e "1. Run the port-forward command above."
echo -e "2. Open http://localhost:3000 in your browser."
echo -e "3. Explore the pre-configured Loki, Mimir, and Tempo datasources!"
echo -e "4. Check out the Alloy collector logs to see data flowing: "
echo -e "   ${YELLOW}kubectl logs -l app.kubernetes.io/name=alloy -n $NAMESPACE${NC}"
