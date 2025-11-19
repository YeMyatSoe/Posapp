from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import WasteProduct, Product
from django.db import models
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import ProductVariant, Product, OrderItem, WasteProduct

# Update product stock when a variant changes
@receiver([post_save, post_delete], sender=ProductVariant)
def update_product_stock(sender, instance, **kwargs):
    product = instance.product
    total_stock = product.variants.aggregate(total=models.Sum('stock_quantity'))['total'] or 0
    product.stock_quantity = total_stock
    product.save()

# # Reduce variant stock when an order is created
# @receiver(post_save, sender=OrderItem)
# def reduce_variant_stock(sender, instance, created, **kwargs):
#     if created and hasattr(instance, 'variant') and instance.variant:
#         variant = instance.variant
#         variant.stock_quantity -= instance.quantity
#         if variant.stock_quantity < 0:
#             variant.stock_quantity = 0
#         variant.save()

# Reduce variant stock for waste
@receiver(post_save, sender=WasteProduct)
def adjust_variant_stock_waste(sender, instance, created, **kwargs):
    variant = instance.variant
    if created:
        variant.stock_quantity -= instance.quantity
    else:
        # Fetch previous quantity from DB
        old_instance = WasteProduct.objects.get(pk=instance.pk)
        diff = instance.quantity - old_instance.quantity
        variant.stock_quantity -= diff
    if variant.stock_quantity < 0:
        variant.stock_quantity = 0
    variant.save()


###################
# Employee
#####################
from .models import User, Employee

@receiver(post_save, sender=User)
def create_employee_profile(sender, instance, created, **kwargs):
    if created and instance.role in [User.Roles.HR, User.Roles.CASHIER, User.Roles.MANAGER]:
        Employee.objects.create(user=instance, shop=instance.shop)

# ============= New Function Debt Paid & Pay ====================
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from .models import DebtToBePaid


@receiver([post_save, post_delete], sender=DebtToBePaid)
def update_customer_total_debt(sender, instance, **kwargs):
    """Recalculate customer total debt whenever a debt record changes."""
    instance.customer.recalculate_debt()
