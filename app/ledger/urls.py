from django.urls import path

from ledger import views

app_name = "ledger"

urlpatterns = [
    path("", views.index, name="index"),
    path("api/releases/", views.release_list, name="release-list"),
    path("api/releases/current/", views.release_summary, name="release-summary"),
    path("version", views.version, name="version"),
]
