# Backstage Access Methods

This guide explains how to access your Backstage deployment and when to use each method.

## Default: Port Forward (Recommended)

**Best for:** Development, testing, and deployments without a custom domain

### Access Backstage

```bash
# Port forward the Backstage service
kubectl port-forward svc/backstage 7007:7007 -n backstage

# Access in browser
open http://localhost:7007
```

### Advantages
✅ **No domain required** - Works immediately after deployment
✅ **No SSL issues** - Browsers don't force HTTPS upgrade on localhost
✅ **Secure** - Only accessible from your machine
✅ **Simple** - No additional AWS resources or configuration

### Disadvantages
❌ **Single user** - Only accessible from the machine running port-forward
❌ **Manual process** - Need to run kubectl command each time
❌ **No team sharing** - Can't share URL with team members

### When to Use
- Initial testing and evaluation
- Development environments
- Personal deployments
- When you don't have a custom domain

---

## Optional: Application Load Balancer with Custom Domain

**Best for:** Production deployments with team access

### Prerequisites

1. **Custom Domain**
   - You own a domain (e.g., `example.com`)
   - Can create DNS records (Route 53, Cloudflare, etc.)

2. **SSL Certificate**
   - AWS Certificate Manager (ACM) certificate
   - Validated for your domain

3. **AWS Load Balancer Controller**
   - Installed in EKS cluster (done by deploy script)

### Setup Steps

#### 1. Request ACM Certificate

```bash
# Request certificate
aws acm request-certificate \
  --domain-name backstage.example.com \
  --validation-method DNS \
  --region us-east-1

# Get certificate ARN
aws acm list-certificates --region us-east-1
```

#### 2. Validate Certificate

Add the CNAME records provided by ACM to your DNS:

```bash
# Get validation records
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

Add these records to your DNS provider (Route 53, Cloudflare, etc.).

#### 3. Update helm-values.yaml

Edit `backstage-setup/templates/helm-values.yaml` **before running deploy-backstage.sh**:

```yaml
ingress:
  enabled: true  # Change from false to true
  className: alb
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    # Enable HTTPS:
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    # Add your certificate ARN:
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:ACCOUNT:certificate/CERT_ID
    # Redirect HTTP to HTTPS:
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/healthcheck-path: /healthcheck
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=60
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30
  host: "backstage.example.com"  # Set your domain

appConfig:
  app:
    baseUrl: https://backstage.example.com  # Update to HTTPS with your domain
  
  backend:
    baseUrl: https://backstage.example.com  # Update to HTTPS with your domain
```

#### 4. Deploy or Update Backstage

**New deployment:**
```bash
cd backstage-setup/scripts
./deploy-backstage.sh backstage-platform
```

**Existing deployment:**
```bash
cd backstage-setup/scripts
./deploy-backstage.sh backstage-platform
```

#### 5. Create DNS Record

```bash
# Get ALB DNS name
ALB_DNS=$(kubectl get ingress backstage -n backstage -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "ALB DNS: $ALB_DNS"
```

Create a CNAME record in your DNS:
- **Name:** `backstage.example.com`
- **Type:** `CNAME`
- **Value:** `<ALB_DNS from above>`
- **TTL:** `300` (5 minutes)

**Route 53 Example:**
```bash
# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name example.com \
  --query 'HostedZones[0].Id' \
  --output text | cut -d'/' -f3)

# Create CNAME record
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "backstage.example.com",
        "Type": "CNAME",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
      }
    }]
  }'
```

#### 6. Access Backstage

Wait 2-5 minutes for:
- ALB to become healthy
- DNS propagation

Then access:
```
https://backstage.example.com
```

### Advantages
✅ **Team access** - Share URL with entire team
✅ **Production ready** - Proper SSL/TLS encryption
✅ **Always available** - No need to run port-forward
✅ **Professional** - Custom domain looks better

### Disadvantages
❌ **Requires domain** - Must own and manage a domain
❌ **SSL certificate** - Need to request and validate ACM certificate
❌ **Additional cost** - ALB costs ~$20-25/month
❌ **DNS management** - Need to create and maintain DNS records

### When to Use
- Production deployments
- Team environments
- When you have a custom domain
- When you need public access

---

## Comparison

| Feature | Port Forward | ALB + Domain |
|---------|-------------|--------------|
| **Setup Time** | 1 minute | 30-60 minutes |
| **Cost** | Free | ~$20-25/month |
| **Domain Required** | No | Yes |
| **SSL Certificate** | No | Yes |
| **Team Access** | No | Yes |
| **Always Available** | No | Yes |
| **Best For** | Dev/Test | Production |

---

## Switching Between Methods

### From Port Forward to ALB

1. Update `helm-values.yaml` with ingress configuration
2. Run `./deploy-backstage.sh backstage-platform`
3. Create DNS record
4. Access via custom domain

### From ALB to Port Forward

1. Update `helm-values.yaml`: set `ingress.enabled: false`
2. Run `./deploy-backstage.sh backstage-platform`
3. Use `kubectl port-forward` to access

---

## Troubleshooting

### Port Forward Issues

**Connection refused:**
```bash
# Check if pods are running
kubectl get pods -n backstage

# Check service
kubectl get svc -n backstage
```

**Port already in use:**
```bash
# Use a different local port
kubectl port-forward svc/backstage 8080:7007 -n backstage
# Access at http://localhost:8080
```

### ALB Issues

**ALB not created:**
```bash
# Check ingress status
kubectl describe ingress backstage -n backstage

# Check ALB controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

**Certificate errors:**
```bash
# Verify certificate is validated
aws acm describe-certificate \
  --certificate-arn <your-cert-arn> \
  --region us-east-1 \
  --query 'Certificate.Status'
# Should return: ISSUED
```

**DNS not resolving:**
```bash
# Check DNS propagation
dig backstage.example.com

# Check CNAME record
nslookup backstage.example.com
```

---

## Security Considerations

### Port Forward
- ✅ Secure - Only accessible from your machine
- ✅ No public exposure
- ⚠️ Requires kubectl access (which implies cluster admin)

### ALB + Domain
- ✅ SSL/TLS encryption
- ✅ AWS security groups control access
- ⚠️ Publicly accessible (consider adding authentication)
- ⚠️ Ensure proper authentication is configured in Backstage

---

## Recommendations

**For Development/Testing:**
- Use port-forward
- Simple, fast, secure
- No additional costs

**For Production:**
- Use ALB with custom domain
- Enable SSL/TLS
- Configure authentication (OAuth, SAML, etc.)
- Set up monitoring and alerting
- Consider adding WAF for additional security

---

## Next Steps

- **[Quick Start Guide](./QUICK-START.md)** - Deploy Backstage
- **[Usage Guide](./USAGE-GUIDE.md)** - Use the self-service portal
- **[Deployment Guide](./DEPLOYMENT-GUIDE.md)** - Advanced configuration
