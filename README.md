# tf-kube

This project uses Terraform to deploy a small Kubernetes stack with:

- Nginx as a front door
- Redis with password authentication
- Redis Commander for a Redis web UI
- A Flask counter app backed by Redis
- Netdata for monitoring

## What gets deployed

The Terraform configuration creates:

- Namespace: apps
- Namespace: monitoring
- Nginx deployment and NodePort service
- Redis deployment and service
- Redis Commander deployment and service
- Counter app deployment and service
- Netdata deployment and service

## Prerequisites

Before running this project, make sure you have:

- Terraform installed
- kubectl installed
- A working Kubernetes cluster (for example, Minikube)
- A kubeconfig file available at ~/.kube/config

## Configuration

Copy the example file and edit it with your Redis password:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then update the file with your chosen password:

```hcl
redis_password = "your-strong-password"
```

## Deploy

From this directory, run:

```bash
terraform init
terraform apply -var-file=terraform.tfvars
```

## Build the counter app image

The Flask app is expected to run from a local Docker image named `flask-counter:v1`.

Build it with:

```bash
cd counter-app
docker build -t flask-counter:v1 .
```

## Access the services

### Nginx

```bash
kubectl get svc -n apps nginx-service
```

Then open the NodePort URL shown by Kubernetes.

### Redis Commander

The Redis UI is available through Nginx at:

```text
http://<node-ip>:<nginx-node-port>/redis/
```

### Counter app

The counter app is exposed via:

```text
http://<node-ip>:<counter-app-node-port>/counter/
```

### Netdata

The Netdata service is reachable through Nginx at:

```text
http://<node-ip>:<nginx-node-port>/netdata/
```

## Useful commands

```bash
kubectl get pods -n apps
kubectl get svc -n apps
kubectl logs deployment/redis-commander -n apps
kubectl logs deployment/counter-app -n apps
```

## Notes

- The Redis password is passed into both Redis and Redis Commander.
- The Nginx config uses basic auth for the Redis UI path.
- The counter app reads the Redis connection details from environment variables.

