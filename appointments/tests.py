from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from rest_framework.test import APIClient

from .models import Appointment


class AppointmentAPITests(TestCase):

    def setUp(self):
        self.client = APIClient()

        self.staff_user = get_user_model().objects.create_user(
            username="teststaff",
            password="local-test-password",
            is_staff=True,
        )

        self.valid_data = {
            "patient_name": "Jane Example",
            "patient_email": "jane@example.com",
            "appointment_date": (
                timezone.now() + timedelta(days=7)
            ).isoformat(),
            "reason": "Routine medical checkup",
            "status": "scheduled",
        }

    def test_health_endpoint(self):
        response = self.client.get("/api/health/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json()["status"], "healthy"
        )

    def test_unauthenticated_access_denied(self):
        response = self.client.get("/api/appointments/")

        self.assertEqual(response.status_code, 403)

    def test_staff_can_create_appointment(self):
        self.client.force_authenticate(user=self.staff_user)

        response = self.client.post(
            "/api/appointments/",
            self.valid_data,
            format="json",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(Appointment.objects.count(), 1)

    def test_past_appointment_rejected(self):
        self.client.force_authenticate(user=self.staff_user)

        data = self.valid_data.copy()
        data["appointment_date"] = (
            timezone.now() - timedelta(days=1)
        ).isoformat()

        response = self.client.post(
            "/api/appointments/",
            data,
            format="json",
        )

        self.assertEqual(response.status_code, 400)

    def test_staff_can_list_appointments(self):
        self.client.force_authenticate(user=self.staff_user)

        Appointment.objects.create(**self.valid_data)

        response = self.client.get("/api/appointments/")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)

    def test_staff_can_cancel_appointment(self):
        self.client.force_authenticate(user=self.staff_user)

        appointment = Appointment.objects.create(
            **self.valid_data
        )

        response = self.client.patch(
            f"/api/appointments/{appointment.id}/",
            {"status": "cancelled"},
            format="json",
        )

        self.assertEqual(response.status_code, 200)

        appointment.refresh_from_db()
        self.assertEqual(appointment.status, "cancelled")

    def test_non_staff_user_cannot_access_appointments(self):
        user = get_user_model().objects.create_user(
            username="regularuser",
            password="local-test-password",
        )

        self.client.force_authenticate(user=user)

        response = self.client.get("/api/appointments/")

        self.assertEqual(response.status_code, 403)
