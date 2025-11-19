import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_app/screens/Admin/category.dart';
import 'package:pos_app/screens/Admin/orders.dart';
import 'package:pos_app/screens/Admin/shop.dart';
import 'package:pos_app/screens/Admin/waste_products.dart';
import 'package:pos_app/screens/customer.dart';
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

  Future<void> _navigate(BuildContext context, String label) async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ Always retrieve stored values safely
    final int effectiveShopId = prefs.getInt('shopId') ?? 1;
    final String token = prefs.getString('accessToken') ?? '';

    late final Widget screen;

    switch (label) {
      case 'အစီရင်ခံစာ': // Reports
        screen = ReportsScreen(shopId: effectiveShopId);
        break;

      case 'ရောင်းချမှု': // Sale (Dashboard/Home)
        screen = HomeScreen(
          role: '',
          shopId: effectiveShopId,
          token: token,
        );
        break;

      case 'အမျိုးအစား':
        screen = const CategoryScreen();
        break;

      case 'အမှတ်တံဆိပ်':
        screen = const BrandScreen();
        break;

      case 'အရောင်':
        screen = const ColorScreen();
        break;

      case 'အရွယ်အစား':
        screen = const SizeScreen();
        break;

      case 'ထုတ်ကုန်များ':
        screen = const ProductScreen();
        break;

      case 'မသုံးတော့သောပစ္စည်း':
        screen = const WasteScreen();
        break;

      case 'ပေးသွင်းသူ':
        screen = const SupplierScreen();
        break;

      case 'ဖောက်သည်များ':
        screen = CustomerListScreen(
          shopId: effectiveShopId,
          accessToken: token,
        );
        break;

      case 'ဝန်ထမ်းများ':
        screen = const EmployeeScreen();
        break;

      case 'ဘဏ္ဍာရေးစီမံခန့်ခွဲမှု':
        final prefs = await SharedPreferences.getInstance();
        final int? userShopId = prefs.getInt('userShopId'); // This must match the key you saved at login

        if (userShopId != null) {
          screen = FinanceScreen(selectedShopId: userShopId);
        } else {
          // Fallback if shop ID not found
          screen = const FinanceScreen(selectedShopId: 0);
        }
        break;


      case 'လူ့စွမ်းအားစီမံခန့်ခွဲမှု':
        screen = const HrScreen();
        break;

      case 'အမှာစာများ':
        screen = const OrdersScreen();
        break;

      case 'ထွက်မည်': // Logout
        await prefs.clear(); // ✅ simpler than removing one by one

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Successfully logged out.")),
          );

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
                (Route<dynamic> route) => false,
          );
        }
        return;

      default:
        screen = ReportsScreen(shopId: effectiveShopId);
    }

    // ✅ Safer navigation replacement
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => screen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {'icon': Icons.bar_chart, 'label': 'အစီရင်ခံစာ'}, // Reports
      {'icon': Icons.shopping_cart, 'label': 'ရောင်းချမှု'}, // Sale
      {'icon': Icons.category, 'label': 'အမျိုးအစား'}, // Category
      {'icon': Icons.branding_watermark, 'label': 'အမှတ်တံဆိပ်'}, // Brand
      {'icon': Icons.color_lens, 'label': 'အရောင်'}, // Color
      {'icon': Icons.straighten, 'label': 'အရွယ်အစား'}, // Size
      {'icon': Icons.grid_view, 'label': 'ထုတ်ကုန်များ'}, // Products
      {'icon': Icons.delete, 'label': 'မသုံးတော့သောပစ္စည်း'}, // WasteProduct
      {'icon': Icons.local_shipping, 'label': 'ပေးသွင်းသူ'}, // Supplier
      {'icon': Icons.people, 'label': 'ဖောက်သည်များ'}, // Customers
      {'icon': Icons.people, 'label': 'ဝန်ထမ်းများ'}, // Employees
      {
        'icon': Icons.account_balance_wallet,
        'label': 'ဘဏ္ဍာရေးစီမံခန့်ခွဲမှု'
      }, // Finance
      {'icon': Icons.people, 'label': 'လူ့စွမ်းအားစီမံခန့်ခွဲမှု'}, // HR
      {'icon': Icons.receipt_long, 'label': 'အမှာစာများ'}, // Orders
      {'icon': Icons.logout, 'label': 'ထွက်မည်'}, // Logout
    ];

    return Drawer(
      child: Container(
        color: Colors.blueGrey.shade900,
        child: ListView(
          children: menuItems.map((item) {
            final isSelected = selectedPage == item['label'];
            return ListTile(
              leading: Icon(
                item['icon'] as IconData,
                color: isSelected ? Colors.white : Colors.grey,
              ),
              title: Text(
                item['label'] as String,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey,
                ),
              ),
              selected: isSelected,
              onTap: () => _navigate(context, item['label'] as String),
            );
          }).toList(),
        ),
      ),
    );
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
