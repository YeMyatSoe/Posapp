###############User Control##############
from django.contrib.auth.models import AbstractUser
from django.db import models
from decimal import Decimal, ROUND_HALF_UP
from django.utils import timezone
class User(AbstractUser):
    class Roles(models.TextChoices):
        SUPER_ADMIN = "SUPER_ADMIN", "Super Admin"
        OWNER = "OWNER", "Owner"
        MANAGER = "MANAGER", "Manager"
        FINANCE = "FINANCE", "Finance"
        HR = "HR", "HR"
        CASHIER = "CASHIER", "Cashier"

    role = models.CharField(
        max_length=20,
        choices=Roles.choices,
        default=Roles.CASHIER,
    )

    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
        related_name="users"
    )

    def is_super_admin(self):
        return self.role == self.Roles.SUPER_ADMIN

    def is_owner(self):
        return self.role == self.Roles.OWNER

    def __str__(self):
        return f"{self.username} ({self.role})"

##########By Shop##############
class Shop(models.Model):
    name = models.CharField(max_length=255, unique=True)
    owner = models.OneToOneField(
        "User",
        on_delete=models.CASCADE,
        related_name="owned_shop",
        null=True,
        blank=True
    )
    address = models.TextField(blank=True, null=True)
    phone = models.CharField(max_length=20, blank=True, null=True)
    email = models.EmailField(blank=True, null=True)
    tax_id = models.CharField(max_length=50, blank=True, null=True)  # optional
    registration_number = models.CharField(max_length=50, blank=True, null=True)
    logo = models.ImageField(upload_to="shop_logos/", blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    is_active = models.BooleanField(default=True)

    def __str__(self):
        return f"{self.name} ({'Active' if self.is_active else 'Inactive'})"
    def total_waste_loss(self):
            agg = self.waste_products.aggregate(
                total_loss=Sum(F('quantity') * F('variant__purchase_price'), output_field=DecimalField())
            )
            return agg['total_loss'] or 0

    def total_sales(self):
        agg = self.orders.filter(status="COMPLETED").aggregate(
            total=Sum('total_price')
        )
        return agg['total'] or 0

    def total_cogs(self):
        # Sum of quantity * purchase price for all sold items
        from pos.models import OrderItem
        agg = OrderItem.objects.filter(order__shop=self, order__status="COMPLETED").aggregate(
            total_cogs=Sum(F('quantity') * F('variant__purchase_price'), output_field=DecimalField())
        )
        return agg['total_cogs'] or 0

    def total_expenses(self):
        agg = self.expenses.aggregate(total=Sum('amount'))
        return agg['total'] or 0

    def total_adjustments(self):
        agg = self.adjustments.aggregate(total=Sum('amount'))
        return agg['total'] or 0

    def net_profit(self):
        profit = self.total_sales() - self.total_cogs() - self.total_waste_loss() - self.total_expenses() + self.total_adjustments()
        return profit
############Content&Banner################
class Content(models.Model):
    title = models.CharField(max_length=255)
    body = models.TextField()
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Content"
        verbose_name_plural = "Contents"
        ordering = ["-created_at"]  # newest first

    def __str__(self):
        return self.title

    @classmethod
    def latest_active(cls, n=3):
        return cls.objects.filter(is_active=True).order_by("-created_at")[:n]


class Banner(models.Model):
    title = models.CharField(max_length=255)
    image = models.ImageField(upload_to="banners/")
    link = models.URLField(blank=True, null=True)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Banner"
        verbose_name_plural = "Banners"
        ordering = ["-created_at"]

    def __str__(self):
        return self.title

    @classmethod
    def latest_active(cls, n=3):
        return cls.objects.filter(is_active=True).order_by("-created_at")[:n]

####################### Product Part ########################
from django.db import models
from django.core.validators import MinValueValidator

# ===========================
# Category
# ===========================
class Category(models.Model):
    shop = models.ForeignKey("Shop", on_delete=models.CASCADE, related_name="categories", blank=True, null=True)
    name = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = "Categories"
        unique_together = ("shop", "name")  # prevent duplicate names per shop

    def __str__(self):
        return f"{self.name} ({self.shop.name})"

# ===========================
# Brand
# ===========================
class Brand(models.Model):
    shop = models.ForeignKey("Shop", on_delete=models.CASCADE, related_name="brands", blank=True, null=True)
    name = models.CharField(max_length=255)
    is_active = models.BooleanField(default=True)

    class Meta:
        unique_together = ("shop", "name")

    def __str__(self):
        return f"{self.name} ({self.shop.name})"


# ===========================
# Color
# ===========================
class Color(models.Model):
    name = models.CharField(max_length=50)

    def __str__(self):
        return self.name

# ===========================
# Size
# ===========================
class Size(models.Model):
    name = models.CharField(max_length=50)

    def __str__(self):
        return self.name

# ===========================
# Supplier
# ===========================
class Supplier(models.Model):
    shop = models.ForeignKey("Shop", on_delete=models.CASCADE, related_name="suppliers", blank=True, null=True)
    name = models.CharField(max_length=255)
    phone = models.CharField(max_length=20, blank=True, null=True)
    email = models.EmailField(blank=True, null=True)
    address = models.TextField(blank=True, null=True)

    class Meta:
        unique_together = ("shop", "name")

    def __str__(self):
        return f"{self.name} ({self.shop.name})"

# ===========================
# Product
# ===========================
class Product(models.Model):
    shop = models.ForeignKey("Shop", on_delete=models.CASCADE, related_name="products", blank=True, null=True)
    name = models.CharField(max_length=255)
    category = models.ForeignKey(Category, on_delete=models.CASCADE)
    brand = models.ForeignKey(Brand, on_delete=models.SET_NULL, null=True, blank=True)
    colors = models.ManyToManyField("Color", blank=True)
    sizes = models.ManyToManyField("Size", blank=True)
    supplier = models.ForeignKey(Supplier, on_delete=models.SET_NULL, null=True, blank=True)

    stock_quantity = models.PositiveIntegerField(default=0)
    purchase_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(0)])
    sale_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(0)])
    is_active = models.BooleanField(default=True)
    image = models.ImageField(upload_to="product_images/", null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

#     class Meta:
#         unique_together = ("shop", "name")  # Product names unique within shop

    def __str__(self):
        return f"{self.name} ({self.shop.name})"

class ProductVariant(models.Model):
    product = models.ForeignKey(Product, on_delete=models.CASCADE, related_name="variants")
    color = models.ForeignKey(Color, on_delete=models.SET_NULL, null=True, blank=True)
    size = models.ForeignKey(Size, on_delete=models.SET_NULL, null=True, blank=True)
    barcode = models.CharField(
        max_length=50,  # Adjust max_length based on your barcode standard (e.g., 13 for EAN-13)
        unique=True,
        null=True,      # Allow null values in the database
        blank=True,     # Allow the field to be left empty in forms/admin
        help_text="EAN, UPC, or custom product code"
    )
    stock_quantity = models.PositiveIntegerField(default=0)
    purchase_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(0)])
    sale_price = models.DecimalField(max_digits=10, decimal_places=2, validators=[MinValueValidator(0)])

    class Meta:
        unique_together = ("product", "color", "size")  # Each combination is unique

    def __str__(self):
        name_parts = [self.product.name]
        if self.color:
            name_parts.append(str(self.color))
        if self.size:
            name_parts.append(str(self.size))
        return " / ".join(name_parts)

