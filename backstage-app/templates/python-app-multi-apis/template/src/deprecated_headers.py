"""
RFC 9745 (Deprecation) + RFC 8594 (Sunset) header middleware (env-driven).

Reads DEPRECATED_VERSIONS from environment (set by the Helm chart per env)
and attaches the headers on any response whose path starts with /api/<v>/
for v ∈ DEPRECATED_VERSIONS.

Why per-env config: the same image runs in dev/staging/prod, but a version is
not necessarily deprecated everywhere at once.  In our pipeline, v2 is only
listed as DEPRECATED_VERSIONS=v2 on prod (where it still serves traffic
during the sunset window); staging and dev have already removed v2, so they
list v2 in REMOVED_VERSIONS — that's a different middleware path
(removed_handlers.py) returning 410.
"""

from flask import request
import os


# Per-version sunset + successor (kept in sync with removed_handlers.SUNSET_INFO).
# When a version transitions from "deprecated" → "removed", remove from
# DEPRECATED_VERSIONS in values-prod.yaml and add to REMOVED_VERSIONS instead.
PER_VERSION_META = {
    "v1": {"sunset": "Wed, 31 Dec 2024 23:59:59 GMT", "successor": "v2",
           "guide": "/docs/migration-v1-to-v2"},
    "v2": {"sunset": "Tue, 30 Jun 2026 23:59:59 GMT", "successor": "v3",
           "guide": "/docs/migration-v2-to-v3"},
    "v3": {"sunset": "Sat, 31 Dec 2026 23:59:59 GMT", "successor": "v4",
           "guide": "/docs/migration-v3-to-v4"},
    "v4": {"sunset": "(none)", "successor": "v5", "guide": "/docs/migration-v4-to-v5"},
    "v5": {"sunset": "(none)", "successor": "v6", "guide": "/docs/migration-v5-to-v6"},
}


def _parse(env_value):
    return [v.strip() for v in (env_value or "").split(",") if v.strip()]


DEPRECATED_PREFIXES = {
    f"/api/{v}": PER_VERSION_META.get(v, {
        "sunset": "(unknown)",
        "successor": "(see service docs)",
        "guide": "/docs/api-versions",
    })
    for v in _parse(os.environ.get("DEPRECATED_VERSIONS", ""))
}

# Note re Backstage Nunjucks: this file is plain Python; the scaffolder does
# not template-process it (no dollar-double-brace expressions).  Comments may
# safely contain brace characters.


def add_deprecation_headers(response):
    """Flask after_request hook — see app.py for wiring."""
    for prefix, info in DEPRECATED_PREFIXES.items():
        if request.path.startswith(prefix):
            response.headers["Deprecation"] = "true"
            response.headers["Sunset"] = info["sunset"]
            response.headers.add(
                "Link",
                f'</api/{info["successor"]}>; rel="successor-version"',
            )
            response.headers.add(
                "Link",
                f'<{info["guide"]}>; rel="deprecation"',
            )
    return response
