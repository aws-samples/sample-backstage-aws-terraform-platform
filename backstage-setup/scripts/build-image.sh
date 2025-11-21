#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_tools=()
    
    # Check required tools
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    command -v node >/dev/null 2>&1 || missing_tools+=("node")
    command -v yarn >/dev/null 2>&1 || missing_tools+=("yarn")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        print_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "docker")
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                "aws-cli")
                    echo "  AWS CLI: https://aws.amazon.com/cli/"
                    ;;
                "node")
                    echo "  Node.js: https://nodejs.org/ (version 18 or 20)"
                    ;;
                "yarn")
                    echo "  Yarn: npm install -g yarn@1"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check Node.js version (must be 18.x, 20.x, or 22.x)
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" != "18" ] && [ "$NODE_VERSION" != "20" ] && [ "$NODE_VERSION" != "22" ]; then
        print_error "Node.js version must be 18.x, 20.x, or 22.x (LTS). Current: $(node --version)"
        print_error "Please install Node.js from https://nodejs.org/"
        exit 1
    fi
    
    # Check Yarn version (Backstage now supports Yarn 4+)
    YARN_VERSION=$(yarn --version 2>/dev/null || echo "0")
    if [ "$YARN_VERSION" == "0" ]; then
        print_error "Yarn is not installed"
        print_error "Install Yarn: npm install -g yarn"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        print_error "Please start Docker Desktop or Docker daemon"
        exit 1
    fi
    
    print_success "All prerequisites met"
    print_info "Node.js: $(node --version)"
    print_info "Yarn: $(yarn --version)"
    print_info "Docker: $(docker --version | cut -d',' -f1)"
}

# Parse command line arguments
parse_args() {
    if [ $# -lt 1 ]; then
        print_error "Usage: $0 <cloudformation-stack-name> [platform]"
        print_error "Example: $0 backstage-platform"
        print_error "Example: $0 backstage-platform linux/arm64"
        print_error ""
        print_error "Platform options:"
        print_error "  linux/amd64 (default) - For standard x86_64 EKS nodes (t3, m5, c5, r5, etc.)"
        print_error "  linux/arm64           - For Graviton EKS nodes (t4g, m6g, c6g, r6g, etc.)"
        exit 1
    fi
    
    STACK_NAME=$1
    PLATFORM="${2:-linux/amd64}"  # Default to amd64
    
    print_info "Getting configuration from CloudFormation stack: $STACK_NAME"
    print_info "Target platform: $PLATFORM"
}

# Get stack outputs
get_stack_outputs() {
    print_step "Retrieving CloudFormation stack outputs..."
    
    ECR_REPOSITORY_URI=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" --output text)
    ECR_REPOSITORY_NAME=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryName'].OutputValue" --output text)
    IMAGE_TAG=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='BackstageImageTag'].OutputValue" --output text)
    AWS_REGION=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackId" --output text | cut -d':' -f4)
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${ECR_REPOSITORY_URI}:${IMAGE_TAG}"
    
    print_info "ECR Repository URI: ${ECR_REPOSITORY_URI}"
    print_info "ECR Repository Name: ${ECR_REPOSITORY_NAME}"
    print_info "AWS Region: ${AWS_REGION}"
    print_info "Image Tag: ${IMAGE_TAG}"
    print_info "Full Image Name: ${FULL_IMAGE_NAME}"
}

# Create Backstage app if it doesn't exist
create_backstage_app() {
    print_step "Setting up Backstage application..."
    
    if [ ! -d "backstage-app" ]; then
        print_info "Creating new Backstage app..."
        
        # Create app with name 'backstage-app' non-interactively
        echo "backstage-app" | npx @backstage/create-app@latest --skip-install
        
        # Verify the directory was created
        if [ ! -d "backstage-app" ]; then
            print_error "Failed to create Backstage app directory"
            exit 1
        fi
        
        print_success "Backstage app created"
    else
        print_info "Backstage app directory already exists"
    fi
}

# Verify build prerequisites
verify_build_files() {
    print_step "Verifying build prerequisites..."
    
    cd backstage-app
    
    # Verify Dockerfile exists at packages/backend/Dockerfile (created by @backstage/create-app)
    if [ ! -f "packages/backend/Dockerfile" ]; then
        print_error "Dockerfile not found at packages/backend/Dockerfile"
        print_error "This should have been created by @backstage/create-app"
        exit 1
    fi
    print_info "✓ Dockerfile found at packages/backend/Dockerfile"
    
    # Verify default config files exist (created by @backstage/create-app)
    if [ ! -f "app-config.yaml" ]; then
        print_error "app-config.yaml not found - should be created by @backstage/create-app"
        exit 1
    fi
    print_info "✓ Default app-config.yaml found"
    
    # Verify .dockerignore exists (created by @backstage/create-app)
    if [ ! -f ".dockerignore" ]; then
        print_warn ".dockerignore not found, creating one..."
        cat > .dockerignore << 'EOF'
.git
.yarn/cache
.yarn/install-state.gz
node_modules
packages/*/src
packages/*/node_modules
plugins
*.local.yaml
EOF
        print_info "✓ Created .dockerignore"
    else
        print_info "✓ .dockerignore found"
    fi
    
    cd ..
    
    print_success "All build prerequisites verified"
}

