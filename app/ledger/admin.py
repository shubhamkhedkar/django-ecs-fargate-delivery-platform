from django.contrib import admin

from ledger.models import Release


@admin.register(Release)
class ReleaseAdmin(admin.ModelAdmin):
    list_display = ("service", "version", "environment", "status", "deployed_by", "created_at")
    list_filter = ("environment", "status")
    search_fields = ("service", "version", "image_digest", "deployed_by")
    date_hierarchy = "created_at"
