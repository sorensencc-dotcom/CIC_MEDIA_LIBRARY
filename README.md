# CIC (Continuous Intelligence Console)

## Overview
CIC is a multi-agent system for continuous analysis, governance, and evolution of SMB websites and media assets.

## Repos and Layout
- `infra/docker` — Docker Compose for CIC + NIM integration
- `infra/k8s` — Kubernetes manifests for CIC services
- `src/clients` — NIM HTTP clients (TypeScript)
- `media` — CIC media library (ingested assets, sidecars, metadata)

## Running with Docker
```bash
cd infra/docker
docker compose -f docker-compose.cic.yml up -d
```

## NIM Integration
CIC uses Nemotron + NIM via:
- `POST /v1/chat/completions` (text + multimodal)
- `POST /v1/embeddings`
- `POST /v1/rerank`
- `POST /v1/parse`

Models are configured via `.env` and injected into CIC services.

## K8s Deployment
```bash
kubectl apply -f infra/k8s/nim-gateway.yaml
kubectl apply -f infra/k8s/nemotron-nano-text.yaml
kubectl apply -f infra/k8s/nemotron-nano-omni.yaml
kubectl apply -f infra/k8s/nemotron-retriever.yaml
kubectl apply -f infra/k8s/nemotron-parse.yaml
kubectl apply -f infra/k8s/cic-orchestrator.yaml
kubectl apply -f infra/k8s/cic-ingestion.yaml
kubectl apply -f infra/k8s/cic-audit.yaml
kubectl apply -f infra/k8s/cic-operator-console.yaml
```
