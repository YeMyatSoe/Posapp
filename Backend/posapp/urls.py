from django.contrib import admin
from django.urls import path, include   # ✅ include added
from django.conf import settings
from django.conf.urls.static import static
urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('pos.urls')),  # now works
    path('reports/', include('pos.urls')),
]
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)