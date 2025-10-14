import 'package:flutter/material.dart';
import 'package:pos_app/screens/Admin/reports.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🚨 NEW IMPORT for Logout

import '../providers/cart_provider.dart';
import '../screens/home_screen.dart';
import '../screens/cart_screen.dart';
import '../screens/login_screen.dart'; // 🚨 NEW IMPORT for Logout redirect

class POSMenuBar extends StatelessWidget implements PreferredSizeWidget {
  final double totalAmount;
  final String userRole;
  final int? userShopId;
  final String token;
  // Removed 'role' since it's redundant with 'userRole'
  const POSMenuBar({
    super.key,
    required this.totalAmount,
    required this.userRole,
    required this.userShopId,
    required this.token,
    required String role, // Kept for constructor compatibility, but marked as unused
  });

  void _navigate(BuildContext context, String label) async {
    // Determine the effective shop ID, falling back to null or 1 if necessary
    final int effectiveShopId = userShopId ?? 1;

    switch (label) {
      case 'Sale':
      // case 'Dashboard': // Dashboard often redirects to the main Sale screen for POS users
      //   Navigator.pushReplacement(
      //     context,
      //     MaterialPageRoute(
      //       builder: (_) => HomeScreen(
      //         role: userRole,
      //         shopId: effectiveShopId,
      //         token: token,
      //       ),
      //     ),
      //   );
      //   break;

      case 'Cart':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CartScreen(
              role: userRole,
              shopId: effectiveShopId,
            ),
          ),
        );
        break;

      case 'Dashboard':
      // 🚨 FIX: Pass the actual userShopId instead of hardcoding '1'
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ReportsScreen(shopId: effectiveShopId),
          ),
        );
        break;

      case 'Logout':
      // 🚨 FIX: Implement Logout logic to clear tokens and redirect
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('accessToken');
        await prefs.remove('refreshToken');
        await prefs.remove('shopId'); // Clear shop ID as well

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Successfully logged out."))
        );

        // Navigate to LoginScreen and clear the navigation stack
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
              (Route<dynamic> route) => false,
        );
        return; // Return immediately after handling logout

      default:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$label pressed")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuItems = [
      {'icon': Icons.home, 'label': 'Dashboard'},
      {'icon': Icons.inventory, 'label': 'Sale'},
      {'icon': Icons.shopping_cart, 'label': 'Cart'},
      {'icon': Icons.report, 'label': 'Reports'},
      {'icon': Icons.logout, 'label': 'Logout'},
    ];

    return AppBar(
      title: const Text('POS System'),
      toolbarHeight: kToolbarHeight + 10,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Container(
          color: Colors.blue[700],
          height: 50,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: menuItems.map((item) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => _navigate(context, item['label'] as String),
                    icon: Icon(item['icon'] as IconData, size: 20, color: Colors.white),
                    label: Text(item['label'] as String),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      actions: [
        // Cart Icon action is kept the same, ensuring it uses userShopId
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CartScreen(
                  role: userRole,
                  shopId: userShopId, // Correctly uses passed shopId
                ),
              ),
            ),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                const Icon(Icons.shopping_cart, size: 32),
                Consumer<CartProvider>(
                  builder: (context, cart, child) {
                    final totalItems = cart.totalItems;
                    return totalItems > 0
                        ? Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '$totalItems',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    )
                        : const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 50);
}