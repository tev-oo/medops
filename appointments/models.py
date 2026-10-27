from django.db import models


class Appointment(models.Model):
    class Status(models.TextChoices):
        SCHEDULED = "scheduled", "Scheduled"
        COMPLETED = "completed", "Completed"
        CANCELLED = "cancelled", "Cancelled"

    patient_name = models.CharField(max_length=150)
    patient_email = models.EmailField()
    appointment_date = models.DateTimeField()
    reason = models.TextField()

    status = models.CharField(
        max_length=20, choices=Status.choices, default=Status.SCHEDULED
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["appointment_date"]

    def __str__(self):
        return f"{self.patient_name} - {self.appointment_date}"