# ===========================
# WasteProduct (lost/damaged)
# ===========================
class WasteProduct(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="waste_products",
        blank=True,
        null=True
    )
    variant = models.ForeignKey(
        "ProductVariant",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="wastes"
    )

    quantity = models.PositiveIntegerField(default=0)
    reason = models.CharField(max_length=255, blank=True, null=True)
    recorded_at = models.DateTimeField(auto_now_add=True)

    color_name = models.CharField(max_length=100, null=True, blank=True)
    size_name = models.CharField(max_length=100, null=True, blank=True)
    waste_value = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    def save(self, *args, **kwargs):
        if self.variant:
            # snapshot color/size names
            self.color_name = self.variant.color.name if self.variant.color else None
            self.size_name = self.variant.size.name if self.variant.size else None

            # check and reduce stock
            if self.variant.stock_quantity >= self.quantity:
                self.variant.stock_quantity -= self.quantity
                self.variant.save()
            else:
                raise ValueError(f"Not enough stock to mark as waste for {self.variant}")

            # snapshot waste value at save time
            if self.variant.purchase_price:  # <- correct field name
                self.waste_value = Decimal(self.quantity) * self.variant.purchase_price

        super().save(*args, **kwargs)

    def __str__(self):
        return f"{self.variant} - {self.quantity} wasted ({self.shop.name if self.shop else 'No Shop'})"

    @property
    def total_loss_value(self):
        return self.waste_value

