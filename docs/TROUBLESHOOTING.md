## Troubleshooting

Common issues and how to resolve them.

### Table of Contents

- [ALB Returns 503](#alb-returns-503)
- [ECS Tasks Crash Loop](#ecs-tasks-crash-loop)
- [Database Connection Failures](#database-connection-failures)
- [Valkey Session Errors](#valkey-session-errors)
- [OAuth Not Working](#oauth-not-working)
- [Terraform Apply Fails](#terraform-apply-fails)

### ALB Returns 503

**Possible causes:**
- ECS task not healthy
- Incorrect target group health check path
- Security group blocking traffic

**Checks:**
- Verify `/healthz` inside the container
- Check ECS task logs in CloudWatch
- Confirm the target group health check path is `/healthz`

### ECS Tasks Crash Loop

**Possible causes:**
- Missing env variables (`SECRET_KEY_BASE`, DB creds)
- Invalid DB host or credentials

**Checks:**
- Inspect task definition environment and secrets
- Check Secrets Manager values

### Database Connection Failures

**Possible causes:**
- RDS Proxy endpoint wrong
- Password rotated but tasks not restarted

**Checks:**
- Verify `DB_HOST` is the proxy endpoint
- Force ECS new deployment to refresh secrets

### Valkey Session Errors

**Possible causes:**
- Incorrect `VALKEY_URL`
- Auth token mismatch after rotation

**Checks:**
- Validate `VALKEY_URL` and `VALKEY_PASSWORD`
- Confirm rotation Lambda ran and ECS updated

### OAuth Not Working

**Possible causes:**
- Missing OAuth credentials
- Incorrect redirect URLs

**Checks:**
- Ensure OAuth secrets are present in Secrets Manager
- Verify callback URLs match your providers settings

### Terraform Apply Fails

**Possible causes:**
- Missing required variables
- IAM permission gaps

**Checks:**
- Run `terraform validate` locally
- Verify GitHub OIDC role permissions
