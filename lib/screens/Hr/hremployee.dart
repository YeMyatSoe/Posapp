import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http; // Still needed for _loadToken and manual handling if needed

import '../../widgets/admin/sidebar.dart';
import '../../services/employee_service.dart'; // Contains ApiService class
import 'form.dart'; // Assumed to contain form screens

/// ==================== HR MAIN SCREEN ====================
class HrScreen extends StatefulWidget {
  const HrScreen({super.key});

  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> {
  // We no longer need to store the token here, as all data fetching
  // will now use the static methods in ApiService which handle the token internally.
  bool _isLoggedIn = false;
  String selectedCategory = 'Employee Management';
  final List<String> categories = [
    'Employee Management',
    'Attendance & Leave Management',
    'Payroll Management',
    'Performance Management',
    'Recruitment',
    'Employee Self-Service',
    'Notifications & Reminders',
    'Compliance & Security',
  ];

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  // CRITICAL FIX: Simply check if *any* token exists to confirm login status.
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('accessToken');

    if (accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        // If token is missing, redirect to login
        Navigator.pushReplacementNamed(context, '/login');
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
        });
      }
    }
  }

  Widget content() {
    if (!_isLoggedIn) return const Center(child: CircularProgressIndicator());

    // CRITICAL FIX: All screens now use their standard, non-token-dependent constructors.
    switch (selectedCategory) {
      case 'Employee Management':
        return const EmployeeManageScreen();
      case 'Attendance & Leave Management':
        return const AttendanceScreen();
      case 'Payroll Management':
        return const PayrollScreen();
      case 'Performance Management':
        return const PerformanceScreen();
      case 'Recruitment':
        return const RecruitmentScreen();
      case 'Employee Self-Service':
        return const EmployeeSelfServiceScreen();
      case 'Notifications & Reminders':
        return const NotificationsScreen();
      case 'Compliance & Security':
        return const ComplianceScreen();
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("HR Management")),
      drawer: const SideBar(selectedPage: 'HrManagement'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  "Select HR Module: ",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: selectedCategory,
                    items: categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedCategory = value!),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: SingleChildScrollView(child: content())),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// REFACTORED SCREENS TO USE ApiService METHODS
// -------------------------------------------------------------

/// ==================== EMPLOYEE MANAGEMENT ====================
class EmployeeManageScreen extends StatefulWidget {
  // CRITICAL FIX: Remove token argument
  const EmployeeManageScreen({super.key});

  @override
  State<EmployeeManageScreen> createState() => _EmployeeManageScreenState();
}

class _EmployeeManageScreenState extends State<EmployeeManageScreen> {
  List<Map<String, dynamic>> employees = [];
  bool loading = true;

  // CRITICAL FIX: Remove manual headers

  @override
  void initState() {
    super.initState();
    fetchEmployees();
  }

  Future<void> fetchEmployees() async {
    setState(() => loading = true);
    try {
      // CRITICAL FIX: Use the robust static method
      employees = await ApiService.getEmployees();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // Unified error handler that checks for the Unauthorized exception
  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    // ApiService handles token removal, just redirect now.
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _navigateToForm({Map<String, dynamic>? employee}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: employee)),
    );