# ========================New Function Debt ==================
from decimal import Decimal
from django.db import models
from django.db.models import Sum, F, DecimalField
from django.utils import timezone


class Customer(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="customers"
    )

    name = models.CharField(max_length=255)
    phone = models.CharField(max_length=20, blank=True, null=True)
    email = models.EmailField(blank=True, null=True)
    address = models.TextField(blank=True, null=True)

    total_debt = models.DecimalField(
        max_digits=12, decimal_places=2, default=Decimal("0.00"),
        help_text="Total outstanding amount owed by this customer."
    )

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        unique_together = ("shop", "phone")
        ordering = ["name"]

    def __str__(self):
        return f"{self.name} ({self.shop.name})"

    # ---- Helper methods ----
    def add_debt(self, amount):
        """Increase customer's outstanding balance."""
        self.total_debt += Decimal(amount)
        self.save(update_fields=["total_debt"])

    def pay_debt(self, amount):
        """Reduce customer's outstanding balance."""
        self.total_debt = max(Decimal("0.00"), self.total_debt - Decimal(amount))
        self.save(update_fields=["total_debt"])

    def recalculate_debt(self):
        """
        Re-sync total_debt by summing the 'remaining_amount'
        of all debts that are not fully 'PAID'.
        """
        total = self.debts_to_be_paid.exclude(status="PAID").aggregate(
            total=Sum("remaining_amount", output_field=DecimalField())
        )["total"] or Decimal("0.00")

        self.total_debt = total
        self.save(update_fields=["total_debt"])
#         =========================================
# ======================
class Order(models.Model):
    shop = models.ForeignKey("Shop", on_delete=models.CASCADE, related_name="orders")
    user = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    customer = models.ForeignKey(Customer, on_delete=models.SET_NULL, null=True, blank=True)
    total_price = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    paid_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    STATUS_CHOICES = [
        ("PENDING", "Pending"),
        ("COMPLETED", "Completed"),
        ("CANCELLED", "Cancelled"),
    ]
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="PENDING")

    @property
    def debt_amount(self):
        return self.total_price - self.paid_amount

    def __str__(self):
        return f"Order #{self.id} - {self.shop.name}"
class OrderItem(models.Model):
    order = models.ForeignKey(Order, related_name='items', on_delete=models.CASCADE)
    variant = models.ForeignKey(
        'ProductVariant',
        on_delete=models.SET_NULL,
        null=True,
        blank=True
    )

    quantity = models.PositiveIntegerField(default=1)
    price = models.DecimalField(max_digits=10, decimal_places=2)

    # Store names for historical record
    color_name = models.CharField(max_length=100, null=True, blank=True)
    size_name = models.CharField(max_length=100, null=True, blank=True)

    def save(self, *args, **kwargs):
        if self.variant:
            self.color_name = self.variant.color.name if self.variant.color else None
            self.size_name = self.variant.size.name if self.variant.size else None
            self.price = self.variant.sale_price * self.quantity
        super().save(*args, **kwargs)
    def process_order(order):
        for item in order.items.all():
            variant = item.variant
            if variant.stock_quantity >= item.quantity:
                variant.stock_quantity -= item.quantity
                variant.save()
            else:
                raise ValueError(f"Not enough stock for {variant}")

from django.db import models
from django.core.validators import MinValueValidator
# Assuming the following models are available via import or defined earlier:
# from .user_control import User
# from .shop import Shop

