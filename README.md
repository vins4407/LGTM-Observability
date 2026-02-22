<p align="center">
  <!-- Replace with your own logo when ready -->
  <img src="https://grafana.com/media/grafana/images/grafana-logo-dark.svg" alt="LGTM Stack" width="200">
</p>

<h1 align="center">LGTM Stack</h1>
<p align="center">
  <b>Metrics · Logs · Traces — One Helm Install on Kubernetes</b>
</p>

<p align="center">
  A production-ready, unified observability stack built on Grafana's open-source ecosystem.<br/>
  Deploy a complete monitoring platform in minutes — not days.
</p>

<p align="center">
  <a href="#-quick-start-local"><img src="https://img.shields.io/badge/Quick_Start-Local-blue?style=for-the-badge" alt="Quick Start"></a>
  <a href="#%EF%B8%8F-deploy-to-eks"><img src="https://img.shields.io/badge/Deploy-EKS-orange?style=for-the-badge" alt="Deploy EKS"></a>
  <a href="https://opensource.org/licenses/Apache-2.0"><img src="https://img.shields.io/badge/License-Apache_2.0-green?style=for-the-badge" alt="License"></a>
</p>

---

## The Problem

Setting up a full observability stack on Kubernetes is hard. You need to independently deploy and wire together Loki, Mimir, Tempo, Grafana, and one or more collectors — each with its own Helm chart, its own storage config, and its own quirks. The learning curve is steep, the documentation is scattered across multiple projects, and getting trace-to-log correlation working takes hours of trial and error.

**LGTM Stack solves this.** It packages the entire Grafana ecosystem into a single Helm chart with sane defaults, so you go from zero to a fully correlated observability platform with one command.

---

## What's Inside

