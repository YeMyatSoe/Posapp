from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenRefreshView
from .views import (
    UserViewSet, ShopViewSet, CustomerViewSet, DebtToBePaidViewSet,
    ContentViewSet, BannerViewSet, MonthlyTotalPayrollView ,
    CategoryViewSet, BrandViewSet, ColorViewSet, SizeViewSet, SupplierViewSet,
    ProductViewSet, WasteProductViewSet, OrderViewSet, ShopReportView, ProductVariantViewSet, ExpenseViewSet, AdjustmentViewSet
)
from .views import ShopViewSet, UserViewSet, EmployeeViewSet, AttendanceViewSet, PerformanceViewSet, PayrollViewSet, SignupView, LoginView
router = DefaultRouter()
router.register(r'users', UserViewSet)
router.register(r'shops', ShopViewSet)
router.register(r'contents', ContentViewSet)
router.register(r'banners', BannerViewSet)
router.register(r'categories', CategoryViewSet)
router.register(r'brands', BrandViewSet)
router.register(r'colors', ColorViewSet)
router.register(r'sizes', SizeViewSet)
router.register(r'suppliers', SupplierViewSet)
router.register(r'products', ProductViewSet)
router.register(r'waste-products', WasteProductViewSet, basename='wasteproduct')
router.register(r'customers', CustomerViewSet, basename='customer')
router.register(r'debts', DebtToBePaidViewSet, basename='debttobepaid')
router.register(r"orders", OrderViewSet, basename="orders")
router.register(r'product-variants', ProductVariantViewSet)
router.register(r'expenses', ExpenseViewSet, basename='expense')
router.register(r'adjustments', AdjustmentViewSet, basename='adjustment')
################### Employee #####################

router.register(r'employees', EmployeeViewSet)
router.register(r'attendance', AttendanceViewSet)
router.register(r'performance', PerformanceViewSet, basename='performance')
router.register(r'payrolls', PayrollViewSet)
urlpatterns = [
    path('', include(router.urls)),
    path('shop_report/', ShopReportView.as_view(), name='shop_report'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),

    path('payrolls/total/', MonthlyTotalPayrollView.as_view(), name='total-monthly-payroll'),
    path("signup/", SignupView.as_view(), name="signup"),
    path("login/", LoginView.as_view(), name="login"),
]
