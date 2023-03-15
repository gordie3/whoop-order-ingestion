import os
from dataclasses import dataclass
import hmac
import hashlib
import base64
import json
from typing import Any, Dict

import requests
import boto3

from notion import enter_sleep

SECRETS_MANAGER_ENDPOINT = os.getenv("SECRETS_MANAGER_ENDPOINT")
WHOOP_SECRET_ID = os.getenv("WHOOP_SECRET_ID")
WHOOP_CLIENT_SECRET = os.getenv("WHOOP_CLIENT_SECRET")
WHOOP_CLIENT_ID = os.getenv("WHOOP_CLIENT_ID")


@dataclass
class Webhook:
    """WHOOP webhook object."""

    user_id: int
    event_id: int
    event_type: str
    trace_id: str

    @classmethod
    def create_from_body(cls, body: str):
        body = json.loads(body)
        return cls(body["user_id"], body["id"], body["type"], body["trace_id"])


def verify_signature(signature: str, timestamp: str, body: str) -> bool:
    computed_signature = base64.b64encode(
        hmac.new(
            WHOOP_CLIENT_SECRET.encode("utf-8"),
            f"{timestamp}{body}".encode("utf-8"),
            hashlib.sha256,
        ).digest()
    ).decode("utf-8")
    return computed_signature == signature


def process_recovery(recovery_id: str):
    print(f"Processing recovery {recovery_id}")
    recovery_data = _get_recovery(recovery_id)
    if recovery_data["score_state"] != "SCORED":
        print("Recovery not scored")
        return

    # Load Sleep From WHOOP API
    sleep_data = _get_sleep(recovery_data["sleep_id"])
    sleep_score = sleep_data["score"]
    totat_sleep_ms = (
        sleep_score["stage_summary"]["total_in_bed_time_milli"]
        - sleep_score["stage_summary"]["total_awake_time_milli"]
    )

    # Create or update data
    enter_sleep(
        date=sleep_data["end"][:10],
        recovery=recovery_data["score"]["recovery_score"],
        performance=sleep_score["sleep_performance_percentage"],
        sleep_ms=totat_sleep_ms,
    )


def handle_webhook(webhook: Webhook):
    print("Handling webhook")
    if webhook.event_type == "recovery.updated":
        process_recovery(webhook.event_id)
    else:
        print("Not Handling Webhook")


def _get_recovery(recovery_cycle_id: str) -> Dict[str, Any]:
    print(f"Fetching recovery cycle {recovery_cycle_id}")
    return _execute_api(f"/v1/cycle/{recovery_cycle_id}/recovery")


def _get_sleep(sleep_id: str) -> Dict[str, Any]:
    print(f"Fetching sleep {sleep_id}")
    return _execute_api(f"/v1/activity/sleep/{sleep_id}")


def _execute_api(endpoint: str) -> Dict[str, Any]:
    service_client = boto3.client(
        "secretsmanager", endpoint_url=SECRETS_MANAGER_ENDPOINT
    )
    secret_value = service_client.get_secret_value(SecretId=WHOOP_SECRET_ID)
    secret = json.loads(secret_value["SecretString"])
    headers = {"Authorization": f'Bearer {secret["access_token"]}'}
    r = requests.get(f"https://api.prod.whoop.com/developer{endpoint}", headers=headers)
    r.raise_for_status()
    return r.json()


def refresh_token():
    print("refreshing token")
    service_client = boto3.client(
        "secretsmanager", endpoint_url=SECRETS_MANAGER_ENDPOINT
    )
    secret_value = service_client.get_secret_value(SecretId=WHOOP_SECRET_ID)
    secret = json.loads(secret_value["SecretString"])

    payload = f'grant_type=refresh_token&refresh_token={secret["refresh_token"]}&client_id={WHOOP_CLIENT_ID}&client_secret={WHOOP_CLIENT_SECRET}&scope=offline%20read:recovery%20read:cycles%20read:sleep%20read:workout%20read:profile%20read:body_measurement'
    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    r = requests.post(
        "https://api.prod.whoop.com/oauth/oauth2/token",
        headers=headers,
        data=payload,
    )
    r.raise_for_status()
    response = r.json()

    service_client.put_secret_value(
        SecretId=WHOOP_SECRET_ID,
        SecretString=json.dumps(
            {
                "access_token": response["access_token"],
                "refresh_token": response["refresh_token"],
            }
        ),
    )
    print("Rotated Secret")