# Build Docker image using official Host Build method
build_image() {
    print_step "Building Docker image using Host Build method..."
    
    cd backstage-app
    
    # Verify config file exists
    if [ ! -f "app-config.production.yaml" ]; then
        print_error "app-config.production.yaml not found in backstage-app directory"
        exit 1
    fi
    
    # Step 1: Install dependencies
    print_info "Step 1/4: Installing dependencies..."
    
    # Check if this is a fresh app or has dependency issues
    if [ ! -f "yarn.lock.bak" ]; then
        print_info "First-time setup: resolving dependencies and generating lockfile..."
        yarn install
        
        # Mark lockfile as validated
        cp yarn.lock yarn.lock.bak
        print_success "Lockfile generated and validated"
    fi
    
    # Now use immutable for reproducible builds
    print_info "Installing dependencies with immutable lockfile..."
    yarn install --immutable
    
    # Step 2: Generate type definitions (outputs to dist-types/)
    print_info "Step 2/4: Generating type definitions..."
    yarn tsc
    
    # Step 3: Build the backend package (bundles into packages/backend/dist)
    print_info "Step 3/4: Building backend package..."
    yarn build:backend
    
    # Step 4: Build Docker image with BuildKit
    # Build from repo root with packages/backend/Dockerfile (as per official docs)
    print_info "Step 4/4: Building Docker image for $PLATFORM..."
    export DOCKER_BUILDKIT=1
    docker image build --platform "$PLATFORM" . -f packages/backend/Dockerfile --tag "${FULL_IMAGE_NAME}" --tag "${ECR_REPOSITORY_URI}:latest"
    
    cd ..
    
    print_success "Docker image built successfully: ${FULL_IMAGE_NAME}"
}

# Login to ECR
ecr_login() {
    print_step "Logging in to Amazon ECR..."
    
    aws ecr get-login-password --region "${AWS_REGION}" | \
        docker login --username AWS --password-stdin "${ECR_REGISTRY}"
    
    print_info "Successfully logged in to ECR"
}

# Push image to ECR
push_image() {
    print_step "Pushing image to ECR..."
    
    docker push "${FULL_IMAGE_NAME}"
    docker push "${ECR_REPOSITORY_URI}:latest"
    
    print_info "Image pushed successfully to ECR"
}

# Display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "  Build and Push Complete!"
    echo "=========================================="
    echo ""
    echo "Image Details:"
    echo "  Repository: ${ECR_REPOSITORY_NAME}"
    echo "  Region: ${AWS_REGION}"
    echo "  Tag: ${IMAGE_TAG}"
    if [ "$PLATFORM" == "linux/amd64" ]; then
        echo "  Platform: linux/amd64 (x86_64 - standard EKS nodes)"
    elif [ "$PLATFORM" == "linux/arm64" ]; then
        echo "  Platform: linux/arm64 (aarch64 - Graviton EKS nodes)"
    else
        echo "  Platform: $PLATFORM"
    fi
    echo "  Full Name: ${FULL_IMAGE_NAME}"
    echo ""
    echo "Configuration Approach:"
    echo "  ✓ Official Backstage Dockerfile (Node.js 22)"
    echo "  ✓ Default config baked into image (app-config.yaml)"
    echo "  ✓ Helm will override with environment-specific values"
    echo "  ✓ Secrets injected at runtime via Kubernetes"
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy or update Backstage:"
    echo "     ./deploy-backstage.sh ${STACK_NAME}"
    echo ""
    echo "  2. Or manually update the deployment:"
    echo "     kubectl set image deployment/backstage backstage=${FULL_IMAGE_NAME} -n backstage"
    echo ""
    echo "=========================================="
}

# Main function
main() {
    print_info "Starting Backstage image build from CloudFormation stack..."
    echo ""
    
    parse_args "$@"
    check_prerequisites
    get_stack_outputs
    create_backstage_app
    verify_build_files
    build_image
    ecr_login
    push_image
    display_summary
    
    print_info "Process completed successfully!"
}

main "$@"
