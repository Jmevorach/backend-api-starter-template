# Architecture

This document explains how the Phoenix API and AWS infrastructure fit together,
why each component exists, and how data flows through the system.

## Table of Contents

- [Goals](#goals)
- [Non-Goals](#non-goals)
- [High-Level Components](#high-level-components)
- [Networking](#networking)
- [Request Flow](#request-flow)
- [Session Storage](#session-storage)
- [Database Layer](#database-layer)
- [Secrets and Rotation](#secrets-and-rotation)
- [Observability](#observability)
- [Backups](#backups)
- [Cost and Scaling](#cost-and-scaling)
- [Where to Customize](#where-to-customize)

## Goals

- Provide a secure, scalable backend baseline
- Separate app concerns from infrastructure concerns
- Keep the baseline generic for many product types
- Use managed AWS services where possible

## Non-Goals

- UI rendering or web templates
- Business-specific data models
- Non-AWS infrastructure variants (Kubernetes, GCP, etc.)

## High-Level Components

```
Clients
  |
  v
Global Accelerator
  |
  v
ALB (HTTPS)
  |
  v
ECS Fargate (Phoenix API)
  |                 |
  |                 +--> Valkey/Redis (sessions)
  |
  +--> RDS Proxy --> Aurora Serverless v2 (PostgreSQL)
```

## Networking

- **VPC** with public and private subnets
- **Public subnets** host ALB and NAT Gateway
- **Private subnets** host ECS tasks, RDS, and Valkey
- **Security groups** restrict access between tiers

Why it matters:
- Keeps databases and caches off the public internet
- Limits ingress/egress to controlled paths

## Request Flow

1. Clients connect to **Global Accelerator** for low-latency routing.
2. Traffic hits the **ALB** with HTTPS termination.
3. ALB forwards to **ECS Fargate** tasks running Phoenix.
4. Phoenix accesses:
   - **Valkey** for session storage (optional)
   - **RDS Proxy** for database pooling
5. **Aurora Serverless v2** handles PostgreSQL storage.

## Session Storage

Sessions are stored server-side in Valkey via `Backend.RedisSessionStore`.
This allows:

- Multi-task compatibility (no sticky sessions)
- Fast session lookups
- Reduced cookie size and exposure

If `VALKEY_HOST` is not configured, the app still runs, but shared
multi-instance session persistence is not available.

## Database Layer

- Phoenix uses **Ecto** to connect to PostgreSQL.
- **RDS Proxy** smooths connection spikes and rotation changes.
- **Aurora Serverless v2** scales with workload demand.

## Secrets and Rotation

Secrets live in AWS Secrets Manager:

- DB password
- SECRET_KEY_BASE
- Valkey auth token
- OAuth credentials (provided externally by ARN)

Rotation Lambdas live in `infra/lambdas/` and trigger ECS deployments after
rotation so tasks pick up new values.

## Observability

- **CloudWatch Logs** for ECS, Lambda, and VPC flow logs
- **CloudTrail** for auditing AWS API calls
- **ALB Logs** for request tracing

## Backups

- **AWS Backup** protects the Aurora cluster
- Long-term retention policies are pre-configured

## Cost and Scaling

- ECS auto scaling based on CPU
- Aurora Serverless v2 scales by ACUs
- Global Accelerator is optional but recommended for mobile latency

## Where to Customize

- App routes: `app/lib/backend_web/router.ex`
- Auth providers: environment variables and Ueberauth config
- Infrastructure: `infra/*.tf`

For deployment steps, see `docs/OPERATIONS.md`.
