# 📊 MLTP-Stack: Unified LGTM Observability

The **MLTP-Stack** (Metrics, Logs, Traces, Profiling) is a pre-configured, production-ready observability distribution based on the **Grafana LGTM stack** (Loki, Grafana, Tempo, Mimir, Alloy).

This stack is optimized to provide a **SigNoz-like one-click experience** for the community while retaining the power of industry-standard components.

---

## 🚀 Key Features

- **One-Click Setup**: Zero-to-Observability in minutes with `kind` and `helm`.
- **Staging Optimized**: Resource-efficient configurations (Request = Limit) out of the box.
- **Unified Collection**: Uses **Grafana Alloy** for high-performance telemetry collection.
- **Multi-Environment**: Seamlessly switch between Local (MinIO) and Cloud (EKS/S3) storage.
- **Correlated Data**: Pre-configured trace-to-log and trace-to-metric correlation in Grafana.

---

## 🏗️ Architecture

```text
  [ App Pods ] --- (OTLP) ---> [ Alloy-Traces ] --+--> [ Tempo (Traces) ]
       |                                          |
       +------- (Logs) ------> [ Alloy-DS ] ------+--> [ Loki (Logs) ]
       |                                          |
       +------ (Metrics) ----> [ Alloy-DS ] ------+--> [ Mimir (Metrics) ]
                                      |
  [ K8s Infra ] -- (Metrics) -> [ Alloy-KSM ] ----+
```

---

## 🏁 Quick Start (Local Setup)

This mode is perfect for developers wanting to explore the stack without any cloud costs. It uses **MinIO** as an internal S3-compatible storage.

### 1. Prerequisites
- [Docker](https://docs.docker.com/get-docker/)
- [Kind](https://kind.sigs.k8s.io/)
- [Helm](https://helm.sh/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

### 2. Run the One-Click Setup
```bash
cd mltp-stack
./setup.sh
```

### 3. Access Grafana
```bash
kubectl port-forward svc/mltp-stack-grafana -n grafana-monitoring 3000:80
```
Visit **http://localhost:3000** (Login: `admin` / `admin`).

---

## ☁️ EKS / Production Deployment (Cloud Guide)

To deploy on EKS, you need to manually configure AWS S3 buckets and IAM roles for high-performance storage.

### 🛠️ Prerequisites
- [AWS CLI](https://aws.amazon.com/cli/) installed and configured.
- [eksctl](https://eksctl.io/) installed (recommended for IAM setup).

### 1️⃣ Create S3 Buckets
Create three buckets for the stack. **Tip:** Use a unique prefix like `mltp-obs-`.

```bash
aws s3 mb s3://mltp-loki-chunks
aws s3 mb s3://mltp-mimir-blocks
aws s3 mb s3://mltp-tempo-traces
```

### 2️⃣ Setup IAM Roles for Service Accounts (IRSA)
This allows the LGTM pods to talk to S3 without using static AWS keys.

```bash
# Example using eksctl for Loki
eksctl create iamserviceaccount \
    --name lgtm-s3-role \
    --namespace grafana-monitoring \
    --cluster <your-cluster-name> \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
    --approve
```
*Repeat or use a single role for all components. Note the Role ARN generated.*

### 3️⃣ Configure `values/values-eks.yaml`
Open `values/values-eks.yaml` and update the following:
- `global.clusterName`: Your EKS cluster name.
- `eks.amazonaws.com/role-arn`: The ARN of the role you created in Step 2.
- `bucketnames`: The names of the buckets you created in Step 1.

### 4️⃣ Deploy
```bash
helm upgrade --install mltp-stack . \
  --namespace grafana-monitoring \
  --create-namespace \
  -f values/values-eks.yaml
```

---

## 🛠️ Configuration Reference

The stack is highly parameterized. You can customize the following in `values.yaml`:

| Parameter | Default | Description |
| :--- | :--- | :--- |
| `global.clusterName` | `mltp-cluster` | Label used to identify data from different clusters. |
| `global.tenantId` | `tenant1` | Tenant ID for multi-tenancy in Loki/Mimir. |
| `global.storage.type` | `s3` | Can be `s3` (AWS) or `minio` (Local). |

---

## 📁 Repository Structure

- `charts/`: Sub-chart dependencies (Loki, Mimir, etc.)
- `templates/`: Custom templates for Alloy configurations and helpers.
- `values/`: Environment-specific value files (`values-local.yaml`, `values-eks.yaml`).
- `setup.sh`: The automated local setup script.

---

## 🤝 Community & Support

This project is built on top of the open-source LGTM stack. If you find it helpful, please give it a ⭐ on GitHub!

For any issues or contributions, feel free to open a PR or issue. Let's make observability more accessible to everyone!
