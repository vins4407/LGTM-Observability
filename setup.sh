#!/bin/bash

# =============================================================================
# LGTM-STACK: One-Click Local Setup
# =============================================================================
# Creates a Kind cluster and deploys the full LGTM observability stack
# (Loki, Grafana, Tempo, Mimir) with MinIO as local storage.
# =============================================================================

set -e

CLUSTER_NAME="lgtm-local"
NAMESPACE="observability"
CHART_DIR="."
VALUES_FILE="values/values-local.yaml"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  LGTM Stack — Local Setup                            ${NC}"
echo -e "${BLUE}  Metrics · Logs · Traces on Kubernetes                ${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# --- Prerequisites ---
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"
MISSING=""
command -v docker >/dev/null 2>&1 || MISSING="${MISSING} docker"
command -v kind >/dev/null 2>&1   || MISSING="${MISSING} kind"
command -v helm >/dev/null 2>&1   || MISSING="${MISSING} helm"
command -v kubectl >/dev/null 2>&1 || MISSING="${MISSING} kubectl"

if [ -n "$MISSING" ]; then
    echo -e "${RED}Missing required tools:${MISSING}${NC}"
    echo -e "Install them and try again."
    exit 1
fi
echo -e "${GREEN}All prerequisites found.${NC}"

# --- Kind Cluster ---
echo -e "${YELLOW}[2/5] Setting up Kind cluster '${CLUSTER_NAME}'...${NC}"
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo -e "${GREEN}Cluster '${CLUSTER_NAME}' already exists. Skipping creation.${NC}"
else
    kind create cluster --name "$CLUSTER_NAME"
    echo -e "${GREEN}Cluster created.${NC}"
fi

# --- Helm Repos ---
echo -e "${YELLOW}[3/5] Adding Helm repositories...${NC}"
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update

# --- Dependencies ---
echo -e "${YELLOW}[4/5] Building chart dependencies...${NC}"
helm dependency build "$CHART_DIR"

# --- Deploy ---
echo -e "${YELLOW}[5/5] Deploying LGTM Stack to namespace '${NAMESPACE}'...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install lgtm-stack "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --wait --timeout 15m

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  LGTM Stack deployed successfully!                    ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  Grafana UI:   ${BLUE}http://localhost:3000${NC}"
echo -e "  Username:     admin"
echo -e "  Password:     admin"
echo ""
echo -e "  To access Grafana, run:"
echo -e "  ${GREEN}kubectl port-forward svc/lgtm-stack-grafana -n ${NAMESPACE} 3000:80${NC}"
echo ""
echo -e "  To check pod status:"
echo -e "  ${YELLOW}kubectl get pods -n ${NAMESPACE}${NC}"
echo ""
echo -e "  Retention: 7 days (logs, metrics, traces)"
echo -e "  Storage:   MinIO (in-cluster, PVC-backed)"
echo ""
