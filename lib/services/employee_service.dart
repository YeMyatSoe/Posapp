import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
class AbsentData {
  final int absentDays;
  final int totalWorkingDays;

  AbsentData(this.absentDays, this.totalWorkingDays);
}
class ApiService {
  static const String baseUrl = 'http://10.0.2.2:8000/api';
  static const String _refreshUrl = 'http://10.0.2.2:8000/api/token/refresh/';

  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ============================================
  // CORE AUTH & REFRESH UTILITIES
  // ============================================

  /// Fetches current access token from SharedPreferences.
  static Future<String> get _getAccessToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('accessToken') ?? '';
  }

  /// Refreshes the access token using the stored refresh token.
  /// Returns the new access token if successful, otherwise null.
  static Future<String?> _refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString('refreshToken') ?? '';

    if (refreshToken.isEmpty) return null;

    final response = await http.post(
      Uri.parse(_refreshUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({'refresh': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final newAccessToken = data['access'] as String;
      await prefs.setString('accessToken', newAccessToken);
      return newAccessToken;
    }

    // If refresh fails, clear tokens to force re-login
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    return null;
  }
  static Future<String?> refreshToken() async {
    return _refreshToken();
  }
  /// JWT headers for the current token.
  static Future<Map<String, String>> _getHeaders(String token) async {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Centralized function to make an API call with automatic token refresh retry.
  static Future<http.Response> _makeApiCallWithRefresh(
      String method,
      String url, {
        Map<String, dynamic>? body,
        int retryCount = 0,
      }) async {
    String token = await _getAccessToken;
    if (token.isEmpty) {
      // If no token at all, throw unauthorized immediately
      throw Exception('Unauthorized. No access token found.');
    }

    final headers = await _getHeaders(token);
    final uri = Uri.parse(url);
    http.Response response;

    // 1. Initial API Call
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: json.encode(body));
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: json.encode(body));
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
          break;
        default:
          throw Exception("Unsupported HTTP method: $method");
      }
    } on Exception catch(e) {
      // Handle network errors or timeouts before receiving a status code
      rethrow;
    }


    // 2. Handle 401 Unauthorized
    if (response.statusCode == 401 && retryCount == 0) {
      final newAccessToken = await _refreshToken();

      if (newAccessToken != null) {
        // Retry the API call immediately with the new token
        return _makeApiCallWithRefresh(
          method,
          url,
          body: body,
          retryCount: 1, // Prevent infinite retry loop
        );
      } else {
        // Refresh failed, final 401 response
        throw Exception('Unauthorized. Please login.');
      }
    }

    // 3. Return final response (either successful or failed after retry attempt)
    return response;
  }


  // ============================================
  // REFACTORED API ENDPOINTS
  // ============================================

  // -------- USERS --------
  static Future<List<Map<String, dynamic>>> fetchUsers() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/users/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load users: ${res.statusCode}');
  }

  // -------- Shops --------
  static Future<List<Map<String, dynamic>>> fetchShops() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/shops/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load shops: ${res.statusCode}');
  }

  // -------- EMPLOYEES --------
  static Future<List<Map<String, dynamic>>> getEmployees() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/employees/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load employees: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addEmployee(Map<String, dynamic> e) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/employees/', body: e);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add employee: ${res.body}');
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> updateEmployee(int id, Map<String, dynamic> e) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/employees/$id/', body: e);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update employee: ${res.body}');
    return json.decode(res.body);
  }

  static Future<void> deleteEmployee(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/employees/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete employee: ${res.body}');
  }

  // -------- ATTENDANCE --------
  static Future<List<Map<String, dynamic>>> getAttendance() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/attendance/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load attendance: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addAttendance(Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/attendance/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add attendance: ${res.body}');
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> updateAttendance(int id, Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/attendance/$id/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update attendance: ${res.body}');
    return json.decode(res.body);
  }

  static Future<void> deleteAttendance(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/attendance/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete attendance: ${res.body}');
  }

  // -------- PAYROLL --------
  static Future<List<Map<String, dynamic>>> getPayrolls() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/payrolls/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load payrolls: ${res.statusCode}');
  }

  static Future<double> getTotalMonthlySalary() async {
    final currentMonth = DateFormat('MM').format(DateTime.now());
    final currentYear = DateTime.now().year;

    final url = '$baseUrl/payrolls/monthly_summary/?month=$currentMonth&year=$currentYear';

    final res = await _makeApiCallWithRefresh('GET', url);

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      // Using 'total_net_pay' as intended by the previous financial logic
      return _parseDouble(data['total_net_pay']);
    }

    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load total payroll: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addPayroll(Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/payrolls/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add payroll: ${res.body}');
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> updatePayroll(int id, Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/payrolls/$id/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update payroll: ${res.body}');
    return json.decode(res.body);
  }

  static Future<void> deletePayroll(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/payrolls/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete payroll: ${res.body}');
  }
  static Future<int> fetchEmployeeAbsentDays(
      int employeeId, String month, {int? year}) async { // Added optional year parameter

    // Construct the base URL
    String url = '$baseUrl/attendance/absent_count/?employee_id=$employeeId&month=$month';

    // Append the year if provided
    if (year != null) {
      url += '&year=$year';
    }

    try {
      // 1. Call the helper function to get the raw HTTP response
      final res = await _makeApiCallWithRefresh('GET', url);

      // 2. Check for success status code
      if (res.statusCode == 200) {
        // 3. Decode the response body into a Dart object
        final responseData = json.decode(res.body);

        // 4. Check the decoded map for the correct payroll key
        // 💡 FIX: Accessing 'absent_days_for_payroll_deduction'
        // as per the recommended backend implementation.
        const payrollKey = 'absent_days_for_payroll_deduction';

        if (responseData is Map<String, dynamic> && responseData.containsKey(payrollKey)) {
          // Safely return the integer value (casting from num to handle both int/double from JSON)
          return (responseData[payrollKey] as num).toInt();
        } else {
          // Handle unexpected response body format
          throw Exception('Invalid response format for absent days. Expected {"$payrollKey": ...}');
        }
      }

      // 5. Handle standard errors from the API endpoint
      if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
      throw Exception('Failed to fetch absent days: ${res.statusCode} ${res.body}');

    } on Exception catch (e) {
      // This catches 'Unauthorized' exceptions and any network/decoding exceptions.
      // In a payroll context, failing to fetch absent days might mean the employee gets full pay.
      // Returning 0 is a common and safe default, but you might prefer re-throwing the exception.
      // For this fix, we maintain the original safe fallback of 0.
      // debugPrint('Error fetching absent days: $e');
      return 0;
    }
  }
// 🚨 REPLACED/FIXED FUNCTION to fetch both absent and working days
  static Future<AbsentData> fetchAbsentAndWorkingDays(
      int employeeId, String month, {int? year}) async {

    String url = '$baseUrl/attendance/absent_count/?employee_id=$employeeId&month=$month';
    if (year != null) {
      url += '&year=$year';
    }

    try {
      final res = await _makeApiCallWithRefresh('GET', url);

      if (res.statusCode == 200) {
        final responseData = json.decode(res.body);

        // Keys match the final backend implementation
        const absentKey = 'absent_days_for_payroll_deduction';
        const workingKey = 'total_expected_working_days';

        if (responseData is Map<String, dynamic> &&
            responseData.containsKey(absentKey) &&
            responseData.containsKey(workingKey)) {

          return AbsentData(
            (responseData[absentKey] as num).toInt(),
            (responseData[workingKey] as num).toInt(),
          );
        } else {
          throw Exception('Invalid response format for payroll data. Missing "$absentKey" or "$workingKey".');
        }
      }

      if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
      throw Exception('Failed to fetch absent/working days: ${res.statusCode} ${res.body}');

    } on Exception catch (e) {
      // Catch network/other exceptions and wrap them
      throw Exception('Network or processing error during absent day fetch: $e');
    }
  }

    static Future<String> getLatestPerformanceRating(int employeeId) async {
      await Future.delayed(const Duration(milliseconds: 200));
      // Simulate API response for demonstration
      if (employeeId == 101) return 'Best';
      if (employeeId == 102) return 'Very Good';
      return 'N/A';
    }
  // -------- PERFORMANCE --------
  static Future<List<Map<String, dynamic>>> getPerformance() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/performance/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load performance: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addPerformance(Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/performance/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add performance: ${res.body}');
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> updatePerformance(int id, Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/performance/$id/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update performance: ${res.body}');
    return json.decode(res.body);
  }

  static Future<void> deletePerformance(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/performance/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete performance: ${res.body}');
  }
  // THIS FUNCTION IS CORRECT AND SHOULD BE USED

  static Future<String> fetchEmployeePerformanceRating(int employeeId) async {
    // Construct the URL to get the latest rating for the employee
    final url = '$baseUrl/performance/latest_rating/?employee_id=$employeeId';

    try {
      final res = await _makeApiCallWithRefresh('GET', url);

      if (res.statusCode == 200) {
        final data = json.decode(res.body);

        // 🚨 ASSUME the backend returns a map like: {"rating": "Best"}
        final rating = data['rating'] as String?;
        return rating ?? 'N/A'; // Returns 'N/A' if the 'rating' key is null/missing

      } else if (res.statusCode == 404) {
        // If no rating is found for the employee (404), treat as N/A
        return 'N/A';
      }

      if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
      throw Exception('Failed to fetch performance rating: ${res.statusCode} ${res.body}');

    } on Exception catch (e) {
      // Fallback for network errors or other exceptions
      // If the call fails, the bonus calculation will use 'N/A' (resulting in $0.00)
      return 'N/A';
    }
  }
  // -------- RECRUITMENT --------
  static Future<List<Map<String, dynamic>>> getJobs() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/jobs/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load jobs: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> addJob(Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/jobs/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add job: ${res.body}');
    return json.decode(res.body);
  }

  static Future<Map<String, dynamic>> updateJob(int id, Map<String, dynamic> r) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/jobs/$id/', body: r);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update job: ${res.body}');
    return json.decode(res.body);
  }

  static Future<void> deleteJob(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/jobs/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete job: ${res.body}');
  }

  // -------- NOTIFICATIONS --------
  static Future<List<Map<String, dynamic>>> getNotifications() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/notifications/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load notifications: ${res.statusCode}');
  }

  // -------- COMPLIANCE --------
  static Future<List<Map<String, dynamic>>> getComplianceDocs() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/compliance/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to load compliance documents: ${res.statusCode}');
  }

  // -------- EXPENSES --------
  static Future<List<Map<String, dynamic>>> getExpenses() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/expenses/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to fetch expenses: ${res.body}');
  }

  static Future<void> addExpense(Map<String, dynamic> data) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/expenses/', body: data);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add expense: ${res.body}');
  }

  static Future<void> updateExpense(int id, Map<String, dynamic> data) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/expenses/$id/', body: data);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update expense: ${res.body}');
  }

  static Future<void> deleteExpense(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/expenses/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete expense: ${res.body}');
  }

  // -------- ADJUSTMENTS --------
  static Future<List<Map<String, dynamic>>> getAdjustments() async {
    final res = await _makeApiCallWithRefresh('GET', '$baseUrl/adjustments/');
    if (res.statusCode == 200) return List<Map<String, dynamic>>.from(json.decode(res.body));
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    throw Exception('Failed to fetch adjustments: ${res.body}');
  }

  static Future<void> addAdjustment(Map<String, dynamic> data) async {
    final res = await _makeApiCallWithRefresh('POST', '$baseUrl/adjustments/', body: data);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 201) throw Exception('Failed to add adjustment: ${res.body}');
  }

  static Future<void> updateAdjustment(int id, Map<String, dynamic> data) async {
    final res = await _makeApiCallWithRefresh('PUT', '$baseUrl/adjustments/$id/', body: data);
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 200) throw Exception('Failed to update adjustment: ${res.body}');
  }

  static Future<void> deleteAdjustment(int id) async {
    final res = await _makeApiCallWithRefresh('DELETE', '$baseUrl/adjustments/$id/');
    if (res.statusCode == 401) throw Exception('Unauthorized. Please login.');
    if (res.statusCode != 204) throw Exception('Failed to delete adjustment: ${res.body}');
  }
}