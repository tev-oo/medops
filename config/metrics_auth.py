import hmac
import os
from pathlib import Path

from django.http import HttpResponseNotFound


class MetricsAuthMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path.rstrip("/") != "/metrics":
            return self.get_response(request)

        token_file = os.getenv("MEDOPS_METRICS_TOKEN_FILE")

        if not token_file:
            return HttpResponseNotFound()

        try:
            expected = Path(token_file).read_text().strip()
        except OSError:
            return HttpResponseNotFound()

        supplied = request.headers.get("Authorization", "")
        prefix = "Bearer "

        if (
            not expected
            or not supplied.startswith(prefix)
            or not hmac.compare_digest(supplied[len(prefix) :], expected)
        ):
            return HttpResponseNotFound()

        return self.get_response(request)
