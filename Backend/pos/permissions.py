from rest_framework import permissions

class IsSuperAdmin(permissions.BasePermission):
    """Only SUPER_ADMIN can access"""
    def has_permission(self, request, view):
        return getattr(request.user, "role", None) == "SUPER_ADMIN"

class IsAdminOrHigher(permissions.BasePermission):
    """
    SUPER_ADMIN, OWNER, MANAGER can access.
    CASHIER, FINANCE, HR cannot.
    """
    allowed_roles = ["SUPER_ADMIN", "OWNER", "MANAGER", "FINANCE", "HR"]

    def has_permission(self, request, view):
        return getattr(request.user, "role", None) in self.allowed_roles

class IsCashier(permissions.BasePermission):
    """Only CASHIER can access"""
    def has_permission(self, request, view):
        return getattr(request.user, "role", None) == "CASHIER"
