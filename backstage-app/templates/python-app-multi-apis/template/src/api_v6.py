"""${{values.app_name}} — API v6 (EXPERIMENTAL / PREVIEW). v5 carry-over + /events."""

from flask import Blueprint, Response, jsonify, request
import datetime
import socket
import os
import random
import time
import json

bp = Blueprint("api_v6", __name__, url_prefix="/api/v6")
_STARTED_AT = time.time()


@bp.route("/info")
def info():
    return jsonify({
        "time": datetime.datetime.now().strftime("%I:%M:%S%p  on %B %d, %Y"),
        "hostname": socket.gethostname(),
        "deployed_on": "kubernetes",
        "api_version": "v6",
    })


@bp.route("/healthz")
def healthz():
    return jsonify({"status": "ok", "api_version": "v6"}), 200


@bp.route("/hostname")
def hostname():
    return jsonify({"hostname": socket.gethostname(), "api_version": "v6"})


@bp.route("/echo", methods=["POST"])
def echo():
    return jsonify({"received": request.get_json(silent=True) or {}, "api_version": "v6"})


@bp.route("/time")
def time_endpoint():
    return jsonify({"utc": datetime.datetime.utcnow().isoformat() + "Z", "api_version": "v6"})


@bp.route("/random")
def random_endpoint():
    return jsonify({"number": random.randint(1, 100), "api_version": "v6"})


@bp.route("/uptime")
def uptime_endpoint():
    return jsonify({"uptime_seconds": int(time.time() - _STARTED_AT), "api_version": "v6"})


@bp.route("/metrics")
def metrics_endpoint():
    return jsonify({
        "uptime_seconds": int(time.time() - _STARTED_AT),
        "image": os.environ.get("IMAGE_TAG", "unknown"),
        "api_version": "v6",
    })


@bp.route("/list")
def list_endpoint():
    limit = min(int(request.args.get("limit", 10)), 100)
    offset = int(request.args.get("offset", 0))
    return jsonify({
        "items": [random.randint(1, 1000) for _ in range(limit)],
        "limit": limit,
        "offset": offset,
        "api_version": "v6",
    })


# v6-only net-new — Server-Sent Events stream (preview / may change shape)
@bp.route("/events")
def events_endpoint():
    """Emits 5 events ~250ms apart as text/event-stream (v6 preview)."""
    def stream():
        for i in range(5):
            payload = {"seq": i, "value": random.randint(1, 1000), "api_version": "v6"}
            yield f"data: {json.dumps(payload)}\n\n"
            time.sleep(0.25)
    return Response(stream(), mimetype="text/event-stream")
