"""Database Password Rotation Lambda.

This Lambda function rotates the database password in Secrets Manager
and updates the RDS cluster master password.

Rotation Steps:
1. createSecret: Generate new password and store in AWSPENDING
2. setSecret: Update RDS cluster master password
3. testSecret: Verify new password works (optional)
4. finishSecret: Promote AWSPENDING to AWSCURRENT

Environment Variables:
- RDS_CLUSTER_IDENTIFIER: The RDS cluster identifier
- ECS_CLUSTER: ECS cluster name (for triggering deployment)
- ECS_SERVICE: ECS service name (for triggering deployment)
"""

from __future__ import annotations

import json
import logging
import os
import secrets
import string
from typing import TYPE_CHECKING, Final, TypedDict

import boto3
from botocore.exceptions import ClientError

if TYPE_CHECKING:
    from mypy_boto3_ecs import ECSClient
    from mypy_boto3_rds import RDSClient
    from mypy_boto3_secretsmanager import SecretsManagerClient

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)

# Password generation constants
PASSWORD_LENGTH: Final[int] = 32
# RDS passwords: 8-128 chars, printable ASCII except /, @, ", space
PASSWORD_ALPHABET: Final[str] = string.ascii_letters + string.digits + "!#$%&()*+,-.;<=>?[]^_`{|}~"

# Rotation step constants
STEP_CREATE_SECRET: Final[str] = "createSecret"  # noqa: S105
STEP_SET_SECRET: Final[str] = "setSecret"  # noqa: S105
STEP_TEST_SECRET: Final[str] = "testSecret"  # noqa: S105
STEP_FINISH_SECRET: Final[str] = "finishSecret"  # noqa: S105

# Version stage constants
VERSION_STAGE_PENDING: Final[str] = "AWSPENDING"
VERSION_STAGE_CURRENT: Final[str] = "AWSCURRENT"

# Environment variable names
ENV_RDS_CLUSTER_IDENTIFIER: Final[str] = "RDS_CLUSTER_IDENTIFIER"
ENV_ECS_CLUSTER: Final[str] = "ECS_CLUSTER"
ENV_ECS_SERVICE: Final[str] = "ECS_SERVICE"


class RotationEvent(TypedDict):
    """Define the subset of the Secrets Manager rotation event payload."""

    SecretId: str
    ClientRequestToken: str
    Step: str


def _secrets_client() -> SecretsManagerClient:
    """Create a Secrets Manager client."""
    return boto3.client("secretsmanager")


def _rds_client() -> RDSClient:
    """Create an RDS client."""
    return boto3.client("rds")


def _ecs_client() -> ECSClient:
    """Create an ECS client."""
    return boto3.client("ecs")


def _check_rotation_enabled(
    secrets_client: SecretsManagerClient,
    secret_arn: str,
) -> dict[str, list[str]]:
    """Verify secret has rotation enabled and return version stages."""
    metadata = secrets_client.describe_secret(SecretId=secret_arn)
    if not metadata.get("RotationEnabled"):
        msg = f"Secret {secret_arn} is not enabled for rotation"
        raise ValueError(msg)
    return metadata.get("VersionIdsToStages", {})


def _validate_token_stages(
    versions: dict[str, list[str]],
    token: str,
    secret_arn: str,
) -> list[str] | None:
    """Validate token has correct version stages for rotation."""
    if token not in versions:
        msg = f"Secret version {token} has no stage for rotation of secret {secret_arn}"
        raise ValueError(msg)

    stages = versions[token]
    if VERSION_STAGE_CURRENT in stages:
        LOGGER.info("Secret version %s already set as AWSCURRENT", token)
        return None

    if VERSION_STAGE_PENDING not in stages:
        msg = f"Secret version {token} not set as AWSPENDING for rotation"
        raise ValueError(msg)

    return stages


def _handle_create_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
    token: str,
) -> None:
    """Generate a new password and store it as AWSPENDING."""
    # Check if AWSPENDING version already exists
    try:
        secrets_client.get_secret_value(
            SecretId=secret_arn,
            VersionId=token,
            VersionStage=VERSION_STAGE_PENDING,
        )
    except secrets_client.exceptions.ResourceNotFoundException:
        pass
    else:
        LOGGER.info("AWSPENDING version already exists, using existing secret")
        return

    # Generate new password
    new_password = "".join(secrets.choice(PASSWORD_ALPHABET) for _ in range(PASSWORD_LENGTH))

    # Store the new password as AWSPENDING
    secrets_client.put_secret_value(
        SecretId=secret_arn,
        ClientRequestToken=token,
        SecretString=new_password,
        VersionStages=[VERSION_STAGE_PENDING],
    )
    LOGGER.info("Created new secret version %s", token)


