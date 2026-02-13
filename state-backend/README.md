# Terraform State Backend (Bootstrap)

This directory bootstraps the **remote Terraform backend** used by the main
`infra/` stack:

- S3 bucket storing Terraform state (versioned, encrypted)
- DynamoDB table for state locking with point-in-time recovery (PITR)

> The main `infra/` configuration expects these resources to exist.

## Table of Contents

- [Resources](#resources)
- [One-Time Setup](#one-time-setup)
- [If You Change Names](#if-you-change-names)

## Resources

- S3 bucket: `backend-infra-tf-state`
  - Versioning enabled
  - Server-side encryption enabled
  - Public access blocked
- DynamoDB table: `backend-infra-tf-locks`
  - Primary key: `LockID` (string)
  - Billing mode: `PAY_PER_REQUEST`
  - PITR enabled

## One-Time Setup

Run this **once per account/region** to create the backend:

```bash
cd state-backend
terraform init
terraform apply -auto-approve
```

After this succeeds:

1. The S3 bucket and DynamoDB table exist.
2. The main `infra/` directory can safely use the configured `s3` backend.

Then, from `infra/`:

```bash
cd ../infra
terraform init   # will detect and (if needed) migrate state to S3
terraform plan
terraform apply
```

## If You Change Names

If you customize bucket/table names, update the backend block in `infra/` to
match, then re-run `terraform init`.
