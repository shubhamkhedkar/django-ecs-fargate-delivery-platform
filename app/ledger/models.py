from django.core.validators import RegexValidator
from django.db import models

service_name = RegexValidator(
    r"^[a-z][a-z0-9-]{1,62}$", "Use lowercase letters, digits and hyphens (2-63 chars)."
)


class Release(models.Model):
    """One rollout of one service version to one environment."""

    class Environment(models.TextChoices):
        DEV = "dev", "Development"
        STAGING = "staging", "Staging"
        PROD = "prod", "Production"

    class Status(models.TextChoices):
        IN_PROGRESS = "in_progress", "In progress"
        SUCCEEDED = "succeeded", "Succeeded"
        ROLLED_BACK = "rolled_back", "Rolled back"
        FAILED = "failed", "Failed"

    service = models.CharField(max_length=63, validators=[service_name])
    version = models.CharField(max_length=64)
    image_digest = models.CharField(max_length=80, blank=True)
    environment = models.CharField(max_length=16, choices=Environment.choices)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.IN_PROGRESS)
    deployed_by = models.CharField(max_length=100, blank=True)
    notes = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)

    class Meta:
        ordering = ["-created_at", "-id"]
        indexes = [models.Index(fields=["environment", "service", "-created_at"])]

    def __str__(self) -> str:
        return f"{self.service}@{self.version} -> {self.environment} ({self.status})"

    def as_dict(self) -> dict:
        return {
            "id": self.pk,
            "service": self.service,
            "version": self.version,
            "image_digest": self.image_digest,
            "environment": self.environment,
            "status": self.status,
            "deployed_by": self.deployed_by,
            "notes": self.notes,
            "created_at": self.created_at.isoformat(),
        }