def _handle_set_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
    token: str,
) -> None:
    """Update the RDS cluster with the new password."""
    # Get the pending password
    response = secrets_client.get_secret_value(
        SecretId=secret_arn,
        VersionId=token,
        VersionStage=VERSION_STAGE_PENDING,
    )
    new_password = response["SecretString"]

    # Get cluster identifier from environment
    cluster_id = os.environ.get(ENV_RDS_CLUSTER_IDENTIFIER)
    if not cluster_id:
        msg = f"{ENV_RDS_CLUSTER_IDENTIFIER} environment variable not set"
        raise ValueError(msg)

    # Update RDS cluster master password
    try:
        rds_client = _rds_client()
        rds_client.modify_db_cluster(
            DBClusterIdentifier=cluster_id,
            MasterUserPassword=new_password,
            ApplyImmediately=True,
        )
        LOGGER.info("Updated RDS cluster %s master password", cluster_id)
    except ClientError:
        LOGGER.exception("Failed to update RDS password")
        raise


def _handle_test_secret() -> None:
    """Test the new password (optional - we rely on RDS API success)."""
    # For simplicity, we trust the RDS modify operation succeeded
    # A more thorough test would attempt a database connection
    LOGGER.info("Test step: trusting RDS modify operation succeeded")


def _handle_finish_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
    token: str,
) -> None:
    """Promote AWSPENDING to AWSCURRENT and trigger ECS deployment."""
    # Get current version
    metadata = secrets_client.describe_secret(SecretId=secret_arn)
    versions = metadata.get("VersionIdsToStages", {})

    current_version = None
    for version_id, stages in versions.items():
        if VERSION_STAGE_CURRENT in stages and version_id != token:
            current_version = version_id
            break

    # Move AWSCURRENT to the new version
    update_kwargs: dict[str, str] = {
        "SecretId": secret_arn,
        "VersionStage": VERSION_STAGE_CURRENT,
        "MoveToVersionId": token,
    }
    if current_version is not None:
        update_kwargs["RemoveFromVersionId"] = current_version
    secrets_client.update_secret_version_stage(**update_kwargs)
    LOGGER.info("Secret version %s is now AWSCURRENT", token)

    # Trigger ECS service update to pick up new password
    _trigger_ecs_deployment()


def _trigger_ecs_deployment() -> None:
    """Force ECS service to restart with new secret value."""
    cluster = os.environ.get(ENV_ECS_CLUSTER)
    service = os.environ.get(ENV_ECS_SERVICE)

    if not cluster or not service:
        LOGGER.warning("ECS_CLUSTER or ECS_SERVICE not set, skipping deployment")
        return

    try:
        ecs_client = _ecs_client()
        ecs_client.update_service(
            cluster=cluster,
            service=service,
            forceNewDeployment=True,
        )
        LOGGER.info("Triggered ECS deployment for %s/%s", cluster, service)
    except ClientError:
        LOGGER.exception("Failed to trigger ECS deployment")
        # Don't raise - secret rotation succeeded, deployment can be retried


def lambda_handler(event: RotationEvent, _context: object) -> None:
    """Handle Secrets Manager rotation steps for database password."""
    LOGGER.info("Rotation event: %s", json.dumps(event))

    secrets_client = _secrets_client()
    secret_arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    # Validate rotation is enabled and get version stages
    versions = _check_rotation_enabled(secrets_client, secret_arn)

    # Validate token has correct stages
    stages = _validate_token_stages(versions, token, secret_arn)
    if stages is None:
        return

    # Execute the rotation step
    if step == STEP_CREATE_SECRET:
        _handle_create_secret(secrets_client, secret_arn=secret_arn, token=token)
    elif step == STEP_SET_SECRET:
        _handle_set_secret(secrets_client, secret_arn=secret_arn, token=token)
    elif step == STEP_TEST_SECRET:
        _handle_test_secret()
    elif step == STEP_FINISH_SECRET:
        _handle_finish_secret(secrets_client, secret_arn=secret_arn, token=token)
    else:
        msg = f"Invalid step: {step}"
        raise ValueError(msg)
