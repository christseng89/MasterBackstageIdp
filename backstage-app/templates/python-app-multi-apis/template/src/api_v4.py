"""${{values.app_name}} — API v4 (PRODUCTION). v3 carry-over + /metrics."""

from flask import Blueprint, jsonify, request
import datetime
import socket
import os
import random
import time

bp = Blueprint("api_v4", __name__, url_prefix="/api/v4")
_STARTED_AT = time.time()


@bp.route("/info")
def info():
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "deployed_on": "kubernetes",
        "api_version": "v4",
    })


@bp.route("/healthz")
def healthz():
    return jsonify({"status": "ok", "api_version": "v4"}), 200


@bp.route("/hostname")
def hostname():
    return jsonify({"hostname": socket.gethostname(), "api_version": "v4"})


@bp.route("/echo", methods=["POST"])
def echo():
    return jsonify({
        "received": request.get_json(silent=True) or {},
        "api_version": "v4",
    })


@bp.route("/time")
def time_endpoint():
    return jsonify({"utc": datetime.datetime.utcnow().isoformat() + "Z", "api_version": "v4"})


@bp.route("/random")
def random_endpoint():
    return jsonify({"number": random.randint(1, 100), "api_version": "v4"})


@bp.route("/uptime")
def uptime_endpoint():
    return jsonify({"uptime_seconds": int(time.time() - _STARTED_AT), "api_version": "v4"})


# v4-only net-new
@bp.route("/metrics")
def metrics_endpoint():
    """Lightweight metrics snapshot (v4-only)."""
    return jsonify({
        "uptime_seconds": int(time.time() - _STARTED_AT),
        "image": os.environ.get("IMAGE_TAG", "unknown"),
        "api_version": "v4",
    })
