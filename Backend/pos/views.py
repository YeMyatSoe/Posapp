from turtle import pd
from django.forms import ValidationError
from django.http import HttpResponse
from rest_framework import viewsets, permissions, generics, status
from rest_framework.response import Response
from django.contrib.auth import get_user_model
from datetime import date, timedelta
import json
from decimal import ROUND_UP, Decimal
from rest_framework.views import APIView
from collections import defaultdict
from django.db.models import Sum, F, DecimalField
from django.db.models import F, Sum, DecimalField, ExpressionWrapper
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import DebtToPaySerializer, LowStockVariantSerializer, UserSignupSerializer, UserLoginSerializer
from rest_framework import viewsets, filters
from rest_framework.decorators import action
from django.db.models import F, Sum, DecimalField, Value, Case, When
from django.db.models.functions import Coalesce  # ✅ THIS WAS MISSING
from decimal import Decimal
import pandas as pd
from .models import (
    Shop, Content, Banner,
    Category, Brand, Color, Size, Supplier,
    Product, WasteProduct, OrderItem, Order,Holiday ,
    Expense, Adjustment, DebtToBePaid, DebtToPay    # make sure these models exist in models.py
)
from rest_framework.permissions import AllowAny
from .serializers import (
    UserSerializer, ShopSerializer,
    ContentSerializer, BannerSerializer,
    CategorySerializer, BrandSerializer, ColorSerializer, SizeSerializer,
    SupplierSerializer, ProductSerializer, WasteProductSerializer,
    ShopReportSerializer, OrderSerializer, CustomerSerializer, DebtToBePaidSerializer
)
from rest_framework_simplejwt.authentication import JWTAuthentication
from .utils import get_tokens_for_user
from .permissions import IsAdminOrHigher

User = get_user_model()


class ShopRestrictedMixin:
    """
    Restricts queryset to the user's shop unless Super Admin.
    Works for models that either have:
      - a direct 'shop' field, or
      - an 'employee' field that links to a shop.
    """

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user

        # Super admins see all data
        if user.is_superuser or getattr(user, "is_super_admin", lambda: False)():
            return qs

        # 🔍 Detect the correct filter path
        model_fields = [f.name for f in qs.model._meta.get_fields()]

        if "shop" in model_fields:
            return qs.filter(shop=user.shop)
        elif "employee" in model_fields:
            return qs.filter(employee__shop=user.shop)
        else:
            # Model has no link to shop
            return qs.none()

    def perform_create(self, serializer):
        user = self.request.user
        if user.is_superuser or getattr(user, "is_super_admin", lambda: False)():
            serializer.save()
        else:
            # Try to auto-assign shop if field exists
            model_fields = serializer.Meta.model._meta.get_fields()
            field_names = [f.name for f in model_fields]

            if "shop" in field_names:
                serializer.save(shop=user.shop)
            else:
                serializer.save()

# =======================
# User & Shop
# =======================
class UserViewSet( viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]


class ShopViewSet( viewsets.ModelViewSet):
    queryset = Shop.objects.all()
    serializer_class = ShopSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


# =======================
# Content & Banner


# =======================
class ContentViewSet(viewsets.ModelViewSet):
    queryset = Content.objects.all()
    serializer_class = ContentSerializer
    permission_classes = [permissions.AllowAny]


class BannerViewSet(viewsets.ModelViewSet):
    queryset = Banner.objects.all()
    serializer_class = BannerSerializer
    permission_classes = [permissions.AllowAny]


# =======================
# Category / Brand / Supplier
# =======================
class CategoryViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [permissions.IsAuthenticated]


class BrandViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


class SupplierViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]

    @action(detail=True, methods=["post"])
    def pay(self, request, pk=None):
        supplier = self.get_object()
        amount = request.data.get("amount")

        if not amount:
            return Response({"error": "Amount is required"}, status=status.HTTP_400_BAD_REQUEST)

        try:
            amount = Decimal(amount)
        except:
            return Response({"error": "Invalid amount"}, status=status.HTTP_400_BAD_REQUEST)

        # Find unpaid or partially paid debts for this supplier
        debts = DebtToPay.objects.filter(supplier=supplier, remaining_amount__gt=0)

        if not debts.exists():
            return Response({"message": "No outstanding debts"}, status=status.HTTP_200_OK)

        total_remaining = sum([d.remaining_amount for d in debts])
        remaining = amount

        for debt in debts:
            if remaining <= 0:
                break
            if remaining >= debt.remaining_amount:
                remaining -= debt.remaining_amount
                debt.paid_amount += debt.remaining_amount
                debt.remaining_amount = 0
                debt.status = "PAID"
            else:
                debt.paid_amount += remaining
                debt.remaining_amount -= remaining
                debt.status = "PARTIAL"
                remaining = 0
            debt.save()

        return Response({
            "supplier": supplier.name,
            "amount_paid": str(amount),
            "remaining_unallocated": str(remaining),
            "message": "Payment processed successfully"
        }, status=status.HTTP_200_OK)
    @action(detail=False, methods=["get"])
    def monthly_summary(self, request):
        month = int(request.query_params.get("month", 0))
        year = int(request.query_params.get("year", 0))

        if not month or not year:
            return Response({"error": "month and year are required"}, status=400)

        total_paid = (
            DebtToPay.objects.filter(
                created_at__year=year,
                created_at__month=month,
                paid_amount__gt=0,
            ).aggregate(total=Sum("paid_amount"))["total"] or 0
        )

        return Response({"total_supplies": total_paid})
# =======================
# Color & Size
# =======================
class ColorViewSet(viewsets.ModelViewSet):
    queryset = Color.objects.all()
    serializer_class = ColorSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


