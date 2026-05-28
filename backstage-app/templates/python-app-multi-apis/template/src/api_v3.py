"""
${{values.app_name}} — API v3 (EXPERIMENTAL / PREVIEW).

8 endpoints = v2's 5 + 3 net-new (random, uptime, env). May change before
promotion to production. Clients integrating against v3 should be prepared
for non-breaking additions and the occasional schema tweak prior to GA.
"""

from flask import Blueprint, jsonify, request
import datetime
import socket
import os
import random
import time

bp = Blueprint("api_v3", __name__, url_prefix="/api/v3")

# Process start time used by /uptime
_STARTED_AT = time.time()


@bp.route("/info")
def info():
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "deployed_on": "kubernetes",
        "api_version": "v3",
    })


@bp.route("/healthz")
def healthz():
    return jsonify({"status": "ok", "api_version": "v3"}), 200


@bp.route("/hostname")
def hostname():
    return jsonify({"hostname": socket.gethostname(), "api_version": "v3"})


@bp.route("/echo", methods=["POST"])
def echo():
    return jsonify({
        "received": request.get_json(silent=True) or {},
        "api_version": "v3",
    })


@bp.route("/time")
def time_endpoint():
    return jsonify({
        "utc": datetime.datetime.utcnow().isoformat() + "Z",
        "api_version": "v3",
    })


# --- v3-only endpoints --------------------------------------------------------

@bp.route("/random")
def random_endpoint():
    """Returns a pseudo-random integer in [1, 100] (v3-only)."""
    return jsonify({"number": random.randint(1, 100), "api_version": "v3"})


@bp.route("/uptime")
def uptime_endpoint():
    """Returns process uptime in seconds (v3-only)."""
    return jsonify({
        "uptime_seconds": int(time.time() - _STARTED_AT),
        "api_version": "v3",
    })


@bp.route("/env")
def env_endpoint():
    """
    Returns a curated subset of environment variables relevant to deployment
    (v3-only). Never expose secrets here — the allowlist is explicit on purpose.
    """
    allowlist = ["IMAGE_TAG", "GIT_SHA", "DEFAULT_API_VERSION", "APP_NAME"]
    return jsonify({
        "env": {k: os.environ.get(k, "") for k in allowlist},
        "api_version": "v3",
    })
