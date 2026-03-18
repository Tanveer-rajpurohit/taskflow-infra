# start.ps1
Write-Host "--- TaskFlow Local Kubernetes Startup ---" -ForegroundColor Cyan

# Check if kubectl is installed
if (!(Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Error: kubectl is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

Write-Host "1/5 Cleaning up old clusters..." -ForegroundColor Yellow
kind delete cluster --name taskflow

Write-Host "2/5 Creating Kubernetes Cluster using 'kind'..." -ForegroundColor Yellow
# Creates a cluster named 'taskflow' using your explicit cluster.yml setup
kind create cluster --name taskflow --config k8s/cluster.yml

Write-Host "3/5 Installing NGINX Ingress Controller for Kind..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
Write-Host "Waiting for Ingress Controller to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s

Write-Host "4/5 Applying Kustomize Local Overlay..." -ForegroundColor Yellow
# This applies the namespace, base manifests, and local overrides all at once
kubectl apply -k k8s/local

Write-Host "5/5 Waiting for Services to Boot..." -ForegroundColor Yellow
# Sleep briefly to ensure pods are registered before waiting
Start-Sleep -Seconds 3

# We use continue on error because sometimes the pod isn't instantly available to wait on
try {
    kubectl wait --for=condition=ready pod -l app=mongo -n taskflow --timeout=120s
    kubectl wait --for=condition=ready pod -l app=redis -n taskflow --timeout=120s
} catch {
    Write-Host "Warning: Timeout while waiting for databases. They might still be pulling images." -ForegroundColor DarkYellow
}

try {
    kubectl wait --for=condition=ready pod -l app=backend -n taskflow --timeout=120s
    kubectl wait --for=condition=ready pod -l app=frontend -n taskflow --timeout=120s
    kubectl wait --for=condition=ready pod -l app=worker -n taskflow --timeout=120s

} catch {
    Write-Host "Warning: Timeout while waiting for applications. Check 'kubectl get pods -n taskflow'." -ForegroundColor DarkYellow
}

Write-Host "--- Deployment Applied! ---" -ForegroundColor Green
Write-Host "To access the platform locally, ensure you have:"
Write-Host "1. An NGINX Ingress Controller running in your local cluster."
Write-Host "2. Mapped '127.0.0.1 taskflow.local' in your C:\Windows\System32\drivers\etc\hosts file."
Write-Host "Then, visit: http://localhost" -ForegroundColor Cyan
