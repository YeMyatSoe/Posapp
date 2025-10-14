import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void saveProfitLossReport(BuildContext context, List<Map<String, dynamic>> rows) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      build: (pw.Context context) {
        return pw.Table.fromTextArray(
          headers: ["Description", "Amount"],
          data: rows.map((row) => [
            row["label"],
            "\$${(row["amount"] as double).toStringAsFixed(2)}",
          ]).toList(),
        );
      },
    ),
  );

  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: "profit_loss_report.pdf",
  );
}
