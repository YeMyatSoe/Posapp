import 'package:flutter/material.dart';
import '../../widgets/admin/sidebar.dart';
import 'employeeform.dart';
// 🚨 NEW IMPORTS for API service and error handling
import '../../services/employee_service.dart'; // Assuming ApiService is here
import 'package:shared_preferences/shared_preferences.dart'; // For logout redirection

// 🚨 RENAMED to reflect its API management function
class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  // 🚨 State class name updated to reflect the widget name
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

// 🚨 ADOPTING THE ROBUST, API-DRIVEN STATE STRUCTURE
class _EmployeeScreenState extends State<EmployeeScreen> {
  // 🚨 REPLACED local dummy data with API-driven state
  List<Map<String, dynamic>> employees = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchEmployees();
  }

  // 1. FETCH METHOD (Uses ApiService.getEmployees)
  Future<void> fetchEmployees() async {
    setState(() => loading = true);
    try {
      // ✅ Use the robust static method
      employees = await ApiService.getEmployees();
    } on Exception catch (e) {
      _handleApiError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // 2. UNIFIED ERROR HANDLER
  void _handleApiError(Exception e) {
    if (e.toString().contains('Unauthorized. Please login.')) {
      _handleUnauthorized();
    } else if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: ${e.toString()}")));
    }
  }

  // 3. UNAUTHORIZED REDIRECTION
  void _handleUnauthorized() async {
    // ApiService handles token removal; we just redirect now.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('accessToken');
    await prefs.remove('refreshToken');
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  // 4. ADD/EDIT METHOD (Uses ApiService.addEmployee/updateEmployee)
  void _openEmployeeForm({Map<String, dynamic>? employee}) async {
    // 🚨 Renamed to match the preferred style
    final result = await Navigator.push(
      context,
      // Assuming EmployeeFormScreen is updated to return the Map data on save
      MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: employee, onSave: (Map<String, dynamic> p1) {  },)),
    );

    if (result != null) {
      try {
        // ✅ Use the robust static methods for CRUD
        if (employee != null) {
          await ApiService.updateEmployee(employee['id'], result);
        } else {
          await ApiService.addEmployee(result);
        }
        await fetchEmployees(); // Refresh list after operation
      } on Exception catch (e) {
        _handleApiError(e);
      }
    }
  }

  // 5. DELETE METHOD (Uses ApiService.deleteEmployee)
  void _deleteEmployee(int id) async {
    try {
      // ✅ Use the robust static method
      await ApiService.deleteEmployee(id);
      fetchEmployees(); // Refresh list
    } on Exception catch (e) {
      _handleApiError(e);
    }
  }

  // 🚨 REMOVED _statusBadge WIDGET: Status is now a simple string from the API

  @override
  Widget build(BuildContext context) {
    // Show loading spinner
    if (loading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Employee Management"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openEmployeeForm(),
          ),
        ],
      ),
      drawer: const SideBar(selectedPage: 'Employees'),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton.icon(
              onPressed: () => _openEmployeeForm(),
              icon: const Icon(Icons.add),
              label: const Text("Add Employee"),
            ),
            const SizedBox(height: 16),
            Expanded( // Use Expanded to give DataTable space in the Column
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
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
                      // 🚨 ADOPTING API DATA STRUCTURE:
                      // Assuming user fields (username, email) are nested under 'user'
                      final user = e['user'] ?? {};
                      return DataRow(
                        cells: [
                          DataCell(Text(e['id'].toString())),
                          DataCell(Text(user['username'] ?? 'N/A')),
                          DataCell(Text(e['role'] ?? '')),
                          DataCell(Text(user['email'] ?? '')),
                          DataCell(Text(e['phone'] ?? '')), // phone/address might be on employee or user
                          DataCell(Text(e['address'] ?? '')),
                          DataCell(Text("\$${e['salary'] ?? 0}")),
                          DataCell(Text(e['join_date']?.toString().split('T')[0] ?? '')),
                          DataCell(Text(e['status'] ?? 'N/A')), // Status is now a string
                          DataCell(Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _openEmployeeForm(employee: e),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteEmployee(e['id']),
                              ),
                            ],
                          )),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}