"""
/version — service metadata endpoint.

Anyone who can hit the service (curl, kubectl port-forward, ingress) can
discover which image is running, which API versions it serves, which are
deprecated, and the matching Backstage entity refs. This is the runtime
counterpart to Backstage's static catalog metadata.
"""

from flask import Blueprint, jsonify
import os

bp = Blueprint("version", __name__)


@bp.route("/version")
def version():
    app_name = os.environ.get("APP_NAME", "${{values.app_name}}")
    return jsonify({
        "image": os.environ.get("IMAGE_TAG", "unknown"),
        "git_sha": os.environ.get("GIT_SHA", "unknown"),
        "api_versions_supported": ["v1", "v2", "v3"],
        "api_versions_deprecated": ["v1"],
        "default_api_version": os.environ.get("DEFAULT_API_VERSION", "v2"),
        "openapi": {
            "v1": "/openapi-v1.yaml",
            "v2": "/openapi-v2.yaml",
            "v3": "/openapi-v3.yaml",
        },
        "backstage_refs": {
            "v1": f"api:default/{app_name}-api-v1",
            "v2": f"api:default/{app_name}-api-v2",
            "v3": f"api:default/{app_name}-api-v3",
        },
    })
