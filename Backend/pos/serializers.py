from rest_framework import serializers
import json
from django.contrib.auth import get_user_model
from .models import (
    Shop, Content, Banner,
    Category, Brand, Color, Size, Supplier,
    Product, WasteProduct, Order, OrderItem, ProductVariant, DebtToPay
)
import json  # <-- ADD THIS IMPORT
from django.db import transaction
User = get_user_model()


# ==========================
# User & Shop
# ==========================
class ShopSerializer(serializers.ModelSerializer):
    class Meta:
        model = Shop
        fields = [
            "id", "name", "owner", "address", "phone", "email",
            "tax_id", "registration_number", "logo",
            "created_at", "updated_at", "is_active"
        ]


class UserSerializer(serializers.ModelSerializer):
    shop = ShopSerializer(read_only=True)
    shop_id = serializers.PrimaryKeyRelatedField(
        queryset=Shop.objects.all(), source="shop", write_only=True, allow_null=True
    )

    class Meta:
        model = User
        fields = [
            "id", "username", "email", "first_name", "last_name",
            "role", "is_active", "is_staff", "is_superuser",
            "shop", "shop_id"
        ]

class UserSignupSerializer(serializers.Serializer):
    username = serializers.CharField()
    email = serializers.EmailField()
    password = serializers.CharField()
    role = serializers.ChoiceField(choices=[
        ("OWNER", "Owner"),
        ("MANAGER", "Manager"),
        ("FINANCE", "Finance"),
        ("HR", "HR"),
        ("CASHIER", "Cashier"),
    ])
    shop_name = serializers.CharField(required=False, allow_blank=True)
    shop = serializers.IntegerField(required=False)
# ==========================
# Content & Banner
# ==========================
class ContentSerializer(serializers.ModelSerializer):
    class Meta:
        model = Content
        fields = ["id", "title", "body", "is_active", "created_at", "updated_at"]


class BannerSerializer(serializers.ModelSerializer):
    class Meta:
        model = Banner
        fields = ["id", "title", "image", "link", "is_active", "created_at", "updated_at"]


# ==========================
# Product-related models
# ==========================
class CategorySerializer(serializers.ModelSerializer):
    shop = ShopSerializer(read_only=True)
    shop_id = serializers.PrimaryKeyRelatedField(
        queryset=Shop.objects.all(), source="shop", write_only=True
    )

    class Meta:
        model = Category
        fields = ["id", "name", "is_active", "shop", "shop_id"]


# ==========================
# Brand
# ==========================
class BrandSerializer(serializers.ModelSerializer):
    shop = ShopSerializer(read_only=True)
    shop_id = serializers.PrimaryKeyRelatedField(
        queryset=Shop.objects.all(), source="shop", write_only=True
    )

    class Meta:
        model = Brand
        fields = ["id", "name", "is_active", "shop", "shop_id"]



class ColorSerializer(serializers.ModelSerializer):
    class Meta:
        model = Color
        fields = ["id", "name"]


class SizeSerializer(serializers.ModelSerializer):
    class Meta:
        model = Size
        fields = ["id", "name"]

# ==========================
# Supplier
# ==========================
from django.db.models import Sum

class SupplierSerializer(serializers.ModelSerializer):
    shop = ShopSerializer(read_only=True)
    shop_id = serializers.PrimaryKeyRelatedField(
        queryset=Shop.objects.all(), source="shop", write_only=True
    )
    remaining_amount = serializers.SerializerMethodField()

    class Meta:
        model = Supplier
        fields = ["id", "name", "phone", "email", "address", "shop", "shop_id", "remaining_amount"]

    def get_remaining_amount(self, obj):
        # obj is a Supplier instance
        return DebtToPay.objects.filter(supplier=obj).aggregate(
            total=Sum('remaining_amount')
        )['total'] or 0


class DebtToPaySerializer(serializers.ModelSerializer):
    class Meta:
        model = DebtToPay
        fields = "__all__"

    # ---------------- ProductVariant Serializer (Remains the same) ----------------
