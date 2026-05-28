"""
${{values.app_name}} — API v1 (DEPRECATED).

3 endpoints. Sunset target: 2025-12-31. Clients should migrate to v2.
The Deprecation / Sunset HTTP headers are added by deprecated_headers.py
middleware on every response under /api/v1/*.
"""

from flask import Blueprint, jsonify
import datetime
import socket

bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")


@bp.route("/info")
def info():
    """Returns current time + hostname (deprecated — use /api/v2/info)."""
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "api_version": "v1",
    })


@bp.route("/healthz")
def healthz():
    """Liveness / readiness probe (deprecated — use /api/v2/healthz)."""
    return jsonify({"status": "up", "api_version": "v1"}), 200


@bp.route("/hostname")
def hostname():
    """Returns the pod hostname (deprecated — use /api/v2/hostname)."""
    return jsonify({"hostname": socket.gethostname(), "api_version": "v1"})
