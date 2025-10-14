from rest_framework import viewsets, permissions, generics, status
from rest_framework.response import Response
from django.contrib.auth import get_user_model
from datetime import date
from decimal import Decimal
from rest_framework.views import APIView
from collections import defaultdict
from django.db.models import Sum, F, DecimalField
from django.db.models import F, Sum, DecimalField, ExpressionWrapper
from rest_framework_simplejwt.tokens import RefreshToken
from .serializers import UserSignupSerializer, UserLoginSerializer
from rest_framework import viewsets, filters
from rest_framework.decorators import action
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
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


class BrandViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Brand.objects.all()
    serializer_class = BrandSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]


class SupplierViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Supplier.objects.all()
    serializer_class = SupplierSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]

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
class ProductViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = Product.objects.select_related(
        "category", "brand", "supplier", "shop"
    ).prefetch_related("colors", "sizes")
    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        product = self.perform_create(serializer)
        return Response(ProductSerializer(product).data, status=status.HTTP_201_CREATED)

    def perform_create(self, serializer):
        user = self.request.user
        product = serializer.save(shop=user.shop if not user.is_superuser else None)

        # Calculate total purchase price
        total_price = Decimal(
            sum(v.purchase_price * v.stock_quantity for v in product.variants.all())
            if hasattr(product, "variants") and product.variants.exists()
            else product.purchase_price
        )

        try:
            paid_amount = Decimal(self.request.data.get("paid_amount", "0"))
        except (TypeError, ValueError):
            paid_amount = Decimal("0")

        remaining_amount = total_price - paid_amount
        if remaining_amount < 0:
            raise ValidationError("Paid amount cannot exceed total price")

        # Create Debt record
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

        return product

    def update(self, request, *args, **kwargs):
        partial = kwargs.pop("partial", False)
        instance = self.get_object()
        serializer = self.get_serializer(instance, data=request.data, partial=partial)
        serializer.is_valid(raise_exception=True)
        product = serializer.save()
        return Response(ProductSerializer(product).data)


# =======================
# Waste Product
# =======================
class WasteProductViewSet(ShopRestrictedMixin, viewsets.ModelViewSet):
    queryset = WasteProduct.objects.select_related("shop", "variant", "variant__product", "variant__color", "variant__size")
    serializer_class = WasteProductSerializer
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]




# =======================
from decimal import Decimal, InvalidOperation
from django.db import transaction, models
from rest_framework import viewsets, permissions
from rest_framework.exceptions import ValidationError
from .models import Order, Shop, Customer, DebtToBePaid
from .serializers import OrderSerializer

class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.all().prefetch_related('items__variant')
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]

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
        shop = getattr(user, "shop", None) or Shop.objects.first()

        order = serializer.save(user=user, shop=shop)

        # Payment logic
        payment_method = self.request.data.get("payment_method", "CASH")
        try:
            paid_amount = Decimal(self.request.data.get("paid_amount", 0))
        except (TypeError, ValueError, InvalidOperation):
            paid_amount = Decimal("0")

        customer_id = self.request.data.get("customer_id")

        if customer_id and paid_amount < Decimal(order.total_price):
            try:
                customer = Customer.objects.get(id=customer_id, shop=shop)
            except Customer.DoesNotExist:
                raise ValueError("Invalid customer for this shop")

            total_amount = Decimal(order.total_price)
            remaining_amount = total_amount - paid_amount

            DebtToBePaid.objects.create(
                shop=shop,
                customer=customer,
                order=order,
                amount=total_amount,
                paid_amount=paid_amount,
                remaining_amount=remaining_amount,
            )

#             customer.total_debt += remaining_amount
            customer.save()

        return order