class ProductVariantSerializer(serializers.ModelSerializer):
    color_name = serializers.CharField(source='color.name', read_only=True)
    size_name = serializers.CharField(source='size.name', read_only=True)

    barcode = serializers.CharField(required=False, allow_null=True)

    # Pack fields
    is_pack = serializers.BooleanField(required=False)
    units_per_pack = serializers.IntegerField(required=False)
    linked_single_variant = serializers.PrimaryKeyRelatedField(
        queryset=ProductVariant.objects.all(),
        required=False,
        allow_null=True
    )
    single_sale_price = serializers.DecimalField(
        max_digits=10, decimal_places=2,
        required=False, allow_null=True
    )
    pack_sale_price = serializers.DecimalField(
        max_digits=10, decimal_places=2,
        required=False, allow_null=True
    )

    effective_price = serializers.ReadOnlyField()

    class Meta:
        model = ProductVariant
        fields = [
            "id", "color", "color_name", "size", "size_name",
            "stock_quantity", "barcode",
            "sale_price", "single_sale_price", "pack_sale_price",
            "is_pack", "units_per_pack", "linked_single_variant",
            "effective_price"
        ]


# ===========================
# Product Serializer
# ===========================
class ProductSerializer(serializers.ModelSerializer):
    # Dynamic total stock
    stock_quantity = serializers.SerializerMethodField(read_only=True)

    # Keep slugs, write-only ids, variants, colors/sizes as before
    shop = serializers.SlugRelatedField(read_only=True, slug_field="name")
    category = serializers.SlugRelatedField(read_only=True, slug_field="name")
    brand = serializers.SlugRelatedField(read_only=True, slug_field="name")
    supplier = serializers.SlugRelatedField(read_only=True, slug_field="name")
    shop_id = serializers.PrimaryKeyRelatedField(queryset=Shop.objects.all(), source="shop", write_only=True)
    category_id = serializers.PrimaryKeyRelatedField(queryset=Category.objects.all(), source="category", write_only=True)
    brand_id = serializers.PrimaryKeyRelatedField(queryset=Brand.objects.all(), source="brand", allow_null=True, required=False, write_only=True)
    supplier_id = serializers.PrimaryKeyRelatedField(queryset=Supplier.objects.all(), source="supplier", allow_null=True, required=False, write_only=True)

    colors = serializers.SlugRelatedField(many=True, read_only=True, slug_field="name")
    sizes = serializers.SlugRelatedField(many=True, read_only=True, slug_field="name")
    color_ids = serializers.PrimaryKeyRelatedField(queryset=Color.objects.all(), source="colors", many=True, write_only=True, required=False)
    size_ids = serializers.PrimaryKeyRelatedField(queryset=Size.objects.all(), source="sizes", many=True, write_only=True, required=False)

    variants = ProductVariantSerializer(many=True, read_only=True)
    variants_json = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = Product
        fields = [
            "id", "name", "stock_quantity",
            "category", "brand", "supplier",
            "colors", "sizes",
            "category_id", "brand_id", "supplier_id",
            "color_ids", "size_ids",
            "variants", "variants_json",
            "image", "shop", "shop_id"
        ]
        read_only_fields = ["stock_quantity"]

    # Dynamic stock calculation
    def get_min_purchase_price(self, obj):
        prices = [v.purchase_price for v in obj.variants.all()]
        return min(prices) if prices else None

    def get_stock_quantity(self, obj):
        return sum(v.stock_quantity for v in obj.variants.all())


    # ===========================================
    # Helpers
    # ===========================================
    def _parse_variants(self, variants_raw):
        try:
            return json.loads(variants_raw or "[]")
        except json.JSONDecodeError:
            raise serializers.ValidationError("Invalid variants_json payload.")

    def _create_or_update_variant(self, product, v_data):
        variant_id = v_data.pop("id", None)

        if variant_id:
            ProductVariant.objects.filter(id=variant_id, product=product).update(**v_data)
        else:
            ProductVariant.objects.create(product=product, **v_data)

    # ===========================================
    # Create
    # ===========================================
    @transaction.atomic
    def create(self, validated_data):
        color_ids = validated_data.pop("colors", [])
        size_ids = validated_data.pop("sizes", [])
        variants_raw = validated_data.pop("variants_json", "")

        product = Product.objects.create(**validated_data)

        if color_ids:
            product.colors.set(color_ids)
        if size_ids:
            product.sizes.set(size_ids)

        variants = self._parse_variants(variants_raw)

        for v_data in variants:
            v_data.setdefault("purchase_price", product.purchase_price)
            v_data.setdefault("sale_price", product.sale_price)
            ProductVariant.objects.create(product=product, **v_data)

        return product

    # ===========================================
    # Update
    # ===========================================
    @transaction.atomic
    def update(self, instance, validated_data):
        color_ids = validated_data.pop("colors", None)
        size_ids = validated_data.pop("sizes", None)
        variants_raw = validated_data.pop("variants_json", "")

        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()

        if color_ids is not None:
            instance.colors.set(color_ids)
        if size_ids is not None:
            instance.sizes.set(size_ids)

        variants = self._parse_variants(variants_raw)

        for v_data in variants:
            self._create_or_update_variant(instance, v_data)

        return instance
