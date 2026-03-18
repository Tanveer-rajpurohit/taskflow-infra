# TaskFlow Architecture & Production Readiness

This document outlines the architectural decisions made to ensure the TaskFlow platform is resilient, scalable, and capable of handling production-tier workloads (such as 100,000 tasks per day), fulfilling the requirements of the DevOps & MERN Assignment.

## 1. Worker Scaling Strategy

To ensure tasks are processed efficiently without bottlenecking the system, the Python Worker service is decoupled from the Node.js Backend using Redis as a message broker.

*   **Kubernetes HPA (Horizontal Pod Autoscaler)**: In a production environment, an HPA is attached to the `worker` Deployment targeting average CPU utilization (e.g., 70%). As the number of tasks in the Redis queue increases, the CPU load on the active workers spikes, triggering the HPA to spin up additional worker replicas automatically.
*   **Stateless Processing**: The Python worker is entirely stateless. It pulls a task off the Redis queue, performs the CPU-bound text transformation, writes the status/result to MongoDB, and dies/awaits the next task. This guarantees that scaling horizontally from 1 to 50 replicas will cause no race conditions or split-brain scenarios.

## 2. Handling High Task Volume (100k tasks/day)

Handling 100,000 tasks per day equates to roughly 1-2 tasks per second on average, but systems must be designed for bursts. 

*   **Asynchronous Processing**: The Node.js Express backend does *not* execute the text operations. It simply validates the JWT, inserts a `pending` record into MongoDB, pushes the Task ID to Redis, and instantly returns `202 Accepted`. This ensures the API remains heavily responsive under load.
*   **Redis Buffering**: Redis acts as a high-throughput buffer. If a massive burst of user requests occurs, the Node.js API writes them to Redis in sub-milliseconds. The Python workers consume from this queue at their own pace, preventing the databases or backend from being overwhelmed.
*   **Connection Pooling**: MongoDB connections are pooled efficiently on the Node.js backend to prevent connection churn during high RPS (Requests Per Second) events.

## 3. Database Indexing Strategy

To maintain rapid query performance as the `tasks` collection grows, precise indexing is mandated.

*   **`userId` Index**: Every read query on the dashboard fetches tasks filtered by the logged-in user. A widespread B-Tree index on `userId` (`{ userId: 1 }`) ensures these queries execute in `O(log N)` time instead of triggering a full collection scan.
*   **`status` Index**: The worker frequently queries by `status` (or updates by ID where status is `pending`). An index on the `status` field (`{ status: 1 }`) accelerates finding tasks that are pending or filtering failed tasks on the dashboard.
*   **Compound Indexing**: A compound index on `{ userId: 1, createdAt: -1 }` guarantees that when a user loads their dashboard, fetching their most recent tasks requires zero in-memory sorting by the database engine.

## 4. Handling Redis Failure

As Redis operates as the central Nervous System for queuing tasks and tracking global rate limits, its failure must be handled gracefully.

*   **StatefulSets & PVCs**: In this Kubernetes migration, Redis is deployed as a StatefulSet with a Persistent Volume Claim (PVC) and AOF/RDB persistence enabled (`--save 20 1`). If the Redis pod crashes and is rescheduled by the Kubernetes scheduler, it retains its data volume and restarts without dropping the entire pending queue.
*   **Kubernetes Probes**: Liveness and Readiness probes using `redis-cli ping` ensure that if the Redis application deadlocks, Kubernetes will automatically restart the pod.
*   **Application-Level Grace**: If the Node.js backend detects a Redis connection timeout, the HTTP request for task creation fails gracefully with a `503 Service Unavailable`, rather than silently dropping the user's task or crashing the Node process.
*   **(Production Enhancement) Redis Sentinel**: In a true multi-node production setup, Redis would be deployed as a Sentinel Cluster (1 Master, 2 Replicas) to provide automatic failover within seconds.

## 5. Deployment Environments (Staging vs. Production)

This repository utilizes **Kustomize** to enforce a strict boundary between base infrastructure and environment-specific implementations. 

*   **Base (`k8s/base`)**: Contains the universal truths of the application.
*   **Staging Overlay (`k8s/staging`)**: Connects to staging databases, uses lower resource limits to save costs.
*   **Production Overlay (`k8s/production`)**: Applies intense resource patches, configures Argo CD to sync automatically, applies external Production-grade Load Balancers, and injects real production secrets.

## 6. Networking & Ingress Strategy

Instead of exposing every microservice (Frontend, Backend) via separate LoadBalancers or NodePorts—which is costly and difficult to manage—the architecture utilizes an **Ingress Controller** (e.g., NGINX).

*   **Single Entrypoint**: The Ingress operates as a smart reverse proxy listening continuously on ports `80` / `443`.
*   **Path-Based Routing**: When a user navigates to `/api/...`, the Ingress immediately recognizes the path and routes the traffic specifically to the `backend` Service. All other traffic (matching `/`) is safely routed to the `frontend` Next.js Service.
*   **SSL Termination**: In production environments, the Ingress terminates HTTPS (managing the SSL certs via cert-manager), passing unencrypted HTTP traffic securely to the backend nodes. This relieves the Node.js and Next.js applicatons from the CPU-heavy burden of decrypting SSL traffic.

Using **Argo CD**, any merged Pull Request to the `main` branch immediately updates the Git tree, prompting Argo CD to automatically synchronize the production cluster state to match the repository.
