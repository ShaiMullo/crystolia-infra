# Infrastructure Configuration

This directory contains Docker and orchestration files for the Crystolia DevOps Platform.

## Files

| File | Description |
|------|-------------|
| `docker-compose.yml` | Local development environment |
| `docker-compose.prod.yml` | Production environment (coming soon) |

## Quick Start

### Prerequisites
- Docker Desktop installed
- Docker Compose v2+

### Start Development Environment

```bash
cd infra
docker-compose up -d
```

### Access Services

| Service | URL |
|---------|-----|
| Frontend | http://localhost:3000 |
| PostgreSQL | localhost:5432 |

### Default Database Credentials

```
User: crystolia
Password: crystolia123
Database: crystolia
```

### Useful Commands

```bash
# View logs
docker-compose logs -f

# Stop all services
docker-compose down

# Rebuild and start
docker-compose up -d --build

# Remove all data (including database)
docker-compose down -v
```