# =======================
# Shop Report
# =======================
class ShopReportView(ShopRestrictedMixin, generics.GenericAPIView):
    serializer_class = ShopReportSerializer
    # Only Admin/SuperUser can see ALL reports; shop users can only see their own.
    permission_classes = [permissions.IsAuthenticated, IsAdminOrHigher]

    def get(self, request, *args, **kwargs):
        user = request.user

        # 1. Access Control Check (Crucial step)
        shop_id_str = request.query_params.get('shop_id')

        if not shop_id_str:
            return Response({"error": "Shop ID is required."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            shop_id = int(shop_id_str)
        except ValueError:
             return Response({"error": "Invalid Shop ID format."}, status=status.HTTP_400_BAD_REQUEST)


        # --- ENFORCE SHOP RESTRICTION ---
        # Allow SuperUsers/Admins to view any shop_id report
        is_admin_or_higher = user.is_superuser or getattr(user, "is_super_admin", lambda: False)()

        if not is_admin_or_higher:
            # For regular shop users, enforce that the requested shop_id must match their shop_id
            if not hasattr(user, 'shop') or user.shop is None:
                # User is logged in but not linked to a shop
                return Response({"error": "User is not associated with a shop."}, status=status.HTTP_403_FORBIDDEN)

            if user.shop.id != shop_id:
                # The user is trying to access another shop's report
                return Response({"error": "You do not have permission to view this shop's report."},
                                status=status.HTTP_403_FORBIDDEN)
        # --- END ENFORCE SHOP RESTRICTION ---


        period = request.query_params.get('period', 'monthly')
        end_date = date.today()
        start_date = end_date

        # Determine date range (Logic remains the same)
        try:
            if period == 'daily':
                start_date = end_date
            # ... (monthly, yearly, custom logic is unchanged)
            elif period == 'monthly':
                start_date = end_date.replace(day=1)
            elif period == 'yearly':
                start_date = end_date.replace(month=1, day=1)
            elif period == 'custom':
                start_date_str = request.query_params.get('start_date')
                end_date_str = request.query_params.get('end_date')
                if start_date_str and end_date_str:
                    start_date = date.fromisoformat(start_date_str)
                    end_date = date.fromisoformat(end_date_str)
                else:
                    return Response({"error": "Custom requires start_date and end_date."},
                                    status=status.HTTP_400_BAD_REQUEST)
            else:
                return Response({"error": "Invalid period."}, status=status.HTTP_400_BAD_REQUEST)
        except ValueError:
            return Response({"error": "Invalid date format. Use YYYY-MM-DD."}, status=status.HTTP_400_BAD_REQUEST)

        # The rest of the report generation logic is correct since it uses the validated shop_id:

        # Filter orders (shop_id is now secure)
        completed_orders = Order.objects.filter(
            shop_id=shop_id,
            status='COMPLETED',
            created_at__date__range=(start_date, end_date)
        )
        # ... (rest of the aggregation and calculation logic) ...
        order_items = OrderItem.objects.filter(order__in=completed_orders)\
                                       .select_related('variant__product')

        # Aggregate sales
        sales_agg = order_items.aggregate(
            total_revenue=Sum(
                ExpressionWrapper(F('quantity') * F('price'), output_field=DecimalField())
            ),
            total_cogs=Sum(
                ExpressionWrapper(F('quantity') * F('variant__product__purchase_price'), output_field=DecimalField())
            )
        )

        total_revenue = sales_agg.get('total_revenue') or Decimal('0.00')
        total_cogs = sales_agg.get('total_cogs') or Decimal('0.00')
        # Waste
        waste_records = WasteProduct.objects.filter(
            shop_id=shop_id,
            recorded_at__date__range=(start_date, end_date)
        ).select_related('variant__product', 'shop')

        total_waste_loss = waste_records.aggregate(
            total_loss=Sum(F('quantity') * F('variant__product__purchase_price'), output_field=DecimalField())
        ).get('total_loss') or Decimal('0.00')

        # Expenses & Adjustments
        total_expenses = Expense.objects.filter(shop_id=shop_id, date__range=(start_date, end_date))\
                                        .aggregate(total=Sum('amount', output_field=DecimalField()))\
                                        .get('total') or Decimal('0.00')

        total_adjustments = Adjustment.objects.filter(shop_id=shop_id, date__range=(start_date, end_date))\
                                              .aggregate(total=Sum('amount', output_field=DecimalField()))\
                                              .get('total') or Decimal('0.00')

        # Profit calculations
        gross_profit = total_revenue - total_cogs - total_waste_loss
        net_profit = gross_profit - total_expenses + total_adjustments

        # Waste details
        waste_details = []
        for r in waste_records:
            product = getattr(r.variant, 'product', None)
            unit_purchase_price = product.purchase_price if product and product.purchase_price is not None else Decimal(0)
            loss_value = r.quantity * unit_purchase_price

            waste_details.append({
                'date': r.recorded_at.date(),
                'product_name': product.name if product else "-",
                'sku': product.id if product else "-",
                'category': getattr(getattr(product, 'category', None), 'name', 'N/A'),
                'quantity': r.quantity,
                'unit_purchase_price': unit_purchase_price,
                'loss_value': loss_value,
                'reason': r.reason,
            })

        # P&L per product
        pl_data_map = defaultdict(lambda: {
            'sold': 0, 'revenue': Decimal('0.00'), 'cogs': Decimal('0.00'),
            'waste_qty': 0, 'waste_loss': Decimal('0.00'),
            'product': None, 'unit_sale_price': Decimal('0.00'), 'unit_cogs': Decimal('0.00')
        })

        for item in order_items:
            product = getattr(item.variant, 'product', None)
            if not product or product.purchase_price is None:
                continue
            pid = product.id
            pl_data_map[pid]['sold'] += item.quantity
            pl_data_map[pid]['revenue'] += item.quantity * item.price
            pl_data_map[pid]['cogs'] += item.quantity * product.purchase_price
            pl_data_map[pid]['product'] = product
            pl_data_map[pid]['unit_sale_price'] = item.price
            pl_data_map[pid]['unit_cogs'] = product.purchase_price

        for r in waste_records:
            product = getattr(r.variant, 'product', None)
            if not product or product.purchase_price is None:
                continue
            pid = product.id
            pl_data_map[pid]['waste_qty'] += r.quantity
            pl_data_map[pid]['waste_loss'] += r.quantity * product.purchase_price

        pl_details = []
        for pid, d in pl_data_map.items():
            if not d['product']:
                continue
            profit = d['revenue'] - (d['cogs'] + d['waste_loss'])
            pl_details.append({
                'product_name': d['product'].name,
                'sku': d['product'].id,
                'quantity_sold': d['sold'],
                'unit_sale_price': d['unit_sale_price'],
                'unit_cogs': d['unit_cogs'],
                'waste_qty': d['waste_qty'],
                'waste_loss': d['waste_loss'],
                'revenue': d['revenue'],
                'cogs': d['cogs'],
                'profit': profit,
            })

        response_data = {
            'start_date': start_date,
            'end_date': end_date,
            'total_revenue': total_revenue,
            'total_cogs': total_cogs,
            'total_waste_loss': total_waste_loss,
            'total_expenses': total_expenses,
            'total_adjustments': total_adjustments,
            'gross_profit': gross_profit,
            'net_profit': net_profit,
            'waste_details': waste_details,
            'pl_details': pl_details,
        }

        serializer = self.get_serializer(response_data)
        return Response(serializer.data, status=status.HTTP_200_OK)
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
            # Since 'barcode' is unique, this filter should return at most one result.
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


class SignupView(generics.CreateAPIView):
    permission_classes = [AllowAny]
    queryset = User.objects.all()
    serializer_class = UserSignupSerializer

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        tokens = get_tokens_for_user(user)
        return Response(
            {
                "user": UserSignupSerializer(user).data,
                "tokens": tokens,
            },
            status=status.HTTP_201_CREATED,
        )

class LoginView(APIView):
    permission_classes = []  # allow anyone to access login

    def post(self, request):
        serializer = UserLoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]

        # ✅ 1. Call the external utility function
        tokens_data = get_tokens_for_user(user)

        # 2. Safely retrieve shop ID
        # user.shop.id is only safe if 'user.shop' is a foreign key and is not None.
        shop_id = getattr(user, "shop", None)
        if shop_id and hasattr(user.shop, 'id'):
            shop_id = user.shop.id
        else:
            shop_id = None

        # 3. Construct the response to match Flutter's expected structure
        return Response(
            {
                "user": {
                    "id": user.id,
                    "username": user.username,
                    "email": user.email,
                    # Return the role and shop ID directly from the user object
                    "role": getattr(user, "role", None),
                    "shop": shop_id,
                },
                # ✅ 4. Send the tokens dictionary, which contains 'access' and 'refresh'
                "tokens": {
                    "access": tokens_data['access'],
                    "refresh": tokens_data['refresh'], # <-- FLUTTER WILL FIND THE REFRESH TOKEN HERE
                }
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