| Signal | Powered By | What It Does |
| :--- | :--- | :--- |
| **Metrics** | [Grafana Mimir](https://grafana.com/oss/mimir/) | Long-term, horizontally scalable Prometheus-compatible metrics storage. |
| **Logs** | [Grafana Loki](https://grafana.com/oss/loki/) | Cost-effective, label-based log aggregation — like Prometheus, but for logs. |
| **Traces** | [Grafana Tempo](https://grafana.com/oss/tempo/) | Distributed tracing backend with no indexing overhead. |
| **Collection** | [Grafana Alloy](https://grafana.com/docs/alloy/latest/) | Unified telemetry collector for metrics, logs, and traces. |
| **Visualization** | [Grafana](https://grafana.com/oss/grafana/) | Pre-configured dashboards with trace ↔ log ↔ metric correlation. |

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                                  │
│                                                                             │
│   ┌──────────────┐                                                          │
│   │  Your Apps   │──── OTLP (gRPC/HTTP) ───▶  ┌─────────────────┐           │
│   └──────────────┘                            │  Alloy-Traces   │           │
│                                               │  (StatefulSet)  │────▶ Tempo|
│                                               └─────────────────┘           │
│   ┌──────────────┐                                                          │
│   │  All Pods    │──── stdout/stderr ───────▶ ┌─────────────────┐           │
│   │  (Logs)      │                            │  Alloy-DS       │           │
│   └──────────────┘                            │  (DaemonSet)    │────▶ Loki |
│                                               │                 │           │
│   ┌──────────────┐                            │  Scrapes pod    │           │
│   │  Pod Metrics │──── /metrics ────────────▶ │  & node metrics │────▶ Mimir|
│   │  cAdvisor    │                            └─────────────────┘           │
│   │  Node Export │                                                          │
│   └──────────────┘                            ┌─────────────────┐           │
│                                               │  Alloy-KSM      │           │
│   ┌──────────────┐                            │  (StatefulSet)  │────▶Mimir |
│   │  KSM Metrics │──── /metrics ────────────▶ └─────────────────┘           │
│   └──────────────┘                                                          │
│                                                                             │
│                       ┌───────────────────────────────────────────┐         │
│                       │              MinIO / S3                   │         │
│                       │  ┌───────────┬───────────┬────────────┐   │         │
│                       │  │loki-chunks│mimir-block│tempo-traces│   │         │
│                       │  └───────────┴───────────┴────────────┘   │         │
│                       │         (Single PVC or AWS S3)            │         │
│                       └───────────────────────────────────────────┘         │
│                                                                             │
│                       ┌─────────────────┐                                   │
│                       │    Grafana      │ ◀── All signals pre-wired         │
│                       │  (Dashboards)   │     trace ↔ log ↔ metric          │
│                       └─────────────────┘                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Storage

All components run in **distributed mode** — multiple pods per component for reliability and throughput. This means they need **shared storage** (an S3-compatible API) so that all pods can read and write to the same data.

You have two options:

| Option | What It Is | When to Use |
| :--- | :--- | :--- |
| **MinIO** (default) | An S3-compatible server running inside your cluster on a single PVC. All three backends (Loki, Mimir, Tempo) write to separate "buckets" inside this one MinIO instance. | Local development, Kind clusters, teams that want everything self-contained. |
| **AWS S3** | Real cloud object storage. No in-cluster storage pods needed. | Production on EKS, cost-effective at scale, durable. |

> **Note:** MinIO stores all data on its own PVC (a disk volume). So your data IS on a PVC — it's just accessed through the S3 API. This is required because in distributed mode, multiple Loki/Mimir/Tempo pods need to access the same data simultaneously, and regular PVCs only allow one pod to mount them.

### "Why do Loki/Mimir/Tempo need PVCs if MinIO is the storage?"

The component PVCs are **not** for long-term data. They serve two critical short-lived purposes:

| PVC Owner | Size | Purpose | Without it |
| :--- | :---: | :--- | :--- |
| Loki/Mimir/Tempo **ingesters** | 10 Gi each | **Write-Ahead Log (WAL)** — data is written to local disk first, then flushed to MinIO/S3 in batches every few minutes. If the pod crashes, the WAL recovers un-flushed data on restart. | Pod crash = **un-flushed data lost permanently** |
| Mimir **store_gateway** | 5 Gi | **Index cache** — caches block indexes downloaded from MinIO so queries don't re-fetch them on every request. | Queries work but are **significantly slower** |
| Mimir/Tempo **compactors** | 10 Gi each | **Scratch space** — downloads blocks from MinIO, merges and deduplicates them locally, then re-uploads the compacted result. | Compaction **fails** (no workspace) |

**In summary:**
- **MinIO PVC (20 Gi)** → your actual data warehouse. All logs, metrics, and traces live here for the full retention period. Increase for production (50–100 Gi for high-volume environments).
- **Component PVCs (45 Gi total)** → crash-safety buffers and temporary work areas. Data lives here for **seconds to minutes**, not days.

---

## Retention

Data retention is configured globally and defaults to **7 days** for all signals.

```yaml
global:
  retention:
    logs: "168h"     # Loki — 7 days
    metrics: "168h"  # Mimir — 7 days
    traces: "168h"   # Tempo — 7 days
```

Change these values in `values.yaml` or in your environment-specific override file. For example, to keep metrics for 30 days:

```yaml
global:
  retention:
    metrics: "720h"  # 30 days
```

---

## Quick Start (Local)

Get a fully working observability stack on your laptop in under 5 minutes.

### Prerequisites

| Tool | Install |
| :--- | :--- |
| Docker | https://docs.docker.com/get-docker/ |
| Kind | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| Helm v3+ | https://helm.sh/docs/intro/install/ |
| kubectl | https://kubernetes.io/docs/tasks/tools/ |

### Install

```bash
git clone https://github.com/YOUR_USERNAME/lgtm-stack.git
cd lgtm-stack
./setup.sh
```

The script will:
1. Create a local Kind cluster (`lgtm-local`).
2. Deploy MinIO as in-cluster S3 storage (single PVC).
3. Install the full LGTM stack via Helm into the `observability` namespace.
4. Print access instructions.

### Access Grafana

```bash
kubectl port-forward svc/lgtm-stack-grafana -n observability 3000:80
```

Open **http://localhost:3000** — Login: `admin` / `admin`

All three datasources (Loki, Mimir, Tempo) are pre-configured with full trace ↔ log ↔ metric correlation out of the box.

---

## ☁️ Deploy to EKS

For production or staging environments on AWS EKS. Pick the storage backend that fits your needs — each has its own values file, so there's no editing or commenting required.

### Storage Choice on EKS

| Option | Values File | What to Change | Pros | Cons |
| :--- | :--- | :--- | :--- | :--- |
| **AWS S3** | `values/values-eks-s3.yaml` | Bucket names, IAM role ARNs, region | Durable, scalable, no in-cluster storage | Requires AWS setup |
| **MinIO** | `values/values-eks-minio.yaml` | Just `clusterName` | Zero AWS setup, data on EBS | Uses cluster resources |

---

### Option A: EKS with AWS S3

**Step 1 — Create S3 Buckets:**

```bash
export BUCKET_PREFIX="myorg-observability"
export REGION="us-east-1"

aws s3 mb s3://${BUCKET_PREFIX}-loki-chunks --region $REGION
aws s3 mb s3://${BUCKET_PREFIX}-loki-ruler --region $REGION
aws s3 mb s3://${BUCKET_PREFIX}-mimir-blocks --region $REGION
aws s3 mb s3://${BUCKET_PREFIX}-tempo-traces --region $REGION
```

**Step 2 — Create IRSA Role:**

```bash
eksctl create iamserviceaccount \
  --name lgtm-s3-access \
  --namespace observability \
  --cluster <your-cluster-name> \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
  --approve
```

> For tighter security, create a custom IAM policy scoped to only the four buckets above.

**Step 3 — Fill in `values/values-eks-s3.yaml`:**

Open the file and replace every `# CHANGE THIS` placeholder with your values — cluster name, region, bucket names, and IAM role ARNs.

**Step 4 — Deploy:**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm dependency build .

helm upgrade --install lgtm-stack . \
  --namespace observability \
  --create-namespace \
  -f values/values-eks-s3.yaml
```

---

### Option B: EKS with MinIO

No S3 buckets, no IAM roles — just deploy. MinIO runs inside your cluster on an EBS-backed PVC.

**Step 1 — Edit `values/values-eks-minio.yaml`:**

Only change `global.clusterName` to your EKS cluster name (and optionally the MinIO password).

**Step 2 — Deploy:**

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm dependency build .

helm upgrade --install lgtm-stack . \
  --namespace observability \
  --create-namespace \
  -f values/values-eks-minio.yaml
```

That's it. MinIO provisions an EBS volume, and Loki/Mimir/Tempo use it as shared storage. No AWS resource setup needed.

---

## Configuration

### Global Parameters

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `global.clusterName` | `lgtm-cluster` | Injected as a label into all metrics, logs, and traces for multi-cluster identification. |
| `global.tenantId` | `tenant1` | `X-Scope-OrgID` header for Loki, Mimir, and Tempo multi-tenancy. |
| `global.retention.logs` | `168h` | How long Loki keeps logs before deletion. |
| `global.retention.metrics` | `168h` | How long Mimir keeps metric blocks before deletion. |
| `global.retention.traces` | `168h` | How long Tempo keeps trace data before deletion. |
| `minio.enabled` | `true` | Set to `false` when using cloud storage (AWS S3). |

### Values Files

| File | Use Case |
| :--- | :--- |
| `values.yaml` | Production defaults — full distributed mode, 2 replicas, caches enabled. |
| `values/values-local.yaml` | **Laptop-friendly** — 1 replica, no caches, ~3 Gi RAM, ~23 Gi disk. |
| `values/values-eks-minio.yaml` | EKS with MinIO — just set your cluster name and deploy. |
| `values/values-eks-s3.yaml` | EKS with AWS S3 — fill in bucket names, IAM role ARNs, and region. |

### Resource Footprint

The stack ships with **two profiles** — a lightweight one for laptops and a full distributed one for production. The local profile (`values-local.yaml`) uses single replicas, disables in-memory caches, and reduces resource requests so it actually runs on a MacBook.

#### Local Profile (`values-local.yaml`)

| Component | Pods | CPU Request | Memory | PVC |
| :--- | :---: | :---: | :---: | :---: |
| **Loki** | 6 | 375m | ~1.1 Gi | 2 Gi |
| **Mimir** | 7 | 375m | ~0.9 Gi | 6 Gi |
| **Tempo** | 5 | 300m | ~0.7 Gi | 4 Gi |
| **Alloy-DS** | 1 | 50m | 128Mi | — |
| **Alloy-Traces** | 1 | 50m | 128Mi | — |
| **Alloy-KSM** | 1 | 25m | 64Mi | — |
| **Grafana** | 1 | 50m | 128Mi | 512Mi |
| **MinIO** | 1 | 50m | 128Mi | 10 Gi |
| | | | | |
| **Total** | **23** | **~1.3 cores** | **~3.3 Gi** | **~23 Gi** |

| Requirement | Minimum |
| :--- | :--- |
| Docker Desktop CPU | **4 cores** |
| Docker Desktop Memory | **6 GB** |
| Free disk space | **~25 GB** |
| Cloud cost | **$0** |

> Runs entirely on your laptop. Allocate resources to Docker Desktop via **Settings → Resources**.

#### Production Profile (`values.yaml`)

| Component | Pods | CPU Request | Memory | PVC |
| :--- | :---: | :---: | :---: | :---: |
| **Loki** (distributed) | 11 | 1.25 cores | ~6.1 Gi | 10 Gi |
| **Mimir** (distributed) | 12 | 1.05 cores | ~3.3 Gi | 20 Gi |
| **Tempo** (distributed) | 6 | 800m | ~1.9 Gi | 15 Gi |
| **Alloy-DS** (DaemonSet) | 1/node | 200m/pod | 512Mi/pod | — |
| **Alloy-Traces** | 2 | 400m | 512Mi | — |
| **Alloy-KSM** | 1 | 50m | 128Mi | — |
| **Grafana** | 1 | *(defaults)* | *(defaults)* | 1 Gi |
| **MinIO** | 1 | *(defaults)* | *(defaults)* | 20 Gi |
| | | | | |
| **Total** | **~37*** | **~4.6 cores** | **~14 Gi** | **~66 Gi** |

*\*Alloy-DS runs 1 pod per node — total assumes 3-node cluster. MinIO is not deployed when using AWS S3.*

#### AWS EKS Cost Estimate

| | Minimum | Recommended |
| :--- | :--- | :--- |
| **Node type** | 3× `t3.large` (2 vCPU, 8 Gi) | 2× `t3.xlarge` (4 vCPU, 16 Gi) |
| **Allocatable capacity** | 6 vCPU / ~21 Gi | 8 vCPU / ~28 Gi |
| | | |
| **EKS control plane** | ~$73/mo | ~$73/mo |
| **EC2 nodes (on-demand)** | ~$180/mo | ~$240/mo |
| **EBS storage (gp3, ~66 Gi)** | ~$6/mo | ~$6/mo |
| **S3 (if using S3 instead of MinIO)** | ~$2/mo | ~$2/mo |
| | | |
| **Estimated total** | **~$255/month** | **~$315/month** |

> 💡 **Cost tip:** Use [AWS Savings Plans](https://aws.amazon.com/savingsplans/) or Reserved Instances to save **30–40%** on EC2 costs. Spot instances for non-critical workloads (Alloy-DS, caches) can reduce costs further.

---

## How It Works

The chart deploys **seven components** as sub-charts, wired together automatically:

1. **Grafana Alloy (DaemonSet)** — Runs on every node. Discovers pods, collects logs via the Kubernetes API, scrapes Prometheus metrics from pods, cAdvisor, and node-exporter. Forwards everything to Loki and Mimir.

2. **Grafana Alloy (Traces)** — A StatefulSet that receives OTLP traces (gRPC on `:4317`, HTTP on `:4318`) from your instrumented applications and forwards them to Tempo. Automatically injects the cluster name as a trace attribute. Also generates service graph metrics and sends them to Mimir.

3. **Grafana Alloy (KSM)** — A dedicated StatefulSet that scrapes kube-state-metrics. Separated from the DaemonSet to avoid duplicate scrapes across nodes.

4. **Grafana Loki** — Distributed mode. Receives logs from Alloy, stores them in MinIO/S3 with TSDB indexing. Retention is enforced by the compactor.

5. **Grafana Mimir** — Distributed mode. Receives metrics from Alloy, provides long-term Prometheus-compatible storage. Retention is enforced by the compactor.

6. **Grafana Tempo** — Distributed mode. Receives traces from Alloy-Traces, stores them in MinIO/S3. Retention is enforced by the compactor.

7. **Grafana** — Pre-configured with all three datasources and full correlation: traces → logs, traces → metrics, and service graph visualization.

---

## Repository Structure

```
lgtm-stack/
├── Chart.yaml                        # Umbrella chart — all dependencies declared here
├── values.yaml                       # Base configuration (7-day retention, distributed mode)
├── setup.sh                          # One-click local setup script
├── values/
│   ├── values-local.yaml             # Local dev (Kind + MinIO) — used by setup.sh
│   ├── values-eks-minio.yaml         # EKS + MinIO — change clusterName and deploy
│   └── values-eks-s3.yaml            # EKS + AWS S3 — fill in buckets, IAM roles, region
└── templates/
    ├── _helpers.tpl                  # Helm template helpers
    ├── alloy-ds-config.yaml          # Alloy DaemonSet config (logs + metrics collection)
    ├── alloy-traces-config.yaml      # Alloy Traces config (OTLP receiver + service graphs)
    └── alloy-ksm-config.yaml         # Alloy KSM config (kube-state-metrics scraper)
```

---

## Cleanup

**Local (Kind):**
```bash
kind delete cluster --name lgtm-local
```

**EKS:**
```bash
helm uninstall lgtm-stack -n observability
```

---

## Contributing

Contributions are welcome. Whether it's fixing a bug, improving docs, or adding support for a new cloud provider (GKE, AKS) — open an issue or submit a PR.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

---

<p align="center">
  Built with the open-source <a href="https://grafana.com/oss/">Grafana LGTM ecosystem</a>.
</p>
