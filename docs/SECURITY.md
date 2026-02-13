## Security Overview

This document summarizes the security posture of the baseline and how to extend
it for your production needs.

### Table of Contents

- [Data Protection](#data-protection)
- [Network Isolation](#network-isolation)
- [IAM and Least Privilege](#iam-and-least-privilege)
- [Auditing and Logs](#auditing-and-logs)
- [CI Security Scans](#ci-security-scans)
- [Hardening Suggestions](#hardening-suggestions)
- [What This Repo Does Not Do](#what-this-repo-does-not-do)

### Data Protection

- **At rest**: KMS encryption for RDS, Secrets Manager, and logs
- **In transit**: TLS termination at the ALB
- **Secrets**: stored in Secrets Manager and injected at runtime

### Network Isolation

- Databases and cache live in **private subnets**
- Only ALB is publicly reachable
- Security groups limit east-west traffic

### IAM and Least Privilege

- Separate task roles for ECS execution vs application access
- Rotation Lambdas have scoped permissions
- GitHub OIDC role restricts who can deploy

### Auditing and Logs

- CloudTrail records AWS API activity
- ALB, VPC flow logs, and ECS logs support incident response

### CI Security Scans

- **Semgrep** scans source for common security anti-patterns.
- **CodeQL** performs semantic security analysis on supported languages.
- **Bandit**, **Ruff**, and **Mypy** validate Python Lambda security and quality.

### Hardening Suggestions

- Add AWS WAF to protect against common attacks
- Enable GuardDuty and Security Hub
- Set IAM permissions to least privilege for your team
- Use customer-managed KMS keys for all sensitive services

### What This Repo Does Not Do

- It does not enforce organizational compliance standards
- It does not implement multi-tenant access control
- It does not include distributed, tenant-aware rate limiting policies by default

Treat this baseline as a secure foundation, then tighten further based on your
risk model and compliance requirements.