# ===========================
# Waste Product Serializer
# ===========================
class WasteProductSerializer(serializers.ModelSerializer):
    shop = serializers.StringRelatedField(read_only=True)
    shop_id = serializers.PrimaryKeyRelatedField(
        queryset=Shop.objects.all(), source="shop", write_only=True
    )

    variant = serializers.StringRelatedField(read_only=True)
    variant_id = serializers.PrimaryKeyRelatedField(
        queryset=ProductVariant.objects.all(), source="variant", write_only=True
    )

    product_name = serializers.CharField(source="variant.product.name", read_only=True)
    color_name = serializers.CharField(read_only=True)
    size_name = serializers.CharField(read_only=True)
    unit_purchase_price = serializers.DecimalField(
        source="variant.purchase_price", max_digits=12, decimal_places=2, read_only=True
    )
    total_loss_value = serializers.DecimalField(
        source="waste_value", max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = WasteProduct
        fields = [
            "id", "shop", "shop_id",
            "variant", "variant_id", "product_name",
            "color_name", "size_name",
            "quantity", "reason", "recorded_at",
            "unit_purchase_price", "total_loss_value"
        ]


# ===========================
# Low Stock Serializer
# ===========================
class LowStockVariantSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='product.name', read_only=True)
    color_name = serializers.CharField(source='color.name', read_only=True)
    size_name = serializers.CharField(source='size.name', read_only=True)

    class Meta:
        model = ProductVariant
        fields = ['id', 'product_name', 'color_name', 'size_name', 'stock_quantity']


# ===========================
# Order & OrderItem Serializers
# ===========================
class OrderItemSerializer(serializers.ModelSerializer):
    product_name = serializers.CharField(source='variant.product.name', read_only=True)
    color_name = serializers.CharField(required=False, allow_null=True)
    size_name = serializers.CharField(required=False, allow_null=True)
    variant = serializers.PrimaryKeyRelatedField(queryset=ProductVariant.objects.all())
    units_per_pack = serializers.IntegerField(required=False, default=1)

    class Meta:
        model = OrderItem
        fields = ["variant", "product_name", "color_name", "size_name", "quantity", "units_per_pack", "price"]
        read_only_fields = ["product_name", "price"]


from decimal import Decimal
from django.db import transaction

class OrderSerializer(serializers.ModelSerializer):
    items = OrderItemSerializer(many=True)
    customer_name = serializers.CharField(source='customer.name', read_only=True)  # <-- new field

    class Meta:
        model = Order
        fields = [
            "id", "shop", "user", "total_price", "status",
            "created_at", "items", "paid_amount", "customer_id", "customer_name"
        ]
        read_only_fields = ["total_price", "status", "created_at", "customer_name"]

    @transaction.atomic
    def create(self, validated_data):
        items_data = validated_data.pop("items")
        user = validated_data.pop("user", None)
        customer_id = validated_data.pop("customer_id", None)
        paid_amount = validated_data.get("paid_amount", Decimal("0"))

        order = Order.objects.create(user=user, **validated_data)

        total_price = Decimal("0")

        for item_data in items_data:
            variant = item_data["variant"]
            qty = int(item_data["quantity"])

            # Determine correct price
            if qty == variant.units_per_pack and variant.is_pack:
                price = Decimal(variant.pack_sale_price)
            else:
                price = Decimal(variant.single_sale_price)

            # Reduce stock
            variant.reduce_stock(qty)

            OrderItem.objects.create(
                order=order,
                variant=variant,
                quantity=qty,
                units_per_pack=variant.units_per_pack if variant.is_pack else 1,
                price=price,
                color_name=variant.color.name if variant.color else None,
                size_name=variant.size.name if variant.size else None,
            )

            # Add price * quantity only for single units; pack already counted as whole
            if qty == variant.units_per_pack and variant.is_pack:
                total_price += price
            else:
                total_price += price * qty

        order.total_price = total_price

        # Attach customer if provided
        customer_id = self.initial_data.get("customer_id")
        if customer_id:
            try:
                customer = Customer.objects.get(id=customer_id, shop=order.shop)
                order.customer = customer
            except Customer.DoesNotExist:
                pass


        order.save()
        return order



