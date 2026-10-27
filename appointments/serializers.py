from django.utils import timezone
from rest_framework import serializers

from .models import Appointment


class AppointmentSerializer(serializers.ModelSerializer):

    class Meta:
        model = Appointment
        fields = [
            "id",
            "patient_name",
            "patient_email",
            "appointment_date",
            "reason",
            "status",
            "created_at",
        ]

        read_only_fields = ["id", "created_at"]

    def validate_appointment_date(self, value):
        if value <= timezone.now():
            raise serializers.ValidationError(
                "Appointment date must be in the future."
            )
        return value
