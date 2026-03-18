# TaskFlow - Kubernetes Infrastructure

This directory contains the Kubernetes manifests designed to deploy the TaskFlow AI Platform using an enterprise-grade structure via **Kustomize**.

## Directory Structure

We use Kustomize overlays to manage configurations across multiple environments without duplicating YAML files:

*   **`base/`**: The core application components. Contains the Namespace, StatefulSets (Mongo, Redis) with PersistentVolumeClaims, Deployments (Frontend, Backend, Worker), and internal Services.
*   **`local/`**: Patches and overlays for local development. Includes local ConfigMaps, local Secrets, and an NGINX Ingress routing rule mapped to `taskflow.local`.
*   **`staging/` & `production/`**: *(Placeholders)* Designed for CI/CD pipelines. These would overlay production API URLs, higher replica counts, and production SSL/TLS certificates.

## Quick Start (Local Deployment)

To deploy the entire system to your local Kubernetes cluster (e.g., Docker Desktop, Minikube, or k3s):

### Prerequisites

1.  A running local Kubernetes cluster.
2.  An **NGINX Ingress Controller** installed in your cluster.
    *(For Docker Desktop or k3s, this is often a 1-click extension or a simple helm install).*
3.  The local Docker images must be built. Run `docker compose build` at the project root first if you haven't.

### Step 1: DNS Mapping

The local ingress routes traffic based on the hostname. You must map the local domain to your machine.
Edit your hosts file (`C:\Windows\System32\drivers\etc\hosts` on Windows, or `/etc/hosts` on Linux/Mac) and add:

```text
127.0.0.1   taskflow.local
```

### Step 2: Apply the Deployment

From the root of the project, run the startup script:

```powershell
.\start.ps1
```

This script will use Kustomize to apply the `k8s/local` overlay, which automatically includes everything in `k8s/base`.

### Step 3: Access the Application

Once the pods are in the `Running` state, open your browser and navigate to:
**http://taskflow.local**

## Teardown

To remove all resources associated with the local deployment:

```powershell
kubectl delete -k k8s/local
```

*Note: Deleting the Kustomize overlay will remove the StatefulSets and their bound PVCs, meaning local MongoDB and Redis data will be lost upon teardown.*

---
**For information on Architecture, Scaling, and High Availability, please read `explane.md`.**