class SizeViewSet(viewsets.ModelViewSet):
    queryset = Size.objects.all()
    serializer_class = SizeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


# =======================
# Product
# =======================
from django.db import transaction
from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from rest_framework.exceptions import ValidationError
from decimal import Decimal


class ProductViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Product.objects.select_related(
        "category", "brand", "supplier", "shop"
    ).prefetch_related("colors", "sizes", "variants")

    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]

    # ===========================================
    # CREATE
    # ===========================================
    @transaction.atomic
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        product = self.perform_create(serializer)

        # Handle debt after variants are created
        self._handle_debt(product, request)

        return Response(
            ProductSerializer(product).data,
            status=status.HTTP_201_CREATED
        )

    def perform_create(self, serializer):
        user = self.request.user
        return serializer.save(
            shop=user.shop if not user.is_superuser else None
        )

    # ===========================================
    # UPDATE
    # ===========================================
    @transaction.atomic
    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        instance = self.get_object()

        serializer = self.get_serializer(
            instance, data=request.data, partial=partial
        )
        serializer.is_valid(raise_exception=True)
        product = serializer.save()

        # No debt logic on update (usually)
        return Response(
            ProductSerializer(product).data,
            status=status.HTTP_200_OK
        )

    # ===========================================
    # DEBT HANDLING
    # ===========================================
    def _handle_debt(self, product, request):
        """Create debt record after full product + variants creation."""

        total_price = sum(
            v.purchase_price * v.stock_quantity
            for v in product.variants.all()
        )

        try:
            paid_amount = Decimal(request.data.get("paid_amount", "0"))
        except (TypeError, ValueError):
            raise ValidationError("Invalid paid_amount value")

        if paid_amount > total_price:
            raise ValidationError("Paid amount cannot exceed total price")

        remaining_amount = total_price - paid_amount

        DebtToPay.objects.create(
            shop=product.shop,
            supplier=product.supplier,
            product=product,
            total_amount=total_price,
            paid_amount=paid_amount,
            remaining_amount=remaining_amount,
            status="UNPAID" if paid_amount == 0 else "PARTIAL",
            note=f"Paid {paid_amount}" if paid_amount > 0 else None
        )

# =======================
# Waste Product
# =======================
class WasteProductViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = WasteProduct.objects.select_related("shop", "variant", "variant__product", "variant__color", "variant__size")
    serializer_class = WasteProductSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


#======================Low Stock ==============
import pandas as pd
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from django.http import HttpResponse
from .models import ProductVariant
from .serializers import LowStockVariantSerializer

