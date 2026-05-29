"""${{values.app_name}} — API v5 (PRODUCTION). v4 carry-over + paginated query."""

from flask import Blueprint, jsonify, request
import datetime
import socket
import os
import random
import time

bp = Blueprint("api_v5", __name__, url_prefix="/api/v5")
_STARTED_AT = time.time()


@bp.route("/info")
def info():
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "deployed_on": "kubernetes",
        "api_version": "v5",
    })


@bp.route("/healthz")
def healthz():
    return jsonify({"status": "ok", "api_version": "v5"}), 200


@bp.route("/hostname")
def hostname():
    return jsonify({"hostname": socket.gethostname(), "api_version": "v5"})


@bp.route("/echo", methods=["POST"])
def echo():
    return jsonify({"received": request.get_json(silent=True) or {}, "api_version": "v5"})


@bp.route("/time")
def time_endpoint():
    return jsonify({"utc": datetime.datetime.utcnow().isoformat() + "Z", "api_version": "v5"})


@bp.route("/random")
def random_endpoint():
    return jsonify({"number": random.randint(1, 100), "api_version": "v5"})


@bp.route("/uptime")
def uptime_endpoint():
    return jsonify({"uptime_seconds": int(time.time() - _STARTED_AT), "api_version": "v5"})


@bp.route("/metrics")
def metrics_endpoint():
    return jsonify({
        "uptime_seconds": int(time.time() - _STARTED_AT),
        "image": os.environ.get("IMAGE_TAG", "unknown"),
        "api_version": "v5",
    })


# v5-only net-new — paginated random number stream
@bp.route("/list")
def list_endpoint():
    """Returns a paginated batch of random numbers (v5+)."""
    limit = min(int(request.args.get("limit", 10)), 100)
    offset = int(request.args.get("offset", 0))
    return jsonify({
        "items": [random.randint(1, 1000) for _ in range(limit)],
        "limit": limit,
        "offset": offset,
        "api_version": "v5",
    })
