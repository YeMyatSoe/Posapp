import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/report.dart';


class ReportService {
  // Replace with your actual base URL
  final String _baseUrl = "http://127.0.0.1:8000/api/reports/shop-report/";
  final String _mockToken = "YOUR_AUTH_TOKEN"; // Replace with real token logic

  // Fetches aggregated report data for a given shop and period
  Future<ShopReport> fetchShopReport({
    required int shopId,
    required String period,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // 1. Build query parameters
    final Map<String, String> queryParams = {
      'shop_id': shopId.toString(),
      'period': period,
    };

    if (period == 'custom' && startDate != null && endDate != null) {
      queryParams['start_date'] = startDate.toIso8601String().split('T').first;
      queryParams['end_date'] = endDate.toIso8601String().split('T').first;
    }

    // 2. Build URI
    final uri = Uri.parse(_baseUrl).replace(queryParameters: queryParams);

    // 3. Prepare headers
    final headers = {
      'Content-Type': 'application/json',
      // IMPORTANT: Replace with actual authentication logic
      'Authorization': 'Token $_mockToken',
    };

    try {
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ShopReport.fromJson(data);
      } else {
        // Handle specific API errors (e.g., 400 bad request)
        print("API Error: ${response.statusCode} - ${response.body}");
        throw Exception('Failed to load report: ${response.statusCode}');
      }
    } catch (e) {
      print("Network/Parsing Error: $e");
      // Fallback to initial report structure on error
      return initialReport;
    }
  }
}
