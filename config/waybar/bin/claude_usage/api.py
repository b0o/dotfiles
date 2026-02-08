"""API calls for Claude usage monitor."""

import json
import urllib.error
import urllib.request
from typing import Dict, Optional

from .auth import get_valid_token
from .constants import OAUTH_PROFILE_URL


def fetch_profile(token: str) -> Optional[Dict]:
    """Fetch user profile including plan/tier info."""
    req = urllib.request.Request(
        OAUTH_PROFILE_URL,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def query_usage_headers(token: str) -> Optional[Dict[str, str]]:
    """Query the Anthropic API and return rate limit headers."""
    url = "https://api.anthropic.com/v1/messages?beta=true"
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "Authorization": f"Bearer {token}",
        "anthropic-version": "2023-06-01",
        "anthropic-beta": "oauth-2025-04-20,interleaved-thinking-2025-05-14",
        "anthropic-dangerous-direct-browser-access": "true",
        "x-app": "cli",
        "User-Agent": "claude-cli/2.1.3 (external, cli)",
    }
    payload = json.dumps(
        {
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [{"role": "user", "content": "quota"}],
        }
    ).encode("utf-8")

    req = urllib.request.Request(url, data=payload, headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return {k.lower(): v for k, v in response.headers.items()}
    except urllib.error.HTTPError as e:
        # Even on error responses, we can get headers
        return {k.lower(): v for k, v in e.headers.items()}
    except (urllib.error.URLError, TimeoutError):
        return None


def query_codex_usage(token: str) -> Optional[Dict]:
    """Query the Codex usage API and return parsed JSON."""
    req = urllib.request.Request(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
        },
        method="GET",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)
    except urllib.error.HTTPError as e:
        try:
            return json.load(e)
        except (json.JSONDecodeError, ValueError):
            return None
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError):
        return None


def parse_usage_data(headers: Dict[str, str]) -> Optional[Dict]:
    """Parse rate limit headers into usage data."""
    try:
        data = {
            "status": headers.get("anthropic-ratelimit-unified-status", "unknown"),
            "5h_status": headers.get(
                "anthropic-ratelimit-unified-5h-status", "unknown"
            ),
            "5h_reset": int(headers.get("anthropic-ratelimit-unified-5h-reset", 0)),
            "5h_utilization": float(
                headers.get("anthropic-ratelimit-unified-5h-utilization", 0)
            ),
            "7d_status": headers.get(
                "anthropic-ratelimit-unified-7d-status", "unknown"
            ),
            "7d_reset": int(headers.get("anthropic-ratelimit-unified-7d-reset", 0)),
            "7d_utilization": float(
                headers.get("anthropic-ratelimit-unified-7d-utilization", 0)
            ),
            "representative_claim": headers.get(
                "anthropic-ratelimit-unified-representative-claim", ""
            ),
            "fallback_percentage": float(
                headers.get("anthropic-ratelimit-unified-fallback-percentage", 0)
            ),
        }
        return data
    except (ValueError, TypeError):
        return None


def parse_codex_usage_data(payload: Dict) -> Optional[Dict]:
    """Parse Codex usage payload into common usage shape."""
    try:
        rate_limit = payload.get("rate_limit") or {}
        primary = rate_limit.get("primary_window") or {}
        secondary = rate_limit.get("secondary_window") or {}

        allowed = bool(rate_limit.get("allowed", False))
        limit_reached = bool(rate_limit.get("limit_reached", False))
        if allowed and not limit_reached:
            status = "allowed"
        elif allowed and limit_reached:
            status = "allowed_warning"
        else:
            status = "rejected"

        used_5h = float(primary.get("used_percent", 0)) / 100.0
        reset_5h = int(primary.get("reset_at", 0) or 0)

        used_7d = float(secondary.get("used_percent", 0)) / 100.0
        reset_7d = int(secondary.get("reset_at", 0) or 0)

        data = {
            "status": status,
            "5h_status": status,
            "5h_reset": reset_5h,
            "5h_utilization": used_5h,
            "7d_status": status,
            "7d_reset": reset_7d,
            "7d_utilization": used_7d,
            "representative_claim": "five_hour",
            "fallback_percentage": 0.0,
        }
        return data
    except (ValueError, TypeError):
        return None


def fetch_usage_data(
    previous_token: Optional[str] = None,
    prefer_source: Optional[str] = None,
    provider: str = "claude",
) -> tuple[
    Optional[Dict],
    Optional[Dict],
    Optional[str],
    Optional[str],
    bool,
    bool,
    Optional[str],
]:
    """Fetch and parse usage data from the API.

    Returns (data, profile, token, source, is_fallback, has_token, error).
    Profile is only fetched if token changed from previous_token.
    Source is "cc" (Claude Code) or "oc" (OpenCode).
    is_fallback is True if using non-preferred source due to preferred being unavailable.
    error contains the reason for failure if has_token is False.
    """
    token, source, is_fallback, token_error = get_valid_token(
        prefer_source, provider=provider
    )
    if not token:
        return None, None, None, None, False, False, token_error

    profile = None
    if provider == "codex":
        payload = query_codex_usage(token)
        if not payload:
            return None, None, token, source, is_fallback, True, None
        usage_data = parse_codex_usage_data(payload)
        if token != previous_token:
            profile = {
                "account": {
                    "uuid": payload.get("account_id") or payload.get("user_id"),
                    "email": payload.get("email"),
                },
                "organization": {
                    "organization_type": f"codex_{payload.get('plan_type', 'free')}",
                    "rate_limit_tier": None,
                },
            }
    else:
        headers = query_usage_headers(token)
        if not headers:
            return None, None, token, source, is_fallback, True, None
        usage_data = parse_usage_data(headers)
        # Only fetch profile if token changed (new login or refresh)
        if token != previous_token:
            profile = fetch_profile(token)

    return usage_data, profile, token, source, is_fallback, True, None