class LowStockVariantReportView(APIView):
    """
    Returns low-stock variants with analytics.
    Optional CSV or Excel export via ?export=csv or ?export=excel
    """

    def get(self, request):
        # Threshold
        threshold = request.query_params.get("threshold", 10)
        try:
            threshold = int(threshold)
        except ValueError:
            threshold = 10

        # Export type
        export_type = request.query_params.get("export", None)  # "csv" or "excel"

        # Fetch variants
        variants_qs = ProductVariant.objects.filter(
            stock_quantity__lte=threshold
        ).select_related("product", "color", "size")

        serializer = LowStockVariantSerializer(variants_qs, many=True)
        variant_list = serializer.data

        # Load into Pandas
        df = pd.DataFrame(variant_list)

        # Ensure numeric columns exist and are clean
        for col in ['stock_quantity', 'purchase_price']:
            if col not in df.columns:
                df[col] = 0
            else:
                df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)

        # Analytics calculation
        if not df.empty:
            analytics = {
                "total_stock_value": float((df['stock_quantity'] * df['purchase_price']).sum()),
                "average_stock_quantity": float(df['stock_quantity'].mean()),
                "low_stock_count": len(df)
            }
        else:
            analytics = {
                "total_stock_value": 0,
                "average_stock_quantity": 0,
                "low_stock_count": 0
            }

        # Suggested restock (optional)
        df['suggested_restock'] = (df['stock_quantity'].apply(int) * 0)  # default 0
        # Fill any remaining NaN/None for JSON export
        df = df.fillna('')

        # Export CSV
        if export_type == "csv":
            response = HttpResponse(content_type='text/csv')
            response['Content-Disposition'] = 'attachment; filename="low_stock_report.csv"'
            df.to_csv(response, index=False)
            return response

        # Export Excel
        if export_type == "excel":
            response = HttpResponse(content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
            response['Content-Disposition'] = 'attachment; filename="low_stock_report.xlsx"'
            with pd.ExcelWriter(response, engine='xlsxwriter') as writer:
                df.to_excel(writer, index=False, sheet_name='Low Stock Variants')
            return response

        # Default JSON response
        return Response({
            "variants": variant_list,
            "analytics": analytics
        }, status=status.HTTP_200_OK)


# =======================
from decimal import Decimal, InvalidOperation, ROUND_UP
from django.db import transaction, models
from django.db.models import Sum
from django.utils import timezone
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Order, Shop, Customer, DebtToBePaid, OrderItem, ProductVariant
from .serializers import OrderSerializer
from django.db import models
import pandas as pd
from datetime import timedelta

class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.all().prefetch_related('items__variant')
    serializer_class = OrderSerializer
    permission_classes = [permissions.AllowAny]

    def get_queryset(self):
        user = self.request.user
        base_queryset = Order.objects.all().prefetch_related(
            'items__variant',
            'items__variant__color',
            'items__variant__size'
        )
        if getattr(user, "role", None) == "SUPER_ADMIN":
            return base_queryset
        elif getattr(user, "shop", None):
            return base_queryset.filter(shop=user.shop)
        return Order.objects.none()

    @transaction.atomic
    def perform_create(self, serializer):
        user = self.request.user
        # Ensure shop is handled correctly (e.g., from user or default)
        shop = getattr(user, "shop", None) or Shop.objects.first()

        # 1. Execute the serializer's create method
        # This creates Order, OrderItems, calculates total_price, and REDUCES STOCK.
        order = serializer.save(user=user, shop=shop)

        # 2. Get finalized total price from the order object
        total_price = order.total_price

        # 3. Handle paid_amount and customer logic
        paid_amount = self.request.data.get("paid_amount", 0)
        customer_id = self.request.data.get("customer_id")

        try:
            paid_amount = Decimal(paid_amount)
        except:
            paid_amount = Decimal('0')

        order.paid_amount = paid_amount

        # 4. Handle Debt creation if necessary
        if customer_id and paid_amount < total_price:
            try:
                customer = Customer.objects.get(id=customer_id, shop=shop)
                remaining = total_price - paid_amount
                DebtToBePaid.objects.create(
                    shop=shop,
                    customer=customer,
                    order=order,
                    amount=total_price,
                    paid_amount=paid_amount,
                    remaining_amount=remaining,
                )
                order.customer = customer
            except Customer.DoesNotExist:
                # Handle case where customer ID is invalid
                pass

        # 5. Final save for paid_amount and customer linkage
        update_fields = ['paid_amount']
        if customer_id:
             update_fields.append('customer')

        order.save(update_fields=update_fields)

        return order


    @action(detail=False, methods=["get"], url_path="best-selling")
    def get_best_selling_products(self, months_back: int = 2, top_n: int = 10):
        start_date = timezone.now() - timedelta(days=30 * months_back)

        qs = (
            OrderItem.objects
            .filter(order__created_at__gte=start_date)
            .values('variant', 'order__created_at')
            .annotate(quantity_sold=Sum('quantity'))
            .order_by('variant')
        )

        if not qs:
            return []

        df = pd.DataFrame(list(qs))
        df['order__created_at'] = pd.to_datetime(df['order__created_at'])
        df = df.sort_values(by=['variant', 'order__created_at'])

        results = []
        grouped = df.groupby('variant')

        for variant_id, group in grouped:
            variant = ProductVariant.objects.filter(id=variant_id).first()
            if not variant:
                continue

            # Aggregate daily sales
            group = group.groupby(pd.Grouper(key='order__created_at', freq='D'))['quantity_sold'].sum().reset_index()
            if group.empty:
                continue

            group['rolling_mean'] = group['quantity_sold'].rolling(window=7, min_periods=1).mean()
            group['rolling_std'] = group['quantity_sold'].rolling(window=7, min_periods=1).std().fillna(0)

            last_7_avg = group['rolling_mean'].tail(7).mean()
            last_30_avg = group['rolling_mean'].tail(30).mean() if len(group) >= 30 else group['rolling_mean'].mean()

            trend_factor = (last_7_avg - last_30_avg) / max(1, last_30_avg)
            trend_factor = max(min(trend_factor, 0.5), -0.5)  # cap ±50%

            daily_avg = group['quantity_sold'].mean()
            predicted_next_month = (daily_avg * 30) * (1 + trend_factor)

            volatility = min(group['rolling_std'].mean() / max(1, daily_avg), 0.2)
            safety_buffer = Decimal(predicted_next_month * volatility)

            total_sold = group['quantity_sold'].sum()
            avg_monthly_sold = total_sold / months_back
            current_stock = Decimal(variant.stock_quantity or 0)

            suggested_restock = Decimal(predicted_next_month) + safety_buffer - current_stock
            upper_cap = Decimal(avg_monthly_sold * 3)
            suggested_restock = max(Decimal(0), min(suggested_restock, upper_cap))
            suggested_restock = suggested_restock.quantize(Decimal('1.'), rounding=ROUND_UP)

            # 🧠 Economic intelligence
            last_sale_date = group['order__created_at'].max()
            days_since_last_sale = (timezone.now() - last_sale_date).days

            notes = []
            if total_sold < 10:
                notes.append("Low Demand")
            if current_stock > avg_monthly_sold * 2:
                notes.append("Overstocked")
            if days_since_last_sale > 45:
                notes.append("Consider Clearance / Discount")
            if suggested_restock < 3 and total_sold > 0:
                suggested_restock = Decimal(3)  # maintain visibility

            results.append({
                "variant_id": variant.id,
                "product_name": variant.product.name,
                "variant_name": str(variant),
                "current_stock": int(current_stock),
                f"total_sold_last_{months_back}_months": int(total_sold),
                "avg_monthly_sold": float(avg_monthly_sold),
                "predicted_next_month_sales": float(predicted_next_month),
                "suggested_restock": int(suggested_restock),
                "notes": notes,
            })

        results_sorted = sorted(
            results,
            key=lambda x: x[f"total_sold_last_{months_back}_months"],
            reverse=True
        )

        top_selling = results_sorted[:top_n]
        low_selling = results_sorted[-top_n:]  # bottom N slow movers

        return {
            "best_selling": top_selling,
            "low_selling": low_selling
        }

    @action(detail=False, methods=['get'], url_path='best-selling')
    def best_selling(self, request):
        months_back = int(request.query_params.get('months', 2))
        top_n = int(request.query_params.get('top', 10))

        data = self.get_best_selling_products(months_back=months_back, top_n=top_n)
        return Response(data, status=status.HTTP_200_OK)


# =======================
# Shop Report
# =======================
class ShopReportView(ShopRestrictedMixin, generics.GenericAPIView):
    serializer_class = ShopReportSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]

    def get(self, request, *args, **kwargs):
        user = request.user
        shop_id_str = request.query_params.get('shop_id')
        if not shop_id_str:
            return Response({"error": "Shop ID is required."}, status=400)
        try:
            shop_id = int(shop_id_str)
        except ValueError:
            return Response({"error": "Invalid Shop ID format."}, status=400)

        # --- SHOP ACCESS CONTROL ---
        is_admin_or_higher = user.is_superuser or getattr(user, "is_super_admin", lambda: False)()
        if not is_admin_or_higher:
            if not hasattr(user, 'shop') or user.shop is None:
                return Response({"error": "User is not associated with a shop."}, status=403)
            if user.shop.id != shop_id:
                return Response({"error": "No permission to view this shop's report."}, status=403)

        # --- DATE RANGE ---
        period = request.query_params.get('period', 'monthly')
        end_date = date.today()
        start_date = end_date
        try:
            if period == 'daily':
                start_date = end_date
            elif period == 'monthly':
                start_date = end_date.replace(day=1)
            elif period == 'yearly':
                start_date = end_date.replace(month=1, day=1)
            elif period == 'custom':
                start_str = request.query_params.get('start_date')
                end_str = request.query_params.get('end_date')
                if start_str and end_str:
                    start_date = date.fromisoformat(start_str)
                    end_date = date.fromisoformat(end_str)
                else:
                    return Response({"error": "Custom requires start_date and end_date."}, status=400)
            else:
                return Response({"error": "Invalid period."}, status=400)
        except ValueError:
            return Response({"error": "Invalid date format."}, status=400)

        # --- FETCH ORDERS & ITEMS ---
        completed_orders = Order.objects.filter(
            shop_id=shop_id, status='COMPLETED', created_at__date__range=(start_date, end_date)
        )
        order_items = OrderItem.objects.filter(order__in=completed_orders).select_related('variant__product')

        # --- FETCH WASTE ---
        waste_records = WasteProduct.objects.filter(
            shop_id=shop_id, recorded_at__date__range=(start_date, end_date)
        ).select_related('variant__product')

        # --- FETCH EXPENSES & ADJUSTMENTS ---
        total_expenses = Expense.objects.filter(
            shop_id=shop_id, date__range=(start_date, end_date)
        ).aggregate(total=Coalesce(Sum('amount'), Decimal('0.00')))['total']

        total_adjustments = Adjustment.objects.filter(
            shop_id=shop_id, date__range=(start_date, end_date)
        ).aggregate(total=Coalesce(Sum('amount'), Decimal('0.00')))['total']

        # --- AGGREGATE PER PRODUCT ---
        pl_data_map = defaultdict(lambda: {
            'sold': 0,
            'revenue': Decimal('0.00'),
            'cogs': Decimal('0.00'),
            'waste_qty': 0,
            'waste_loss': Decimal('0.00'),
            'product': None,
            'unit_sale_price': Decimal('0.00'),
            'unit_cogs': Decimal('0.00'),
        })

        for item in order_items:
            variant = getattr(item, 'variant', None)
            product = getattr(variant, 'product', None) if variant else None
            if not variant or not product:
                continue

            pid = product.id
            sold_units = item.quantity

            if variant.is_pack and variant.units_per_pack:
                num_packs = sold_units // variant.units_per_pack
                leftover_units = sold_units % variant.units_per_pack

                revenue = (num_packs * variant.pack_sale_price) + (leftover_units * variant.single_sale_price)
                unit_sale_price = revenue / sold_units  # average price per unit
            else:
                revenue = sold_units * (variant.single_sale_price or variant.sale_price or Decimal('0.00'))
                unit_sale_price = variant.single_sale_price or variant.sale_price or Decimal('0.00')

            # Cost per unit
            cogs_per_unit = variant.purchase_price or Decimal('0.00')

            # Update PL map
            pl_data_map[pid]['sold'] += sold_units
            pl_data_map[pid]['revenue'] += revenue
            pl_data_map[pid]['cogs'] += sold_units * cogs_per_unit
            pl_data_map[pid]['product'] = product
            pl_data_map[pid]['unit_sale_price'] = unit_sale_price
            pl_data_map[pid]['unit_cogs'] = cogs_per_unit


        # --- CALCULATE TOTALS FROM PL MAP ---
        total_revenue = sum(d['revenue'] for d in pl_data_map.values())
        total_cogs = sum(d['cogs'] for d in pl_data_map.values())
        total_waste_loss = sum(d['waste_loss'] for d in pl_data_map.values())
        gross_profit = total_revenue - total_cogs - total_waste_loss
        net_profit = gross_profit - total_expenses + total_adjustments

        # --- PROFIT & PL DETAILS ---
        pl_details = []
        for d in pl_data_map.values():
            product = d.get('product')
            if not product:
                continue
            revenue = d['revenue']
            cogs = d['cogs']
            waste_loss = d['waste_loss']
            profit = revenue - (cogs + waste_loss)

            pl_details.append({
                'product_name': product.name,
                'sku': str(product.id),
                'quantity_sold': d['sold'],
                'unit_sale_price': f"{d['unit_sale_price']:.2f}",
                'unit_cogs': f"{d['unit_cogs']:.2f}",
                'waste_qty': d['waste_qty'],
                'waste_loss': f"{waste_loss:.2f}",
                'revenue': f"{revenue:.2f}",
                'cogs': f"{cogs:.2f}",
                'profit': f"{profit:.2f}",
            })

        best_selling = sorted(pl_details, key=lambda x: x['quantity_sold'], reverse=True)[:10]
        low_selling = sorted(pl_details, key=lambda x: x['quantity_sold'])[:10]

        # --- WASTE DETAILS ---
        waste_details = []
        for r in waste_records:
            variant = getattr(r, 'variant', None)
            product = getattr(variant, 'product', None) if variant else None
            unit_price = getattr(product, 'purchase_price', Decimal('0.00')) if product else Decimal('0.00')
            waste_details.append({
                'date': r.recorded_at.date(),
                'product_name': product.name if product else f"Variant {variant.id}",
                'sku': product.id if product else f"variant_{variant.id}",
                'category': getattr(getattr(product, 'category', None), 'name', 'N/A') if product else 'N/A',
                'quantity': r.quantity,
                'unit_purchase_price': f"{unit_price:.2f}",
                'loss_value': f"{r.quantity * unit_price:.2f}",
                'reason': r.reason,
            })

        # --- MONTHLY COMPARISON (last 6 months) ---
        monthly_comparison = []
        for i in range(5, -1, -1):
            month_start = (date.today().replace(day=1) - relativedelta(months=i)).replace(day=1)
            month_end = (month_start + relativedelta(months=1)) - timedelta(days=1)
            month_items = OrderItem.objects.filter(
                order__shop_id=shop_id,
                order__status='COMPLETED',
                order__created_at__date__range=(month_start, month_end)
            ).select_related('variant__product')

            month_pl_map = defaultdict(lambda: {'revenue': Decimal('0.00'), 'cogs': Decimal('0.00'), 'waste_loss': Decimal('0.00')})
            for item in month_items:
                variant = getattr(item, 'variant', None)
                product = getattr(variant, 'product', None) if variant else None
                if not variant or not product:
                    continue
                sold_units = item.quantity

                if variant.is_pack and variant.units_per_pack:
                    num_packs = sold_units // variant.units_per_pack
                    leftover_units = sold_units % variant.units_per_pack
                    revenue = (num_packs * variant.pack_sale_price) + (leftover_units * (variant.single_sale_price or variant.sale_price or Decimal('0.00')))
                else:
                    revenue = sold_units * (variant.single_sale_price or variant.sale_price or Decimal('0.00'))

                cogs = sold_units * (variant.purchase_price or Decimal('0.00'))

                month_pl_map[product.id]['revenue'] += revenue
                month_pl_map[product.id]['cogs'] += cogs


            month_revenue = sum(d['revenue'] for d in month_pl_map.values())
            month_cogs = sum(d['cogs'] for d in month_pl_map.values())
            month_waste = sum(d['waste_loss'] for d in month_pl_map.values())
            month_gross = month_revenue - month_cogs - month_waste
            month_net = month_gross  # can subtract expenses if needed

            monthly_comparison.append({
                'month_name': month_start.strftime('%b'),
                'revenue': float(month_revenue),
                'gross_profit': float(month_gross),
                'net_profit': float(month_net),
            })

        # --- RESPONSE ---
        response_data = {
            'start_date': start_date,
            'end_date': end_date,
            'total_revenue': f"{total_revenue:.2f}",
            'total_cogs': f"{total_cogs:.2f}",
            'total_waste_loss': f"{total_waste_loss:.2f}",
            'total_expenses': f"{total_expenses:.2f}",
            'total_adjustments': f"{total_adjustments:.2f}",
            'gross_profit': f"{gross_profit:.2f}",
            'net_profit': f"{net_profit:.2f}",
            'waste_details': waste_details,
            'pl_details': pl_details,
            'best_selling': best_selling,
            'low_selling': low_selling,
            'monthly_comparison': monthly_comparison,
        }

        serializer = self.get_serializer(response_data)
        return Response(serializer.data, status=200)