from rest_framework import serializers
from decimal import Decimal

# --- Nested Detail Serializers (for tables) ---

class WasteItemSerializer(serializers.Serializer):
    """Serializes a single wasted item detail for the waste table."""
    date = serializers.DateField()
    product_name = serializers.CharField(max_length=255)
    sku = serializers.CharField(max_length=255)
    category = serializers.CharField(max_length=255)
    quantity = serializers.IntegerField()
    unit_purchase_price = serializers.DecimalField(max_digits=10, decimal_places=2)
    loss_value = serializers.DecimalField(max_digits=12, decimal_places=2)
    reason = serializers.CharField(max_length=255, allow_null=True)

from .models import Expense, Adjustment

class ExpenseSerializer(serializers.ModelSerializer):
    shop_name = serializers.ReadOnlyField(source='shop.name')
    user_name = serializers.ReadOnlyField(source='user.username')

    class Meta:
        model = Expense
        fields = [
            'id', 'shop', 'shop_name', 'user', 'user_name',
            'date', 'amount', 'description', 'category', 'created_at'
        ]

class AdjustmentSerializer(serializers.ModelSerializer):
    # 1. Read-only fields for display
    # These fields are included in the JSON response but cannot be written to.
    shop_name = serializers.ReadOnlyField(source='shop.name')
    user_name = serializers.ReadOnlyField(source='user.username')

    # 2. Explicitly define 'amount' as DecimalField with min/max values
    # DRF usually infers this, but being explicit can ensure consistency.
    # Note: When DRF sends this to Flutter, it typically comes as a string,
    # which requires safe parsing in Flutter's Adjustment.fromJson.
    amount = serializers.DecimalField(
        max_digits=12,
        decimal_places=2,
        required=True, # Ensure it is explicitly marked as required
        # You could add min_value=0 if 'LOSS' adjustments were handled by a negative sign
        # But since you have 'LOSS' type, any sign might be allowed initially.
    )

    class Meta:
        model = Adjustment
        fields = [
            'id', 'shop', 'shop_name', 'user', 'user_name',
            'date', 'amount', 'description', 'adjustment_type', 'created_at'
        ]

        # 3. Security and Workflow
        read_only_fields = ['created_at', 'user', 'shop_name', 'user_name']

    # 4. Optional: Custom Validation for GAIN/LOSS consistency
    def validate(self, data):
        """
        Check that GAIN is generally positive and LOSS is generally negative/zero.
        This helps prevent logic errors in the front-end data entry.
        """
        amount = data.get('amount')
        adjustment_type = data.get('adjustment_type')

        if amount is not None and adjustment_type:
            if adjustment_type == 'GAIN' and amount < 0:
                raise serializers.ValidationError(
                    {"amount": "GAIN adjustments must be a positive amount."}
                )
            if adjustment_type == 'LOSS' and amount > 0:
                # Allowing 0 here might be appropriate for a correction with no value change
                raise serializers.ValidationError(
                    {"amount": "LOSS/Write-off adjustments must be zero or negative."}
                )

        return data
class PLItemSerializer(serializers.Serializer):
    """Serializes a single item's contribution to Profit/Loss."""
    product_name = serializers.CharField(max_length=255)
    sku = serializers.CharField(max_length=255)
    quantity_sold = serializers.IntegerField()
    unit_sale_price = serializers.DecimalField(max_digits=10, decimal_places=2)
    unit_cogs = serializers.DecimalField(max_digits=10, decimal_places=2)
    waste_qty = serializers.IntegerField(default=0)
    waste_loss = serializers.DecimalField(max_digits=12, decimal_places=2, default=Decimal('0.00'))
    revenue = serializers.DecimalField(max_digits=12, decimal_places=2)
    cogs = serializers.DecimalField(max_digits=12, decimal_places=2)
    profit = serializers.DecimalField(max_digits=12, decimal_places=2)


# --- Main Report Serializer ---

