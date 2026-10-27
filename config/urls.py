from django.contrib import admin
from django.urls import include, path
from rest_framework.routers import DefaultRouter

from appointments.views import (
    AppointmentViewSet,
    health_check,
)

router = DefaultRouter()

router.register(r"appointments", AppointmentViewSet, basename="appointments")

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/health/", health_check),
    path("api/", include(router.urls)),
    path("api-auth/", include("rest_framework.urls")),
]