from datetime import date
from dateutil.relativedelta import relativedelta
import pandas as pd
from decimal import Decimal

def get_monthly_comparison(shop_id, months=6):
    end_date = date.today()
    start_date = (end_date - relativedelta(months=months-1)).replace(day=1)

    # --- FETCH DATA ---
    orders = Order.objects.filter(
        shop_id=shop_id, status='COMPLETED', created_at__date__range=(start_date, end_date)
    )
    items = OrderItem.objects.filter(order__in=orders).select_related('variant')
    expenses = Expense.objects.filter(shop_id=shop_id, date__range=(start_date, end_date))
    waste = WasteProduct.objects.filter(
        shop_id=shop_id, recorded_at__date__range=(start_date, end_date)
    ).select_related('variant')

    # --- AGGREGATE PER ITEM BY MONTH ---
    monthly_data = {}
    for item in items:
        month_key = item.order.created_at.strftime('%Y-%m')
        revenue = Decimal(item.quantity) * Decimal(getattr(item, 'price', 0) or 0)
        cogs = Decimal(item.quantity) * Decimal(getattr(item.variant, 'purchase_price', 0) or 0)

        if month_key not in monthly_data:
            monthly_data[month_key] = {'revenue': Decimal('0.00'), 'cogs': Decimal('0.00'), 'waste_loss': Decimal('0.00'), 'expenses': Decimal('0.00')}
        monthly_data[month_key]['revenue'] += revenue
        monthly_data[month_key]['cogs'] += cogs

    for w in waste:
        month_key = w.recorded_at.strftime('%Y-%m')
        loss = Decimal(w.quantity) * Decimal(getattr(w.variant, 'purchase_price', 0) or 0)
        if month_key not in monthly_data:
            monthly_data[month_key] = {'revenue': Decimal('0.00'), 'cogs': Decimal('0.00'), 'waste_loss': Decimal('0.00'), 'expenses': Decimal('0.00')}
        monthly_data[month_key]['waste_loss'] += loss

    for e in expenses:
        month_key = e.date.strftime('%Y-%m')
        if month_key not in monthly_data:
            monthly_data[month_key] = {'revenue': Decimal('0.00'), 'cogs': Decimal('0.00'), 'waste_loss': Decimal('0.00'), 'expenses': Decimal('0.00')}
        monthly_data[month_key]['expenses'] += Decimal(e.amount or 0)

    # --- ENSURE LAST N MONTHS EXIST ---
    month_list = [(end_date - relativedelta(months=i)).strftime('%Y-%m') for i in reversed(range(months))]
    result = []
    for m in month_list:
        data = monthly_data.get(m, {'revenue': 0, 'cogs': 0, 'waste_loss': 0, 'expenses': 0})
        gross_profit = data['revenue'] - data['cogs'] - data['waste_loss']
        net_profit = gross_profit - data['expenses']
        result.append({
            'month_name': pd.to_datetime(m, format='%Y-%m').strftime('%b'),
            'revenue': float(data['revenue']),
            'gross_profit': float(gross_profit),
            'net_profit': float(net_profit),
        })

    return result

