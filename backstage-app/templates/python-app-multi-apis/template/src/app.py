"""
${{values.app_name}} — multi-API-version Flask service (6 versions, env-driven).

Same image, different per-env routing — controlled entirely by environment
variables set by the Helm chart's values-{dev,staging,prod}.yaml:

  ENABLED_VERSIONS      — comma list of versions to register normally   (e.g. "v3,v4,v5,v6")
  DEPRECATED_VERSIONS   — subset of ENABLED, also gets RFC 9745 headers (e.g. "v2")
  REMOVED_VERSIONS      — versions to register as 410 Gone catch-all    (e.g. "v1,v2")
  DEFAULT_API_VERSION   — surfaced on K8s label + /version metadata     (e.g. "v4")

Anything not in any of the three lists isn't registered → vanilla Flask 404.

Typical distribution across the env pipeline:

      | v1      | v2          | v3        | v4    | v5    | v6
  ----+---------+-------------+-----------+-------+-------+-----------
  Dev | removed | removed     | removed   | stable| stable| stable
  Stg | removed | removed     | stable    | stable| stable| stable
  Prd | removed | deprecated  | stable    | stable| n/a   | n/a
"""

from flask import Flask, render_template, send_from_directory
import os
import random

from api_v1 import bp as v1_bp
from api_v2 import bp as v2_bp
from api_v3 import bp as v3_bp
from api_v4 import bp as v4_bp
from api_v5 import bp as v5_bp
from api_v6 import bp as v6_bp
from version_endpoint import bp as version_bp
from deprecated_headers import add_deprecation_headers
from removed_handlers import make_removed_blueprint


dev_excuses = [
    "It worked on my machine.",
    "I thought I fixed that.",
    "That's just a warning, not an error.",
    "You must have a corrupted database.",
    "It was working yesterday.",
    "I didn't write that part of the code.",
    "That's a hardware problem.",
    "I can't reproduce the problem.",
    "The client must have done something wrong.",
    "I have never seen that before.",
]


# Catalog of all known API blueprints keyed by version string.
ALL_VERSION_BLUEPRINTS = {
    "v1": v1_bp,
    "v2": v2_bp,
    "v3": v3_bp,
    "v4": v4_bp,
    "v5": v5_bp,
    "v6": v6_bp,
}


def _parse_versions(env_value):
    """Split a comma-separated env var into a clean list of version strings."""
    return [v.strip() for v in (env_value or "").split(",") if v.strip()]


app = Flask(__name__)

enabled = _parse_versions(os.environ.get("ENABLED_VERSIONS", "v4"))
removed = _parse_versions(os.environ.get("REMOVED_VERSIONS", ""))
deprecated = _parse_versions(os.environ.get("DEPRECATED_VERSIONS", ""))

# Sanity: deprecated must be a subset of enabled — if the chart accidentally
# lists a deprecated version that isn't enabled, treat it as "removed" so
# /api/v<n>/* still returns a useful 410 instead of vanishing as 404.
for v in deprecated:
    if v not in enabled and v not in removed:
        removed.append(v)

print(f"[startup] enabled={enabled}  deprecated={deprecated}  removed={removed}")

# Step 1 — register enabled blueprints (normal routes)
for v in enabled:
    bp = ALL_VERSION_BLUEPRINTS.get(v)
    if bp is None:
        print(f"[startup] WARN: ENABLED_VERSIONS contains unknown version '{v}'")
        continue
    app.register_blueprint(bp)

# Step 2 — register removed catch-all (410 Gone)
for v in removed:
    app.register_blueprint(make_removed_blueprint(v))

# Step 3 — always-on endpoints
app.register_blueprint(version_bp)


@app.after_request
def attach_deprecation_headers(response):
    """Attach RFC 9745 / RFC 8594 headers when a deprecated path is hit."""
    return add_deprecation_headers(response)


@app.route("/")
def home():
    return render_template(
        "index.html",
        cat_img=f"images-front/cat{random.randint(1, 7)}.gif",
        dev_excuse=random.choice(dev_excuses),
    )


@app.route("/images-front/<filename>")
def images_frontend(filename):
    return send_from_directory("templates/img", filename)


if __name__ == "__main__":
    app.run(host="0.0.0.0")
