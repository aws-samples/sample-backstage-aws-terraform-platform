# Backstage Deployment Guide

Complete guide for deploying Backstage on AWS with existing VPC and EKS cluster.

> **💡 Quick Start:** See [QUICK-START.md](./QUICK-START.md) for streamlined deployment (10-20 minutes).

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Phase 1: Deploy Infrastructure](#phase-1-deploy-infrastructure)
4. [Phase 2: Deploy Backstage](#phase-2-deploy-backstage)
5. [Configuration](#configuration)
6. [Troubleshooting](#troubleshooting)
7. [Cleanup](#cleanup)

---

## Overview

### Architecture

![Architecture Diagram](../images/architecture_diagram.png)

**Components:**
- **Amazon ECR** - Private container registry
- **Amazon EKS** - Kubernetes cluster (existing)
- **Amazon RDS** - PostgreSQL database
- **GitHub** - Source control with OIDC authentication
- **Terraform** - Infrastructure as Code

### Resources Created

| Resource | Purpose |
|----------|---------|
| RDS PostgreSQL | Backstage metadata storage (AWS-managed password) |
| ECR Repository | Container image registry |
| S3 Bucket | Terraform state storage |
| Secrets Manager | Credential storage |
| KMS Keys | Encryption keys |
| GitHub OIDC Provider | Secure GitHub Actions authentication |
| IAM Role | GitHub Actions role (OIDC-based, no long-lived credentials) |
| Security Groups | Network access control |
| DynamoDB Table | Terraform state locking (optional) |

---

## Prerequisites

### Required Infrastructure

You need an **existing EKS cluster** (Kubernetes 1.29+) with:
- At least 2 vCPU and 4GB RAM available
- VPC with private subnets in 2+ AZs

**Gather these values:**
- VPC ID
- Private Subnet IDs (2 minimum)
- EKS Cluster Name

> **💡 Find in AWS Console:** EKS → Your Cluster → Networking tab

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2.x | AWS operations |
| kubectl | v1.26+ | Kubernetes management |
| Helm | v3.2.0+ | Kubernetes deployments |
| Docker | v20.10+ | Container builds |
| Node.js | 20.x LTS | Backstage runtime |
| Yarn | v1.22.5+ | Package management |
| GitHub CLI | Latest | Repository operations |

**Verify installation:**
```bash
aws --version && kubectl version --client && helm version && docker --version && node --version && yarn --version && gh --version
```

### AWS Credentials

Configure AWS credentials with permissions to create:
- CloudFormation stacks
- RDS, ECR, S3, Secrets Manager, KMS
- IAM roles and policies

```bash
# Verify credentials
aws sts get-caller-identity
```

### GitHub Requirements

Create a Personal Access Token with these scopes:
- `repo` - Full repository control
- `workflow` - Update workflows
- `read:org` - Read organization
- `write:org` - Manage organization (for forking)
- `admin:repo_hook` - Repository webhooks

```bash
# Authenticate GitHub CLI
gh auth login
```

---

## Phase 1: Deploy Infrastructure

### Step 1: Create Parameters File

```bash
cd backstage-setup

cat > parameters.json << 'EOF'
[
  {"ParameterKey": "ExistingVPCId", "ParameterValue": "vpc-XXXXX"},
  {"ParameterKey": "ExistingVPCCidr", "ParameterValue": "10.x.x.x/16"},
  {"ParameterKey": "ExistingPrivateSubnet1", "ParameterValue": "subnet-XXXXX"},
  {"ParameterKey": "ExistingPrivateSubnet2", "ParameterValue": "subnet-XXXXX"},
  {"ParameterKey": "ExistingEKSCluster", "ParameterValue": "my-eks-cluster"},
  {"ParameterKey": "GitHubToken", "ParameterValue": "REPLACE_WITH_GITHUB_TOKEN"},
  {"ParameterKey": "GitHubOrg", "ParameterValue": "your-github-org"},
  {"ParameterKey": "GitHubRepo", "ParameterValue": "repo-name"},
  {"ParameterKey": "EnableStateLocking", "ParameterValue": "true"}
]
EOF
```

**Replace with your values:**
- VPC ID and subnet IDs
- EKS cluster name
- GitHub token
- GitHub organization

> **💡 Note:** AWS RDS automatically generates and manages the database password securely

### Step 2: Deploy CloudFormation Stack

```bash
aws cloudformation create-stack \
  --stack-name backstage-platform \
  --template-body file://templates/backstage-stack.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for completion (10-15 minutes)
aws cloudformation wait stack-create-complete --stack-name backstage-platform
```

**What gets created:**
- ✅ RDS PostgreSQL with AWS-managed password and enhanced security
- ✅ ECR repository with KMS encryption
- ✅ Secrets Manager with customer-managed KMS keys
- ✅ S3 bucket for Terraform state with access logging
- ✅ DynamoDB table for state locking (optional)
- ✅ GitHub OIDC provider for secure authentication
- ✅ IAM role for GitHub Actions with scoped permissions
- ✅ Security groups for RDS access

### Step 3: Verify Deployment

```bash
# Check status
aws cloudformation describe-stacks \
  --stack-name backstage-platform \
  --query 'Stacks[0].StackStatus'

# View outputs
aws cloudformation describe-stacks \
  --stack-name backstage-platform \
  --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
  --output table
```

---

## Phase 2: Deploy Backstage

### Authenticate GitHub CLI

Before running deployment scripts, authenticate with GitHub:

```bash
gh auth login
# Choose: GitHub.com → HTTPS → Paste your token
```

> **Note:** This token is used for forking the repository and configuring GitHub secrets for Backstage integration.

### Automated Deployment

Run the quickstart script to automate all steps:

```bash
cd scripts
./quickstart.sh backstage-platform
```

**What it does:**
1. Waits for CloudFormation completion
2. Forks repository and configures GitHub secrets
3. Builds and pushes Docker image to ECR
4. Deploys Backstage to EKS cluster

**Duration:** 5-10 minutes

### Manual Deployment (Alternative)

If you prefer manual control:

**1. Setup Repository:**
```bash
./setup-repo.sh backstage-platform
```

**2. Build Docker Image:**
```bash
# For standard x86_64 nodes (default)
./build-image.sh backstage-platform

# For ARM64/Graviton nodes
./build-image.sh backstage-platform linux/arm64
```

**3. Deploy to EKS:**
```bash
./deploy-backstage.sh backstage-platform
```

> **💡 Platform Selection:**
> - `linux/amd64` (default) - For t3, m5, c5, r5, and other x86_64 instance types
> - `linux/arm64` - For t4g, m6g, c6g, r6g, and other Graviton instance types
> 
> Check your EKS node group instance types to determine which platform to use.

### Verify Deployment

```bash
# Check pods
kubectl get pods -n backstage

# Check service
kubectl get svc -n backstage

# Check ingress
kubectl get ingress -n backstage
```

### Access Backstage

**Via Port Forward (default):**
```bash
kubectl port-forward svc/backstage 7007:7007 -n backstage
# Access at: http://localhost:7007
```

**Via Custom Domain:**
For custom domain setup with SSL, see [ACCESS-METHODS.md](./ACCESS-METHODS.md)

---

## Configuration

### Authentication

**Default: Guest Authentication**

No setup required. Users click "Enter" → "Guest" to access.

**GitHub OAuth (Production):**

1. Create OAuth App at https://github.com/settings/developers
2. Set callback URL: `http://your-alb-url/api/auth/github/handler/frame`
3. Update `helm-values.yaml`:

```yaml
auth:
  environment: production
  providers:
    github:
      development:
        clientId: ${GITHUB_CLIENT_ID}
        clientSecret: ${GITHUB_CLIENT_SECRET}
```

4. Create Kubernetes secret:
```bash
kubectl create secret generic github-oauth \
  --from-literal=GITHUB_CLIENT_ID=your-id \
  --from-literal=GITHUB_CLIENT_SECRET=your-secret \
  -n backstage
```

5. Redeploy:
```bash
helm upgrade backstage ./backstage-chart -n backstage -f helm-values.yaml
```

---

## Troubleshooting

### Pods Not Starting

```bash
# Describe pod
kubectl describe pod -n backstage <pod-name>

# Check logs
kubectl logs -n backstage <pod-name>

# Check events
kubectl get events -n backstage --sort-by='.lastTimestamp'
```

### Database Connection Issues

```bash
# Test from pod
kubectl run -it --rm debug --image=postgres:15 --restart=Never -- \
  psql -h <rds-endpoint> -U backstage -d backstage

# Check security groups
aws ec2 describe-security-groups --group-ids <sg-id>
```

### ALB Not Created

```bash
# Check ALB controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# Check ingress
kubectl describe ingress backstage -n backstage
```

### Image Pull Errors

```bash
# Verify ECR repository
aws ecr describe-repositories --repository-names backstage-app

# Check images
aws ecr describe-images --repository-name backstage-app

# Verify node IAM role has ECR permissions
```

### CloudFormation Stack Failed

```bash
# View recent events
aws cloudformation describe-stack-events \
  --stack-name backstage-platform \
  --max-items 20
```

---

## Cleanup

Use the cleanup script to safely delete all resources:

```bash
cd backstage-setup/scripts
./cleanup.sh backstage-platform
```

For detailed cleanup instructions, see [CLEANUP.md](./CLEANUP.md)

---

## Configuration Reference

### CloudFormation Parameters

**Network (Existing VPC):**
- `ExistingVPCId` - Your VPC ID (required)
- `ExistingPrivateSubnet1` - Private subnet 1 (required)
- `ExistingPrivateSubnet2` - Private subnet 2 (required)
- `ExistingEKSCluster` - EKS cluster name (required)

**Database:**

> **Note:** Database password is automatically generated and managed by AWS RDS. RDS is configured with Multi-AZ for high availability.

**GitHub:**
- `GitHubToken` - Personal Access Token (required)
- `GitHubOrg` - Organization name (required)

**Optional:**
- `EnableStateLocking` - DynamoDB state locking (default: true)

### Environment Recommendations

**Development:**
```json
{
  "EnableRDSDeletionProtection": "false"
}
```

**Production:**
```json
{
  "EnableRDSDeletionProtection": "true"
}
```

---

## Security Checklist

- [ ] Use strong database passwords (16+ characters)
- [ ] Rotate GitHub tokens regularly
- [ ] Enable MFA on AWS account
- [ ] Configure SSL/TLS for ALB (production)
- [ ] Enable CloudTrail logging
- [ ] Enable VPC Flow Logs
- [ ] Set up AWS Config rules
- [ ] Regular security scanning of Docker images
- [ ] Keep Kubernetes and Backstage updated

---

## Next Steps

1. Configure custom domain with SSL
2. Set up GitHub OAuth authentication
3. Add monitoring with CloudWatch Container Insights
4. Configure backup policies for RDS
5. Add custom Backstage plugins
6. Train team on using the platform

---

## Resources

- [Backstage Documentation](https://backstage.io/docs/)
- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [QUICK-START.md](./QUICK-START.md) - Streamlined deployment
- [USAGE-GUIDE.md](./USAGE-GUIDE.md) - Using the self-service portal
- [CLEANUP.md](./CLEANUP.md) - Safe deletion instructions
