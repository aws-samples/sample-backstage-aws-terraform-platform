#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check required tools
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    command -v aws >/dev/null 2>&1 || { print_error "AWS CLI is required but not installed. Aborting."; exit 1; }
    command -v kubectl >/dev/null 2>&1 || { print_error "kubectl is required but not installed. Aborting."; exit 1; }
    command -v helm >/dev/null 2>&1 || { print_error "Helm is required but not installed. Aborting."; exit 1; }
    
    print_info "All prerequisites met!"
}

# Get CloudFormation stack outputs
get_stack_outputs() {
    local stack_name=$1
    print_info "Retrieving CloudFormation stack outputs..."
    
    CLUSTER_NAME=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs[?OutputKey=='EKSClusterName'].OutputValue" --output text)
    RDS_ENDPOINT=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs[?OutputKey=='RDSEndpoint'].OutputValue" --output text)
    RDS_PORT=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs[?OutputKey=='RDSPort'].OutputValue" --output text)
    SECRETS_ARN=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].Outputs[?OutputKey=='BackstageSecretsArn'].OutputValue" --output text)
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    AWS_REGION=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query "Stacks[0].StackId" --output text | cut -d':' -f4)
    
    print_info "Cluster Name: $CLUSTER_NAME"
    print_info "AWS Region: $AWS_REGION"
    print_info "RDS Endpoint: $RDS_ENDPOINT"
}

# Configure kubectl
configure_kubectl() {
    print_info "Configuring kubectl for cluster: $CLUSTER_NAME in region: $AWS_REGION"
    aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
    kubectl cluster-info
}



# Get secrets from AWS Secrets Manager
get_secrets() {
    print_info "Retrieving secrets from AWS Secrets Manager..."
    
    # Get Backstage secrets
    SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRETS_ARN" --query SecretString --output text)
    
    POSTGRES_HOST=$(echo "$SECRET_JSON" | jq -r '.POSTGRES_HOST')
    POSTGRES_PORT=$(echo "$SECRET_JSON" | jq -r '.POSTGRES_PORT')
    POSTGRES_USER=$(echo "$SECRET_JSON" | jq -r '.POSTGRES_USER')
    RDS_SECRET_ARN=$(echo "$SECRET_JSON" | jq -r '.RDS_SECRET_ARN')
    GITHUB_TOKEN=$(echo "$SECRET_JSON" | jq -r '.GITHUB_TOKEN')
    GITHUB_ORG=$(echo "$SECRET_JSON" | jq -r '.GITHUB_ORG')
    
    # Get RDS password from AWS-managed secret
    print_info "Retrieving RDS password from AWS-managed secret..."
    RDS_SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --query SecretString --output text)
    POSTGRES_PASSWORD=$(echo "$RDS_SECRET_JSON" | jq -r '.password')
}

# Create Backstage namespace and secrets
create_backstage_namespace() {
    print_info "Creating Backstage namespace and secrets..."
    
    kubectl create namespace backstage --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Kubernetes secret for database with all connection details
    kubectl create secret generic backstage-postgres-secret \
        --from-literal=postgres-host="$POSTGRES_HOST" \
        --from-literal=postgres-port="$POSTGRES_PORT" \
        --from-literal=postgres-user="$POSTGRES_USER" \
        --from-literal=postgres-password="$POSTGRES_PASSWORD" \
        --namespace backstage \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Kubernetes secret for GitHub
    kubectl create secret generic backstage-github-secret \
        --from-literal=github-token="$GITHUB_TOKEN" \
        --namespace backstage \
        --dry-run=client -o yaml | kubectl apply -f -
}

# Install Backstage using Helm
install_backstage() {
    print_info "Installing Backstage using Helm..."
    
    # Get ECR details from CloudFormation outputs
    ECR_REPOSITORY_URI=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" --output text)
    BACKSTAGE_TAG=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='BackstageImageTag'].OutputValue" --output text)
    
    # Parse registry and repository from ECR URI
    # Format: account.dkr.ecr.region.amazonaws.com/repo-name
    ECR_REGISTRY=$(echo "$ECR_REPOSITORY_URI" | cut -d'/' -f1)
    ECR_REPOSITORY=$(echo "$ECR_REPOSITORY_URI" | cut -d'/' -f2)
    
    print_info "Using ECR image: $ECR_REPOSITORY_URI:$BACKSTAGE_TAG"
    
    # Add Backstage Helm repository
    helm repo add backstage https://backstage.github.io/charts
    helm repo update
    
    # Set default values for optional parameters
    ORGANIZATION_NAME="${ORGANIZATION_NAME:-My Organization}"
    SCAFFOLDER_EMAIL="${SCAFFOLDER_EMAIL:-backstage@example.com}"
    BASE_URL="http://backstage.local"  # Placeholder - works with port-forward. For ALB/custom domain, update helm-values.yaml with your actual URL
    
    # Get the directory where this script is located
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")/templates"
    
    # Use the helm-values.yaml template and substitute variables
    print_info "Using Helm values template from: $TEMPLATE_DIR/helm-values.yaml"
    
    # Export variables for envsubst
    export ECR_REGISTRY ECR_REPOSITORY BACKSTAGE_TAG
    export POSTGRES_HOST POSTGRES_PORT POSTGRES_USER
    export GITHUB_ORG ORGANIZATION_NAME SCAFFOLDER_EMAIL BASE_URL
    
    # Substitute only deployment-time variables, preserve runtime variables for Backstage
    # POSTGRES_* and GITHUB_TOKEN are preserved as ${VAR} for Backstage runtime substitution
    envsubst '${ECR_REGISTRY} ${ECR_REPOSITORY} ${BACKSTAGE_TAG} ${GITHUB_ORG} ${ORGANIZATION_NAME} ${SCAFFOLDER_EMAIL} ${BASE_URL}' \
        < "$TEMPLATE_DIR/helm-values.yaml" > /tmp/backstage-values.yaml
    
    print_info "Generated Helm values file at /tmp/backstage-values.yaml"
    
    
    # Install Backstage
    helm upgrade --install backstage backstage/backstage \
        --namespace backstage \
        --values /tmp/backstage-values.yaml \
        --wait \
        --timeout 10m
    
    print_info "Backstage installed successfully!"
    print_info "Note: The Docker image contains default configuration."
    print_info "      Helm values override environment-specific settings."
}

# Main deployment function
main() {
    if [ $# -lt 1 ]; then
        print_error "Usage: $0 <cloudformation-stack-name>"
        exit 1
    fi
    
    STACK_NAME=$1
    
    print_info "Starting Backstage deployment..."
    
    check_prerequisites
    get_stack_outputs "$STACK_NAME"
    configure_kubectl
    get_secrets
    create_backstage_namespace
    install_backstage
    
    echo ""
    echo "=========================================="
    print_success "Deployment Completed Successfully!"
    echo "=========================================="
    echo ""
    print_success "Access Backstage using port-forward:"
    echo ""
    echo "  kubectl port-forward svc/backstage 7007:7007 -n backstage"
    echo ""
    echo "  Then open: http://localhost:7007"
    echo ""
    print_info "For custom domain with ALB, see: docs/ACCESS-METHODS.md"
    echo ""
}

main "$@"
