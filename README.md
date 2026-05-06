# DevOps Challenge — Production-Ready Application Deployment



## Deployment Steps

### Step 1 — Bootstrap (one-time)

```bash
# Clone the repo
git clone https://github.com/your-org/devops-challenge.git
cd devops-challenge

# Edit variables in the script
vim scripts/bootstrap.sh   # set GITHUB_ORG and GITHUB_REPO

# Run bootstrap (creates S3 bucket, DynamoDB table, OIDC IAM role)
chmod +x scripts/bootstrap.sh
./scripts/bootstrap.sh
```

The script outputs three values — add them as **GitHub Actions secrets**:

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role for OIDC keyless auth |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state |
| `TF_LOCK_TABLE` | DynamoDB table for state locking |

### Step 2 — First Terraform Apply (optional local run)

```bash
cd terraform

terraform init \
  -backend-config="bucket=<TF_STATE_BUCKET>" \
  -backend-config="dynamodb_table=<TF_LOCK_TABLE>"

terraform plan -var="alarm_email=you@example.com"
terraform apply -var="alarm_email=you@example.com"
```

### Step 3 — Push to main → Automated Pipeline

```bash
git push origin main
```

GitHub Actions will automatically:
1. **Test** — install deps, run Jest with coverage
2. **Build** — build multi-stage Docker image, push to ECR, Trivy security scan
3. **Plan** — `terraform plan` with the new image tag
4. **Deploy** — `terraform apply`, wait for ECS stability, smoke test `/health`

### Step 4 — Verify

```bash
# Get the ALB DNS from Terraform output
terraform output alb_dns_name

# Test endpoints
curl http://<alb-dns>/
curl http://<alb-dns>/health
curl http://<alb-dns>/metrics
```


## Repository Structure

```
.
├── app/
│   ├── src/
│   │   ├── index.js           # Application entry point
│   │   └── index.test.js      # Jest unit/integration tests
│   ├── Dockerfile             # Multi-stage production image
│   ├── .dockerignore
│   └── package.json
│
├── terraform/
│   ├── main.tf                # Root module — wires everything together
│   ├── variables.tf           # All input variables with descriptions
│   ├── outputs.tf             # ALB DNS, ECR URL, cluster/service names
│   └── modules/
│       ├── networking/        # VPC, subnets, IGW, NAT, route tables
│       ├── ecr/               # ECR repository + lifecycle policy
│       ├── ecs/               # Cluster, task def, service, ALB, IAM, ASG
│       └── monitoring/        # Log group, alarms, SNS, dashboard
│
├── .github/
│   └── workflows/
│       └── ci-cd.yml          # 4-job pipeline: test → build → plan → deploy
│
├── scripts/
│   └── bootstrap.sh           # One-time: S3 bucket, DynamoDB, OIDC IAM role
│
└── README.md
```

---

## Prerequisites

- AWS CLI configured (`aws configure` or IAM role)
- Terraform >= 1.6.0
- Docker >= 24.0
- Node.js >= 18.0
- A GitHub repository with Actions enabled

---


### Monitoring

- **Logs**: CloudWatch Log Group `/ecs/devops-challenge-prod`
- **Dashboard**: CloudWatch → Dashboards → `devops-challenge-prod-dashboard`
- **Alarms**: CPU > 80%, Memory > 85%, 5xx errors > 5/min, P95 latency > 1s

---

## CI/CD Pipeline Details

```
┌─────────┐    ┌───────────┐    ┌─────────────────┐    ┌────────────┐
│  Test   │───►│  Build &  │───►│ Terraform Plan  │───►│   Deploy   │
│         │    │   Push    │    │                 │    │            │
│ npm ci  │    │ docker    │    │ tf init         │    │ tf apply   │
│ jest    │    │ build     │    │ tf fmt check    │    │ ecs wait   │
│ coverage│    │ ecr push  │    │ tf validate     │    │ smoke test │
│         │    │ trivy scan│    │ tf plan         │    │ rollback?  │
└─────────┘    └───────────┘    └─────────────────┘    └────────────┘

  On PR:       ✅ test only (no build/deploy)
  On main:     ✅ full pipeline
  On failure:  ✅ ECS circuit breaker auto-rollback
```

