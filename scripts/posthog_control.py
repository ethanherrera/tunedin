#!/usr/bin/env python3
"""Validate and operate the single approved tunedIn PostHog Staging project."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "observability" / "posthog" / "staging.json"
APPROVED_PROJECT_ID = 507318
APPLY_CONFIRMATION = "staging-507318"


class PostHogContractError(RuntimeError):
    """A safe, actionable configuration or drift failure."""


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise PostHogContractError(f"Could not load {path}: {error}") from error


def _balanced_body(source: str, opening_index: int, opening: str = "{") -> str:
    closing = {"{": "}", "[": "]"}[opening]
    depth = 0
    in_string = False
    escaped = False
    for index in range(opening_index, len(source)):
        character = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == opening:
            depth += 1
        elif character == closing:
            depth -= 1
            if depth == 0:
                return source[opening_index + 1 : index]
    raise PostHogContractError(f"Unbalanced {opening}{closing} in Swift telemetry source")


def parse_swift_string_enum(source: str, enum_name: str) -> dict[str, str]:
    match = re.search(rf"\benum\s+{re.escape(enum_name)}\s*:[^{{]+{{", source)
    if not match:
        raise PostHogContractError(f"Could not find Swift enum {enum_name}")
    body = _balanced_body(source, match.end() - 1)
    values: dict[str, str] = {}
    for case_name, raw_value in re.findall(
        r"^\s*case\s+(\w+)(?:\s*=\s*\"([^\"]+)\")?\s*$",
        body,
        flags=re.MULTILINE,
    ):
        values[case_name] = raw_value or case_name
    if not values:
        raise PostHogContractError(f"Swift enum {enum_name} contains no string cases")
    return values


def _property_array(source: str, marker: str) -> list[str]:
    marker_index = source.find(marker)
    if marker_index < 0:
        raise PostHogContractError(f"Could not find {marker} in TelemetrySanitizer")
    opening_index = source.find("[", source.find("=", marker_index))
    if opening_index < 0:
        raise PostHogContractError(f"Could not parse {marker} in TelemetrySanitizer")
    return re.findall(r"\.(\w+)", _balanced_body(source, opening_index, "["))


def parse_sanitizer_contract(
    source: str,
    event_cases: dict[str, str],
    property_cases: dict[str, str],
) -> tuple[list[str], dict[str, list[str]]]:
    common_case_names = _property_array(source, "private static let commonProperties")
    common = [property_cases[name] for name in common_case_names]

    marker = "private static let eventProperties"
    marker_index = source.find(marker)
    opening_index = source.find("[", source.find("=", marker_index))
    dictionary_body = _balanced_body(source, opening_index, "[")
    result: dict[str, list[str]] = {}
    for case_name, raw_event_name in event_cases.items():
        entry = re.search(rf"\.{re.escape(case_name)}\s*:\s*\[", dictionary_body)
        if not entry:
            raise PostHogContractError(f"TelemetrySanitizer has no property contract for {raw_event_name}")
        property_body = _balanced_body(dictionary_body, entry.end() - 1, "[")
        result[raw_event_name] = [
            property_cases[name] for name in re.findall(r"\.(\w+)", property_body)
        ]
    return common, result


def _require_exact_keys(value: dict[str, Any], expected: set[str], label: str) -> None:
    actual = set(value)
    if actual != expected:
        raise PostHogContractError(
            f"{label} keys differ: missing={sorted(expected - actual)}, extra={sorted(actual - expected)}"
        )


def validate_manifest(
    manifest: dict[str, Any],
    repository_root: Path = REPOSITORY_ROOT,
) -> None:
    _require_exact_keys(
        manifest,
        {
            "schema_version",
            "environment",
            "project",
            "privacy_settings",
            "sdk_policy",
            "contract",
            "managed_dashboard",
        },
        "manifest",
    )
    if manifest["schema_version"] != 1 or manifest["environment"] != "Staging":
        raise PostHogContractError("Only schema version 1 for Staging is supported")

    project = manifest["project"]
    expected_project = {
        "id": APPROVED_PROJECT_ID,
        "name": "tunedIn Staging",
        "api_host": "https://us.posthog.com",
        "ingestion_host": "https://us.i.posthog.com",
    }
    if project != expected_project:
        raise PostHogContractError(
            f"Manifest must target only the approved Staging project {APPROVED_PROJECT_ID}"
        )

    expected_privacy = {
        "anonymize_ips": True,
        "autocapture_opt_out": True,
        "autocapture_exceptions_opt_in": False,
        "autocapture_web_vitals_opt_in": False,
        "capture_console_log_opt_in": False,
        "session_recording_opt_in": False,
        "inject_web_apps": False,
        "heatmaps_opt_in": False,
    }
    if manifest["privacy_settings"] != expected_privacy:
        raise PostHogContractError("Staging privacy settings must match the restrictive approved policy")

    expected_sdk_policy = {
        "application_lifecycle_events": False,
        "automatic_screen_views": False,
        "element_interactions": False,
        "session_replay": False,
        "surveys": False,
        "feature_flags": False,
        "exception_autocapture": True,
        "person_profiles": "identified_only",
        "user_content_allowed": False,
    }
    if manifest["sdk_policy"] != expected_sdk_policy:
        raise PostHogContractError("SDK policy differs from the approved explicit-only collection policy")

    models_path = repository_root / "ios/tunedIn/Sources/Core/Telemetry/TelemetryModels.swift"
    sanitizer_path = repository_root / "ios/tunedIn/Sources/Core/Telemetry/TelemetrySanitizer.swift"
    models = models_path.read_text(encoding="utf-8")
    sanitizer = sanitizer_path.read_text(encoding="utf-8")
    event_cases = parse_swift_string_enum(models, "TelemetryEvent")
    property_cases = parse_swift_string_enum(models, "TelemetryProperty")
    log_cases = parse_swift_string_enum(models, "TelemetryLogMessage")
    operation_cases = parse_swift_string_enum(models, "TelemetryOperation")
    screen_cases = parse_swift_string_enum(models, "TelemetryScreen")
    common, event_properties = parse_sanitizer_contract(sanitizer, event_cases, property_cases)

    contract = manifest["contract"]
    if set(contract["event_properties"]) != set(event_cases.values()):
        raise PostHogContractError("Tracked event names differ from TelemetryEvent")
    if contract["common_properties"] != common:
        raise PostHogContractError("Tracked common properties differ from TelemetrySanitizer")
    for event_name, properties in event_properties.items():
        if contract["event_properties"][event_name] != properties:
            raise PostHogContractError(
                f"Tracked properties for {event_name} differ from TelemetrySanitizer"
            )
    declared_properties = set(contract["common_properties"])
    for properties in contract["event_properties"].values():
        declared_properties.update(properties)
    if declared_properties != set(property_cases.values()):
        raise PostHogContractError("Tracked property allow-list differs from TelemetryProperty")
    if contract["log_messages"] != list(log_cases.values()):
        raise PostHogContractError("Tracked log messages differ from TelemetryLogMessage")
    if contract["operations"] != list(operation_cases.values()):
        raise PostHogContractError("Tracked operations differ from TelemetryOperation")
    if contract["screens"] != list(screen_cases.values()):
        raise PostHogContractError("Tracked screens differ from TelemetryScreen")

    dashboard = manifest["managed_dashboard"]
    insight_names = [insight["name"] for insight in dashboard["insights"]]
    if len(insight_names) != len(set(insight_names)) or not insight_names:
        raise PostHogContractError("Managed insight names must be non-empty and unique")
    serialized_queries = json.dumps([item["query"] for item in dashboard["insights"]])
    for referenced_event in re.findall(r'"event":\s*"([^\"]+)"', serialized_queries):
        if referenced_event not in contract["event_properties"]:
            raise PostHogContractError(f"Dashboard references undeclared event {referenced_event}")


def project_drift(manifest: dict[str, Any], project: dict[str, Any]) -> list[str]:
    drift: list[str] = []
    expected_project = manifest["project"]
    if project.get("id") != expected_project["id"]:
        drift.append("project.id")
    if project.get("name") != expected_project["name"]:
        drift.append("project.name")
    for key, value in manifest["privacy_settings"].items():
        if project.get(key) != value:
            drift.append(f"privacy_settings.{key}")
    return drift


def _is_subset(expected: Any, actual: Any) -> bool:
    if isinstance(expected, dict):
        return isinstance(actual, dict) and all(
            key in actual and _is_subset(value, actual[key]) for key, value in expected.items()
        )
    if isinstance(expected, list):
        return isinstance(actual, list) and len(expected) == len(actual) and all(
            _is_subset(left, right) for left, right in zip(expected, actual)
        )
    return expected == actual


class PostHogAPI:
    def __init__(self, host: str, key: str) -> None:
        self.host = host.rstrip("/")
        self.key = key

    def request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            f"{self.host}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.key}",
                "Content-Type": "application/json",
                "User-Agent": "tunedIn-posthog-control/1",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            raise PostHogContractError(
                f"PostHog {method} {path} failed with HTTP {error.code}"
            ) from error
        except urllib.error.URLError as error:
            raise PostHogContractError(f"Could not reach the PostHog Management API: {error.reason}") from error


def _management_key() -> str:
    if value := os.environ.get("POSTHOG_PERSONAL_API_KEY", "").strip():
        return value
    if sys.platform == "darwin":
        result = subprocess.run(
            ["security", "find-generic-password", "-s", "tunedin/posthog/management-api", "-w"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()
    raise PostHogContractError(
        "Set POSTHOG_PERSONAL_API_KEY or add macOS Keychain item tunedin/posthog/management-api"
    )


def _list_results(api: PostHogAPI, path: str) -> list[dict[str, Any]]:
    response = api.request("GET", path)
    if not isinstance(response, dict) or not isinstance(response.get("results"), list):
        raise PostHogContractError(f"PostHog returned an unexpected collection for {path}")
    return response["results"]


def hosted_drift(manifest: dict[str, Any], api: PostHogAPI) -> list[str]:
    project_id = manifest["project"]["id"]
    drift = project_drift(manifest, api.request("GET", f"/api/projects/{project_id}/"))
    dashboards = _list_results(api, f"/api/environments/{project_id}/dashboards/?limit=100")
    expected_dashboard = manifest["managed_dashboard"]
    dashboard = next((item for item in dashboards if item.get("name") == expected_dashboard["name"]), None)
    if dashboard is None:
        return drift + ["managed_dashboard.missing"]
    for key in ("description", "pinned"):
        if dashboard.get(key) != expected_dashboard[key]:
            drift.append(f"managed_dashboard.{key}")
    if set(dashboard.get("tags", [])) != set(expected_dashboard["tags"]):
        drift.append("managed_dashboard.tags")

    insights = _list_results(api, f"/api/environments/{project_id}/insights/?limit=100")
    for expected in expected_dashboard["insights"]:
        insight = next((item for item in insights if item.get("name") == expected["name"]), None)
        if insight is None:
            drift.append(f"managed_insight.{expected['name']}.missing")
            continue
        detail = api.request("GET", f"/api/environments/{project_id}/insights/{insight['id']}/")
        if detail.get("description") != expected["description"]:
            drift.append(f"managed_insight.{expected['name']}.description")
        if not _is_subset(expected["query"], detail.get("query")):
            drift.append(f"managed_insight.{expected['name']}.query")
        if dashboard["id"] not in detail.get("dashboards", []):
            drift.append(f"managed_insight.{expected['name']}.dashboard")
    return drift


def apply_manifest(manifest: dict[str, Any], api: PostHogAPI) -> None:
    if os.environ.get("POSTHOG_CONFIRM_APPLY") != APPLY_CONFIRMATION:
        raise PostHogContractError(
            f"Refusing mutation: set POSTHOG_CONFIRM_APPLY={APPLY_CONFIRMATION}"
        )
    project_id = manifest["project"]["id"]
    if project_id != APPROVED_PROJECT_ID:
        raise PostHogContractError("Refusing to mutate any project except approved Staging")
    api.request(
        "PATCH",
        f"/api/projects/{project_id}/",
        {"name": manifest["project"]["name"], **manifest["privacy_settings"]},
    )

    expected_dashboard = manifest["managed_dashboard"]
    dashboards_path = f"/api/environments/{project_id}/dashboards/"
    dashboards = _list_results(api, f"{dashboards_path}?limit=100")
    existing_dashboard = next(
        (item for item in dashboards if item.get("name") == expected_dashboard["name"]),
        None,
    )
    dashboard_payload = {
        key: expected_dashboard[key] for key in ("name", "description", "pinned", "tags")
    }
    if existing_dashboard:
        dashboard = api.request(
            "PATCH",
            f"/api/environments/{project_id}/dashboards/{existing_dashboard['id']}/",
            dashboard_payload,
        )
    else:
        dashboard = api.request("POST", dashboards_path, dashboard_payload)

    insights_path = f"/api/environments/{project_id}/insights/"
    existing_insights = _list_results(api, f"{insights_path}?limit=100")
    for expected in expected_dashboard["insights"]:
        existing = next(
            (item for item in existing_insights if item.get("name") == expected["name"]),
            None,
        )
        payload = {
            "name": expected["name"],
            "description": expected["description"],
            "query": expected["query"],
            "dashboards": [dashboard["id"]],
            "saved": True,
        }
        if existing:
            api.request(
                "PATCH",
                f"/api/environments/{project_id}/insights/{existing['id']}/",
                payload,
            )
        else:
            api.request("POST", insights_path, payload)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("validate", "plan", "verify", "apply"))
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    try:
        manifest = load_manifest(args.manifest)
        validate_manifest(manifest)
        if args.command == "validate":
            print("PostHog Staging contract is valid and matches the Swift allow-list.")
            return 0

        api = PostHogAPI(manifest["project"]["api_host"], _management_key())
        if args.command == "apply":
            apply_manifest(manifest, api)
            print("Applied the managed PostHog contract to Staging project 507318.")

        drift = hosted_drift(manifest, api)
        if not drift:
            print("PostHog Staging matches the tracked contract.")
            return 0
        print("PostHog Staging drift:")
        for item in drift:
            print(f"- {item}")
        return 1 if args.command in ("verify", "apply") else 0
    except PostHogContractError as error:
        print(f"PostHog control error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
