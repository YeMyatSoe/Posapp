// import 'package:esc_pos_bluetooth/esc_pos_bluetooth.dart';
// import 'package:esc_pos_utils/esc_pos_utils.dart';
//
// class ReceiptPrinter {
//   final PrinterBluetoothManager printerManager = PrinterBluetoothManager();
//
//   Future<void> printReceipt(List<Map<String, dynamic>> cartItems, double discountPercent) async {
//     // Load capability profile
//     final profile = await CapabilityProfile.load();
//     final generator = Generator(PaperSize.mm58, profile);
//
//     // Example: Select the first paired printer
//     // In real app, you should scan and select printer
//     final printers = await printerManager.scanResults.first;
//     if (printers.isEmpty) return;
//     final printer = printers.first;
//     printerManager.selectPrinter(printer);
//
//     final ticket = <List<int>>[];
//
//     // Header
//     ticket.addAll(generator.text('POS Receipt', styles: PosStyles(bold: true, align: PosAlign.center)) as Iterable<List<int>>);
//     ticket.addAll(generator.hr() as Iterable<List<int>>);
//
//     // Items
//     double total = 0;
//     for (var item in cartItems) {
//       final name = item['name'];
//       final price = item['price'];
//       final qty = item['quantity'];
//       final lineTotal = price * qty;
//       total += lineTotal;
//
//       ticket.addAll(generator.row([
//         PosColumn(text: name, width: 6),
//         PosColumn(text: '$qty x \$${price.toStringAsFixed(2)}', width: 6, styles: PosStyles(align: PosAlign.right)),
//         PosColumn(text: '\$${lineTotal.toStringAsFixed(2)}', width: 4, styles: PosStyles(align: PosAlign.right)),
//       ]) as Iterable<List<int>>);
//     }
//
//     ticket.addAll(generator.hr() as Iterable<List<int>>);
//
//     // Discount
//     final discountAmount = total * discountPercent / 100;
//     ticket.addAll(generator.row([
//       PosColumn(text: 'Discount (${discountPercent.toStringAsFixed(1)}%)', width: 8),
//       PosColumn(text: '-\$${discountAmount.toStringAsFixed(2)}', width: 8, styles: PosStyles(align: PosAlign.right)),
//     ]) as Iterable<List<int>>);
//
//     // Total
//     final finalTotal = total - discountAmount;
//     ticket.addAll(generator.row([
//       PosColumn(text: 'Total', width: 8, styles: PosStyles(bold: true)),
//       PosColumn(text: '\$${finalTotal.toStringAsFixed(2)}', width: 8, styles: PosStyles(bold: true, align: PosAlign.right)),
//     ]) as Iterable<List<int>>);
//
//     ticket.addAll(generator.hr() as Iterable<List<int>>);
//     ticket.addAll(generator.text('Thank You!', styles: PosStyles(align: PosAlign.center)) as Iterable<List<int>>);
//     ticket.addAll(generator.cut() as Iterable<List<int>>);
//
//     // Print
//     await printerManager.printTicket(ticket.cast<int>());
//   }
// }
