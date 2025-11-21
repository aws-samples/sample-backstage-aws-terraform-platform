# Cleanup Guide

Remove the Backstage platform and all associated resources.

## ⚠️ Important

**This will permanently delete:**
- Backstage deployment from your EKS cluster
- RDS database and all data
- ECR repository and images
- S3 bucket and Terraform state
- IAM roles and policies

**Your existing EKS cluster, VPC, and subnets remain untouched.**

---

## Quick Cleanup (Recommended)

```bash
cd backstage-setup/scripts
./cleanup.sh backstage-platform
```

**Duration:** 15-20 minutes

The script automatically:
1. Removes Backstage from your EKS cluster
2. Deletes ECR images
3. Empties S3 bucket
4. Deletes CloudFormation stack (RDS, IAM, etc.)

---

## Manual Cleanup

If the automated script fails:

### 1. Remove Backstage from EKS

```bash
STACK_NAME="backstage-platform"
helm uninstall backstage -n backstage
```

### 2. Empty ECR Repository

```bash
REPO_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryName'].OutputValue" \
  --output text)

aws ecr batch-delete-image \
  --repository-name $REPO_NAME \
  --image-ids "$(aws ecr list-images --repository-name $REPO_NAME --query 'imageIds[*]' --output json)"
```

### 3. Empty S3 Bucket

```bash
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='TerraformStateBucket'].OutputValue" \
  --output text)

aws s3 rm s3://$BUCKET_NAME --recursive
```

### 4. Delete CloudFormation Stack

```bash
aws cloudformation delete-stack --stack-name $STACK_NAME
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
```

---

## Troubleshooting

**ECR repository not empty:**
```bash
aws ecr batch-delete-image --repository-name backstage-app \
  --image-ids "$(aws ecr list-images --repository-name backstage-app --query 'imageIds[*]' --output json)"
```

**S3 bucket not empty:**
```bash
aws s3 rm s3://your-bucket-name --recursive
```

**Stack deletion failed:**
```bash
aws cloudformation describe-stack-events --stack-name backstage-platform --max-items 20
```

---

---

**To redeploy:** Follow the [Quick Start Guide](./QUICK-START.md)
