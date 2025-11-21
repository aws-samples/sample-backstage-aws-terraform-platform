#!/bin/bash
set -e

# Repository Setup Script
# Fetches configuration from CloudFormation and sets up the repository
# Usage: ./setup-repo.sh <cloudformation-stack-name>

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_tools=()
    local warnings=()
    
    # Check required tools for repository setup
    command -v aws >/dev/null 2>&1 || missing_tools+=("aws-cli")
    command -v gh >/dev/null 2>&1 || missing_tools+=("gh")
    command -v git >/dev/null 2>&1 || missing_tools+=("git")
    
    # Check required tools for image building (will be needed later)
    command -v docker >/dev/null 2>&1 || missing_tools+=("docker")
    command -v node >/dev/null 2>&1 || missing_tools+=("node")
    command -v yarn >/dev/null 2>&1 || missing_tools+=("yarn")
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        print_info "Install missing tools:"
        for tool in "${missing_tools[@]}"; do
            case $tool in
                "aws-cli")
                    echo "  AWS CLI: https://aws.amazon.com/cli/"
                    ;;
                "gh")
                    echo "  GitHub CLI: https://cli.github.com/"
                    ;;
                "git")
                    echo "  Git: https://git-scm.com/"
                    ;;
                "docker")
                    echo "  Docker: https://docs.docker.com/get-docker/"
                    ;;
                "node")
                    echo "  Node.js: https://nodejs.org/ (version 18, 20, or 22)"
                    ;;
                "yarn")
                    echo "  Yarn: npm install -g yarn"
                    ;;
            esac
        done
        exit 1
    fi
    
    # Check GitHub CLI authentication
    if ! gh auth status &> /dev/null; then
        print_error "GitHub CLI is not authenticated"
        print_info "Run: gh auth login"
        exit 1
    fi
    
    # Check Node.js version (must be 18.x, 20.x, or 22.x)
    NODE_VERSION=$(node --version | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" != "18" ] && [ "$NODE_VERSION" != "20" ] && [ "$NODE_VERSION" != "22" ]; then
        print_error "Node.js version must be 18.x, 20.x, or 22.x (LTS). Current: $(node --version)"
        print_info "Install from: https://nodejs.org/"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running"
        print_info "Please start Docker Desktop or Docker daemon"
        exit 1
    fi
    
    print_success "All prerequisites met"
    print_info "Node.js: $(node --version)"
    print_info "Yarn: $(yarn --version)"
    print_info "Docker: $(docker --version | cut -d',' -f1)"
    print_info "GitHub CLI: $(gh --version | head -n1)"
}

# Check arguments
if [ $# -lt 1 ]; then
    print_error "Usage: $0 <cloudformation-stack-name>"
    print_error "Example: $0 backstage-platform"
    echo ""
    print_info "This script must be run AFTER deploying the CloudFormation stack"
    print_info "The CloudFormation stack creates:"
    print_info "  - GitHub OIDC Provider"
    print_info "  - IAM Role for GitHub Actions"
    print_info "  - S3 Bucket for Terraform state"
    exit 1
fi

STACK_NAME=$1

print_info "Repository setup for CloudFormation stack: $STACK_NAME"
echo ""

# Check prerequisites
check_prerequisites

# Check if stack exists
print_step "Checking CloudFormation stack..."
if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" &>/dev/null; then
    print_error "CloudFormation stack '$STACK_NAME' not found"
    print_error "Please deploy the CloudFormation stack first:"
    echo ""
    echo "  cd backstage-setup"
    echo "  aws cloudformation create-stack \\"
    echo "    --stack-name $STACK_NAME \\"
    echo "    --template-body file://templates/backstage-eks-stack.yaml \\"
    echo "    --parameters file://parameters.json \\"
    echo "    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM"
    exit 1
fi

print_success "CloudFormation stack found"

# Get CloudFormation outputs
print_step "Retrieving configuration from CloudFormation..."

GITHUB_ORG=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Parameters[?ParameterKey=='GitHubOrg'].ParameterValue" --output text)
GITHUB_REPO=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Parameters[?ParameterKey=='GitHubRepo'].ParameterValue" --output text)
TF_STATE_BUCKET=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TerraformStateBucket'].OutputValue" --output text)
TF_STATE_LOCK_TABLE=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='TerraformStateLockTable'].OutputValue" --output text 2>/dev/null || echo "")
GITHUB_ACTIONS_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='GitHubActionsRoleArn'].OutputValue" --output text)
OIDC_PROVIDER_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='GitHubOIDCProviderArn'].OutputValue" --output text)
SECRETS_ARN=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].Outputs[?OutputKey=='BackstageSecretsArn'].OutputValue" --output text)
AWS_REGION=$(aws cloudformation describe-stacks --stack-name "$STACK_NAME" --query "Stacks[0].StackId" --output text | cut -d':' -f4)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

