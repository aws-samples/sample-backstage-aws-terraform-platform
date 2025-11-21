# Backstage Template Defaults and Best Practices

This document explains the default values and design decisions for Backstage templates.

## Design Philosophy

Templates are designed to:
- **Minimize user input** - Only ask for essential information
- **Provide sensible defaults** - Match CloudFormation infrastructure
- **Be secure by default** - Private subnets, VPC-only access
- **Support customization** - Advanced users can override defaults

## EC2 Instance Template

### Required Fields
- **Instance Name** - Unique identifier for the instance
- **Environment** - dev, test, or staging
- **Owner** - Team or person responsible

### Smart Defaults

| Field | Default | Rationale |
|-------|---------|-----------|
| **Instance Type** | t3.micro | Cost-effective for testing |
| **AMI** | Latest Amazon Linux 2023 | Auto-selected, always current |
| **Volume Size** | 20 GB | Sufficient for most workloads |
| **VPC Name** | backstage-cluster-vpc | Matches CloudFormation VPC |
| **Subnet** | Auto-selected private subnet | Security best practice |
| **Security Group CIDR** | 10.0.0.0/16 | VPC CIDR - allows internal access only |

### Optional Fields
- **VPC ID** - Override VPC selection
- **Subnet ID** - Override subnet selection
- **Security Group Rules** - Add custom ingress rules

### IAM Role and Permissions

EC2 instances are automatically configured with:
- **IAM Role** - Created automatically for each instance
- **SSM Access** - `AmazonSSMManagedInstanceCore` policy attached by default
- **No Custom Policies** - For security, custom IAM policies are not supported
- **Access Method** - Use AWS Systems Manager Session Manager (no SSH keys needed)

**Why SSM-only?**
- Enhanced security - No SSH keys to manage
- Audit trail - All sessions logged in CloudTrail
- Compliance - Meets security requirements (CKV_AWS_107)
- Simplified - No need to manage custom IAM policies

If your application needs access to AWS services (S3, DynamoDB, etc.), consider:
- Using instance metadata service (IMDS) with the SSM role
- Requesting platform team to create a custom Terraform module
- Using AWS Secrets Manager for credentials

### Security Defaults
- ✅ Deployed in private subnet (no public IP)
- ✅ SSM access enabled by default (no SSH keys needed)
- ✅ IMDSv2 required (metadata security)
- ✅ Root volume encrypted (gp3)
- ✅ Security group allows VPC traffic only

## S3 Bucket Template

### Required Fields
- **Bucket Name** - Globally unique bucket name
- **Environment** - dev, test, or staging
- **Owner** - Team or person responsible

### Smart Defaults

| Field | Default | Rationale |
|-------|---------|-----------|
| **Versioning** | Disabled | Can be enabled if needed |
| **Encryption** | AES256 (S3-managed) | Secure by default |
| **Public Access** | Blocked | Security best practice |
| **Lifecycle Policy** | Disabled | Optional cost optimization |

### Optional Fields
- **Versioning** - Enable object versioning
- **Encryption Type** - Choose KMS if needed
- **Lifecycle Days** - Transition to IA storage
- **Additional Tags** - Custom metadata

### Security Defaults
- ✅ Block all public access
- ✅ Encryption at rest (AES256)
- ✅ Versioning available on demand
- ✅ Lifecycle policies for cost optimization

## RDS Database Template

### Required Fields
- **Database Identifier** - Unique identifier
- **Environment** - dev, test, or staging
- **Owner** - Team or person responsible

### Smart Defaults

| Field | Default | Rationale |
|-------|---------|-----------|
| **Engine** | PostgreSQL | Most common choice |
| **Engine Version** | PostgreSQL 15 | Stable LTS version |
| **Instance Class** | db.t3.micro | Cost-effective for testing |
| **Storage** | 20 GB gp3 | Sufficient for most apps |
| **Master Username** | admin | Standard convention |
| **Port** | 5432 (PostgreSQL) | Engine default |
| **Multi-AZ** | Disabled | Can enable for production |
| **Backup Retention** | 7 days | Balance cost and safety |
| **Publicly Accessible** | No | Security best practice |
| **Encryption** | Enabled | Security best practice |
| **Deletion Protection** | Disabled | Easier for dev/test cleanup |

