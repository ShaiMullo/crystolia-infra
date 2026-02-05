# ArgoCD Applications Directory

This directory contains ArgoCD Application manifests that are managed by the root-app.

## Structure

```
apps/
├── README.md          # This file (placeholder)
├── mongodb.yaml       # (future) MongoDB application
├── monitoring.yaml    # (future) Prometheus/Grafana stack
└── crystolia.yaml     # (future) Main application
```

## How it works

1. The `root-app` in `bootstrap/` watches this directory
2. Any `.yaml` file added here becomes an ArgoCD Application
3. ArgoCD syncs these applications to the cluster automatically

## Current Status

**No applications deployed yet.** This is the initial bootstrap state.
