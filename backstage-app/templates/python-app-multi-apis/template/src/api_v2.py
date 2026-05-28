"""
${{values.app_name}} — API v2 (PRODUCTION).

5 endpoints = v1's 3 + 2 net-new (echo, time). Backwards-compatible with v1
output shape on the carry-over endpoints; the `api_version` field always
reflects the route's namespace, not the client's.
"""

from flask import Blueprint, jsonify, request
import datetime
import socket

bp = Blueprint("api_v2", __name__, url_prefix="/api/v2")


@bp.route("/info")
def info():
    """Returns current time, hostname, and a deployment context message."""
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "deployed_on": "kubernetes",
        "api_version": "v2",
    })


@bp.route("/healthz")
def healthz():
    """Liveness / readiness probe — returns 200 OK when the service is up."""
    return jsonify({"status": "ok", "api_version": "v2"}), 200


@bp.route("/hostname")
def hostname():
    """Returns the pod hostname."""
    return jsonify({"hostname": socket.gethostname(), "api_version": "v2"})


@bp.route("/echo", methods=["POST"])
def echo():
    """Echoes the JSON body back to the caller — useful for connectivity tests."""
    return jsonify({
        "received": request.get_json(silent=True) or {},
        "api_version": "v2",
    })


@bp.route("/time")
def time_endpoint():
    """Returns the current UTC time in ISO 8601 format."""
    return jsonify({
        "utc": datetime.datetime.utcnow().isoformat() + "Z",
        "api_version": "v2",
    })