**Key pipeline features:**
- **OIDC authentication** — no long-lived AWS access keys stored in GitHub
- **Docker layer caching** — GitHub Actions cache speeds up rebuilds significantly
- **Image tagged by Git SHA** — every deploy is fully traceable
- **Terraform plan artifact** — apply uses the exact same plan that was reviewed
- **ECS deployment circuit breaker** — automatic rollback if new tasks fail health checks
- **Smoke test gate** — pipeline fails fast if the deployed app doesn't respond

---

## Design Decisions

### ECS Fargate over EC2 / EKS

ECS Fargate was chosen because it eliminates EC2 instance management entirely — no AMI patching, no node group upgrades. For a challenge deployment, Kubernetes (EKS) adds significant operational overhead (control plane cost, node pools, `kubectl` config) without adding value at this scale. Fargate tasks run in private subnets and scale automatically via Application Auto Scaling.

### Multi-stage Dockerfile

The Dockerfile uses three stages:
1. **deps** — production `node_modules` only
2. **builder** — installs dev deps and runs tests (failing tests abort the image build)
3. **production** — copies prod deps + app from earlier stages, runs as non-root, uses `dumb-init` for proper signal handling

This keeps the final image to ~120MB and ensures test failures are caught at build time, not runtime.

### Keyless GitHub Actions Auth (OIDC)

Instead of storing long-lived IAM access keys as GitHub secrets, an IAM OIDC identity provider is created that trusts GitHub's token issuer. The workflow exchanges a short-lived GitHub JWT for AWS credentials scoped to the deploy role — no static secrets to rotate or leak.

### Terraform Modules

The Terraform code is split into four modules with clear boundaries:
- **networking** — VPC and subnets (rarely changes)
- **ecr** — image registry (changes only with naming)
- **ecs** — the hot path during deployments (`image_tag` variable)
- **monitoring** — log group, alarms, dashboard

This separation means ECS re-deploys don't touch networking resources, and Terraform plan output is minimal and easy to review.

### Private Subnets for Tasks

ECS tasks run in private subnets with no public IPs. Outbound traffic (ECR image pulls, CloudWatch API calls) goes via NAT Gateway. Only the ALB is internet-facing. This follows the principle of least exposure.

---

## Assumptions

- AWS account with appropriate permissions (or use the bootstrap script to create the OIDC role)
- `us-east-1` region (configurable via `var.aws_region`)
- Single environment (`prod`) — extend `var.environment` and workspace strategy for multi-env
- HTTP only — HTTPS/TLS would require an ACM certificate and Route 53 domain
- No persistent database — the app is stateless; add an RDS module if needed

---

## Limitations & Potential Improvements

| Area | Current State | Improvement |
|------|--------------|-------------|
| TLS | HTTP only | Add ACM cert + HTTPS listener + redirect HTTP→HTTPS |
| DNS | Raw ALB DNS name | Register domain in Route 53, create alias record |
| Secrets | Env vars in task def | Use AWS Secrets Manager + `secretsOptions` in task def |
| Multi-env | Single `prod` | Add `staging` workspace with separate tfvars |
| Observability | CloudWatch | Add Prometheus/Grafana or AWS X-Ray tracing |
| Database | Stateless app | Add RDS Postgres module in private subnets |
| Cost | NAT per AZ | Single NAT saves ~$32/month for non-HA dev environments |
| Security | OIDC role has broad policies | Scope IAM policies to specific resource ARNs |
| Image signing | Not implemented | Add AWS Signer / Cosign for supply chain security |

---

## Local Development

```bash
# Run the app locally
cd app
npm install
npm start
# → http://localhost:3000

# Run tests
npm test

# Build and run Docker image
docker build -t devops-challenge-app .
docker run -p 3000:3000 devops-challenge-app

# Test health endpoint
curl http://localhost:3000/health
```

---

## Cleanup

```bash
cd terraform
terraform destroy -var="alarm_email=you@example.com"

# Also delete the bootstrap resources manually:
aws s3 rb s3://<TF_STATE_BUCKET> --force
aws dynamodb delete-table --table-name devops-challenge-tflock
aws iam detach-role-policy ...  # and delete the role
```
=======
# Damolak-Devops-challenge
>>>>>>> 6d09143e218bcc246fc26cf5738e25e2d9c5ee42
