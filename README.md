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
cp .env.example .env
# Edit .env with your NVIDIA_API_KEY
docker compose -f docker-compose.cic.yml up -d
```

**Services:**
- Orchestrator (7001) — reasoning + planning
- Ingestion (7002) — document parsing + embeddings
- Audit (7003) — policy validation
- Operator Console (3100) — web UI

## NIM Integration (Phase 0.7)
CIC uses NVIDIA Nemotron models via cloud API:
- **Base URL:** https://integrate.api.nvidia.com/v1
- **Auth:** Bearer token (NVIDIA_API_KEY env var)
- **Routes:** `/v1/chat/completions`, `/v1/embeddings`, `/v1/rerank`, `/v1/parse`

Models configured via `.env`:
- Text: `nvidia/nvidia-nemotron-nano-9b-v2`
- Multimodal: `nvidia/nvidia-nemotron-nano-9b-v2`
- Embeddings: `nvidia/nvidia-embed-qa-4`
- Reranker: `nvidia/nvidia-reranker-qa-mistral-4b-v3`

**Status:** ✅ Production-ready. All services running and tested.

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
