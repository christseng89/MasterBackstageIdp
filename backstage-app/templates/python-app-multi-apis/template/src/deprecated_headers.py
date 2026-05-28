"""
RFC 9745 (Deprecation) + RFC 8594 (Sunset) header middleware.

Any route whose path starts with a prefix listed in DEPRECATED_PREFIXES
gets the corresponding headers attached on the response, allowing client
SDKs / proxies / monitoring stacks to programmatically detect deprecation
without parsing human-readable docs.
"""

from flask import request


# Edit this map when you mark a new path prefix deprecated, or when a
# previously-deprecated prefix is fully removed (then drop the entry).
DEPRECATED_PREFIXES = {
    "/api/v1": {
        "sunset": "Wed, 31 Dec 2025 23:59:59 GMT",     # RFC 7231 HTTP-date
        "successor": "/api/v2",
        "guide": "/docs/migration-v1-to-v2",
    },
}


def add_deprecation_headers(response):
    """Flask after_request hook — see app.py for wiring."""
    for prefix, info in DEPRECATED_PREFIXES.items():
        if request.path.startswith(prefix):
            response.headers["Deprecation"] = "true"
            response.headers["Sunset"] = info["sunset"]
            response.headers.add(
                "Link",
                f'<{info["successor"]}>; rel="successor-version"',
            )
            response.headers.add(
                "Link",
                f'<{info["guide"]}>; rel="deprecation"',
            )
    return response