    if (result != null) {
      try {
        // CRITICAL FIX: Use the robust static method
        if (employee != null) {
          await ApiService.updateEmployee(employee['id'], result);
        } else {
          await ApiService.addEmployee(result);
        }
        await fetchEmployees();
      } on Exception catch (e) {
        _handleApiError(e);
      }
    }
  }

  void _deleteEmployee(int id) async {
    try {
      // CRITICAL FIX: Use the robust static method
      await ApiService.deleteEmployee(id);
      fetchEmployees();
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToForm(),
            icon: const Icon(Icons.add),
            label: const Text("Add Employee"),
          ),
          const SizedBox(height: 16),
          // Wrap with Expanded if used inside a Column that has finite height
          // or if the parent is an Expanded (as in HrScreen content).
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("ID")),
                DataColumn(label: Text("Name")),
                DataColumn(label: Text("Role")),
                DataColumn(label: Text("Email")),
                DataColumn(label: Text("Phone")),
                DataColumn(label: Text("Address")),
                DataColumn(label: Text("Salary")),
                DataColumn(label: Text("Join Date")),
                DataColumn(label: Text("Status")),
                DataColumn(label: Text("Actions")),
              ],
              rows: employees.map((e) {
                final user = e['user'] ?? {};
                return DataRow(cells: [
                  DataCell(Text(e['id'].toString())),
                  DataCell(Text(user['username'] ?? '')),
                  DataCell(Text(e['role'] ?? '')),
                  DataCell(Text(user['email'] ?? '')),
                  DataCell(Text(e['phone'] ?? '')),
                  DataCell(Text(e['address'] ?? '')),
                  DataCell(Text("\$${e['salary'] ?? 0}")),
                  DataCell(Text(e['join_date']?.toString().split('T')[0] ?? '')),
                  DataCell(Text(e['status'] ?? '')),
                  DataCell(Row(
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(employee: e)),
                      IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteEmployee(e['id'])),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// ==================== ATTENDANCE SCREEN ====================
class AttendanceScreen extends StatefulWidget {
  // CRITICAL FIX: Remove token argument
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  List<Map<String, dynamic>> records = [];
  bool loading = true;

  // CRITICAL FIX: Remove manual headers (already done)

  @override
  void initState() {
    super.initState();
    fetchAttendance();
  }

  Future<void> fetchAttendance() async {
    setState(() => loading = true);
    try {
      // CRITICAL FIX: Use the robust static method
      records = await ApiService.getAttendance();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _navigateToForm({Map<String, dynamic>? record}) async {
    final result = await Navigator.push(
      context,
      // Assuming AttendanceFormScreen is defined and accessible
      MaterialPageRoute(builder: (_) => AttendanceFormScreen(record: record)),
    );

    if (result != null) {
      // 🚨 FIX: Refresh the list, assuming the form handled the API call.
      // This makes the logic consistent with the PayrollScreen.
      await fetchAttendance();
    }
  }

  void _deleteRecord(int id) async {
    try {
      // CRITICAL FIX: Use the robust static method
      await ApiService.deleteAttendance(id);
      fetchAttendance();
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToForm(),
            icon: const Icon(Icons.add),
            label: const Text("Add Attendance"),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("ID")),
                DataColumn(label: Text("Employee")),
                DataColumn(label: Text("Date")),
                DataColumn(label: Text("Status")),
                DataColumn(label: Text("Actions")),
              ],
              rows: records.map((r) {
                return DataRow(cells: [
                  DataCell(Text(r['id'].toString())),
                  DataCell(Text(r['employeeName'] ?? '')),
                  DataCell(Text(r['date']?.toString().split('T')[0] ?? '')),
                  DataCell(Text(r['status'] ?? '')),
                  DataCell(Row(
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(record: r)),
                      IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteRecord(r['id'])),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
/// /////////////// Payroll
class PayrollScreen extends StatefulWidget {
  // CRITICAL FIX: Remove token argument
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  List<Map<String, dynamic>> payrolls = [];
  bool loading = true;

  // CRITICAL FIX: Remove manual headers (already done)

  @override
  void initState() {
    super.initState();
    fetchPayrolls();
  }

  Future<void> fetchPayrolls() async {
    setState(() => loading = true);
    try {
      // CRITICAL FIX: Use the robust static method
      payrolls = await ApiService.getPayrolls();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _navigateToForm({Map<String, dynamic>? payroll}) async {
    final result = await Navigator.push(
      context,
      // Assuming PayrollFormScreen is defined and accessible
      MaterialPageRoute(builder: (_) => PayrollFormScreen(payroll: payroll)),
    );

    if (result != null) {
      // The form returned a result (success), so we refresh the list.
      await fetchPayrolls();
    }
  }

  void _deletePayroll(int id) async {
    try {
      // CRITICAL FIX: Use the robust static method
      await ApiService.deletePayroll(id);
      fetchPayrolls();
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToForm(),
            icon: const Icon(Icons.add),
            label: const Text("Add Payroll"),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("ID")),
                DataColumn(label: Text("Employee")),
                DataColumn(label: Text("Month")),
                DataColumn(label: Text("Basic Salary")),
                DataColumn(label: Text("Bonus")),
                DataColumn(label: Text("Deductions")),
                DataColumn(label: Text("Net Pay")),
                DataColumn(label: Text("Actions")),
              ],
              rows: payrolls.map((p) {
                final employeeName = p['employee']?['user']?['username'] ?? p['employeeName'] ?? '';
                return DataRow(cells: [
                  DataCell(Text(p['id'].toString())),
                  DataCell(Text(employeeName)),
                  DataCell(Text(p['month'] ?? '')),
                  DataCell(Text("\$${p['salary'] ?? 0}")),
                  DataCell(Text("\$${p['bonus'] ?? 0}")),
                  DataCell(Text("\$${p['deductions'] ?? 0}")),
                  DataCell(Text("\$${p['net_pay'] ?? 0}")),
                  DataCell(Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _navigateToForm(payroll: p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deletePayroll(p['id']),
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
/// ---------------- PERFORMANCE ----------------
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  // Performance list structure: 'id', 'date', 'kpi', 'review', and a nested 'employee' object.
  List<Map<String, dynamic>> performance = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchPerformance();
  }

  // --- API Methods ---

  Future<void> fetchPerformance() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      performance = await ApiService.getPerformance();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _savePerformanceRecord(Map<String, dynamic> data) async {
    // Get the ID (null if adding, int if editing)
    final int? id = data['id'] as int?;

    // Remove temporary keys before sending to the API
    data.remove('id');
    data.remove('employeeName');

    try {
      if (id != null) {
        // UPDATE existing record
        await ApiService.updatePerformance(id, data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Performance record updated successfully! 🚀")),
        );
      } else {
        // ADD new record
        await ApiService.addPerformance(data);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Performance record added successfully! 🎉")),
        );
      }
      // Refresh the list after successful operation
      await fetchPerformance();
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  void _deleteRecord(int id) async {
    try {
      await ApiService.deletePerformance(id);

      // Local removal for faster UI update
      setState(() {
        performance.removeWhere((p) => p['id'] == id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Record deleted successfully.")),
      );
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  // --- Helper Methods ---

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  String _getEmployeeUsername(Map<String, dynamic> record) {
    return record['employee']?['user']?['username'] ?? record['employeeName'] ?? 'N/A';
  }

  // --- Navigation ---

  void _navigateToForm({Map<String, dynamic>? record}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PerformanceFormScreen(record: record)),
    );

    // 🚨 CRITICAL FIX: If the form returns data, call the save/update logic.
    if (result != null && result is Map<String, dynamic>) {
      await _savePerformanceRecord(result);
    }
  }

  // --- Widget Build ---

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: () => _navigateToForm(),
              icon: const Icon(Icons.add),
              label: const Text("Add Performance Record"),
            ),
            const SizedBox(height: 16),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text("ID")),
                  DataColumn(label: Text("Employee")),
                  DataColumn(label: Text("Date")),
                  DataColumn(label: Text("KPI")),
                  DataColumn(label: Text("Review")),
                  DataColumn(label: Text("Actions")),
                ],
                rows: performance.map((r) {
                  final id = r['id'] as int?;
                  return DataRow(cells: [
                    DataCell(Text(id?.toString() ?? '')),
                    DataCell(Text(_getEmployeeUsername(r))),
                    DataCell(Text(r['date'] ?? '')),
                    DataCell(Text(r['kpi']?.toString() ?? '')),
                    DataCell(Text(r['review'] ?? '')),
                    DataCell(Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _navigateToForm(record: r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: id == null ? null : () => _deleteRecord(id),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// ---------------- RECRUITMENT ----------------
class RecruitmentScreen extends StatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  State<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends State<RecruitmentScreen> {
  List<Map<String, dynamic>> jobs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchJobs();
  }

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> fetchJobs() async {
    setState(() => loading = true);
    try {
      jobs = await ApiService.getJobs();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      setState(() => loading = false);
    }
  }

  void _navigateToForm({Map<String, dynamic>? job}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobFormScreen(job: job),
      ),
    );

    if (result != null) {
      try {
        if (job != null) {
          await ApiService.updateJob(job['id'], result);
        } else {
          await ApiService.addJob(result);
        }
        await fetchJobs();
      } on Exception catch (e) {
        _handleApiError(e);
      }
    }
  }

  void _deleteJob(int id) async {
    try {
      await ApiService.deleteJob(id);
      await fetchJobs();
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateToForm(),
            icon: const Icon(Icons.add),
            label: const Text("Add Job"),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text("ID")),
                DataColumn(label: Text("Title")),
                DataColumn(label: Text("Department")),
                DataColumn(label: Text("Location")),
                DataColumn(label: Text("Openings")),
                DataColumn(label: Text("Actions")),
              ],
              rows: jobs.map((j) {
                return DataRow(cells: [
                  DataCell(Text(j['id']?.toString() ?? '')),
                  DataCell(Text(j['title'] ?? '')),
                  DataCell(Text(j['department'] ?? '')),
                  DataCell(Text(j['location'] ?? '')),
                  DataCell(Text(j['openings']?.toString() ?? '')),
                  DataCell(Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _navigateToForm(job: j),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteJob(j['id']),
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
/// ---------------- EMPLOYEE SELF SERVICE ----------------
class EmployeeSelfServiceScreen extends StatelessWidget {
  const EmployeeSelfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Center(
        child: Text(
          "Employee Self-Service (Profile, Leaves, Requests)",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

/// ---------------- NOTIFICATIONS ----------------
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> notifications = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> fetchNotifications() async {
    setState(() => loading = true);
    try {
      notifications = await ApiService.getNotifications();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (notifications.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("No notifications found."),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: notifications.length,
        itemBuilder: (context, index) {
          final n = notifications[index];
          return Card(
            child: ListTile(
              title: Text(n['title'] ?? ''),
              subtitle: Text(n['message'] ?? ''),
              trailing: Text(n['date']?.toString().split('T')[0] ?? ''),
            ),
          );
        },
      ),
    );
  }
}
/// ---------------- COMPLIANCE ----------------
class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({super.key});

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> {
  List<Map<String, dynamic>> docs = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchDocs();
  }

  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  void _handleUnauthorized() async {
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> fetchDocs() async {
    setState(() => loading = true);
    try {
      docs = await ApiService.getComplianceDocs();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (docs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text("No compliance documents available."),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: docs.length,
        itemBuilder: (context, index) {
          final doc = docs[index];
          return Card(
            child: ListTile(
              title: Text(doc['name'] ?? ''),
              subtitle: Text(doc['description'] ?? ''),
              trailing: Text(doc['status'] ?? ''),
            ),
          );
        },
      ),
    );
  }
}