from rest_framework import viewsets, permissions
from .models import ProductVariant
from .serializers import ProductVariantSerializer

class ProductVariantViewSet(viewsets.ModelViewSet):
    queryset = ProductVariant.objects.select_related("product", "color", "size")
    serializer_class = ProductVariantSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        queryset = super().get_queryset()

        product_id = self.request.query_params.get("product")
        if product_id:
            queryset = queryset.filter(product_id=product_id)

        barcode = self.request.query_params.get("barcode")
        if barcode:
            queryset = queryset.filter(barcode=barcode)

        return queryset

#============================
# Employee
#=============================
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticated
from .models import Shop, User, Employee, Attendance, Performance, Payroll
from .serializers import ShopSerializer, UserSerializer, EmployeeSerializer, AttendanceSerializer, PerformanceSerializer, PayrollSerializer


class EmployeeViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Employee.objects.all()
    serializer_class = EmployeeSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]

MONTH_TO_NUM = {
    'january': 1, 'february': 2, 'march': 3, 'april': 4, 'may': 5, 'june': 6,
    'july': 7, 'august': 8, 'september': 9, 'october': 10, 'november': 11, 'december': 12
}

import calendar
import datetime

# Helper dict (define outside the viewset for cleaner code)
MONTH_TO_NUM = {
    "january": 1, "february": 2, "march": 3, "april": 4,
    "may": 5, "june": 6, "july": 7, "august": 8,
    "september": 9, "october": 10, "november": 11, "december": 12
}