print_success "Configuration retrieved"
echo ""
echo "  GitHub Organization: $GITHUB_ORG"
echo "  GitHub Repository: $GITHUB_REPO"
echo "  AWS Region: $AWS_REGION"
echo "  AWS Account: $AWS_ACCOUNT_ID"
echo "  Terraform State Bucket: $TF_STATE_BUCKET"
if [ -n "$TF_STATE_LOCK_TABLE" ]; then
    echo "  Terraform State Lock Table: $TF_STATE_LOCK_TABLE"
fi
echo "  GitHub Actions Role: $GITHUB_ACTIONS_ROLE_ARN"
echo ""

# Step 1: Fork repository using GitHub CLI
print_step "Forking repository to $GITHUB_ORG..."

FORK_URL="https://github.com/$GITHUB_ORG/$GITHUB_REPO"
if gh repo view "$GITHUB_ORG/$GITHUB_REPO" &> /dev/null; then
    print_warn "Repository $GITHUB_ORG/$GITHUB_REPO already exists"
    print_info "Skipping fork, will update existing repository"
else
    print_info "Forking repository..."
    if gh repo fork --org "$GITHUB_ORG" --fork-name "$GITHUB_REPO" --clone=false --remote=false; then
        print_success "Repository forked successfully"
    else
        print_error "Failed to fork repository"
        exit 1
    fi
fi

# Step 2: Clone the forked repository
print_step "Cloning forked repository..."
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

# Clone quietly to suppress "set as default repository" message
if gh repo clone "$GITHUB_ORG/$GITHUB_REPO" 2>&1 | grep -v "set as the default repository" | grep -v "To learn more"; then
    print_success "Repository cloned to temporary directory"
else
    print_error "Failed to clone repository"
    exit 1
fi

cd "$GITHUB_REPO"
print_info "Working in: $TEMP_DIR/$GITHUB_REPO"

# Step 3: Update backstage-templates with GitHub org and repo
print_step "Updating backstage-templates with your GitHub organization and repository..."

TEMPLATE_COUNT=$(find backstage-templates -type f -name "*.yaml" | wc -l | tr -d ' ')
# Replace placeholder patterns with actual GitHub org
find backstage-templates -type f -name "*.yaml" -exec sed -i '' "s/\${GITHUB_ORG}/$GITHUB_ORG/g" {} +
find backstage-templates -type f -name "*.yaml" -exec sed -i '' "s/YOUR_GITHUB_ORG/$GITHUB_ORG/g" {} +
find backstage-templates -type f -name "*.yaml" -exec sed -i '' "s/your-github-org/$GITHUB_ORG/g" {} +

# Replace placeholder patterns with actual GitHub repo
find backstage-templates -type f -name "*.yaml" -exec sed -i '' "s/\${GITHUB_REPO}/$GITHUB_REPO/g" {} +

print_success "Updated $TEMPLATE_COUNT template files with GitHub org: $GITHUB_ORG and repo: $GITHUB_REPO"

# Step 3.5: Update helm-values.yaml with GitHub repo
print_step "Updating helm-values.yaml with repository name..."

HELM_VALUES_FILE="backstage-setup/templates/helm-values.yaml"
if [ -f "$HELM_VALUES_FILE" ]; then
    sed -i '' "s/\${GITHUB_REPO}/$GITHUB_REPO/g" "$HELM_VALUES_FILE"
    sed -i '' "s/\${GITHUB_ORG}/$GITHUB_ORG/g" "$HELM_VALUES_FILE"
    print_success "Updated helm-values.yaml with repository: $GITHUB_ORG/$GITHUB_REPO"
else
    print_warn "helm-values.yaml not found (this is okay if not using Helm deployment)"
fi

# Step 4: Update terraform backend configs
print_step "Updating Terraform backend configurations..."

