import tempfile
from pathlib import Path
from unittest.mock import patch

from django.test import SimpleTestCase


class MetricsAuthenticationTests(SimpleTestCase):
    def test_metrics_without_token_returns_404(self):
        with tempfile.TemporaryDirectory() as tmp:
            token_path = Path(tmp) / "metrics-token"
            token_path.write_text("test-secret-token\n")

            with patch.dict(
                "os.environ",
                {"MEDOPS_METRICS_TOKEN_FILE": str(token_path)},
            ):
                response = self.client.get("/metrics")

            self.assertEqual(response.status_code, 404)

    def test_metrics_with_invalid_token_returns_404(self):
        with tempfile.TemporaryDirectory() as tmp:
            token_path = Path(tmp) / "metrics-token"
            token_path.write_text("test-secret-token\n")

            with patch.dict(
                "os.environ",
                {"MEDOPS_METRICS_TOKEN_FILE": str(token_path)},
            ):
                response = self.client.get(
                    "/metrics",
                    HTTP_AUTHORIZATION="Bearer wrong-token",
                )

            self.assertEqual(response.status_code, 404)

    def test_metrics_with_valid_token_returns_200(self):
        with tempfile.TemporaryDirectory() as tmp:
            token_path = Path(tmp) / "metrics-token"
            token_path.write_text("test-secret-token\n")

            with patch.dict(
                "os.environ",
                {"MEDOPS_METRICS_TOKEN_FILE": str(token_path)},
            ):
                response = self.client.get(
                    "/metrics",
                    HTTP_AUTHORIZATION="Bearer test-secret-token",
                )

            self.assertEqual(response.status_code, 200)
            self.assertIn(
                b"django_http_",
                response.content,
            )

    def test_health_endpoint_does_not_require_metrics_token(self):
        with patch.dict(
            "os.environ",
            {"MEDOPS_METRICS_TOKEN_FILE": ""},
        ):
            response = self.client.get("/api/health/")

        self.assertEqual(response.status_code, 200)

    def test_metrics_without_token_file_configuration_returns_404(self):
        with patch.dict(
            "os.environ",
            {"MEDOPS_METRICS_TOKEN_FILE": ""},
        ):
            response = self.client.get("/metrics")

        self.assertEqual(response.status_code, 404)