### Optional Fields
- **VPC ID** - Override VPC selection
- **Subnet IDs** - Override subnet selection
- **Multi-AZ** - Enable for high availability
- **Backup Retention** - Adjust retention period
- **Storage Size** - Increase if needed

### Security Defaults
- ✅ Deployed in private subnets
- ✅ Not publicly accessible
- ✅ Encryption at rest enabled
- ✅ Automated backups (7 days)
- ✅ Password auto-generated and stored in Secrets Manager
- ✅ Security group allows VPC traffic only

## Repository Configuration (All Templates)

### Optional Fields
- **GitHub Organization** - Defaults to your forked org
- **GitHub Repository** - Defaults to your repository name (configured in CloudFormation parameters)

These fields allow users to:
- Use a different repository for Terraform code
- Support multi-repo setups
- Test changes in a separate repository

## Network Configuration

All templates use the CloudFormation-created VPC by default:

| Resource | Value |
|----------|-------|
| **VPC Name** | backstage-cluster-vpc |
| **VPC CIDR** | 10.0.0.0/16 |
| **Private Subnets** | Auto-selected (2 AZs) |
| **Public Subnets** | Not used for workloads |

### Subnet Selection Logic

1. **Try to find private subnets** - Looks for subnets with "private" in name
2. **Fallback to all subnets** - If no private subnets found
3. **User override** - Can specify exact subnet ID

## Best Practices for Users

### Naming Conventions
- Use descriptive names: `web-server-prod`, `api-db-staging`
- Include environment: `myapp-dev`, `myapp-prod`
- Avoid special characters except hyphens

### Security
- Keep default security settings unless you have specific needs
- Use VPC CIDR (10.0.0.0/16) for internal access
- Never use 0.0.0.0/0 unless absolutely necessary
- Review Terraform plan before merging

### Cost Optimization
- Start with smallest instance sizes (t3.micro, db.t3.micro)
- Enable lifecycle policies for S3 if storing large amounts of data
- Use Single-AZ RDS for dev/test (Multi-AZ for production)
- Clean up unused resources regularly

### Tagging
- Always specify an owner
- Use consistent environment names (dev, test, staging, prod)
- Add custom tags for cost allocation if needed

## Customization Guide

### For Platform Teams

To customize defaults for your organization:

1. **Edit template.yaml files** in `backstage-templates/`
2. **Update default values** to match your standards
3. **Add/remove fields** based on your requirements
4. **Update Terraform variables** if adding new fields
5. **Test thoroughly** before deploying

### Common Customizations

**Change default instance types:**
```yaml
instanceType:
  default: t3.small  # Instead of t3.micro
```

**Add required tags:**
```yaml
costCenter:
  title: Cost Center
  type: string
  description: Cost center for billing
```

**Change VPC defaults:**
```yaml
vpcName:
  default: my-company-vpc  # Instead of backstage-cluster-vpc
```

## Validation Rules

Templates include validation to prevent common errors:

### EC2
- Instance name: lowercase, numbers, hyphens only
- Security group ports: 1-65535
- CIDR blocks: valid IP ranges

### S3
- Bucket name: lowercase, numbers, hyphens only
- Max length: 63 characters
- Globally unique

### RDS
- DB identifier: lowercase, numbers, hyphens only
- Max length: 63 characters
- Must start with a letter

## Troubleshooting

### "No subnets found in VPC"
- Check VPC name matches CloudFormation VPC
- Verify VPC has subnets with "private" in the name
- Provide explicit subnet ID if needed

### "Bucket name already exists"
- S3 bucket names are globally unique
- Try a different name or add a suffix

### "Invalid CIDR block"
- Use valid IP ranges (e.g., 10.0.0.0/16, 192.168.1.0/24)
- Don't use 0.0.0.0/0 unless necessary

## Future Enhancements

Planned improvements:
- Dynamic VPC/subnet discovery
- Cost estimation in UI
- Template versioning
- Custom validation rules
- Integration with AWS Service Catalog

---

**Last Updated:** November 2025
**Maintained By:** Platform Team