# ===========================
# Expense
# Tracks general operating costs affecting P&L (e.g., rent, utilities, salaries)
# ===========================
class Expense(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="expenses"
    )
    user = models.ForeignKey(
        "User",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="recorded_expenses",
        help_text="User who recorded the expense."
    )

    date = models.DateField(
        help_text="The date the expense was incurred or recorded."
    )

    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        validators=[MinValueValidator(0)],
        help_text="The amount of the expense."
    )

    description = models.TextField(
        help_text="Detailed description of the expense."
    )

    # Predefined choices for expense classification
    EXPENSE_CATEGORIES = [
        ("RENT", "Rent/Lease"),
        ("UTILITY", "Utilities (Electric, Water)"),
        ("SALARY", "Salaries & Wages"),
        ("MARKETING", "Marketing & Advertising"),
        ("SUPPLIES", "Office Supplies"),
        ("OTHER", "Other"),
    ]
    category = models.CharField(
        max_length=50,
        choices=EXPENSE_CATEGORIES,
        default="OTHER",
        help_text="Category of the expense for reporting."
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date", "-created_at"]
        verbose_name = "Operating Expense"
        verbose_name_plural = "Operating Expenses"

    def __str__(self):
        return f"{self.shop.name} - {self.category} Expense on {self.date}: ${self.amount}"


# ===========================
# Adjustment
# A flexible ledger entry for non-standard financial events
# ===========================
class Adjustment(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="adjustments"
    )
    user = models.ForeignKey(
        "User",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        help_text="User who recorded the adjustment."
    )

    date = models.DateField()

    # Allows tracking both positive (gain) and negative (loss/write-off) adjustments
    amount = models.DecimalField(
        max_digits=12,
        decimal_places=2,
        help_text="The positive or negative adjustment amount."
    )

    description = models.TextField(
        help_text="Reason for the adjustment (e.g., inventory write-off, bank error correction)."
    )

    ADJUSTMENT_TYPES = [
        ("GAIN", "Gain"),
        ("LOSS", "Loss/Write-off"),
        ("CORRECTION", "Correction"),
    ]
    adjustment_type = models.CharField(
        max_length=20,
        choices=ADJUSTMENT_TYPES,
        default="CORRECTION",
    )

    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-date", "-created_at"]
        verbose_name = "Financial Adjustment"
        verbose_name_plural = "Financial Adjustments"

    def __str__(self):
        return f"{self.shop.name} - {self.adjustment_type} Adjustment on {self.date}: ${self.amount}"


#=================
# Employee
#=================
class Employee(models.Model):
    STATUS_CHOICES = [
        ('Active', 'Active'),
        ('Inactive', 'Inactive'),
        ('On Leave', 'On Leave'),
        ('Terminated', 'Terminated'),
    ]

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='employee_profile')
    shop = models.ForeignKey(Shop, on_delete=models.CASCADE, related_name='employees') # Assuming Shop is imported
    salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    join_date = models.DateField(default=timezone.now)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='Active')

    def __str__(self):
        return self.user.username
# --------------------Holiday ---------------------
class Holiday(models.Model):
    """
    Model to store official public or company holidays.
    These days are excluded from the 'Total Expected Working Days' count.
    """
    date = models.DateField(unique=True) # The date of the holiday
    name = models.CharField(max_length=100) # Name of the holiday (e.g., 'Christmas Day')

    def __str__(self):
        return f"{self.name} ({self.date})"

    class Meta:
        verbose_name_plural = "Holidays"
# ----------------- Attendance Model -----------------
from django.utils import timezone

class Attendance(models.Model):
    STATUS_CHOICES = [
        ('Present', 'Present'),
        ('On Time', 'On Time'),       # Added for common time-in distinction
        ('Absent', 'Absent'),
        ('Paid Leave', 'Paid Leave'), # Important: Treat this as 'Present' for payroll
        ('Unpaid Leave', 'Unpaid Leave'), # Important: Treat this as 'Absent' for payroll
    ]

    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='attendances')
    date = models.DateField(default=timezone.now)
    clock_in = models.TimeField(blank=True, null=True)
    clock_out = models.TimeField(blank=True, null=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='Present')

    def __str__(self):
        return f"{self.employee.user.username} - {self.date} ({self.status})"
# Define the choices for the rating
RATING_CHOICES = [
    ('Best', 'Best'),
    ('Very Good', 'Very Good'),
    ('Good', 'Good'),
    ('Average', 'Average'),
    ('Poor', 'Poor'),
    ('N/A', 'Not Applicable'),
]

