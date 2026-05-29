"""
410 Gone catch-all for retired API versions.

For each version listed in REMOVED_VERSIONS (e.g. "v1,v2"), app.py calls
make_removed_blueprint("v1"), which registers a Flask blueprint that intercepts
any path under /api/v1/* and returns:

    HTTP/1.1 410 Gone
    Content-Type: application/json
    Sunset: <past date — informational, not removable>
    Link: </api/<successor>>; rel="successor-version"

    {
      "error": "Gone",
      "message": "/api/v1/* was removed on 2025-12-31.",
      "successor": "v2",
      "migration_guide": "/docs/migration-v1-to-v2"
    }

410 (not 404) is intentional: it tells clients "this WAS a real endpoint, it has
been intentionally retired" — actionable signal rather than a silent miss.
"""

from flask import Blueprint, jsonify


# Per-version sunset metadata. Update when an env retires a new version.
SUNSET_INFO = {
    "v1": {"sunset": "Wed, 31 Dec 2024 23:59:59 GMT", "successor": "v2",
           "guide": "/docs/migration-v1-to-v2"},
    "v2": {"sunset": "Tue, 30 Jun 2026 23:59:59 GMT", "successor": "v3",
           "guide": "/docs/migration-v2-to-v3"},
    "v3": {"sunset": "Sat, 31 Dec 2026 23:59:59 GMT", "successor": "v4",
           "guide": "/docs/migration-v3-to-v4"},
}


def make_removed_blueprint(version):
    """
    Return a Flask blueprint that 410's every request under /api/<version>/*.
    Safe to call from app.py for any version string — unknown versions get
    generic sunset metadata.
    """
    info = SUNSET_INFO.get(version, {
        "sunset": "(unknown)",
        "successor": "(see service docs)",
        "guide": "/docs/api-versions",
    })

    bp = Blueprint(
        f"removed_{version}",
        __name__,
        url_prefix=f"/api/{version}",
    )

    def _gone(path=""):
        response = jsonify({
            "error": "Gone",
            "message": f"/api/{version}/* was removed on {info['sunset']}.",
            "successor": info["successor"],
            "migration_guide": info["guide"],
        })
        response.status_code = 410
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

    # Catch any path under the prefix, including the bare prefix itself.
    bp.add_url_rule("/", "gone_root", _gone, methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
    bp.add_url_rule("/<path:path>", "gone_any", _gone, methods=["GET", "POST", "PUT", "PATCH", "DELETE"])

    return bp
