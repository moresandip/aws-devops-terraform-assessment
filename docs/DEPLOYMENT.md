# DevOps Assessment – Deployment Documentation

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture Design](#2-architecture-design)
3. [Repository Structure](#3-repository-structure)
4. [Infrastructure Components](#4-infrastructure-components)
5. [Security Implementation](#5-security-implementation)
6. [CI/CD Pipeline](#6-cicd-pipeline)
7. [Pre-requisites](#7-pre-requisites)
8. [Deployment Guide (Step-by-Step)](#8-deployment-guide)
9. [Environment Variables & Secrets](#9-environment-variables--secrets)
10. [Terraform State Management](#10-terraform-state-management)
11. [Monitoring & Observability](#11-monitoring--observability)
12. [Assumptions & Design Decisions](#12-assumptions--design-decisions)
13. [Cost Estimation](#13-cost-estimation)

---

## 1. Project Overview

This project delivers a **production-grade AWS infrastructure** for a web application, implemented entirely as code using **Terraform** and automated through **GitHub Actions CI/CD**. No manual console operations are required after bootstrapping.

### High-Level Traffic Flow

```
Users (Internet)
     │  HTTPS :443
     ▼
Application Load Balancer  ──logs──▶  S3 (ALB Logs)
     │  HTTP forward :80
     │  ACM Certificate (TLS 1.3)
     ▼
Auto Scaling Group (EC2 t3.micro)
├── AZ us-east-1a  (private subnet 10.0.10.0/24)
└── AZ us-east-1b  (private subnet 10.0.11.0/24)
     │
     ├──▶  Secrets Manager  (DB credentials)
     ├──▶  S3 App Bucket    (application storage)
     └──▶  RDS MySQL 8.0 (Multi-AZ)
           ├── Primary  (10.0.20.0/24 – us-east-1a)
           └── Standby  (10.0.21.0/24 – us-east-1b)
```

---

## 2. Architecture Design

### VPC Layout

| Subnet Type    | CIDR            | AZ          | Purpose                        |
|---------------|-----------------|-------------|--------------------------------|
| Public-1      | 10.0.1.0/24     | us-east-1a  | ALB, NAT Gateway               |
| Public-2      | 10.0.2.0/24     | us-east-1b  | ALB, NAT Gateway               |
| Private-1     | 10.0.10.0/24    | us-east-1a  | EC2 App Instances              |
| Private-2     | 10.0.11.0/24    | us-east-1b  | EC2 App Instances              |
| DB-1          | 10.0.20.0/24    | us-east-1a  | RDS Primary                    |
| DB-2          | 10.0.21.0/24    | us-east-1b  | RDS Standby (Multi-AZ)         |

### High Availability Design Decisions

- **One NAT Gateway per AZ** – prevents a single NAT Gateway from being a regional SPOF; if one AZ fails, private instances in the surviving AZ retain internet egress
- **ALB spans two public subnets** – requests continue to route if one AZ is degraded
- **ASG min=2 across two AZs** – guarantees at least one instance per AZ at minimum capacity
- **RDS Multi-AZ** – automatic failover to standby within ~60–120 seconds, with no application changes required
- **Rolling instance refresh** – ASG replaces instances with zero downtime on new launch template versions

---

## 3. Repository Structure

```
aws-devops-terraform-assessment/
├── .github/
│   └── workflows/
│       └── terraform.yml          # GitHub Actions CI/CD pipeline
├── app/                           # Application source code
│   ├── src/
│   │   ├── server.js              # Express application entry point
│   │   └── logger.js              # Winston logging configuration
│   ├── tests/
│   │   └── server.test.js         # Jest unit tests
│   ├── Dockerfile                 # Multi-stage container build
│   └── package.json
├── terraform/                     # Terraform IaC
│   ├── versions.tf                # Provider + backend configuration
│   ├── variables.tf               # All input variables with validation
│   ├── networking.tf              # VPC, subnets, IGW, NAT, route tables
│   ├── security_groups.tf         # ALB, EC2, RDS security groups
│   ├── alb.tf                     # ALB, listeners, target group, ACM
│   ├── ec2_asg.tf                 # Launch template, ASG, IAM, KMS
│   ├── rds.tf                     # RDS MySQL, Secrets Manager
│   ├── s3.tf                      # App + logs S3 buckets
│   ├── monitoring.tf              # CloudWatch dashboard, alarms, SNS
│   ├── outputs.tf                 # Resource outputs
│   ├── terraform.tfvars.example   # Example variable values
│   └── templates/
│       └── user_data.sh.tpl       # EC2 bootstrap script (Terraform template)
├── docs/
│   └── DEPLOYMENT.md              # This file
└── README.md
```

---

## 4. Infrastructure Components

### 4.1 Networking (`networking.tf`)

| Resource                | Count | Notes                                    |
|------------------------|-------|------------------------------------------|
| VPC                     | 1     | DNS enabled, /16 CIDR                   |
| Public Subnets          | 2     | map_public_ip disabled for security      |
| Private App Subnets     | 2     | No direct internet access               |
| Private DB Subnets      | 2     | No route to NAT or IGW                  |
| Internet Gateway        | 1     | Attached to VPC                         |
| NAT Gateways            | 2     | One per AZ (Elastic IPs pre-allocated)  |
| Route Tables            | 5     | 1 public, 2 private, 2 DB (no internet) |
| VPC Flow Logs           | 1     | ALL traffic → CloudWatch (30-day retention) |

### 4.2 Application Load Balancer (`alb.tf`)

- **Listeners**: Port 80 (HTTP → 301 redirect to HTTPS), Port 443 (HTTPS forward)
- **SSL Policy**: `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.2 minimum, TLS 1.3 preferred)
- **ACM Certificate**: DNS-validated; Terraform requests it if `certificate_arn` variable is empty
- **Access Logs**: Delivered to dedicated S3 bucket with bucket owner full-control ACL
- **Drop Invalid Headers**: Enabled (mitigates HTTP desync attacks)
- **Deletion Protection**: Enabled

### 4.3 EC2 Auto Scaling (`ec2_asg.tf`)

- **Launch Template** version `$Latest` with `create_before_destroy` lifecycle
- **IMDSv2 enforced** (`http_tokens = required`) – prevents SSRF metadata attacks
- **EBS volumes**: gp3, 20 GB, KMS-encrypted
- **IAM Instance Profile**: SSM Session Manager, CloudWatch Agent, Secrets Manager read, S3 read/write (least-privilege)
- **Scaling Policies**: CPU > 70% and ALB request count > 1000/target (target tracking)
- **Instance Refresh**: Rolling with min_healthy_percentage = 50%

### 4.4 RDS MySQL (`rds.tf`)

| Setting                      | Value                           |
|-----------------------------|---------------------------------|
| Engine                       | MySQL 8.0                      |
| Instance class               | db.t3.micro                    |
| Storage                      | 20 GB gp3, auto-scaling to 100 GB |
| Encryption                   | KMS (same key as EC2/S3)       |
| Multi-AZ                     | ✅ Enabled                     |
| Automated Backups            | 7-day retention, 03:00–04:00 UTC |
| Performance Insights         | 7-day retention                |
| CloudWatch Logs              | error, general, slowquery      |
| require_secure_transport     | ON (TLS connections only)      |
| Deletion Protection          | ✅ Enabled                     |
| Password                     | 32-char random (Secrets Manager) |

### 4.5 AWS Secrets Manager (`rds.tf`)

The database secret stores a JSON object:

```json
{
  "username": "admin",
  "password": "<32-char random>",
  "host":     "rds-endpoint.us-east-1.rds.amazonaws.com",
  "port":     3306,
  "dbname":   "appdb",
  "engine":   "mysql"
}
```

EC2 instances fetch this at boot via `aws secretsmanager get-secret-value`. The IAM policy restricts access to the specific secret ARN.

### 4.6 S3 Buckets (`s3.tf`, `alb.tf`)

| Bucket          | Purpose             | Encryption | Public Access |
|----------------|---------------------|------------|---------------|
| app-storage-*  | Application files   | KMS        | ❌ Blocked    |
| alb-logs-*     | ALB access logs     | AES256     | ❌ Blocked    |

Both buckets enforce HTTPS-only access via bucket policy.

---

## 5. Security Implementation

### 5.1 Network Security

```
Internet ──HTTPS──▶ ALB SG (443,80 from 0.0.0.0/0)
ALB SG   ──HTTP──▶  EC2 SG (80,8080 from ALB SG only)
EC2 SG   ──MySQL──▶ RDS SG (3306 from EC2 SG only)
RDS SG   ──egress──▶ VPC CIDR only
```

### 5.2 Data Encryption

| Layer          | Mechanism                              |
|---------------|----------------------------------------|
| EBS volumes    | AWS KMS (CMK with key rotation)       |
| RDS at rest    | AWS KMS (same CMK)                    |
| S3 objects     | SSE-KMS (app bucket) / SSE-S3 (logs)  |
| Secrets        | AWS KMS                               |
| Data in transit| TLS 1.2+ enforced everywhere          |

### 5.3 IAM Least Privilege

EC2 instances have **only** the following permissions:
- `secretsmanager:GetSecretValue` and `DescribeSecret` on the specific secret ARN
- `s3:Get/Put/Delete/List` on the specific application bucket and its objects
- `kms:Decrypt` and `GenerateDataKey` on the specific CMK
- AWS managed policies: `AmazonSSMManagedInstanceCore`, `CloudWatchAgentServerPolicy`

### 5.4 IMDSv2 Enforcement

The Launch Template sets `http_tokens = required`, which means:
- SSRF attacks cannot access `http://169.254.169.254/` directly
- A session-oriented request with a token is required
- Hop limit = 1 prevents external requests from reaching IMDS

---

## 6. CI/CD Pipeline

### Pipeline Stages

```
Push / PR
    │
    ├─1─▶ Security Scan  (tfsec + Checkov → SARIF)
    │
    ├─2─▶ Validate       (terraform fmt, terraform validate)
    │        │  Post fmt failures as PR comment
    │
    ├─3─▶ Plan           (terraform plan → artifact)
    │        │  Post plan output as PR comment
    │
    ├─4─▶ Apply *        (main branch + environment gate)
    │        │  Requires "production" environment approval
    │
    └─5─▶ Health Check * (ALB target health + HTTPS smoke test)
              │  Creates GitHub Issue on failure

* Apply + Health Check only run on merge to main
```

### OIDC Authentication (Keyless)

GitHub Actions uses **OpenID Connect** to assume an AWS IAM role – no long-lived access keys are stored as secrets:

```hcl
# Add to your AWS account (one-time setup):
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}
```

### Required GitHub Secrets

| Secret Name           | Description                                    |
|----------------------|------------------------------------------------|
| `AWS_OIDC_ROLE_ARN`  | ARN of the IAM role for GitHub Actions         |
| `TF_STATE_BUCKET`    | S3 bucket name for Terraform state             |
| `TF_LOCK_TABLE`      | DynamoDB table name for state locking          |
| `DOMAIN_NAME`        | Application domain (e.g. `app.example.com`)    |
| `ACM_CERTIFICATE_ARN`| ARN of the ACM cert (or empty to auto-create) |
| `EC2_KEY_PAIR_NAME`  | EC2 Key Pair name (optional)                   |

---

## 7. Pre-requisites

### Tools

| Tool        | Version   | Purpose                              |
|------------|-----------|--------------------------------------|
| Terraform   | ≥ 1.6.0   | Infrastructure provisioning          |
| AWS CLI     | ≥ 2.x     | AWS API interactions                 |
| Git         | any       | Version control                      |
| Node.js     | ≥ 18.x    | Application runtime (local dev only) |

### AWS Account Setup (one-time)

1. **S3 backend bucket** – must exist before `terraform init`:
   ```bash
   aws s3 mb s3://terraform-state-devops-assessment --region us-east-1
   aws s3api put-bucket-versioning \
     --bucket terraform-state-devops-assessment \
     --versioning-configuration Status=Enabled
   aws s3api put-bucket-encryption \
     --bucket terraform-state-devops-assessment \
     --server-side-encryption-configuration \
     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```

2. **DynamoDB lock table**:
   ```bash
   aws dynamodb create-table \
     --table-name terraform-state-lock \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST \
     --region us-east-1
   ```

3. **GitHub OIDC provider** (run once per AWS account):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

4. **IAM Role for GitHub Actions** – trust the OIDC provider, attach least-privilege policies (see `scripts/setup_github_oidc_role.sh`).

---

## 8. Deployment Guide

### Local Deployment

```bash
# 1. Clone and navigate
git clone https://github.com/your-org/aws-devops-terraform-assessment.git
cd aws-devops-terraform-assessment/terraform

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Authenticate to AWS
aws configure  # or export AWS_* env vars

# 4. Initialize Terraform (downloads providers, configures backend)
terraform init \
  -backend-config="bucket=terraform-state-devops-assessment" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=terraform-state-lock"

# 5. Validate and plan
terraform validate
terraform plan -out=tfplan

# 6. Review and apply
terraform apply tfplan

# 7. Retrieve outputs
terraform output alb_dns_name
terraform output app_url
```

### CI/CD Deployment (GitHub Actions)

```bash
# Feature branch workflow:
git checkout -b feature/my-change
# ... edit terraform files ...
git add . && git commit -m "feat: update ASG capacity"
git push origin feature/my-change
# → Opens PR → triggers Security Scan → Validate → Plan (commented on PR)

# Merge to main triggers:
# → Plan → Apply (requires "production" environment approval) → Health Check
```

### Updating the Application

```bash
# 1. Build and package
cd app
npm ci
npm test
tar -czf app.tar.gz src/ package.json package-lock.json

# 2. Upload to S3
aws s3 cp app.tar.gz \
  s3://$(terraform -chdir=../terraform output -raw app_s3_bucket_name)/releases/latest/app.tar.gz

# 3. Trigger ASG instance refresh (new instances download latest from S3)
aws autoscaling start-instance-refresh \
  --auto-scaling-group-name $(terraform -chdir=../terraform output -raw asg_name) \
  --preferences '{"MinHealthyPercentage":50,"InstanceWarmup":120}'
```

---

## 9. Environment Variables & Secrets

### EC2 Instance Environment (`.env` – written by user_data)

| Variable     | Source            | Description                    |
|-------------|-------------------|--------------------------------|
| `NODE_ENV`   | Terraform var     | `prod` / `staging` / `dev`     |
| `PORT`       | Hardcoded 80      | HTTP listening port             |
| `DB_HOST`    | Terraform output  | RDS endpoint address            |
| `DB_PORT`    | 3306 (default)    | MySQL port                     |
| `DB_NAME`    | Terraform var     | Database name                  |
| `DB_USER`    | Secrets Manager   | MySQL username                 |
| `DB_PASS`    | Secrets Manager   | MySQL password (fetched at boot) |
| `S3_BUCKET`  | Terraform output  | Application S3 bucket name     |
| `AWS_REGION` | Terraform var     | AWS region                     |

> **Security note**: The `.env` file is written with `chmod 600` and is never committed to version control (`.gitignore` excludes it).

---

## 10. Terraform State Management

### Remote Backend (S3 + DynamoDB)

```
S3 Bucket: terraform-state-devops-assessment
  └── prod/terraform.tfstate   (encrypted with AES-256)

DynamoDB Table: terraform-state-lock
  └── LockID (string hash key)  ← prevents concurrent applies
```

### State Security

- S3 bucket has versioning enabled (roll back to any previous state)
- Bucket is private with public access block
- Server-side encryption with AES-256
- Only the GitHub Actions OIDC role and authorized IAM users have access

---

## 11. Monitoring & Observability

### CloudWatch Dashboard: `devops-assessment-prod-dashboard`

| Widget                | Metric                     | Statistic |
|-----------------------|---------------------------|-----------|
| ALB Request Count      | RequestCount               | Sum/min   |
| ALB 5XX Errors         | HTTPCode_ELB_5XX_Count     | Sum/min   |
| ASG CPU Utilization    | CPUUtilization             | Avg/min   |
| RDS CPU + Free Storage | CPUUtilization / FreeStorageSpace | Avg/5min |

### CloudWatch Alarms → SNS → Email

| Alarm                    | Condition              | Action    |
|--------------------------|------------------------|-----------|
| ALB 5XX Spike            | > 10 in 1 min          | SNS alert |
| EC2 High CPU             | Avg > 85% for 3 mins   | SNS alert |
| RDS Low Storage          | Free < 5 GB            | SNS alert |
| Unhealthy Hosts in TG    | Count > 0              | SNS alert |

### Log Groups (CloudWatch Logs)

| Log Group                                    | Source           | Retention |
|---------------------------------------------|------------------|-----------|
| `/aws/vpc/devops-assessment-prod-flow-logs`  | VPC Flow Logs    | 30 days   |
| `/aws/rds/instance/*/error`                  | RDS error log    | AWS default|
| `/aws/rds/instance/*/slowquery`              | Slow queries     | AWS default|
| `/devops-assessment-prod`                    | EC2 app logs     | 30 days   |
| `/devops-assessment-prod/system`             | EC2 /var/log/messages | 30 days |

### Subscribe to Alerts

```bash
aws sns subscribe \
  --topic-arn $(terraform output -raw sns_alerts_topic_arn) \
  --protocol email \
  --notification-endpoint "your-email@example.com"
```

---

## 12. Assumptions & Design Decisions

| Topic                   | Decision                             | Rationale                                      |
|------------------------|--------------------------------------|------------------------------------------------|
| **Region**              | us-east-1                           | Largest AWS region with all services available |
| **AZ count**            | 2 (1a, 1b)                         | Balances HA vs. cost; add 1c easily via variables |
| **NAT Gateway count**   | 1 per AZ (2 total)                 | Eliminates AZ-level SPOF; cost-conscious teams can use 1 by adjusting variables |
| **Instance type**        | t3.micro                            | Suitable for demo; right-size for production load |
| **RDS class**            | db.t3.micro                        | Demo sizing; scale to db.r6g.large+ for production |
| **Certificate**          | ACM DNS-validated                  | Free, auto-renewed; requires Route 53 or manual DNS setup |
| **No Route 53 module**   | Out of scope per brief             | Domain pointing to ALB alias is left as manual step |
| **EC2 vs ECS/EKS**       | EC2 ASG chosen                     | Matches brief requirements; ECS Fargate is a viable alternative |
| **Live deployment**      | Not required per brief             | Code is deployment-ready; live infra not provisioned |
| **Application**          | Node.js / Express                  | Lightweight; demonstrates DB + S3 + Secrets Manager integration |
| **Secret rotation**      | Not implemented                    | AWS supports automatic rotation; add `aws_secretsmanager_secret_rotation` resource to enable |

---

## 13. Cost Estimation

Approximate monthly cost for the infrastructure in us-east-1 (**demo sizing**):

| Service                | Configuration          | Est. Monthly Cost |
|-----------------------|------------------------|-------------------|
| EC2 (2× t3.micro)     | On-Demand, 730h        | ~$19             |
| ALB                   | 1 ALB + LCU usage      | ~$20             |
| NAT Gateways (2×)     | $0.045/h each          | ~$65             |
| RDS MySQL Multi-AZ    | db.t3.micro            | ~$30             |
| S3 (app + logs)       | < 10 GB                | ~$2              |
| ACM Certificate       | Free                   | $0               |
| Secrets Manager       | 1 secret               | ~$0.40           |
| CloudWatch            | Alarms + Logs + Dash   | ~$10             |
| KMS                   | 1 CMK + API calls      | ~$2              |
| **Total (approx)**    |                        | **~$149/month**  |

> **Cost optimization levers**: Use Reserved Instances for EC2/RDS (~40% saving), reduce to 1 NAT Gateway for non-prod, enable S3 Intelligent-Tiering.

---

*Documentation prepared for DevOps Infrastructure Assessment.*  
*All code is production-ready and deployment-tested via Terraform dry-run.*
