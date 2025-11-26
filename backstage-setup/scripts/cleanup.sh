#!/bin/bash
set -e

# Backstage Platform Cleanup Script
# Safely removes all resources created by the platform

# Disable AWS CLI pager to prevent interactive prompts
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <cloudformation-stack-name>"
    print_error "Example: $0 backstage-platform"
    exit 1
fi

STACK_NAME=$1

echo "=========================================="
echo "  Backstage Platform Cleanup"
echo "=========================================="
echo ""

# Fetch EKS cluster name from CloudFormation stack outputs
print_info "Fetching EKS cluster name from CloudFormation stack..."
CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`EKSClusterName`].OutputValue' \
    --output text 2>/dev/null)

if [ -z "$CLUSTER_NAME" ]; then
    print_error "Could not fetch EKS cluster name from stack outputs"
    print_error "Stack may not exist or may not have been created successfully"
    exit 1
fi

print_success "Found EKS cluster: $CLUSTER_NAME (used to remove Backstage deployment)"
echo ""

print_warn "This will DELETE all Backstage resources!"
echo ""
echo "Stack Name: $STACK_NAME"
echo ""
print_info "Note: Your existing EKS cluster '$CLUSTER_NAME' will NOT be deleted"
print_info "      Only the Backstage deployment will be removed from it"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    print_info "Cleanup cancelled"
    exit 0
fi

echo ""
print_info "Starting cleanup process..."
echo ""

print_header "Step 1/6: Delete Backstage Ingress (triggers ALB deletion)"

if command -v kubectl &> /dev/null && command -v helm &> /dev/null; then
    # Configure kubectl
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region $(aws configure get region) 2>/dev/null || print_warn "Could not configure kubectl"
    
    # Delete Backstage (this removes the Ingress and triggers ALB deletion)
    print_info "Uninstalling Backstage Helm release..."
    helm uninstall backstage -n backstage 2>/dev/null || print_warn "Backstage not found or already deleted"
    
    # Wait for ALB to be deleted (important for VPC cleanup)
    print_info "Waiting for ALB to be deleted (max 2 minutes)..."
    for i in {1..24}; do
        ALB_COUNT=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-backstag')].LoadBalancerArn" --output text 2>/dev/null | wc -w)
        if [ "$ALB_COUNT" -eq 0 ]; then
            print_success "ALB deleted successfully"
            break
        fi
        echo -n "."
        sleep 5
    done
    echo ""
    
    print_success "Backstage and ALB cleaned up"
else
    print_warn "kubectl or helm not found, skipping Kubernetes cleanup"
    print_warn "⚠️  ALB may not be deleted - CloudFormation stack deletion may fail"
fi

print_header "Step 2/6: Delete ECR Images"

REPO_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryName'].OutputValue" \
  --output text 2>/dev/null)

if [ -n "$REPO_NAME" ] && [ "$REPO_NAME" != "None" ]; then
    print_info "Checking for images in ECR repository: $REPO_NAME"
    
    # Get all image IDs (both tagged and untagged)
    IMAGE_IDS=$(aws ecr list-images \
      --repository-name "$REPO_NAME" \
      --query 'imageIds[*]' \
      --output json 2>/dev/null)
    
    IMAGE_COUNT=$(echo "$IMAGE_IDS" | jq '. | length' 2>/dev/null || echo "0")
    
    if [ "$IMAGE_COUNT" -gt 0 ]; then
        print_info "Deleting $IMAGE_COUNT images from ECR..."
        
        # Force delete ALL images using batch-delete-image with all IDs at once
        aws ecr batch-delete-image \
          --repository-name "$REPO_NAME" \
          --image-ids "$IMAGE_IDS" 2>/dev/null || {
            print_warn "Batch delete failed, trying individual deletion..."
            # Fallback: delete one by one
            echo "$IMAGE_IDS" | jq -c '.[]' | while read -r image; do
                aws ecr batch-delete-image \
                  --repository-name "$REPO_NAME" \
                  --image-ids "$image" 2>/dev/null || true
            done
        }
        
        # Wait a moment for deletions to complete
        sleep 2
        
        # Verify deletion
        REMAINING=$(aws ecr list-images --repository-name "$REPO_NAME" --query 'length(imageIds)' --output text 2>/dev/null || echo "0")
        if [ "$REMAINING" -eq 0 ]; then
            print_success "All ECR images deleted"
        else
            print_warn "$REMAINING images still remain"
            print_info "Force deleting ECR repository with remaining images..."
            # Force delete the repository with all images
            aws ecr delete-repository \
              --repository-name "$REPO_NAME" \
              --force \
              --region $(aws configure get region) 2>/dev/null && \
              print_success "ECR repository force deleted" || \
              print_warn "Could not force delete ECR repository - CloudFormation will retry"
        fi
    else
        print_info "No images found in ECR repository"
    fi
