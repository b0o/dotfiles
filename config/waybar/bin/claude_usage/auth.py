"""OAuth token management for Claude usage monitor."""

import json
import os
import sys
import time
import urllib.error
import urllib.request
from typing import Optional

from .constants import (
    CLAUDE_CREDS_PATH,
    OAUTH_CLIENT_ID,
    OAUTH_TOKEN_URL,
    OPENCODE_CREDS_PATH,
    TOKEN_REFRESH_MARGIN,
)


def refresh_claude_token() -> tuple[Optional[str], Optional[str]]:
    """Refresh Claude CLI OAuth token using refresh token.

    Returns:
        Tuple of (access_token, error_message). One will always be None.
    """
    if not os.path.exists(CLAUDE_CREDS_PATH):
        return None, "credentials file not found"

    try:
        with open(CLAUDE_CREDS_PATH) as f:
            data = json.load(f)

        oauth = data.get("claudeAiOauth", {})
        refresh_token = oauth.get("refreshToken")
        if not refresh_token:
            return None, "no refresh token"

        # Make refresh request
        payload = json.dumps(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": OAUTH_CLIENT_ID,
            }
        ).encode("utf-8")

        req = urllib.request.Request(
            OAUTH_TOKEN_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.load(response)

        # Check for OAuth error response
        if "error" in result:
            error = result.get("error", "unknown_error")
            error_desc = result.get("error_description", "")
            msg = f"{error}: {error_desc}" if error_desc else error
            return None, msg

        # Update credentials file with new tokens
        new_access_token = result.get("access_token")
        if not new_access_token:
            return None, "no access_token in response"

        new_refresh_token = result.get("refresh_token")
        expires_in = result.get("expires_in", 28800)

        oauth["accessToken"] = new_access_token
        # expiresAt is in milliseconds
        oauth["expiresAt"] = int((time.time() + expires_in) * 1000)
        if new_refresh_token:
            oauth["refreshToken"] = new_refresh_token
        data["claudeAiOauth"] = oauth

        with open(CLAUDE_CREDS_PATH, "w") as f:
            json.dump(data, f)

        return new_access_token, None

    except (
        json.JSONDecodeError,
        urllib.error.URLError,
        IOError,
        KeyError,
        TimeoutError,
    ) as e:
        return None, str(e)


def refresh_opencode_token() -> tuple[Optional[str], Optional[str]]:
    """Refresh OpenCode OAuth token using refresh token.

    Returns:
        Tuple of (access_token, error_message). One will always be None.
    """
    if not os.path.exists(OPENCODE_CREDS_PATH):
        return None, "credentials file not found"

    try:
        with open(OPENCODE_CREDS_PATH) as f:
            data = json.load(f)

        anthropic = data.get("anthropic", {})
        refresh_token = anthropic.get("refresh")
        if not refresh_token:
            return None, "no refresh token"

        # Make refresh request
        payload = json.dumps(
            {
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": OAUTH_CLIENT_ID,
            }
        ).encode("utf-8")

        req = urllib.request.Request(
            OAUTH_TOKEN_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            result = json.load(response)

        # Check for OAuth error response
        if "error" in result:
            error = result.get("error", "unknown_error")
            error_desc = result.get("error_description", "")
            msg = f"{error}: {error_desc}" if error_desc else error
            return None, msg

        # Update credentials file with new tokens
        new_access_token = result.get("access_token")
        if not new_access_token:
            return None, "no access_token in response"

        new_refresh_token = result.get("refresh_token")
        expires_in = result.get("expires_in", 28800)

        anthropic["access"] = new_access_token
        # expires is in milliseconds
        anthropic["expires"] = int((time.time() + expires_in) * 1000)
        if new_refresh_token:
            anthropic["refresh"] = new_refresh_token
        data["anthropic"] = anthropic

        with open(OPENCODE_CREDS_PATH, "w") as f:
            json.dump(data, f, indent=4)

        return new_access_token, None

    except (
        json.JSONDecodeError,
        urllib.error.URLError,
        IOError,
        KeyError,
        TimeoutError,
    ) as e:
        return None, str(e)


def get_valid_token(
    prefer: Optional[str] = None,
) -> tuple[Optional[str], Optional[str], bool, Optional[str]]:
    """Get a valid OAuth token from Claude CLI or OpenCode credentials.

    Will automatically refresh expired tokens if a refresh token is available.

    Args:
        prefer: "cc" for Claude Code, "oc" for OpenCode, None for auto
                (auto mode tries the most recently modified credential file first)

    Returns:
        Tuple of (token, source, is_fallback, error) where source is "cc" or "oc",
        is_fallback is True if we had to use the non-preferred source,
        error contains the reason for failure if token is None,
        or (None, None, False, error) if no valid token.
    """
    now = time.time()
    errors: list[str] = []

    def check_token_valid(
        path: str, token_key: str, expires_key: str, data_key: Optional[str] = None
    ) -> bool:
        """Check if a credential file has a valid (non-expired) token."""
        if not os.path.exists(path):
            return False
        try:
            with open(path) as f:
                data = json.load(f)
            if data_key:
                data = data.get(data_key, {})
            token = data.get(token_key)
            expires_at = data.get(expires_key)
            if token and expires_at:
                expires_at_sec = expires_at / 1000
                return expires_at_sec > now + TOKEN_REFRESH_MARGIN
        except (json.JSONDecodeError, KeyError, ValueError, IOError):
            pass
        return False

    def get_mtime(path: str) -> float:
        """Get file modification time, or 0 if file doesn't exist."""
        try:
            return os.path.getmtime(path)
        except OSError:
            return 0

    def try_claude_code() -> tuple[Optional[str], Optional[str]]:
        if not os.path.exists(CLAUDE_CREDS_PATH):
            return None, "no credentials file"
        try:
            with open(CLAUDE_CREDS_PATH) as f:
                data = json.load(f)
            oauth = data.get("claudeAiOauth", {})
            token = oauth.get("accessToken")
            expires_at = oauth.get("expiresAt")
            # Check if current token is valid
            if token and expires_at:
                expires_at_sec = expires_at / 1000
                if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                    return token, None
            # Token expired or missing - try to refresh if we have a refresh token
            if oauth.get("refreshToken"):
                new_token, err = refresh_claude_token()
                if new_token:
                    return new_token, None
                return None, f"refresh failed: {err}"
            return None, "token expired, no refresh token"
        except (json.JSONDecodeError, KeyError, ValueError) as e:
            return None, f"credentials error: {e}"

    def try_opencode() -> tuple[Optional[str], Optional[str]]:
        if not os.path.exists(OPENCODE_CREDS_PATH):
            return None, "no credentials file"
        try:
            with open(OPENCODE_CREDS_PATH) as f:
                data = json.load(f)
            anthropic = data.get("anthropic", {})
            token = anthropic.get("access")
            expires_at = anthropic.get("expires")
            # Check if current token is valid
            if token and expires_at:
                expires_at_sec = expires_at / 1000
                if expires_at_sec > now + TOKEN_REFRESH_MARGIN:
                    return token, None
            # Token expired or missing - try to refresh if we have a refresh token
            if anthropic.get("refresh"):
                new_token, err = refresh_opencode_token()
                if new_token:
                    return new_token, None
                return None, f"refresh failed: {err}"
            return None, "token expired, no refresh token"
        except (json.JSONDecodeError, KeyError, ValueError) as e:
            return None, f"credentials error: {e}"

    # Determine order based on preference
    if prefer == "oc":
        sources = [("oc", try_opencode), ("cc", try_claude_code)]
    elif prefer == "cc":
        sources = [("cc", try_claude_code), ("oc", try_opencode)]
    else:
        # Auto mode: if both have valid tokens, prefer the more recently modified file
        cc_valid = check_token_valid(
            CLAUDE_CREDS_PATH, "accessToken", "expiresAt", "claudeAiOauth"
        )
        oc_valid = check_token_valid(
            OPENCODE_CREDS_PATH, "access", "expires", "anthropic"
        )

        if cc_valid and oc_valid:
            # Both valid, use the one with more recent mtime
            cc_mtime = get_mtime(CLAUDE_CREDS_PATH)
            oc_mtime = get_mtime(OPENCODE_CREDS_PATH)
            if oc_mtime > cc_mtime:
                sources = [("oc", try_opencode), ("cc", try_claude_code)]
            else:
                sources = [("cc", try_claude_code), ("oc", try_opencode)]
        else:
            # Default order if not both valid
            sources = [("cc", try_claude_code), ("oc", try_opencode)]

    for i, (source, try_fn) in enumerate(sources):
        token, err = try_fn()
        if token:
            # is_fallback is True if we have a preference and this isn't the first choice
            is_fallback = prefer is not None and i > 0
            return token, source, is_fallback, None
        if err:
            errors.append(f"{source}: {err}")

    # Combine all errors for reporting
    error_msg = "; ".join(errors) if errors else "no credentials found"
    return None, None, False, error_msg