def get_working_days_count(year, month_num):
    """Calculates the total expected working days in a month,
    excluding Saturdays, Sundays, and pre-recorded Holidays."""

    # 1. Get total days in the month
    _, total_days_in_month = calendar.monthrange(year, month_num)
    start_date = datetime.date(year, month_num, 1)
    end_date = datetime.date(year, month_num, total_days_in_month)

    # 2. Get list of dates for public holidays in the specified month
    # ASSUMPTION: You have a 'Holiday' model with a 'date' field
    holiday_dates = list(
        Holiday.objects
        .filter(date__year=year, date__month=month_num)
        .values_list('date', flat=True)
    )

    working_days = 0
    current_date = start_date

    # Iterate through every day in the month
    while current_date <= end_date:
        # Check if the day is a Saturday (5) or Sunday (6) - Monday is 0, Sunday is 6
        is_weekend = current_date.weekday() in [5, 6]

        # Check if the day is a recorded public holiday
        is_holiday = current_date in holiday_dates

        # If it's not a weekend AND not a public holiday, it's a working day
        if not is_weekend and not is_holiday:
            working_days += 1

        current_date += datetime.timedelta(days=1)

    return working_days


class AttendanceViewSet(viewsets.ModelViewSet):
    queryset = Attendance.objects.all()
    serializer_class = AttendanceSerializer
    permission_classes = [IsAuthenticated]

    # 🚨 REVISED CUSTOM ACTION (EXCLUDING NON-WORKING DAYS)
    @action(detail=False, methods=['get'], url_path='absent_count')
    def absent_count(self, request):
        employee_id = request.query_params.get('employee_id')
        month_name = request.query_params.get('month', '').lower()
        year = request.query_params.get('year', datetime.datetime.now().year)

        # --- 1. Parameter Validation (Omitted for brevity, assume valid inputs) ---
        month_num = MONTH_TO_NUM.get(month_name)
        try:
            employee_id = int(employee_id)
            year = int(year)
            Employee.objects.get(id=employee_id)
        except (ValueError, Employee.DoesNotExist, TypeError):
             return Response(
                {"detail": "Invalid employee, month, or year provided."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # --- 2. Data Calculation ---

        # A. Calculate the TOTAL EXPECTED WORKING DAYS
        total_expected_working_days = get_working_days_count(year, month_num)

        # B. Define POSITIVE/NON-DEDUCTIBLE statuses
        positive_statuses = ['Present', 'On Time', 'Paid Leave', 'Sick Leave (Paid)'] # Ensure this list is complete

        # C. Count days employee was present/on leave on a WORKING day

        # 1. Filter the attendance records for the employee, month, and year with positive statuses
        positive_attendance_records = Attendance.objects.filter(
            employee_id=employee_id,
            status__in=positive_statuses,
            date__year=year,
            date__month=month_num
        ).values_list('date', flat=True).distinct() # Get unique dates of positive attendance

        # 2. Exclude dates that fall on a weekend (Sat=5, Sun=6) or a holiday
        # This step is crucial to prevent penalizing the employee for being 'absent' on a non-working day.

        # Get list of non-working dates (Weekends and Holidays)
        _, total_days_in_month = calendar.monthrange(year, month_num)
        start_date = datetime.date(year, month_num, 1)
        end_date = datetime.date(year, month_num, total_days_in_month)

        holiday_dates = list(
            Holiday.objects
            .filter(date__year=year, date__month=month_num)
            .values_list('date', flat=True)
        )

        present_on_working_days = 0

        for date in positive_attendance_records:
            is_weekend = date.weekday() in [5, 6]
            is_holiday = date in holiday_dates

            # Only count positive attendance if it was on an expected working day
            if not is_weekend and not is_holiday:
                present_on_working_days += 1


        # D. Calculate Absent Days (For Payroll Deduction)
        # The number of working days the employee was expected to be present
        # but did not have a positive attendance record.
        absent_days_for_payroll = total_expected_working_days - present_on_working_days

        # --- 3. Return Response ---
        return Response({
            "employee_id": employee_id,
            "month": month_name,
            "year": year,
            "total_expected_working_days": total_expected_working_days, # The new base for deduction
            "days_present_or_on_paid_leave": present_on_working_days,
            "absent_days_for_payroll_deduction": max(0, absent_days_for_payroll), # Ensure no negative count
        }, status=status.HTTP_200_OK)
class PerformanceViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Performance.objects.all()
    serializer_class = PerformanceSerializer
    permission_classes = [IsAuthenticated]

    # 🎯 FIX: Add this custom action to resolve the 404 error
    @action(detail=False, methods=['get'], url_path='latest_rating')
    def latest_rating(self, request):
        employee_id = request.query_params.get('employee_id')

        try:
            employee_id = int(employee_id)
        except (ValueError, TypeError):
             return Response(
                {"detail": "Invalid employee ID provided."},
                status=status.HTTP_400_BAD_REQUEST
            )

        # 1. Find the latest performance record for the employee, ordered by date
        try:
            # Note: .latest('date') requires your Performance model to have a 'date' field
            latest_performance = self.queryset.filter(employee_id=employee_id).latest('date')

            # 2. Extract the rating
            # ASSUMPTION: Your Performance model/serializer has a 'rating' field
            rating = latest_performance.rating

            return Response({
                "employee_id": employee_id,
                "rating": rating
            }, status=status.HTTP_200_OK)

        except Performance.DoesNotExist:
            # If no performance record is found, return "N/A" (matches Flutter's expectation)
            return Response({
                "employee_id": employee_id,
                "rating": "N/A"
            }, status=status.HTTP_200_OK)

class PayrollViewSet( ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Payroll.objects.all()
    serializer_class = PayrollSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]
    filter_backends = [filters.SearchFilter]
    search_fields = ['employee__user__username', 'date']

    @action(detail=False, methods=['get'])
    def monthly_summary(self, request):
        """
        Example: /api/payroll/monthly_summary/?month=10&year=2025
        """
        month = request.query_params.get('month')
        year = request.query_params.get('year')

        if not month or not year:
            return Response({"error": "month and year are required"}, status=400)

        payrolls = self.queryset.filter(date__month=month, date__year=year)
        total_salary = payrolls.aggregate(total=Sum('salary'))['total'] or 0
        total_bonus = payrolls.aggregate(total=Sum('bonus'))['total'] or 0
        total_net = sum([p.net_pay for p in payrolls])

        data = {
            "month": month,
            "year": year,
            "total_salary": total_salary,
            "total_bonus": total_bonus,
            "total_net_pay": total_net,
            "records": PayrollSerializer(payrolls, many=True).data
        }
        return Response(data)

class MonthlyTotalPayrollView(ShopRestrictedMixin, APIView):
    # ... (permission_classes and error handling logic)

    def get(self, request, *args, **kwargs):
        month_name = request.query_params.get('month')
        year_str = request.query_params.get('year')

        # ... (validation for month_name/year_str)

        try:
            year = int(year_str)
        except ValueError:
            return Response(
                {"detail": "Invalid format for 'year'."},
                status=400
            )

        # FIX: Filter using the 'month' string and 'year' integer fields
        payrolls_in_month = Payroll.objects.filter(
            month__iexact=month_name, # Use iexact for case-insensitive match
            year=year
        )

        # Aggregate the 'salary' field (This is the basic salary expense)
        aggregation = payrolls_in_month.aggregate(total_salary=Sum('salary'))

        total_salary = aggregation['total_salary'] if aggregation['total_salary'] is not None else 0.0

        return Response({
            "month": month_name,
            "year": year,
            "total_salary": total_salary
        }, status=200)

from .models import Expense, Adjustment
from .serializers import ExpenseSerializer, AdjustmentSerializer

class ExpenseViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Expense.objects.all()
    serializer_class = ExpenseSerializer
    permission_classes = [IsAuthenticated]

class AdjustmentViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    """
    API endpoint that provides full CRUD operations for Adjustments.
    """
    queryset = Adjustment.objects.all()
    serializer_class = AdjustmentSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        # 1. Start with the base queryset
        queryset = super().get_queryset()
        # By calling super().get_queryset(), you utilize the ShopRestrictedMixin's
        # logic, which already filters by the authenticated user's shop (user.shop).

        # 2. Add select_related for performance
        queryset = queryset.select_related('shop', 'user')

        # 3. Optional: Apply filtering based on URL query parameters
        # You should remove the ability for shop users to filter by an arbitrary shop_id.
        # If you still need this for a SUPERUSER/ADMIN, you must add checks:

        user = self.request.user
        shop_id_param = self.request.query_params.get('shop_id')

        if shop_id_param and (user.is_superuser or getattr(user, "is_super_admin", False)):
            # Only superusers/admins can use the shop_id filter
            queryset = queryset.filter(shop__id=shop_id_param)

        # NOTE: Since super().get_queryset() already restricted the data to the user's
        # shop, a regular shop user cannot pass a different shop_id and see data.
        # The filter from super() prevents data leakage.

        return queryset.order_by('-date', '-created_at')

    # You also need to ensure perform_create sets the shop, not just the user.
    def perform_create(self, serializer):
        user = self.request.user
        # Ensure the shop is set automatically from the user if it's a shop user
        if hasattr(user, 'shop') and user.shop is not None:
            serializer.save(user=user, shop=user.shop)
        else:
            # Handle superusers/admins (they must provide shop_id in data if they aren't tied to one)
            serializer.save(user=user)
#====================
# Login&Sinup
#=====================
from .serializers import UserSignupSerializer  # create this to validate fields

from django.contrib.auth.models import Group
User = get_user_model()
class SignupView(APIView):
    permission_classes = []

    def post(self, request):
        data = request.data
        role = data['role']

        if role == "OWNER":
            # 1️⃣ Create user with staff privileges
            user = User.objects.create_user(
                username=data['username'],
                email=data['email'],
                password=data['password'],
                role=role,
                is_staff=True  # allow admin login
            )

            # 2️⃣ Create Shop and link to owner
            shop = Shop.objects.create(
                name=data['shop_name'],
                owner=user,
                expire_date=date.today() + timedelta(days=30)
            )
            user.shop = shop
            user.save()

            # 3️⃣ Assign Owner group
            owner_group, _ = Group.objects.get_or_create(name="Owner")
            user.groups.add(owner_group)

        else:
            shop = Shop.objects.get(id=data['shop'])
            user = User.objects.create_user(
                username=data['username'],
                email=data['email'],
                password=data['password'],
                role=role,
                shop=shop,
                is_staff=True  # allow admin login for managers/HR if needed
            )

        return Response({
            "user": {
                "id": user.id,
                "username": user.username,
                "role": user.role,
                "shop": shop.id,
                "expire_date": getattr(shop, "expire_date", None)
            }
        }, status=201)
#
#         except Shop.DoesNotExist:
#             return Response({"detail": "Shop not found"}, status=status.HTTP_400_BAD_REQUEST)
#         except Exception as e:
#             return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

class LoginView(APIView):
    permission_classes = []  # allow anyone to access login

    def post(self, request):
        serializer = UserLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]

        # --- Check if user has a shop ---
        shop = getattr(user, "shop", None)
        if not shop:
            return Response(
                {"detail": "No shop is linked to this account."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # --- Check shop expiration ---
        expire_date = getattr(shop, "expire_date", None)
        if expire_date and expire_date < date.today():
            # Optional: also set the shop inactive
            shop.is_active = False
            shop.save(update_fields=["is_active"])

            return Response(
                {
                    "detail": f"Shop access expired on {expire_date}. Please renew your subscription."
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # ✅ If shop not expired, proceed with login
        tokens_data = get_tokens_for_user(user)

        return Response(
            {
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    "role": getattr(user, "role", None),
                    "shop": shop.id,
                    "expire_date": expire_date,
                },
                "tokens": {
                    "access": tokens_data["access"],
                    "refresh": tokens_data["refresh"],
                },
            },
            status=status.HTTP_200_OK,
        )

from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework import status, viewsets
from decimal import Decimal
from .models import Customer, DebtToBePaid

class CustomerViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    # Adjust queryset and permissions as necessary for your application
    queryset = Customer.objects.all()
    serializer_class = CustomerSerializer


    @action(detail=True, methods=['post'])
    def pay(self, request, pk=None):
        customer = self.get_object()

        try:
            # Safely parse the payment amount
            amount = Decimal(request.data.get("amount", 0))
            if amount <= 0:
                 return Response({"detail": "Payment amount must be positive."}, status=status.HTTP_400_BAD_REQUEST)
        except (TypeError, InvalidOperation):
            return Response({"detail": "Invalid amount format"}, status=status.HTTP_400_BAD_REQUEST)

        remaining_payment = amount

        # Only consider debts that are not fully paid, ordered by creation time (FIFO)
        debts = DebtToBePaid.objects.filter(
            customer=customer
        ).exclude(
            status="PAID"
        ).order_by('created_at')

        # Apply payment to debts
        for debt in debts:
            if remaining_payment <= Decimal("0.00"):
                break

            # Calculate the amount to apply to this specific debt
            apply_amount = min(remaining_payment, debt.remaining_amount)

            # Update debt record fields
            debt.paid_amount += apply_amount
            debt.remaining_amount -= apply_amount
            remaining_payment -= apply_amount

            # Update status
            if debt.remaining_amount <= Decimal("0.00"):
                debt.status = "PAID"
                debt.remaining_amount = Decimal("0.00") # Ensure no negative balance
            else:
                debt.status = "PARTIAL"

            debt.save()

        # --- CRITICAL FIX: Update customer's total debt using DB aggregate ---

        # Calculate the new total debt by summing remaining_amount of all unsettled debts
        total_remaining = DebtToBePaid.objects.filter(
            customer=customer
        ).exclude(
            status="PAID"
        ).aggregate(
            total=Sum('remaining_amount')
        )['total'] or Decimal('0.00')

        customer.total_debt = total_remaining
        customer.save(update_fields=["total_debt"])

        # Note: If you implemented customer.recalculate_debt() you could replace
        # the aggregation block above with: customer.recalculate_debt()

        return Response({
            "detail": "Payment recorded successfully",
            "payment_applied": str(amount - remaining_payment),
            "remaining_debt": str(customer.total_debt)
        }, status=status.HTTP_200_OK)
class DebtToBePaidViewSet(viewsets.ModelViewSet):
    queryset = DebtToBePaid.objects.all()
    serializer_class = DebtToBePaidSerializer
