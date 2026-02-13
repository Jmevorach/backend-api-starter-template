# Rotation Lambda Sources

This directory contains the Python source for Secrets Manager rotation Lambdas.
Terraform packages each subdirectory into a ZIP at deploy time.

## Table of Contents

- [IAM Authentication](#iam-authentication)
- [Lambdas](#lambdas)
- [Runtime](#runtime)

## IAM Authentication

Database and ElastiCache now use **IAM authentication** instead of passwords:

- No database passwords to rotate
- No ElastiCache auth tokens to rotate
- Credentials derived from ECS task IAM role
- Only `SECRET_KEY_BASE` requires rotation

## Lambdas

- `secret_key_base_rotation/` – Rotates Phoenix `SECRET_KEY_BASE`

## Runtime

The rotation Lambda targets `python3.14`.
