# Quick Start Guide

Deploy Backstage using your existing VPC and EKS cluster with all security vulnerabilities resolved.

| | |
|---|---|
| **Total Time** | 10-20 minutes |
| **What You Get** | Backstage IDP with 3 AWS resource templates + secure infrastructure |
| **Access Method** | Port-forward to localhost:7007 |

---

## Prerequisites

### 1. Required Infrastructure

Before starting, you need an **existing EKS cluster** (Kubernetes 1.29+) with at least 2 vCPU and 4GB RAM available.

**Gather this information from your EKS cluster:**
- **VPC ID** - Where your EKS cluster is running
- **Private Subnet IDs** - 2 minimum, in different AZs
- **EKS Cluster Name** - Your cluster name

> **💡 Tip:** Find these in AWS Console: EKS → Your Cluster → Networking tab

### 2. Install Required Tools

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

### 2. Configure AWS Credentials

Ensure AWS credentials are configured with appropriate permissions. Use `aws configure` or your organization's preferred method (AWS SSO, environment variables, etc.).

Verify access:
```bash
aws sts get-caller-identity
```

### 3. Create GitHub Personal Access Token

**Create token:** https://github.com/settings/tokens/new

**Required scopes:**
- ✅ `repo` - Full control of repositories
- ✅ `workflow` - Update GitHub Action workflows
- ✅ `read:org` - Read org and team membership
- ✅ `write:org` - Manage organization (required for forking)
- ✅ `read:user` - Read user profile data
- ✅ `user:email` - Access user email addresses

> **Note:** You'll authenticate with this token in Step 2 using `gh auth login`

---

## Step 1: Deploy Infrastructure

**📁 Working Directory:** `<your-repo-name>/backstage-setup/`

### Create Configuration

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

⚠️ **Edit `parameters.json` and replace:**
- `ExistingVPCId` → Your VPC ID
- `ExistingVPCCidr` → Your VPC CIDR block
- `ExistingPrivateSubnet1` → Your first private subnet ID
- `ExistingPrivateSubnet2` → Your second private subnet ID
- `ExistingEKSCluster` → Your EKS cluster name
- `GitHubToken` → Your GitHub Personal Access Token
- `GitHubOrg` → Your GitHub organization or username
- `GitHubRepo` → GitHub repository name that will be used while forking this repo in the mentioned GitHub organization

> **💡 Note:** AWS RDS automatically generates and manages the database password securely

### Deploy Stack

```bash
aws cloudformation create-stack \
  --stack-name backstage-platform \
  --template-body file://templates/backstage-stack.yaml \
  --parameters file://parameters.json \
  --capabilities CAPABILITY_NAMED_IAM

# Wait for completion (10-15 minutes)
aws cloudformation wait stack-create-complete --stack-name backstage-platform
```

**Resources created:**
- ✅ RDS PostgreSQL database (AWS-managed password, no manual password needed)
- ✅ ECR repository (KMS encrypted)
- ✅ S3 bucket for Terraform state (with access logging)
- ✅ Secrets Manager for credentials (customer-managed KMS)
- ✅ KMS keys for encryption
- ✅ GitHub OIDC provider (secure authentication, no long-lived tokens)
- ✅ IAM role for GitHub Actions (OIDC-based, scoped permissions)
- ✅ DynamoDB table for state locking (optional)

---

## Step 2: Deploy Backstage

### Authenticate GitHub CLI

Before running the deployment, authenticate with GitHub:

```bash
gh auth login
# Choose: GitHub.com → HTTPS → Paste your token
```

> **Note:** This token is used for forking the repository and configuring GitHub secrets for Backstage integration.

### Run Quickstart Script

```bash
cd scripts
./quickstart.sh backstage-platform
```

**For ARM64/Graviton EKS nodes:**
```bash
./quickstart.sh backstage-platform linux/arm64
```

**What this script does:**
1. Waits for CloudFormation stack to complete
2. Forks the repository and configures GitHub secrets
3. Builds and pushes Docker image to ECR (default: linux/amd64)
4. Deploys Backstage to your EKS cluster

**Duration:** 5-10 minutes

> **💡 Platform:** Defaults to linux/amd64 (standard x86_64 nodes). Use linux/arm64 for Graviton-based nodes (t4g, m6g, c6g, r6g, etc.)
> 
> **💡 Tip:** The script will show progress for each step and provide helpful error messages if something fails

---

### Enable GitHub Actions

⚠️ **REQUIRED:** After the script completes, enable workflows in your forked repository:

1. Go to: `https://github.com/YOUR_ORG/YOUR_REPO/actions`
2. Click: **"I understand my workflows, go ahead and enable them"**

> GitHub disables workflows by default in forked repositories for security.

---

## Step 3: Access Backstage

### Port forward to localhost

```bash
kubectl port-forward svc/backstage 7007:7007 -n backstage
```

**Open in browser:** http://localhost:7007

**Sign in:** Click "Enter" → Select "Guest"

### Custom Domain (Optional)

If you want to use a custom domain instead of port-forward, follow the [ACCESS-METHODS.md](./ACCESS-METHODS.md) for custom domain setup instructions.

Once configured, access via:
```
https://backstage.example.com
```

---

**📖 Next:** Follow the [Usage Guide](./USAGE-GUIDE.md) to start provisioning AWS resources

---

## What You Get

| Feature | Description |
|---------|-------------|
| ✅ **Port-forward access** | Access via localhost:7007 (no domain/SSL needed) |
| ✅ **Guest authentication** | No OAuth setup required |
| ✅ **3 AWS templates** | EC2, S3, and RDS ready to use |
| ✅ **GitHub OIDC** | Secure GitHub Actions (no long-lived tokens) |
| ✅ **Automated deployment** | Scripts handle everything |

## What's NOT Included

See [DEPLOYMENT-GUIDE.md](./DEPLOYMENT-GUIDE.md) for:
- Custom domain with SSL/TLS
- OAuth authentication (GitHub, Google, Okta)
- High availability (Multi-AZ, multiple replicas)
- Production hardening
- Monitoring and alerting

---

## Next Steps

📖 **[Usage Guide](./USAGE-GUIDE.md)** - Start provisioning AWS resources with Backstage

📖 **[Deployment Guide](./DEPLOYMENT-GUIDE.md)** - Customize and understand the architecture

📖 **[Cleanup Guide](./CLEANUP.md)** - Delete all resources when done

---

## Troubleshooting

**Pods not starting:**
```bash
# Run from any directory
kubectl describe pod -n backstage <pod-name>
kubectl logs -n backstage deployment/backstage
```

**Can't access Backstage via port-forward:**
```bash
# Run from any directory
# Check if pods are running
kubectl get pods -n backstage

# Check service
kubectl get svc -n backstage

# Verify port-forward command
kubectl port-forward svc/backstage 7007:7007 -n backstage
```

**CloudFormation failed:**
```bash
# Run from any directory
aws cloudformation describe-stack-events --stack-name backstage-platform --max-items 20
```

---


## Additional Resources

- **[Usage Guide](./USAGE-GUIDE.md)** - How to use the self-service portal
- **[Deployment Guide](./DEPLOYMENT-GUIDE.md)** - Comprehensive deployment details
- **[Cleanup Guide](./CLEANUP.md)** - Safe deletion instructions
- **[Backstage Docs](https://backstage.io/docs)** - Official documentation
