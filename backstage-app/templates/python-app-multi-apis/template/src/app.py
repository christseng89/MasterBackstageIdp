"""
${{values.app_name}} — multi-API-version Flask service.

This entrypoint registers three versioned blueprints (v1 / v2 / v3) plus the
deprecation-header middleware and a /version metadata endpoint. The same image
serves all three API versions simultaneously — see README and Backstage API
entities for the full lifecycle story.
"""

from flask import Flask, render_template, send_from_directory
import random

from api_v1 import bp as v1_bp
from api_v2 import bp as v2_bp
from api_v3 import bp as v3_bp
from version_endpoint import bp as version_bp
from deprecated_headers import add_deprecation_headers


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


app = Flask(__name__)

# Register every supported API version. To retire v1 in the future:
#   1. flip its lifecycle to `deprecated` in catalog-info.yaml (already done)
#   2. add /api/v1 to DEPRECATED_PREFIXES in deprecated_headers.py (already done)
#   3. when traffic on /api/v1/* drops below ~1%, swap its routes to return 410
#      Gone in this file (see README Phase 4)
app.register_blueprint(v1_bp)        # /api/v1/*  — deprecated
app.register_blueprint(v2_bp)        # /api/v2/*  — production (default)
app.register_blueprint(v3_bp)        # /api/v3/*  — experimental
app.register_blueprint(version_bp)   # /version


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
