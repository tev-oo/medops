from django.http import JsonResponse
from rest_framework import viewsets
from rest_framework.permissions import IsAdminUser

from .models import Appointment
from .serializers import AppointmentSerializer


def health_check(request):
    return JsonResponse(
        {"status": "healthy", "service": "medops-api", "version": "0.1.0"}
    )


class AppointmentViewSet(viewsets.ModelViewSet):
    queryset = Appointment.objects.all()
    serializer_class = AppointmentSerializer
    permission_classes = [IsAdminUser]
