import 'package:flutter/material.dart';
import 'package:pos_app/screens/Admin/category.dart';
import 'package:pos_app/screens/Admin/orders.dart';
import 'package:pos_app/screens/Admin/shop.dart';
import 'package:pos_app/screens/Admin/waste_products.dart';
import 'package:pos_app/screens/customer.dart';
import 'package:shared_preferences/shared_preferences.dart'; // REQUIRED IMPORT

import '../../screens/Admin/brand.dart';
import '../../screens/Admin/color.dart';
import '../../screens/Admin/dashboard.dart';
import '../../screens/Admin/emoloyee.dart';
import '../../screens/Admin/product.dart';
import '../../screens/Admin/reports.dart';
import '../../screens/Admin/size.dart';
import '../../screens/Admin/supplier.dart';
import '../../screens/Finance/financeemployee.dart';
import '../../screens/Hr/hremployee.dart';
import '../../screens/home_screen.dart';
import '../../screens/login_screen.dart';


class SideBar extends StatelessWidget {
  final String selectedPage;
  const SideBar({super.key, required this.selectedPage});

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {'icon': Icons.bar_chart, 'label': 'Reports'},
      {'icon': Icons.shopping_cart, 'label': 'Sale'},
      {'icon': Icons.category, 'label': 'Category'},
      {'icon': Icons.branding_watermark, 'label': 'Brand'},
      {'icon': Icons.color_lens, 'label': 'Color'},
      {'icon': Icons.straighten, 'label': 'Size'},
      {'icon': Icons.grid_view, 'label': 'Products'},
      {'icon': Icons.delete, 'label': 'WasteProduct'},
      {'icon': Icons.local_shipping, 'label': 'Supplier'},
      {'icon': Icons.people, 'label': 'Customers'},
      {'icon': Icons.people, 'label': 'Employees'},
      {'icon': Icons.account_balance_wallet, 'label': 'FinanceManagement'},
      {'icon': Icons.people, 'label': 'HrManagement'},
      // {'icon': Icons.local_shipping, 'label': 'Suppliers'},
      {'icon': Icons.receipt_long, 'label': 'Orders'},
      {'icon': Icons.logout, 'label': 'Logout'},
    ];

    Future<void> _navigate(String label) async {
      // 1. Load SharedPreferences once at the start
      final prefs = await SharedPreferences.getInstance();

      // 2. Retrieve Shop ID and Token from storage
      // Assuming 'shopId' is stored as an int during login
      final int? shopId = prefs.getInt('shopId');
      final String token = prefs.getString('accessToken') ?? '';

      // Fallback for screens requiring shopId. If null, use a default or handle as error.
      // We'll use 1 as a safe default if the ID isn't found, but log a warning.
      final int effectiveShopId = shopId ?? 1;

      Widget screen;
      switch (label) {
        case 'Reports':
        // FIX: Pass the retrieved shopId
          screen = ReportsScreen(shopId: effectiveShopId);
          break;
        case 'Sale':
        // FIX: Pass the retrieved shopId and token
          screen = HomeScreen(role: '', shopId: effectiveShopId, token: token);
          break;
        case 'Category':
          screen = const CategoryScreen();
          break;
        case 'Brand':
          screen = const BrandScreen();
          break;
        case 'Color':
          screen = const ColorScreen();
          break;
        case 'Size':
          screen = const SizeScreen();
          break;
        case 'Products':
          screen = const ProductScreen();
          break;
        case 'WasteProduct':
          screen = const WasteScreen();
          break;
        case 'Supplier':
          screen = const SupplierScreen();
          break;
        case 'Customers':
          screen = CustomerListScreen(shopId: effectiveShopId, accessToken: token);
          break;

        case 'Employees':
          screen = const EmployeeScreen();
          break;
        case 'FinanceManagement':
          screen = const FinanceScreen ();
          break;
        case 'HrManagement':
          screen = const HrScreen();
          break;
        case 'Orders':
          screen = const OrdersScreen();
          break;

        case 'Logout':
        // Clear all tokens
          await prefs.remove('accessToken');
          await prefs.remove('refreshToken');
          await prefs.remove('shopId'); // Clear shop ID as well

          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Successfully logged out."))
          );

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
                (Route<dynamic> route) => false,
          );
          return;

        default:
        // FIX: Use the retrieved shopId for the default case as well
          screen = ReportsScreen(shopId: effectiveShopId);
      }

      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => screen));
    }

    return Drawer(
      child: Container(
        color: Colors.blueGrey.shade900,
        child: ListView(
          children: menuItems.map((item) {
            final isSelected = selectedPage == item['label'];
            return ListTile(
              leading: Icon(item['icon'] as IconData,
                  color: isSelected ? Colors.white : Colors.grey),
              title: Text(item['label'] as String,
                  style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey)),
              selected: isSelected,
              onTap: () => _navigate(item['label'] as String),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// Global navigator key is not used in this file, but kept for completeness
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();