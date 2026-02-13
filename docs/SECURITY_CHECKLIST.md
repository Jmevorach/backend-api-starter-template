# Security Checklist

Use this checklist before deploying to production or during security reviews.

## Table of Contents

- [Pre-Deployment Checklist](#pre-deployment-checklist)
- [Post-Deployment Verification](#post-deployment-verification)
- [Incident Response Quick Reference](#incident-response-quick-reference)
- [Regular Security Tasks](#regular-security-tasks)
- [Resources](#resources)

---

## Pre-Deployment Checklist

### Secrets & Credentials

- [ ] All secrets stored in AWS Secrets Manager
- [ ] No hardcoded credentials in code
- [ ] No secrets in environment variables (use Secrets Manager references)
- [ ] Secret rotation enabled for:
  - [ ] Database password
  - [ ] SECRET_KEY_BASE
  - [ ] ElastiCache auth token
- [ ] API keys rotated since development
- [ ] Default passwords changed

### Authentication & Authorization

- [ ] OAuth providers configured correctly
- [ ] OAuth redirect URIs are production URLs only
- [ ] Session timeout configured appropriately
- [ ] CSRF protection enabled
- [ ] Protected endpoints require authentication
- [ ] API rate limiting configured

### Network Security

- [ ] Database in private subnet (no public access)
- [ ] ElastiCache in private subnet
- [ ] ECS tasks in private subnet
- [ ] Security groups follow least privilege
- [ ] VPC Flow Logs enabled
- [ ] TLS 1.2+ enforced on all endpoints
- [ ] HTTPS redirect enabled on ALB

### Data Protection

- [ ] RDS encryption at rest enabled
- [ ] ElastiCache encryption at rest enabled
- [ ] S3 bucket encryption enabled (if used)
- [ ] KMS keys configured for encryption
- [ ] Backup encryption enabled
- [ ] TLS for data in transit

### Logging & Monitoring

- [ ] CloudWatch Logs configured
- [ ] CloudTrail enabled
- [ ] VPC Flow Logs enabled
- [ ] Alarms configured for:
  - [ ] High error rates
  - [ ] High latency
  - [ ] Resource utilization
  - [ ] Failed login attempts
- [ ] Log retention policy set

### Application Security

- [ ] Dependencies up to date
- [ ] No known vulnerabilities (mix audit)
- [ ] Input validation on all endpoints
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (content security policy)
- [ ] Error messages don't leak sensitive info

### Infrastructure

- [ ] Terraform state encrypted
- [ ] Terraform state in private S3 bucket
- [ ] IAM roles follow least privilege
- [ ] No IAM users with static credentials (use roles)
- [ ] Multi-AZ deployment enabled
- [ ] Auto-scaling configured

### CI/CD Security

- [ ] GitHub Actions uses OIDC (no static AWS credentials)
- [ ] Branch protection enabled on main
- [ ] Code review required for merges
- [ ] Security scanning in CI pipeline:
  - [ ] Dependency audit
  - [ ] SAST (static analysis)
  - [ ] Terraform security scan
  - [ ] Container image scan

---

## Post-Deployment Verification

### Connectivity Tests

```bash
# Health check
curl -k https://your-domain.com/healthz

# Should return 401 (not 500)
curl -k https://your-domain.com/api/me

# Should return service info
curl -k https://your-domain.com/
```

### Security Headers Check

```bash
curl -I https://your-domain.com/
```

Expected headers:
- `Strict-Transport-Security`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY` or `SAMEORIGIN`

### SSL/TLS Check

```bash
# Check TLS configuration
nmap --script ssl-enum-ciphers -p 443 your-domain.com

# Or use online tool:
# https://www.ssllabs.com/ssltest/
```

Expected:
- TLS 1.2 or 1.3 only
- Strong cipher suites
- Valid certificate chain

### Database Access Test

```bash
# Should fail (database not publicly accessible)
psql -h your-rds-endpoint.amazonaws.com -U postgres

# Expected: Connection timeout or refused
```

---

## Incident Response Quick Reference

### Security Incident Detected

1. **Contain** - Isolate affected systems
2. **Assess** - Determine scope and impact
3. **Notify** - Alert stakeholders per policy
4. **Investigate** - Gather logs and evidence
5. **Remediate** - Fix the vulnerability
6. **Recover** - Restore normal operations
7. **Review** - Post-incident analysis

### Useful Commands

```bash
# Check CloudTrail for suspicious activity
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --start-time $(date -d '24 hours ago' --iso-8601=seconds)

# Check VPC Flow Logs
aws logs filter-log-events \
  --log-group-name /aws/vpc/flow-logs \
  --filter-pattern "REJECT"

# List IAM access keys
aws iam list-access-keys --user-name suspicious-user

# Rotate compromised secret
aws secretsmanager rotate-secret --secret-id compromised-secret
```

### Emergency Contacts

| Role | Contact |
|------|---------|
| Security Lead | TBD |
| DevOps On-call | TBD |
| AWS Support | https://console.aws.amazon.com/support |

---

## Regular Security Tasks

### Weekly

- [ ] Review CloudWatch alarms
- [ ] Check for failed deployments
- [ ] Review dependency vulnerability alerts

### Monthly

- [ ] Update dependencies
- [ ] Review access logs for anomalies
- [ ] Test backup restoration
- [ ] Review security group rules

### Quarterly

- [ ] Rotate access keys (if any exist)
- [ ] Review IAM policies
- [ ] Review user access
- [ ] Update security documentation

### Annually

- [ ] Penetration testing
- [ ] Security training for team
- [ ] Full security audit
- [ ] Review and update policies

---

## Resources

- [AWS Security Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [Phoenix Security Guide](https://hexdocs.pm/phoenix/security.html)
- [Elixir Security Guide](https://hexdocs.pm/elixir/security.html)
