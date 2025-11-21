# Backstage Self-Service Portal - Usage Guide

Quick guide for using Backstage to provision AWS resources through a simple web interface.

## Prerequisites

### Enable GitHub Actions Workflows

**⚠️ IMPORTANT:** Before using Backstage templates, you must enable GitHub Actions workflows in your forked repository.

GitHub disables workflows by default in forked repositories for security. To enable them:

1. Go to your forked repository: `https://github.com/YOUR_ORG/YOUR_REPO/actions`
2. You'll see a message: "Workflows aren't being run on this forked repository"
3. Click the green button: **"I understand my workflows, go ahead and enable them"**

Without this step, Backstage templates will create repositories and PRs, but Terraform won't run automatically.

---

## Accessing Backstage

**Default Method: Port Forward**

```bash
# Port forward to access Backstage locally
kubectl port-forward svc/backstage 7007:7007 -n backstage

# Access in browser at:
# http://localhost:7007
```

**With Custom Domain (Optional):**

If you configured a custom domain with ALB, access via your domain:
```
https://backstage.example.com
```

See [ACCESS-METHODS.md](./ACCESS-METHODS.md) for detailed setup instructions.

---

## Available Templates

Templates are automatically loaded from your forked repository (configured in helm-values.yaml).

Navigate to **Create** in Backstage - you should see three templates:
- **AWS EC2 Instance** - Virtual machines for application servers
- **AWS S3 Bucket** - Object storage for static assets and backups
- **AWS RDS Database** - Managed databases for applications

**Note:** Templates are automatically imported. No manual registration needed!

---

## Creating Resources - S3 Bucket Example

This walkthrough shows how to provision an S3 bucket using Backstage.

### Step 1: Select Template

Click **"Create"** in the left sidebar to see available templates.

*Available templates: EC2 Instance, S3 Bucket, RDS Database*

Select **"AWS S3 Bucket"** template.

### Step 2: Fill the Form

**Screen 1: Basic Information**

- Bucket Name: `random-bucket-1009876`
- Environment: `dev`, `staging`, or `prod`

**Screen 2: GitHub Configuration**


- GitHub Organization: Your org name
- Repository: Your repository name (as configured in CloudFormation)

**Screen 3: Review and Submit**


Click **"Create"** to generate the Pull Request.

### Step 3: View Pull Request


Click **"View Pull Request"** to open GitHub.

### Step 4: Review PR Changes


Review the files:
- `terraform.tfvars` - Your bucket configuration
- `backend.config` - Terraform state configuration

### Step 5: Check Terraform Plan


Wait for the Terraform plan check to complete.

### Step 6: Review Plan Output


Review the plan output:
- ✅ S3 bucket will be created
- ✅ Encryption enabled
- ✅ Versioning configured
- ✅ Public access blocked
- ✅ Tags applied

### Step 7: Merge Pull Request


Click **"Merge pull request"** to trigger deployment.

### Step 8: Terraform Apply


GitHub Actions automatically:
- Authenticates with AWS (OIDC)
- Applies Terraform configuration
- Creates the S3 bucket

### Step 9: Verify in AWS Console


Your bucket is now live with:
- ✅ Encryption enabled
- ✅ Versioning enabled
- ✅ Public access blocked
- ✅ Tags applied

### Fill the Form

1. **Basic Information**
   - Bucket Name: `random-bucket-1009876`
   - Environment: `dev`, `staging`, or `prod`

2. **Bucket Configuration**
   - Versioning: `Enabled` (recommended)
   - Encryption: `AES256` (default)
   - Public Access: `Blocked` (recommended)
   - Tags: Automatically applied

### Review and Submit

Click **"Create"** to generate the Pull Request.

### Review Pull Request

1. Review the Terraform plan showing:
   - S3 bucket with encryption
   - Versioning configuration
   - Public access block settings
   - Bucket policy (if specified)

2. Verify bucket name is unique and follows naming conventions

3. Merge the PR to create the bucket

### Verify S3 Bucket

```bash
# List buckets
aws s3 ls | grep my-app-assets

# Check bucket details
aws s3api get-bucket-versioning --bucket my-app-assets-dev
aws s3api get-bucket-encryption --bucket my-app-assets-dev

# Upload a test file
echo "Hello World" > test.txt
aws s3 cp test.txt s3://my-app-assets-dev/
```

---


## Managing Resources

### Updating Resources

1. Modify Terraform code in the repository
2. Create a PR with changes
3. Review the plan
4. Merge to apply

### Deleting Resources

1. Remove resource from Terraform code
2. Create PR with deletion
3. **Carefully review** the destruction plan
4. Merge to destroy

⚠️ **Warning:** Deletion is permanent! Ensure you have backups.


---

## Troubleshooting

### Template Not Found
- Ensure templates are registered in Backstage catalog
- Check GitHub integration is configured

### GitHub Actions Failed
- Check AWS credentials (OIDC)
- Verify IAM role permissions
- Review workflow logs

### Cannot Access Backstage
```bash
# Check status
kubectl get pods -n backstage
kubectl get ingress -n backstage

# View logs
kubectl logs -n backstage deployment/backstage --tail=100
```

### Database Connection Errors
- Verify RDS is running
- Check security groups
- Verify database credentials

---

## Workflow Summary

```
1. Fill Form (2-3 min)
   ↓
2. PR Created (instant)
   ↓
3. Review Plan (5-10 min)
   ↓
4. Merge PR (instant)
   ↓
5. Auto Deploy (2-5 min)
   ↓
6. Resource Ready ✅
```

**Total Time:** ~10-15 minutes

---

## Next Steps

1. **Create Your First Resource** - Start with an S3 bucket
2. **Explore Templates** - Review available options
3. **Follow Best Practices** - Use proper tagging and naming
4. **Provide Feedback** - Report issues and suggest improvements

---

## Additional Resources

- [Backstage Documentation](https://backstage.io/docs)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Deployment Guide](./DEPLOYMENT-GUIDE.md)
- [Quick Start Guide](./QUICK-START.md)

---

**Happy Building! 🚀**
