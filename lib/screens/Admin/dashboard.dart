// import 'package:flutter/material.dart';
// import 'package:pos_app/screens/Admin/reports.dart';
// import '../../widgets/admin/sidebar.dart';
// import '../../widgets/chart_widget.dart';
// import 'emoloyee.dart';
//
// // Assuming 'navigatorKey' is defined globally somewhere and 'ReportsScreen' is a standard widget.
//
// class AdminDashboardScreen extends StatelessWidget {
//   // FIX 1: Add shopId field to the widget
//   final int? shopId;
//
//   // FIX 2: Update the constructor to accept shopId
//   const AdminDashboardScreen({super.key, this.shopId});
//
//   @override
//   Widget build(BuildContext context) {
//     // FIX 3: Define ReportsScreen dynamically using the widget's shopId
//     // If shopId is null, pass null, letting ReportsScreen handle the missing ID.
// // Provide a default shop ID (e.g., 0 or 1) if the widget's shopId is null.
//     final ReportsScreen reportsScreen = ReportsScreen(shopId: shopId ?? 0);
//
//     final stats = [
//       {
//         'title': 'Reports',
//         'value': '\$12,500',
//         'icon': Icons.attach_money,
//         // FIX APPLIED: Use the reportsScreen instance instead of the hardcoded version
//         'screen': reportsScreen,
//         'color': Colors.greenAccent.shade100,
//       },
//       {
//         'title': 'Orders',
//         'value': '120',
//         'icon': Icons.shopping_cart,
//         'screen': null,
//         'color': Colors.blueAccent.shade100,
//       },
//       {
//         'title': 'Employee',
//         'value': '85',
//         'icon': Icons.people,
//         'screen': const EmployeeScreen(),
//         'color': Colors.orangeAccent.shade100,
//       },
//       {
//         'title': 'Low Stock',
//         'value': '5',
//         'icon': Icons.warning,
//         'screen': null,
//         'color': Colors.redAccent.shade100,
//       },
//     ];
//
//     return Scaffold(
//       key: navigatorKey,
//       appBar: AppBar(title: const Text("Admin Dashboard")),
//       drawer: const SideBar(selectedPage: 'Dashboard'),
//       body: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           children: [
//             SizedBox(
//               height: 140,
//               child: ListView.separated(
//                 scrollDirection: Axis.horizontal,
//                 itemCount: stats.length,
//                 separatorBuilder: (_, __) => const SizedBox(width: 16),
//                 itemBuilder: (context, index) {
//                   final stat = stats[index];
//                   return GestureDetector(
//                     onTap: () {
//                       if (stat['screen'] != null) {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (_) => stat['screen'] as Widget,
//                           ),
//                         );
//                       }
//                     },
//                     child: Card(
//                       elevation: 4,
//                       color: stat['color'] as Color?, // ✅ Apply background color
//                       shape: RoundedRectangleBorder(
//                           borderRadius: BorderRadius.circular(16)),
//                       child: SizedBox(
//                         width: 160,
//                         child: Padding(
//                           padding: const EdgeInsets.all(12),
//                           child: Column(
//                             mainAxisAlignment: MainAxisAlignment.center,
//                             children: [
//                               Icon(
//                                 stat['icon'] as IconData,
//                                 size: 32,
//                                 color: Colors.black87,
//                               ),
//                               const SizedBox(height: 10),
//                               Flexible(
//                                 child: Text(
//                                   stat['title'] as String,
//                                   textAlign: TextAlign.center,
//                                   style: const TextStyle(
//                                     fontWeight: FontWeight.bold,
//                                     fontSize: 14,
//                                     color: Colors.black87,
//                                   ),
//                                   overflow: TextOverflow.ellipsis,
//                                   maxLines: 1,
//                                 ),
//                               ),
//                               const SizedBox(height: 6),
//                               Text(
//                                 stat['value'] as String,
//                                 style: const TextStyle(
//                                   fontSize: 16,
//                                   fontWeight: FontWeight.w600,
//                                   color: Colors.black87,
//                                 ),
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   );
//                 },
//               ),
//             ),
//             const SizedBox(height: 16),
//             Expanded(
//               child: Card(
//                 elevation: 3,
//                 shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12)),
//                 child: const Padding(
//                   padding: EdgeInsets.all(16),
//                   child: ChartWidget(),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
//
// // NOTE: Placeholder for navigatorKey for compilation
// final GlobalKey<ScaffoldState> navigatorKey = GlobalKey<ScaffoldState>();