class Performance(models.Model):
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='performances')
    kpi = models.CharField(max_length=255)
    review = models.TextField(blank=True)
    date = models.DateField(default=timezone.now)

    # 🎯 FIX 1: Add the rating field
    rating = models.CharField(
        max_length=20,
        choices=RATING_CHOICES,
        default='N/A' # Default to N/A or a similar non-bonus state
    )

    def __str__(self):
        return f"{self.employee.user.username} - {self.rating} ({self.date.year})"

# ----------------- Payroll Model -----------------
class Payroll(models.Model):
    employee = models.ForeignKey(Employee, on_delete=models.CASCADE, related_name='payrolls')
    salary = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    bonus = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    overtime = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    performance_bonus = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    deductions = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    absent_days = models.IntegerField(default=0)

    # 🚨 NEW FIELD: Stores the manual monetary amount for the absent deduction
    absent_deduction_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    date = models.DateField(default=timezone.now)
    month = models.CharField(max_length=20, blank=True, null=True)

    @property
    def net_pay(self):
        # Convert all fields used in the calculation to Decimal
        salary = Decimal(self.salary)
        bonus = Decimal(self.bonus)
        overtime = Decimal(self.overtime)
        performance_bonus = Decimal(self.performance_bonus)
        deductions = Decimal(self.deductions)

        # 🚨 FIX: Use the manually saved deduction amount instead of calculating it.
        # This corresponds to the value submitted by your Flutter form.
        absent_deduction = Decimal(self.absent_deduction_amount)

        # The net pay calculation now uses the manual price.
        total = salary + bonus + overtime + performance_bonus - deductions - absent_deduction

        return total.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)

    def __str__(self):
        return f"{self.employee.user.username} - Payroll {self.date}"

# ============== New Function Debt Paid & Pay ======================


from decimal import Decimal
from django.db import models
from django.utils import timezone


# --- Customer owes shop ---
class DebtToBePaid(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="debts_to_be_paid"
    )
    customer = models.ForeignKey(
        "Customer",
        on_delete=models.CASCADE,
        related_name="debts_to_be_paid"
    )
    order = models.ForeignKey(
        "Order",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name="customer_debt"
    )

    amount = models.DecimalField(max_digits=12, decimal_places=2)
    status = models.CharField(
        max_length=20,
        choices=[
            ("UNPAID", "Unpaid"),
            ("PARTIAL", "Partially Paid"),
            ("PAID", "Paid"),
        ],
        default="UNPAID"
    )
    paid_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)
    remaining_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0)

    due_date = models.DateField(blank=True, null=True)
    note = models.TextField(blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.customer.name} owes {self.amount} ({self.status})"

    def mark_paid(self, payment_amount):
        # ... (code for applying payment to self.remaining_amount and setting status) ...

        self.save()

        # 💥 FIX: Call the database-level recalculation
        self.customer.recalculate_debt()
# --- Shop owes supplier ---
class DebtToPay(models.Model):
    shop = models.ForeignKey(
        "Shop",
        on_delete=models.CASCADE,
        related_name="debts_to_pay"
    )
    supplier = models.ForeignKey(
        "Supplier",
        on_delete=models.CASCADE,
        related_name="debts_to_receive"
    )
    product = models.ForeignKey(
        "Product",
        on_delete=models.CASCADE,
        related_name="debts",
        null=True,
        blank=True
    )

    total_amount = models.DecimalField(max_digits=12, decimal_places=2, blank=True, null=True)
    paid_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0, blank=True, null=True)
    remaining_amount = models.DecimalField(max_digits=12, decimal_places=2, blank=True, null=True)

    status = models.CharField(
        max_length=20,
        choices=[
            ("UNPAID", "Unpaid"),
            ("PARTIAL", "Partially Paid"),
            ("PAID", "Paid"),
        ],
        default="UNPAID"
    )

    due_date = models.DateField(blank=True, null=True)
    note = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.shop.name} owes {self.supplier.name} {self.remaining_amount} ({self.status})"

    def mark_paid(self, payment_amount):
        payment_amount = Decimal(payment_amount)
        self.paid_amount += payment_amount
        self.remaining_amount -= payment_amount
        if self.remaining_amount <= 0:
            self.status = "PAID"
            self.remaining_amount = Decimal("0.00")
        else:
            self.status = "PARTIAL"
        self.save()