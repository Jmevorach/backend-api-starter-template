"""Rotate Phoenix SECRET_KEY_BASE with Secrets Manager."""

from __future__ import annotations

import logging
import os
import secrets
import string
from typing import TYPE_CHECKING, Final, TypedDict

import boto3
from botocore.exceptions import ClientError

if TYPE_CHECKING:
    from mypy_boto3_ecs import ECSClient
    from mypy_boto3_secretsmanager import SecretsManagerClient

LOGGER = logging.getLogger(__name__)
LOGGER.setLevel(logging.INFO)

HTTP_STATUS_OK: Final[int] = 200
SECRET_LENGTH: Final[int] = 64

STEP_CREATE_SECRET: Final[str] = "createSecret"  # noqa: S105
STEP_SET_SECRET: Final[str] = "setSecret"  # noqa: S105
STEP_TEST_SECRET: Final[str] = "testSecret"  # noqa: S105
STEP_FINISH_SECRET: Final[str] = "finishSecret"  # noqa: S105

VERSION_STAGE_PENDING: Final[str] = "AWSPENDING"
VERSION_STAGE_CURRENT: Final[str] = "AWSCURRENT"

ENV_ECS_CLUSTER: Final[str] = "ECS_CLUSTER"
ENV_ECS_SERVICE: Final[str] = "ECS_SERVICE"


class RotationEvent(TypedDict):
    """Define the subset of the Secrets Manager rotation event payload."""

    SecretId: str
    ClientRequestToken: str
    Step: str


def _secrets_client() -> SecretsManagerClient:
    return boto3.client("secretsmanager")


def _ecs_client() -> ECSClient:
    return boto3.client("ecs")


def _get_secret_string(
    secrets_client: SecretsManagerClient,
    secret_arn: str,
    *,
    version_stage: str | None = None,
) -> str:
    request: dict[str, str] = {"SecretId": secret_arn}
    if version_stage:
        request["VersionStage"] = version_stage

    response = secrets_client.get_secret_value(**request)
    secret_string = response.get("SecretString")
    # SecretString is optional (could be SecretBinary), but stubs type it as required
    if secret_string is None:
        error_message = f"SecretString is missing for secret {secret_arn}"  # type: ignore[unreachable]
        raise TypeError(error_message)
    return secret_string


def _current_version_id(secrets_client: SecretsManagerClient, secret_arn: str) -> str:
    response = secrets_client.describe_secret(SecretId=secret_arn)
    version_map = response.get("VersionIdsToStages")
    # VersionIdsToStages is optional per AWS docs, but stubs type it as required
    if version_map is None:
        error_message = f"VersionIdsToStages missing for secret {secret_arn}"  # type: ignore[unreachable]
        raise TypeError(error_message)

    for version_id, stages in version_map.items():
        if VERSION_STAGE_CURRENT in stages:
            return version_id

    error_message = f"AWSCURRENT version not found for secret {secret_arn}"
    raise ValueError(error_message)


def _handle_create_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
    token: str,
) -> None:
    alphabet = string.ascii_letters + string.digits + "_%@"
    new_secret = "".join(secrets.choice(alphabet) for _ in range(SECRET_LENGTH))

    secrets_client.put_secret_value(
        SecretId=secret_arn,
        ClientRequestToken=token,
        SecretString=new_secret,
        VersionStages=[VERSION_STAGE_PENDING],
    )
    LOGGER.info("Created new SECRET_KEY_BASE for %s", secret_arn)


def _handle_set_secret() -> None:
    LOGGER.info("SECRET_KEY_BASE setSecret step (no action needed)")


def _handle_test_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
) -> None:
    new_secret = _get_secret_string(
        secrets_client,
        secret_arn,
        version_stage=VERSION_STAGE_PENDING,
    )
    if len(new_secret) < SECRET_LENGTH:
        error_message = (
            f"SECRET_KEY_BASE must be at least {SECRET_LENGTH} characters, got {len(new_secret)}"
        )
        raise ValueError(error_message)
    LOGGER.info("New SECRET_KEY_BASE format validated")


def _handle_finish_secret(
    secrets_client: SecretsManagerClient,
    *,
    secret_arn: str,
    token: str,
) -> None:
    current_version_id = _current_version_id(secrets_client, secret_arn)

    secrets_client.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage=VERSION_STAGE_CURRENT,
        MoveToVersionId=token,
        RemoveFromVersionId=current_version_id,
    )
    LOGGER.info("Successfully rotated SECRET_KEY_BASE for %s", secret_arn)

    ecs_cluster = os.environ.get(ENV_ECS_CLUSTER)
    ecs_service = os.environ.get(ENV_ECS_SERVICE)
    if ecs_cluster and ecs_service:
        try:
            ecs_client = _ecs_client()
            ecs_client.update_service(
                cluster=ecs_cluster,
                service=ecs_service,
                forceNewDeployment=True,
            )
            LOGGER.info("Triggered ECS service update")
        except ClientError as exc:
            LOGGER.warning("Could not trigger ECS update: %s", exc)


def lambda_handler(event: RotationEvent, _context: object) -> dict[str, int]:
    """Handle Secrets Manager rotation steps for SECRET_KEY_BASE."""
    secrets_client = _secrets_client()

    secret_arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]

    if step == STEP_CREATE_SECRET:
        _handle_create_secret(secrets_client, secret_arn=secret_arn, token=token)
    elif step == STEP_SET_SECRET:
        _handle_set_secret()
    elif step == STEP_TEST_SECRET:
        _handle_test_secret(secrets_client, secret_arn=secret_arn)
    elif step == STEP_FINISH_SECRET:
        _handle_finish_secret(secrets_client, secret_arn=secret_arn, token=token)
    else:
        LOGGER.warning("Unknown rotation step: %s", step)

    return {"statusCode": HTTP_STATUS_OK}