BACKEND_COUNT=0
for backend_file in terraform/*/backend.tf; do
    if [ -f "$backend_file" ]; then
        sed -i '' "s/YOUR_ORG-terraform-state/$TF_STATE_BUCKET/g" "$backend_file"
        sed -i '' "s/your-org-terraform-state/$TF_STATE_BUCKET/g" "$backend_file"
        sed -i '' "s/us-east-1/$AWS_REGION/g" "$backend_file"
        BACKEND_COUNT=$((BACKEND_COUNT + 1))
    fi
done

# Update template skeleton backend configs
SKELETON_BACKEND_COUNT=$(find backstage-templates -type f -name "backend.config" | wc -l | tr -d ' ')
find backstage-templates -type f -name "backend.config" -exec sed -i '' "s/YOUR_TERRAFORM_STATE_BUCKET/$TF_STATE_BUCKET/g" {} +
find backstage-templates -type f -name "backend.config" -exec sed -i '' "s/YOUR_AWS_REGION/$AWS_REGION/g" {} +

# Configure DynamoDB state locking if table exists
if [ -n "$TF_STATE_LOCK_TABLE" ]; then
    print_step "Configuring DynamoDB state locking..."
    
    # Update template skeleton backend configs with DynamoDB table
    for backend_config in $(find backstage-templates -type f -name "backend.config"); do
        # Uncomment the dynamodb_table line and set the table name
        sed -i '' "s/# dynamodb_table = \"terraform-state-lock\"/dynamodb_table = \"$TF_STATE_LOCK_TABLE\"/g" "$backend_config"
        sed -i '' "s/#dynamodb_table = \"terraform-state-lock\"/dynamodb_table = \"$TF_STATE_LOCK_TABLE\"/g" "$backend_config"
    done
    
    print_success "DynamoDB state locking enabled with table: $TF_STATE_LOCK_TABLE"
else
    print_info "DynamoDB state locking not enabled (EnableStateLocking=false)"
fi

print_success "Updated $BACKEND_COUNT Terraform backend configs with S3 bucket: $TF_STATE_BUCKET"
print_success "Updated $SKELETON_BACKEND_COUNT template backend configs"

# Step 5: Update GitHub Actions workflows
print_step "Updating GitHub Actions workflows..."

if [ -f ".github/workflows/terraform-apply.yml" ]; then
    sed -i '' "s/YOUR_AWS_REGION/$AWS_REGION/g" .github/workflows/terraform-apply.yml
    sed -i '' "s/YOUR_ACCOUNT_ID/$AWS_ACCOUNT_ID/g" .github/workflows/terraform-apply.yml
    print_success "GitHub Actions workflow configured for region: $AWS_REGION"
else
    print_warn "GitHub Actions workflow not found (this is okay)"
fi

# Step 6: Commit and push changes
print_step "Committing and pushing changes..."

# Configure git to use GitHub CLI for authentication
git config --local credential.helper ""
git config --local --add credential.helper '!gh auth git-credential'

git config user.name "Backstage Setup"
git config user.email "setup@backstage.local"
git add .

# Check if there are changes to commit
if git diff --staged --quiet; then
    print_info "No changes to commit (repository already configured)"
else
    git commit -m "Configure repository for $GITHUB_ORG

- Updated backstage-templates with GitHub organization
- Configured Terraform backend with S3 bucket: $TF_STATE_BUCKET
- Updated GitHub Actions workflows with AWS region: $AWS_REGION
- Automated setup via setup-repo.sh" > /dev/null

    git push origin main 2>&1 | grep -v "set as the default repository" | grep -v "To learn more" || true
    print_success "Changes committed and pushed to repository"
fi

# Step 7: Set GitHub repository secrets
print_step "Setting GitHub repository secrets..."

gh secret set AWS_ROLE_ARN --body "$GITHUB_ACTIONS_ROLE_ARN" --repo "$GITHUB_ORG/$GITHUB_REPO"
gh secret set AWS_REGION --body "$AWS_REGION" --repo "$GITHUB_ORG/$GITHUB_REPO"
gh secret set AWS_ACCOUNT_ID --body "$AWS_ACCOUNT_ID" --repo "$GITHUB_ORG/$GITHUB_REPO"

print_success "GitHub secrets configured"

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo ""
echo "=========================================="
print_success "Repository Setup Complete!"
echo "=========================================="
echo ""
echo "🎉 Your repository has been forked and configured!"
echo ""
echo "📦 Forked Repository:"
echo "  URL: ${BLUE}$FORK_URL${NC}"
echo "  Organization: $GITHUB_ORG"
echo "  Repository: $GITHUB_REPO"
echo ""
echo "✅ What Was Configured:"
echo "  • Backstage templates updated with your GitHub organization"
echo "  • Terraform backend configured with S3: $TF_STATE_BUCKET"
if [ -n "$TF_STATE_LOCK_TABLE" ]; then
    echo "  • DynamoDB state locking enabled: $TF_STATE_LOCK_TABLE"
fi
echo "  • GitHub Actions workflows updated for region: $AWS_REGION"
echo "  • GitHub repository secrets set:"
echo "    - AWS_ROLE_ARN"
echo "    - AWS_REGION"
echo "    - AWS_ACCOUNT_ID"
echo ""
echo "⚠️  IMPORTANT: Enable GitHub Actions Workflows"
echo "  GitHub Actions workflows are disabled by default in forked repositories."
echo "  You MUST enable them manually:"
echo ""
echo "  1. Go to: ${BLUE}https://github.com/$GITHUB_ORG/$GITHUB_REPO/actions${NC}"
echo "  2. Click the green button: 'I understand my workflows, go ahead and enable them'"
echo ""
echo "📝 Important: Use Your Forked Repository"
echo "  While using the self service portal in backstage after backstage deployment,"
echo "  use your forked repository, not the original to check for GitHub Actions PR etc!"
echo ""