class ShopReportSerializer(serializers.Serializer):
    """The main serializer for the comprehensive shop report."""

    # Summary Fields
    start_date = serializers.DateField()
    end_date = serializers.DateField()

    # P&L Summary
    total_revenue = serializers.DecimalField(max_digits=15, decimal_places=2)
    total_cogs = serializers.DecimalField(max_digits=15, decimal_places=2)
    total_waste_loss = serializers.DecimalField(max_digits=15, decimal_places=2)
    total_expenses = serializers.DecimalField(max_digits=15, decimal_places=2)
    total_adjustments = serializers.DecimalField(max_digits=15, decimal_places=2)
    gross_profit = serializers.DecimalField(max_digits=15, decimal_places=2)
    net_profit = serializers.DecimalField(max_digits=15, decimal_places=2)

    # Detailed Data
    waste_details = WasteItemSerializer(many=True)
    pl_details = PLItemSerializer(many=True)
    monthly_comparison = serializers.ListField()  # <-- ADD THIS
    # Note: Sales Summary is typically calculated from total_revenue

#==============
# Employee
#==================
from rest_framework import serializers
from .models import Employee, Attendance, Performance, Payroll

class EmployeeSerializer(serializers.ModelSerializer):
    user = UserSerializer(read_only=True)
    user_id = serializers.PrimaryKeyRelatedField(queryset=User.objects.all(), source='user', write_only=True)

    class Meta:
        model = Employee
        fields = ['id', 'user', 'user_id', 'shop', 'salary', 'join_date', 'status']

class AttendanceSerializer(serializers.ModelSerializer):
    employee = EmployeeSerializer(read_only=True)
    employee_id = serializers.PrimaryKeyRelatedField(queryset=Employee.objects.all(), source='employee', write_only=True)

    class Meta:
        model = Attendance
        fields = ['id', 'employee', 'employee_id', 'date', 'clock_in', 'clock_out', 'status']

class PerformanceSerializer(serializers.ModelSerializer):
    employee = EmployeeSerializer(read_only=True)
    employee_id = serializers.PrimaryKeyRelatedField(
        queryset=Employee.objects.all(),
        source='employee',
        write_only=True
    )

    class Meta:
        model = Performance
        fields = [
            'id',
            'employee',
            'employee_id',
            'kpi',
            'review',
            'date',
            'rating'  # 🎯 CRITICAL FIX: Add the 'rating' field here
        ]

class PayrollSerializer(serializers.ModelSerializer):
    employee = EmployeeSerializer(read_only=True)
    employee_id = serializers.PrimaryKeyRelatedField(queryset=Employee.objects.all(), source='employee', write_only=True)
    net_pay = serializers.ReadOnlyField()

    class Meta:
        model = Payroll
        fields = [
            'id',
            'employee',
            'employee_id',
            'salary',
            'bonus',
            'overtime',
            'performance_bonus',
            'deductions',
            'absent_days',

            # 🔑 CRITICAL FIX: ADDING THE MANUAL DEDUCTION FIELD 🔑
            'absent_deduction_amount',

            'date',
            'month',
            'net_pay'
        ]
#==================
#Login&Signup
#====================
class UserSignupSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=6)
    shop_name = serializers.CharField(write_only=True, required=False)  # For owner signup

    class Meta:
        model = User
        fields = ["id", "username", "email", "password", "role", "shop", "shop_name"]

    def validate(self, data):
        role = data.get("role")
        # 'shop' will be the Shop instance resolved by DRF from the 'shop_id' input
        shop = data.get("shop")
        shop_name = data.get("shop_name")

        if role == User.Roles.OWNER:
            if not shop_name:
                raise serializers.ValidationError({"shop_name": "Owner must provide a shop name"})
            # Ensure an Owner is NOT trying to assign themselves to an existing shop
            if shop:
                raise serializers.ValidationError({"shop": "Owner role cannot be assigned to an existing shop at creation."})

        # Check for roles that require a shop assignment
        elif role not in [User.Roles.SUPER_ADMIN, User.Roles.OWNER]:
            if not shop:
                raise serializers.ValidationError({"shop": "This role must be assigned to an existing shop"})

        # SUPER_ADMIN does not need a shop. All other roles that pass validation
        # will have 'shop' in data, or the user is an OWNER (which creates one).

        return data

    def create(self, validated_data):
        password = validated_data.pop("password")
        role = validated_data.get("role")
        shop_name = validated_data.pop("shop_name", None)

        # 1. Pop the 'shop' instance out, as it's not a direct field on AbstractUser's parent.
        #    We will assign it manually later.
        user_shop = validated_data.pop("shop", None)

        # 2. Create user first without the shop relationship
        user = User(**validated_data)
        user.set_password(password)

        # 3. Handle Owner logic (create shop and assign it)
        if role == User.Roles.OWNER and shop_name:
            new_shop = Shop.objects.create(
                name=shop_name,
                owner=user # The owner field on Shop
            )
            # Assign the created shop to the user's shop FK
            user.shop = new_shop

        # 4. Handle non-Owner/non-Super Admin logic (assign existing shop)
        elif user_shop:
            # For MANAGER, CASHIER, etc., the user_shop object came from validation
            user.shop = user_shop

        # 5. Save the user with the correct shop assignment
        user.save()

        return user