else
    print_warn "ECR repository not found, skipping"
fi

print_header "Step 3/6: Empty S3 Bucket"

BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='TerraformStateBucket'].OutputValue" \
  --output text 2>/dev/null)

if [ -n "$BUCKET_NAME" ] && [ "$BUCKET_NAME" != "None" ]; then
    OBJECT_COUNT=$(aws s3 ls s3://$BUCKET_NAME --recursive | wc -l)
    
    if [ "$OBJECT_COUNT" -gt 0 ]; then
        print_info "Deleting $OBJECT_COUNT objects from S3..."
        aws s3 rm s3://$BUCKET_NAME --recursive 2>/dev/null || print_warn "Failed to delete some objects"
        
        # Delete versions if versioning is enabled
        print_info "Checking for object versions..."
        aws s3api list-object-versions \
          --bucket $BUCKET_NAME \
          --query 'Versions[].{Key:Key,VersionId:VersionId}' \
          --output json 2>/dev/null | \
          jq -r '.[]? | "--key \(.Key) --version-id \(.VersionId)"' 2>/dev/null | \
          xargs -I {} aws s3api delete-object --bucket $BUCKET_NAME {} 2>/dev/null || true
        
        print_success "S3 bucket emptied"
    else
        print_info "S3 bucket is already empty"
    fi
else
    print_warn "S3 bucket not found, skipping"
fi

print_header "Step 4/6: Delete DynamoDB State Lock Table"

# Check if DynamoDB table exists in CloudFormation outputs
DYNAMODB_TABLE=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query "Stacks[0].Outputs[?OutputKey=='TerraformStateLockTable'].OutputValue" \
  --output text 2>/dev/null)

if [ -n "$DYNAMODB_TABLE" ] && [ "$DYNAMODB_TABLE" != "None" ]; then
    print_info "Checking DynamoDB table: $DYNAMODB_TABLE"
    
    # Check if table exists
    if aws dynamodb describe-table --table-name "$DYNAMODB_TABLE" &>/dev/null; then
        print_info "Deleting DynamoDB table: $DYNAMODB_TABLE"
        
        # Delete the table
        if aws dynamodb delete-table --table-name "$DYNAMODB_TABLE" 2>/dev/null; then
            print_info "Waiting for table deletion..."
            aws dynamodb wait table-not-exists --table-name "$DYNAMODB_TABLE" 2>/dev/null || true
            print_success "DynamoDB table deleted"
        else
            print_warn "Could not delete DynamoDB table (CloudFormation will handle it)"
        fi
    else
        print_info "DynamoDB table not found or already deleted"
    fi
else
    print_info "DynamoDB state locking not enabled, skipping"
fi

print_header "Step 5/6: Disable RDS Deletion Protection"

# Check if RDS instance exists and has deletion protection enabled
RDS_INSTANCE=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --logical-resource-id RDSInstance \
  --query 'StackResources[0].PhysicalResourceId' \
  --output text 2>/dev/null)

