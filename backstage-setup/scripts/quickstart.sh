#!/bin/bash
set -e

# Backstage Terraform IDP - Quickstart Script
# Automates the complete deployment after CloudFormation stack creation
# Usage: ./quickstart.sh <stack-name>

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${CYAN}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <cloudformation-stack-name> [platform]"
    print_error "Example: $0 backstage-platform"
    print_error "Example: $0 backstage-platform linux/arm64"
    print_error ""
    print_error "Platform: linux/amd64 (default) or linux/arm64 for Graviton nodes"
    exit 1
fi

STACK_NAME=$1
PLATFORM="${2:-linux/amd64}"  # Default to amd64

print_header "Backstage Terraform IDP - Quickstart"
print_info "Stack Name: $STACK_NAME"
print_info "Platform: $PLATFORM"
print_info "Starting automated deployment..."

# Step 1: Wait for CloudFormation stack
print_header "Step 1/4: Waiting for CloudFormation stack to complete..."
print_info "This may take 15-20 minutes for initial stack creation..."

if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" 2>/dev/null; then
    print_success "CloudFormation stack is ready"
elif aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" 2>/dev/null; then
    print_success "CloudFormation stack update is complete"
else
    # Check if stack already exists and is in CREATE_COMPLETE or UPDATE_COMPLETE state
    STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackStatus" --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [[ "$STACK_STATUS" == "CREATE_COMPLETE" ]] || [[ "$STACK_STATUS" == "UPDATE_COMPLETE" ]]; then
        print_success "CloudFormation stack already exists and is ready"
    else
        print_error "CloudFormation stack is not ready. Current status: $STACK_STATUS"
        print_error "Please ensure the stack is created successfully before running this script"
        exit 1
    fi
fi

# Step 2: Setup repository (if setup-repo.sh exists)
if [ -f "./setup-repo.sh" ]; then
    print_header "Step 2/4: Setting up repository..."
    print_info "Forking repo and configuring with CloudFormation outputs..."
    
    if ./setup-repo.sh "$STACK_NAME"; then
        print_success "Repository configured successfully"
    else
        print_error "Repository setup failed"
        print_error "Common causes:"
        print_error "  - GitHub CLI not authenticated (run: gh auth login)"
        print_error "  - Missing required permissions on GitHub token"
        print_error "  - Network connectivity issues"
        echo ""
        print_info "Please fix the issue and run the script again"
        exit 1
    fi
else
    print_error "setup-repo.sh not found in current directory"
    print_info "Please ensure you're running this script from backstage-setup/scripts/"
    exit 1
fi

# Step 3: Build Docker image
print_header "Step 3/4: Building Docker image..."
print_info "This will create a Backstage app and build the Docker image..."

if [ -f "./build-image.sh" ]; then
    if ./build-image.sh "$STACK_NAME" "$PLATFORM"; then
        print_success "Docker image built and pushed to ECR"
    else
        print_error "Docker image build failed"
        exit 1
    fi
else
    print_error "build-image.sh not found"
    exit 1
fi

# Step 4: Deploy Backstage
print_header "Step 4/4: Deploying Backstage to EKS..."
print_info "Deploying Backstage to your EKS cluster..."

if [ -f "./deploy-backstage.sh" ]; then
    if ./deploy-backstage.sh "$STACK_NAME"; then
        print_success "Backstage deployed successfully"
    else
        print_error "Backstage deployment failed"
        exit 1
    fi
else
    print_error "deploy-backstage.sh not found"
    exit 1
fi

# Get deployment information
print_header "Deployment Complete!"

print_info "Retrieving deployment information..."

# Get ECR repository
ECR_REPO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" --output text 2>/dev/null || echo "N/A")

# Get EKS cluster
EKS_CLUSTER=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='EKSClusterName'].OutputValue" --output text 2>/dev/null || echo "N/A")

echo ""
echo "📦 Deployment Details:"
echo "  Stack Name: $STACK_NAME"
echo "  EKS Cluster: $EKS_CLUSTER"
echo "  ECR Repository: $ECR_REPO"
echo ""
echo "🌐 Access Backstage:"
echo "  Use port-forward to access Backstage:"
echo ""
echo "    kubectl port-forward svc/backstage 7007:7007 -n backstage"
echo ""
echo "  Then open: http://localhost:7007"
echo ""
echo "  For custom domain setup, see: docs/ACCESS-METHODS.md"
echo ""
echo "📚 Next Steps:"
echo "  1. Access Backstage using port-forward (command above)"
echo "  2. Sign in as Guest"
echo "  3. Navigate to 'Create' to see available templates"
echo "  4. Start provisioning AWS resources!"
echo ""
echo "🔍 Useful Commands:"
echo "  Check pods:     kubectl get pods -n backstage"
echo "  View logs:      kubectl logs -n backstage -l app=backstage"
echo ""

print_header "🎉 Success!"
print_info "Backstage Terraform IDP is ready to use!"