from django.contrib.auth import authenticate
from rest_framework import serializers, status
from rest_framework.response import Response
from rest_framework.views import APIView
from .models import User  # Your custom user model

# JWT helper
from rest_framework_simplejwt.tokens import RefreshToken

def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {
        'refresh': str(refresh),
        'access': str(refresh.access_token),
    }

class UserLoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, data):
        username = data.get("username")
        password = data.get("password")
        user = authenticate(username=username, password=password)
        if not user:
            raise serializers.ValidationError("Invalid username or password")
        if not user.is_active:
            raise serializers.ValidationError("This account is inactive")
        data["user"] = user
        return data

class LoginView(APIView):
    def post(self, request):
        serializer = UserLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        tokens = get_tokens_for_user(user)

        return Response(
            {
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "role": user.role,
                    "shop": user.shop.id if user.shop else None,
                },
                "tokens": tokens,
            },
            status=status.HTTP_200_OK,
        )

# =============== New Function Debt Paid & Pay =====================
from rest_framework import serializers
from decimal import Decimal
from pos.models import Shop, Supplier, Order  # adjust to your app paths
from .models import Customer, DebtToBePaid, DebtToPay


# ========================
# Customer Serializer
# ========================
class CustomerSerializer(serializers.ModelSerializer):
    shop_name = serializers.CharField(source='shop.name', read_only=True)
    outstanding_balance = serializers.DecimalField(
        source='total_debt', max_digits=12, decimal_places=2, read_only=True
    )

    class Meta:
        model = Customer
        fields = [
            'id', 'shop', 'shop_name', 'name', 'phone', 'email', 'address',
            'total_debt', 'outstanding_balance', 'created_at', 'updated_at'
        ]
        read_only_fields = ['created_at', 'updated_at']


# ========================
# Debt To Be Paid (Customer Credit)
# ========================
class DebtToBePaidSerializer(serializers.ModelSerializer):
    customer_name = serializers.CharField(source='customer.name', read_only=True)
    shop_name = serializers.CharField(source='shop.name', read_only=True)
    order_id = serializers.IntegerField(source='order.id', read_only=True)

    class Meta:
        model = DebtToBePaid
        fields = [
            'id', 'shop', 'shop_name', 'customer', 'customer_name', 'order',
            'order_id', 'amount', 'paid_amount', 'remaining_amount',
            'due_date', 'is_settled', 'created_at', 'updated_at'
        ]
        read_only_fields = ['created_at', 'updated_at', 'remaining_amount', 'is_settled']

    def validate(self, data):
        amount = data.get('amount', Decimal('0'))
        paid_amount = data.get('paid_amount', Decimal('0'))
        if paid_amount > amount:
            raise serializers.ValidationError("Paid amount cannot exceed total amount.")
        return data


# ========================
# Debt To Pay (Supplier Credit)
# ========================
class DebtToPaySerializer(serializers.ModelSerializer):
    supplier_name = serializers.CharField(source='supplier.name', read_only=True)
    shop_name = serializers.CharField(source='shop.name', read_only=True)

    class Meta:
        model = DebtToPay
        fields = [
            'id', 'shop', 'shop_name', 'supplier', 'supplier_name',
            'amount', 'paid_amount', 'remaining_amount', 'due_date',
            'is_settled', 'created_at', 'updated_at'
        ]
        read_only_fields = ['created_at', 'updated_at', 'remaining_amount', 'is_settled']

    def validate(self, data):
        amount = data.get('amount', Decimal('0'))
        paid_amount = data.get('paid_amount', Decimal('0'))
        if paid_amount > amount:
            raise serializers.ValidationError("Paid amount cannot exceed total amount.")
        return data

