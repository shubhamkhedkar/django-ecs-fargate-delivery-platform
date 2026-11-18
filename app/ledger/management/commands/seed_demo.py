"""Load a handful of sample releases so the local demo has something to show."""

from django.core.management.base import BaseCommand

from ledger.models import Release

SAMPLES = [
    ("payments-api", "2.14.0", "prod", Release.Status.SUCCEEDED),
    ("payments-api", "2.15.0", "staging", Release.Status.SUCCEEDED),
    ("checkout-web", "5.3.1", "prod", Release.Status.SUCCEEDED),
    ("checkout-web", "5.4.0", "prod", Release.Status.ROLLED_BACK),
    ("ledger", "1.0.0", "dev", Release.Status.SUCCEEDED),
    ("search-indexer", "0.9.2", "staging", Release.Status.IN_PROGRESS),
]


class Command(BaseCommand):
    help = "Insert sample releases (idempotent)."

    def handle(self, *args, **options):
        created = 0
        for service, version, environment, status in SAMPLES:
            _, was_created = Release.objects.get_or_create(
                service=service,
                version=version,
                environment=environment,
                defaults={"status": status, "deployed_by": "seed_demo"},
            )
            created += int(was_created)
        self.stdout.write(self.style.SUCCESS(f"seed_demo: {created} new release(s)"))
