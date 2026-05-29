"""
/version — service metadata endpoint (env-driven for multi-version pipeline).

Surfaces the per-env reality:
  • image / git SHA
  • api_versions.enabled   — comma list from ENABLED_VERSIONS env
  • api_versions.deprecated — comma list from DEPRECATED_VERSIONS env
  • api_versions.removed   — comma list from REMOVED_VERSIONS env (return 410)
  • default_api_version    — primary version label for this env
  • backstage_refs         — Backstage entity refs for everything ENABLED
"""

from flask import Blueprint, jsonify
import os

bp = Blueprint("version", __name__)


def _parse(env_value):
    return [v.strip() for v in (env_value or "").split(",") if v.strip()]


@bp.route("/version")
def version():
    app_name = os.environ.get("APP_NAME", "${{values.app_name}}")
    enabled = _parse(os.environ.get("ENABLED_VERSIONS", "v4"))
    deprecated = _parse(os.environ.get("DEPRECATED_VERSIONS", ""))
    removed = _parse(os.environ.get("REMOVED_VERSIONS", ""))

    return jsonify({
        "image": os.environ.get("IMAGE_TAG", "unknown"),
        "git_sha": os.environ.get("GIT_SHA", "unknown"),
        "api_versions": {
            "enabled":    enabled,
            "deprecated": deprecated,
            "removed":    removed,
        },
        "default_api_version": os.environ.get("DEFAULT_API_VERSION", "v4"),
        "openapi": {v: f"/openapi-{v}.yaml" for v in enabled},
        "backstage_refs": {v: f"api:default/{app_name}-api-{v}" for v in enabled},
    })
