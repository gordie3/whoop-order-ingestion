import os
from typing import Any, Dict, Optional
import requests
import datetime
import json

DAILY_TRACKING_DB = os.getenv("DAILY_TRACKING_DB")
NOTION_INTEGRATION_TOKEN = os.getenv("NOTION_INTEGRATION_TOKEN")


def enter_sleep(
    date: str,
    recovery: int,
    performance: int,
    sleep_ms: int,
):
    print("Adding sleep into notion")
    payload = {
        "parent": {"database_id": DAILY_TRACKING_DB},
        "properties": {
            "Title": {
                "title": [
                    {
                        "text": {
                            "content": datetime.datetime.strptime(
                                date, "%Y-%m-%d"
                            ).strftime("%b %d")
                        }
                    }
                ]
            },
            "Date": {"date": {"start": date}},
            "Recovery": {"number": recovery * 0.01},
            "Sleep Performance": {"number": performance * 0.01},
            "Sleep Milliseconds": {"number": sleep_ms},
        },
    }

    existing_entry = _get_entry_for_date(date)
    if existing_entry:
        _update_entry(existing_entry["id"], payload)
    else:
        _create_entry(payload)
    print("Successfully added to notion")


def _get_entry_for_date(date: str) -> Optional[Dict[str, Any]]:
    body = {"filter": {"property": "Date", "date": {"equals": date}}}
    response = requests.post(
        f"https://api.notion.com/v1/databases/{DAILY_TRACKING_DB}/query",
        headers=_generate_headers(),
        data=json.dumps(body),
    )
    response.raise_for_status()
    response = response.json()
    results = response["results"]
    if len(results) > 0:
        return results[0]
    else:
        return None


def _create_entry(payload: Dict[str, Any]):
    print(f"Creating daily entry {payload}")
    response = requests.post(
        "https://api.notion.com/v1/pages",
        headers=_generate_headers(),
        data=json.dumps(payload),
    )
    response.raise_for_status()


def _update_entry(page_id: str, payload: Dict[str, Any]):
    print(f"Updating daily entry {page_id} with {payload}")
    response = requests.patch(
        f"https://api.notion.com/v1/pages/{page_id}",
        headers=_generate_headers(),
        data=json.dumps(payload),
    )
    response.raise_for_status()


def _generate_headers() -> Dict[str, Any]:
    return {
        "Authorization": f"Bearer {NOTION_INTEGRATION_TOKEN}",
        "Notion-Version": "2022-06-28",
        "Content-Type": "application/json",
    }