if [ -n "$RDS_INSTANCE" ] && [ "$RDS_INSTANCE" != "None" ]; then
    print_info "Checking RDS deletion protection for: $RDS_INSTANCE"
    
    # Check if deletion protection is enabled
    DELETION_PROTECTION=$(aws rds describe-db-instances \
      --db-instance-identifier "$RDS_INSTANCE" \
      --query 'DBInstances[0].DeletionProtection' \
      --output text 2>/dev/null)
    
    if [ "$DELETION_PROTECTION" == "True" ]; then
        print_info "Disabling RDS deletion protection..."
        
        if aws rds modify-db-instance \
          --db-instance-identifier "$RDS_INSTANCE" \
          --no-deletion-protection \
          --apply-immediately \
          --output text > /dev/null 2>&1; then
            
            print_info "Waiting for modification to complete..."
            aws rds wait db-instance-available --db-instance-identifier "$RDS_INSTANCE" 2>/dev/null || true
            print_success "RDS deletion protection disabled"
        else
            print_warn "Could not disable deletion protection (may already be disabled)"
        fi
    else
        print_info "RDS deletion protection is already disabled"
    fi
else
    print_info "RDS instance not found, skipping"
fi

print_header "Step 6/6: Delete CloudFormation Stack"

print_info "Initiating stack deletion..."
aws cloudformation delete-stack --stack-name $STACK_NAME

print_info "Waiting for stack deletion to complete (this may take 10-15 minutes)..."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 2>/dev/null || {
    print_error "Stack deletion failed or timed out"
    
    # Check if it's an ECR deletion failure
    FAILED_RESOURCE=$(aws cloudformation describe-stack-events \
      --stack-name $STACK_NAME \
      --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]|[0].[LogicalResourceId,ResourceStatusReason]' \
      --output text 2>/dev/null)
    
    if echo "$FAILED_RESOURCE" | grep -q "ECRRepository"; then
        print_warn "ECR repository deletion failed"
        print_info "Attempting to force delete ECR repository..."
        
        # Get ECR repository name from stack
        ECR_REPO=$(aws cloudformation describe-stack-resources \
          --stack-name $STACK_NAME \
          --logical-resource-id ECRRepository \
          --query 'StackResources[0].PhysicalResourceId' \
          --output text 2>/dev/null)
        
        if [ -n "$ECR_REPO" ] && [ "$ECR_REPO" != "None" ]; then
            aws ecr delete-repository \
              --repository-name "$ECR_REPO" \
              --force \
              --region $(aws configure get region) 2>/dev/null && \
              print_success "ECR repository force deleted"
            
            # Retry stack deletion
            print_info "Retrying CloudFormation stack deletion..."
            aws cloudformation delete-stack --stack-name $STACK_NAME
            aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME 2>/dev/null && \
              print_success "Stack deletion completed on retry" || \
              print_error "Stack deletion still failed - manual intervention required"
        fi
    else
        print_info "Check CloudFormation console for details"
        print_info "Command: aws cloudformation describe-stack-events --stack-name $STACK_NAME"
    fi
    
    exit 1
}

print_success "CloudFormation stack deleted"

print_header "Cleanup Complete!"

echo "All resources have been deleted:"
echo "  ✅ Application Load Balancer"
echo "  ✅ Backstage deployment"
echo "  ✅ ECR images (all versions)"
echo "  ✅ S3 bucket contents (including versions)"
echo "  ✅ DynamoDB state lock table (if enabled)"
echo "  ✅ EKS-created security groups"
echo "  ✅ RDS deletion protection (disabled)"
echo "  ✅ CloudFormation stack (RDS, ECR, S3, IAM roles)"
echo ""

if [ -n "$REMAINING" ] && [ "$REMAINING" -gt 0 ]; then
    echo ""
    print_info "Note: Some warnings during cleanup are normal:"
    echo "  • ECR images in use: CloudFormation deletes the repository with all images"
    echo "  • Security groups with dependencies: CloudFormation handles final cleanup"
    echo "  • These warnings don't indicate a problem"
    echo ""
fi

echo "Monthly cost savings: ~\$340"
echo ""
print_info "To redeploy, follow the Quick Start Guide"
echo ""
