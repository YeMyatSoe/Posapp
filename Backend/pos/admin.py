from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from django.core.exceptions import ValidationError
from .models import User, Shop, Content, Banner, ProductVariant, Product

# ===========================
# Super Admin Only Admin
# ===========================

from rest_framework.authtoken.models import Token

# Register Token model so it appears in admin
admin.site.register(Token)

class SuperAdminOnlyAdmin(admin.ModelAdmin):
    """
    Only Super Admin can see/manage these models
    """
    def has_module_permission(self, request):
        return request.user.is_authenticated and request.user.is_super_admin()

    def has_view_permission(self, request, obj=None):
        return request.user.is_authenticated and request.user.is_super_admin()

    def has_add_permission(self, request):
        return request.user.is_authenticated and request.user.is_super_admin()

    def has_change_permission(self, request, obj=None):
        return request.user.is_authenticated and request.user.is_super_admin()

    def has_delete_permission(self, request, obj=None):
        return request.user.is_authenticated and request.user.is_super_admin()

# ===========================
# User Inline for Shop
# ===========================
class UserInline(admin.TabularInline):
    model = User
    extra = 0

    def get_queryset(self, request):
        qs = super().get_queryset(request)  # << define qs here
        if request.user.is_super_admin():
            return qs
        elif request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]:
            return qs.filter(shop=request.user.owned_shop)
        else:
            return qs.none()

    def has_add_permission(self, request, obj=None):
        return request.user.is_authenticated and (
            request.user.is_super_admin() or request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]
        )

    # ===========================
# Custom User Admin
# ===========================
@admin.register(User)
class CustomUserAdmin(UserAdmin):
    fieldsets = UserAdmin.fieldsets + (
        ("Role & Shop", {"fields": ("role", "shop")}),
    )
    list_display = ("username", "email", "role", "shop", "is_staff")

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_super_admin():
            return qs  # Super Admin sees all users
        elif request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]:
            # Can see users of their shop
            return qs.filter(shop=request.user.owned_shop)
        else:
            return qs.none()

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        # Restrict shop assignment for non-super-admins
        if db_field.name == "shop" and not request.user.is_super_admin():
            kwargs["queryset"] = Shop.objects.filter(id=request.user.owned_shop.id)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def formfield_for_choice_field(self, db_field, request, **kwargs):
        # Restrict role assignment
        if db_field.name == "role" and not request.user.is_super_admin():
            allowed_roles = [r for r in User.Roles.choices if r[0] != User.Roles.SUPER_ADMIN]
            kwargs["choices"] = allowed_roles
        return super().formfield_for_choice_field(db_field, request, **kwargs)

    # Control add/edit/delete permissions
    def has_add_permission(self, request):
        return request.user.is_authenticated and (
            request.user.is_super_admin() or request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]
        )

    def has_change_permission(self, request, obj=None):
        return request.user.is_authenticated and (
            request.user.is_super_admin() or request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]
        )

    def has_delete_permission(self, request, obj=None):
        return request.user.is_authenticated and (
            request.user.is_super_admin() or request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]
        )

    def save_model(self, request, obj, form, change):
        # Non-super-admins cannot assign SUPER_ADMIN role
        if not request.user.is_super_admin() and obj.role == User.Roles.SUPER_ADMIN:
            raise ValidationError("Only Super Admin can assign SUPER_ADMIN role.")

        # Non-super-admins cannot assign users to another shop
        if not request.user.is_super_admin() and obj.shop != request.user.owned_shop:
            raise ValidationError("You can only assign users to your own shop.")

        super().save_model(request, obj, form, change)

# ===========================
# Shop Admin
# ===========================
@admin.register(Shop)
class ShopAdmin(admin.ModelAdmin):
    list_display = ("name", "owner", "is_active")
    inlines = [UserInline]

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        if request.user.is_super_admin():
            return qs
        elif request.user.is_owner():
            # Owner can only see their shop
            return qs.filter(id=request.user.owned_shop.id)
        else:
            return qs.none()

    # Only Super Admin can add shops
    def has_add_permission(self, request):
        return request.user.is_authenticated and request.user.is_super_admin()

    # Only Super Admin can change shops (except maybe their own inline)
    def has_change_permission(self, request, obj=None):
        if request.user.is_super_admin():
            return True
        if obj and (request.user.is_owner() or request.user.role in [User.Roles.MANAGER, User.Roles.HR]):
            return obj == request.user.owned_shop
        return False


    # Only Super Admin can delete shops
    def has_delete_permission(self, request, obj=None):
        return request.user.is_authenticated and request.user.is_super_admin()

# ===========================
# Global Models Only Super Admin
# ===========================
admin.site.register(Content, SuperAdminOnlyAdmin)
admin.site.register(Banner, SuperAdminOnlyAdmin)
class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 1

@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    inlines = [ProductVariantInline]