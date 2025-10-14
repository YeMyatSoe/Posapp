import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/employee_service.dart';

/// ---------------- EMPLOYEE FORM ----------------
class EmployeeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController salaryController;
  late TextEditingController joinDateController;
  String status = 'Active';
  int? selectedUserId;
  int? selectedShopId;

  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> shops = [];

  @override
  void initState() {
    super.initState();
    salaryController = TextEditingController(text: widget.employee?['salary']?.toString() ?? '');
    joinDateController = TextEditingController(text: widget.employee?['join_date'] ?? '');
    status = widget.employee?['status'] ?? 'Active';
    selectedUserId = widget.employee?['user']?['id'];
    selectedShopId = widget.employee?['shop'];

    fetchUsersAndShops();
  }

  Future<void> fetchUsersAndShops() async {
    // TODO: replace with your API calls
    users = await ApiService.fetchUsers(); // returns List<Map>
    shops = await ApiService.fetchShops(); // returns List<Map>
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.employee != null ? "Edit Employee" : "Add Employee")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // User dropdown
// User dropdown
              DropdownButtonFormField<int>(
                value: selectedUserId,
                decoration: const InputDecoration(labelText: "User"),
                items: users
                    .map((u) => DropdownMenuItem<int>(
                  value: u['id'] as int,  // ensure it's int
                  child: Text(u['username']),
                ))
                    .toList(),
                onChanged: (v) => setState(() => selectedUserId = v),
                validator: (v) => v == null ? "Select a user" : null,
              ),

// Shop dropdown
              DropdownButtonFormField<int>(
                value: selectedShopId,
                decoration: const InputDecoration(labelText: "Shop"),
                items: shops
                    .map((s) => DropdownMenuItem<int>(
                  value: s['id'] as int,  // ensure it's int
                  child: Text(s['name']),
                ))
                    .toList(),
                onChanged: (v) => setState(() => selectedShopId = v),
                validator: (v) => v == null ? "Select a shop" : null,
              ),


              // Salary
              TextFormField(
                controller: salaryController,
                decoration: const InputDecoration(labelText: "Salary"),
                keyboardType: TextInputType.number,
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),

              // Join date
              TextFormField(
                controller: joinDateController,
                decoration: const InputDecoration(labelText: "Join Date (YYYY-MM-DD)"),
                validator: (v) => v!.isEmpty ? "Required" : null,
              ),

              // Status dropdown
              DropdownButtonFormField<String>(
                value: status,
                decoration: const InputDecoration(labelText: "Status"),
                items: ['Active', 'Inactive', 'On Leave', 'Terminated']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => setState(() => status = v!),
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final data = {
                      "user_id": selectedUserId,
                      "shop": selectedShopId,
                      "salary": salaryController.text,
                      "join_date": joinDateController.text,
                      "status": status,
                    };

                    try {
                      if (widget.employee != null) {
                        await ApiService.updateEmployee(widget.employee!['id'], data);
                      } else {
                        await ApiService.addEmployee(data);
                      }
                      Navigator.pop(context, data); // <-- return the Map instead of true
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- ATTENDANCE FORM ----------------
class AttendanceFormScreen extends StatefulWidget {
  final Map<String, dynamic>? record;
  const AttendanceFormScreen({super.key, this.record});

  @override
  State<AttendanceFormScreen> createState() => _AttendanceFormScreenState();
}

class _AttendanceFormScreenState extends State<AttendanceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // State for fetching employees
  List<Map<String, dynamic>> _employees = [];
  bool _isLoadingEmployees = true;

  // Form Data Controllers/Variables
  int? _selectedEmployeeId;
  late TextEditingController dateController;
  late TextEditingController statusController;

  @override
  void initState() {
    super.initState();
    dateController = TextEditingController(
        text: widget.record?['date']?.toString().split('T')[0] ??
            DateFormat('yyyy-MM-dd').format(DateTime.now()));
    statusController = TextEditingController(text: widget.record?['status'] ?? 'Present');

    // Set initial employee ID if editing
    _selectedEmployeeId = widget.record?['employee_id'] ?? widget.record?['employee']?['id'];

    _fetchEmployees();
  }

  // 🚨 Fetch employee list to populate the dropdown
  Future<void> _fetchEmployees() async {
    try {
      // Assuming ApiService.getEmployees exists
      final employeeList = await ApiService.getEmployees();
      setState(() {
        _employees = employeeList;
        _isLoadingEmployees = false;

        // If not editing, and no employee is pre-selected, default to the first employee
        if (_selectedEmployeeId == null && _employees.isNotEmpty) {
          _selectedEmployeeId = _employees.first['id'];
        }
      });
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load employees: $e')),
        );
      }
      setState(() => _isLoadingEmployees = false);
    }
  }

  // 🚨 Function to open Date Picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(dateController.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // ---------------- SAVE ATTENDANCE RECORD (CRITICAL FIX) ----------------
  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate() || _selectedEmployeeId == null) return;

    final Map<String, dynamic> payload = {
      'employee_id': _selectedEmployeeId,
      'date': dateController.text,
      'status': statusController.text,
    };

    try {
      Map<String, dynamic> savedRecord;
      if (widget.record != null && widget.record!['id'] is int) {
        // 🚨 Use ApiService.updateAttendance
        savedRecord = await ApiService.updateAttendance(widget.record!['id'], payload);
      } else {
        // 🚨 Use ApiService.addAttendance
        savedRecord = await ApiService.addAttendance(payload);
      }

      if (mounted) {
        // Pop and return the saved/updated record to trigger a refresh on the parent screen
        Navigator.pop(context, savedRecord);
      }
    } catch (e) {
      if (mounted) {
        // Handle API errors (401, network, etc.)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save attendance record: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    dateController.dispose();
    statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.record != null ? "Edit Attendance" : "Add Attendance")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Employee Dropdown
              _isLoadingEmployees
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: "Employee"),
                value: _selectedEmployeeId,
                items: _employees.map<DropdownMenuItem<int>>((employee) {
                  return DropdownMenuItem<int>(
                    value: employee['id'],
                    // Display employee username
                    child: Text(employee['user']?['username'] ?? 'Employee ID: ${employee['id']}'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedEmployeeId = newValue;
                  });
                },
                validator: (value) => value == null ? "Please select an employee" : null,
              ),

              const SizedBox(height: 16),

              // Date Picker Text Field
              TextFormField(
                controller: dateController,
                readOnly: true, // Prevents manual editing
                onTap: () => _selectDate(context),
                decoration: const InputDecoration( // Changed to const
                  labelText: "Date",
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                validator: (v) => v!.isEmpty ? "Date is required" : null,
              ),

              const SizedBox(height: 16),

              // Status Dropdown
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Status"),
                value: statusController.text,
                items: const [
                  DropdownMenuItem(value: 'Present', child: Text('Present')),
                  DropdownMenuItem(value: 'Absent', child: Text('Absent')),
                  DropdownMenuItem(value: 'Leave', child: Text('Leave')),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    statusController.text = newValue!;
                  });
                },
                validator: (v) => v!.isEmpty ? "Status is required" : null,
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                // 🚨 FIX: Call the new _saveRecord function
                onPressed: _saveRecord,
                child: Text(widget.record != null ? "Update" : "Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// ---------------- PERFORMANCE FORM (FIXED) ----------------
class PerformanceFormScreen extends StatefulWidget {
  final Map<String, dynamic>? record;
  const PerformanceFormScreen({super.key, this.record});

  @override
  State<PerformanceFormScreen> createState() => _PerformanceFormScreenState();
}

class _PerformanceFormScreenState extends State<PerformanceFormScreen> {
  final _formKey = GlobalKey<FormState>();

  List<Map<String, dynamic>> _employees = [];
  bool _isLoadingEmployees = true;

  int? _selectedEmployeeId;
  late TextEditingController dateController;
  late TextEditingController kpiController;
  late TextEditingController reviewController;

  // 🎯 FIX 1: New state variable for the Performance Rating
  String? _selectedRating;

  // 🎯 FIX 2: List of ratings matching payroll logic
  final List<String> _ratings = ['Best', 'Very Good', 'Good', 'Average', 'Poor'];

  @override
  void initState() {
    super.initState();

    dateController = TextEditingController(
        text: widget.record?['date']?.toString().split('T')[0] ??
            DateFormat('yyyy-MM-dd').format(DateTime.now()));

    kpiController = TextEditingController(text: widget.record?['kpi']?.toString() ?? '');
    reviewController = TextEditingController(text: widget.record?['review'] ?? '');

    _selectedEmployeeId = widget.record?['employee_id'] ?? widget.record?['employee']?['id'];

    // 🎯 FIX 3: Initialize selected rating from existing record
    _selectedRating = widget.record?['rating'];

    _fetchEmployees();
  }

  Future<void> _fetchEmployees() async {
    try {
      final employeeList = await ApiService.getEmployees();
      setState(() {
        _employees = employeeList;
        _isLoadingEmployees = false;

        if (_selectedEmployeeId == null && _employees.isNotEmpty) {
          _selectedEmployeeId = _employees.first['id'];
        }
      });
    } catch (e) {
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load employees: $e')),
        );
      }
      setState(() => _isLoadingEmployees = false);
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(dateController.text) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  @override
  void dispose() {
    dateController.dispose();
    kpiController.dispose();
    reviewController.dispose();
    super.dispose();
  }

  // --- Widget Build ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.record != null ? "Edit Performance" : "Add Performance")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Employee Dropdown
              _isLoadingEmployees
                  ? const Center(child: CircularProgressIndicator())
                  : DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: "Employee"),
                value: _selectedEmployeeId,
                hint: const Text("Select Employee"),
                items: _employees.map<DropdownMenuItem<int>>((employee) {
                  return DropdownMenuItem<int>(
                    value: employee['id'],
                    child: Text(employee['user']?['username'] ?? 'Employee ID: ${employee['id']}'),
                  );
                }).toList(),
                onChanged: (int? newValue) {
                  setState(() {
                    _selectedEmployeeId = newValue;
                  });
                },
                validator: (value) => value == null ? "Please select an employee" : null,
              ),

              const SizedBox(height: 16),

              // 2. KPI Text Field
              TextFormField(
                controller: kpiController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "KPI (Key Performance Indicator)"),
                validator: (v) => v!.isEmpty ? "KPI is required" : null,
              ),

              const SizedBox(height: 16),

              // 3. Date Picker Text Field
              TextFormField(
                controller: dateController,
                readOnly: true,
                onTap: () => _selectDate(context),
                decoration: const InputDecoration(
                  labelText: "Date of Review",
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                validator: (v) => v!.isEmpty ? "Date is required" : null,
              ),

              const SizedBox(height: 16),

              // 4. Review Text Area
              TextFormField(
                controller: reviewController,
                decoration: const InputDecoration(labelText: "Review Details"),
                maxLines: 4,
                validator: (v) => v!.isEmpty ? "Review details are required" : null,
              ),

              const SizedBox(height: 16),

              // 5. Performance Rating Dropdown 🎯 NEW WIDGET
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "Final Performance Rating"),
                value: _selectedRating,
                hint: const Text("Select Rating"),
                items: _ratings.map<DropdownMenuItem<String>>((rating) {
                  return DropdownMenuItem<String>(
                    value: rating,
                    child: Text(rating),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedRating = newValue;
                  });
                },
                validator: (value) => value == null ? "Please select a rating" : null,
              ),

              const SizedBox(height: 30),

              ElevatedButton(
                onPressed: () {
                  // Ensure both employee and rating are selected
                  if (_formKey.currentState!.validate() && _selectedEmployeeId != null && _selectedRating != null) {
                    final Map<String, dynamic> payload = {
                      'id': widget.record?['id'],
                      'employee_id': _selectedEmployeeId,
                      'kpi': int.tryParse(kpiController.text) ?? 0,
                      'review': reviewController.text,
                      'date': dateController.text,

                      // 🎯 FIX 4: Include the selected rating in the payload
                      'rating': _selectedRating,

                      // Include employee info for UI refresh/consistency
                      'employeeName': _employees.firstWhere(
                              (e) => e['id'] == _selectedEmployeeId,
                          orElse: () => <String, dynamic>{}
                      )['user']?['username']
                    };

                    Navigator.pop(context, payload);
                  }
                },
                child: Text(
                    widget.record != null ? "Update" : "Save"
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
//============ Payroll Form ============
// Ensure you have the necessary imports (e.g., flutter/material.dart, api_service.dart)

// Helper function (outside the State class)
double _calculateBonusAmount({required double salary, required String rating}) {
  final cleanRating = rating.toLowerCase().trim();
  double percentage;

  if (cleanRating == 'best') {
    percentage = 0.10; // 10% of salary
  } else if (cleanRating.contains('very good') || cleanRating == 'verygood') {
    percentage = 0.07; // 7% of salary
  } else if (cleanRating == 'good') {
    percentage = 0.05; // 5% of salary
  } else {
    percentage = 0.00; // Handles 'N/A' or other values
  }

  final bonus = salary * percentage;
  return double.parse(bonus.toStringAsFixed(2));
}

// ---------------- PAYROLL FORM SCREEN CLASS ----------------

class PayrollFormScreen extends StatefulWidget {
  final Map<String, dynamic>? payroll;
  const PayrollFormScreen({super.key, this.payroll});

  @override
  State<PayrollFormScreen> createState() => _PayrollFormScreenState();
}

class _PayrollFormScreenState extends State<PayrollFormScreen> {
  final _formKey = GlobalKey<FormState>();

  int? selectedEmployeeId;
  String? selectedMonth;
  DateTime? selectedDate;

  String _employeeRating = '...';

  // Stores the total days the employee was expected to work
  int _totalExpectedWorkingDays = 0;

  // Controllers for editable fields
  late TextEditingController basicSalaryController;
  late TextEditingController bonusController;
  late TextEditingController deductionsController;
  late TextEditingController overtimeController;

  // Controllers for read-only auto-fetched/calculated values (for display only)
  late TextEditingController performanceBonusController; // Holds auto-calculated bonus amount (before manual override)
  late TextEditingController absentDaysController;       // Holds auto-fetched absent days count

  // Controllers for the NEW manual money input fields
  late TextEditingController manualPerformanceBonusController;
  late TextEditingController manualAbsentDeductionController;

  List<Map<String, dynamic>> employees = [];
  final List<String> months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Helper to find an employee's data by ID
  Map<String, dynamic>? _findEmployee(int id) {
    if (employees.isEmpty) return null;

    final foundEmployee = employees.firstWhere(
          (emp) => emp['id'] == id,
      orElse: () => <String, dynamic>{},
    );

    return foundEmployee.isNotEmpty ? foundEmployee : null;
  }

// ---------------- FETCH PERFORMANCE RATING ----------------
  Future<void> _fetchEmployeeRating(int employeeId) async {
    try {
      // Replace ApiService.fetchEmployeePerformanceRating with your actual call
      final rating = await ApiService.fetchEmployeePerformanceRating(employeeId);

      if (mounted) {
        setState(() {
          _employeeRating = rating;
          _calculatePerformanceBonus(); // Trigger bonus calculation
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _employeeRating = 'N/A');
        _calculatePerformanceBonus(); // Calculate 0 bonus based on 'N/A'
      }
    }
  }

// ---------------- CALCULATE PERFORMANCE BONUS (Auto) ----------------
  void _calculatePerformanceBonus() {
    double currentSalary = double.tryParse(basicSalaryController.text) ?? 0.0;

    final calculatedBonus = _calculateBonusAmount(
        salary: currentSalary,
        rating: _employeeRating
    );

    // Update the READ-ONLY side of the split field
    if (performanceBonusController.text != calculatedBonus.toStringAsFixed(2)) {
      performanceBonusController.text = calculatedBonus.toStringAsFixed(2);
      setState(() {});
    }
  }

  Future<void> _fetchAbsentDays(int employeeId, String month) async {
    try {
      final year = selectedDate?.year ?? DateTime.now().year;

      // Replace ApiService.fetchAbsentAndWorkingDays with your actual call
      final absentData = await ApiService.fetchAbsentAndWorkingDays(
          employeeId, month, year: year);

      if (mounted) {
        setState(() {
          // Update the READ-ONLY side of the split field
          absentDaysController.text = absentData.absentDays.toString();
          // Update the Total Expected Working Days state
          _totalExpectedWorkingDays = absentData.totalWorkingDays;
        });
      }
    } catch (e) {
      if (mounted) {
        absentDaysController.text = '0';
        _totalExpectedWorkingDays = 0;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Failed to fetch absent data."))
        );
        setState(() {});
      }
    }
  }

  // ------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    // Standard Controllers
    basicSalaryController = TextEditingController(text: widget.payroll?['salary']?.toString() ?? '0');
    bonusController = TextEditingController(text: widget.payroll?['bonus']?.toString() ?? '0');
    deductionsController = TextEditingController(text: widget.payroll?['deductions']?.toString() ?? '0');
    overtimeController = TextEditingController(text: widget.payroll?['overtime']?.toString() ?? '0');

    // Read-Only Controllers (for display of auto-calculated/fetched values)
    // We can use a default/placeholder value here, as the actual calculation happens later.
    performanceBonusController = TextEditingController(text: '0.00');
    absentDaysController = TextEditingController(text: widget.payroll?['absent_days']?.toString() ?? '0');

    // NEW Manual Money Input Controllers
    manualPerformanceBonusController =
        TextEditingController(text: widget.payroll?['performance_bonus']?.toString() ?? '0');
    // Assuming 'absent_deduction_amount' is the field for the manual deduction amount.
    // If your API uses 'absent_days' for the money, you must adjust the calculation.
    manualAbsentDeductionController =
        TextEditingController(text: widget.payroll?['absent_deduction_amount']?.toString() ?? '0');


    selectedEmployeeId = widget.payroll?['employee_id'] as int?;

    if (widget.payroll != null) {
      _employeeRating = 'Checking...';
    }

    selectedMonth = widget.payroll?['month'] as String?
        ?? months[DateTime.now().month - 1];

    selectedDate = widget.payroll?['date'] != null
        ? DateTime.tryParse(widget.payroll!['date'])
        : DateTime.now();

    fetchEmployees();
  }

  @override
  void dispose() {
    basicSalaryController.dispose();
    bonusController.dispose();
    deductionsController.dispose();
    overtimeController.dispose();
    performanceBonusController.dispose();
    absentDaysController.dispose();
    manualPerformanceBonusController.dispose();
    manualAbsentDeductionController.dispose();
    super.dispose();
  }


  Future<void> fetchEmployees() async {
    try {
      // Replace ApiService.getEmployees with your actual call
      final result = await ApiService.getEmployees();

      if (result is List) {
        employees = result
            .whereType<Map<String, dynamic>>()
            .toList();
      }

      bool shouldAutoFetch = false;

      if (widget.payroll == null && selectedEmployeeId == null && employees.isNotEmpty) {
        selectedEmployeeId = employees.first['id'] as int?;
        shouldAutoFetch = true;

        final employee = _findEmployee(selectedEmployeeId!);
        if (employee != null && employee.containsKey('salary')) {
          basicSalaryController.text = employee['salary']?.toString() ?? '0';
        }
      }
      else if (selectedEmployeeId != null && selectedMonth != null) {
        shouldAutoFetch = true;
      }

      setState(() {
        if (shouldAutoFetch && selectedEmployeeId != null && selectedMonth != null) {
          _fetchAbsentDays(selectedEmployeeId!, selectedMonth!);
          _fetchEmployeeRating(selectedEmployeeId!);
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Failed to load employees.")));
      }
    }
  }


  Future<void> savePayroll() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      "employee_id": selectedEmployeeId,
      "month": selectedMonth,
      "salary": double.tryParse(basicSalaryController.text) ?? 0.0,
      "bonus": double.tryParse(bonusController.text) ?? 0.0,
      "deductions": double.tryParse(deductionsController.text) ?? 0.0,
      "overtime": double.tryParse(overtimeController.text) ?? 0.0,

      // *** SAVE MANUAL MONEY INPUTS ***
      "performance_bonus": double.tryParse(manualPerformanceBonusController.text) ?? 0.0,
      "absent_deduction_amount": double.tryParse(manualAbsentDeductionController.text) ?? 0.0,

      // Save the absent days count as well, as it's separate from the deduction amount
      "absent_days": int.tryParse(absentDaysController.text) ?? 0,

      "date": selectedDate?.toIso8601String().split("T").first,
    };

    try {
      Map<String, dynamic> savedPayroll;
      // Replace ApiService.updatePayroll/addPayroll with your actual calls
      if (widget.payroll != null && widget.payroll!['id'] is int) {
        savedPayroll = await ApiService.updatePayroll(widget.payroll!['id'], data);
      } else {
        savedPayroll = await ApiService.addPayroll(data);
      }
      if (mounted) Navigator.pop(context, savedPayroll);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save payroll: $e')));
      }
    }
  }

  /// Calculates the Net Pay, incorporating manually input absent deduction and bonus.
  double calculateNetPay() {
    final basic = double.tryParse(basicSalaryController.text) ?? 0;
    final bonus = double.tryParse(bonusController.text) ?? 0;
    final overtime = double.tryParse(overtimeController.text) ?? 0;

    // *** USE MANUAL INPUT CONTROLLERS FOR MONETARY VALUES ***
    final perfBonus = double.tryParse(manualPerformanceBonusController.text) ?? 0;
    final absentDeduction = double.tryParse(manualAbsentDeductionController.text) ?? 0;

    final deductions = double.tryParse(deductionsController.text) ?? 0;

    return basic + bonus + overtime + perfBonus - deductions - absentDeduction;
  }

  Widget _buildNumberField(String label, TextEditingController controller,
      {bool isInt = false, bool readOnly = false}) {
    return Column(
      children: [
        TextFormField(
          controller: controller,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.numberWithOptions(decimal: !isInt),
          readOnly: readOnly,
          validator: (v) => v == null || v.isEmpty || double.tryParse(v!) == null
              ? "Enter a valid number"
              : null,
          onChanged: (_) {
            setState(() {});
            // Recalculate auto bonus if basic salary changes (for the read-only display)
            if (controller == basicSalaryController) {
              _calculatePerformanceBonus();
            }
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final netPay = calculateNetPay();
    final theme = Theme.of(context);

    // Set a maximum desirable width for the form content
    const double maxFormWidth = 600.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.payroll != null ? "Edit Payroll" : "Add Payroll")),
      body: Center( // Center the content horizontally
        child: ConstrainedBox( // Constrain the maximum width
          constraints: const BoxConstraints(maxWidth: maxFormWidth),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // --- Section: Employee & Pay Period ---
                  Text(
                    "Employee & Pay Period Details",
                    style: theme.textTheme.titleMedium,
                  ),
                  const Divider(height: 24),

                  // Employee Dropdown
                  DropdownButtonFormField<int>(
                    value: selectedEmployeeId,
                    decoration: InputDecoration(
                      labelText: "Employee",
                      helperText: "Performance Rating: $_employeeRating",
                      helperStyle: TextStyle(color: theme.colorScheme.primary),
                    ),
                    items: employees
                        .map((emp) => DropdownMenuItem<int>(
                      value: emp['id'],
                      child: Text(emp['user']?['username'] ?? 'No Name'),
                    ))
                        .toList(),
                    onChanged: (v) {
                      selectedEmployeeId = v;

                      if (v != null) {
                        final employee = _findEmployee(v);
                        basicSalaryController.text = employee?['salary']?.toString() ?? '0';

                        if (selectedMonth != null) {
                          _fetchAbsentDays(v, selectedMonth!);
                        }
                        _fetchEmployeeRating(v);
                      } else {
                        basicSalaryController.text = '0';
                        absentDaysController.text = '0';
                        _employeeRating = '...';
                        performanceBonusController.text = '0';
                      }
                      setState(() {});
                    },
                    validator: (v) => v == null ? "Select an employee" : null,
                  ),
                  const SizedBox(height: 16),

                  // Month Dropdown
                  DropdownButtonFormField<String>(
                    value: selectedMonth,
                    decoration: const InputDecoration(labelText: "Month of Payroll"),
                    items: months.map((m) => DropdownMenuItem<String>(
                      value: m,
                      child: Text(m),
                    )).toList(),
                    onChanged: (v) {
                      selectedMonth = v;

                      if (selectedEmployeeId != null && v != null) {
                        _fetchAbsentDays(selectedEmployeeId!, v);
                      } else {
                        absentDaysController.text = '0';
                      }
                      setState(() {});
                    },
                    validator: (v) => v == null ? "Select a month" : null,
                  ),
                  const SizedBox(height: 8),

                  // Date Picker
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        "Payment Date: ${selectedDate != null ? selectedDate!.toLocal().toString().split(' ')[0] : 'Not Set'}"),
                    trailing: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => selectedDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Text("Pick Date"),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(height: 1),

                  // --- Section: Earnings ---
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text("Earnings", style: theme.textTheme.titleMedium),
                  ),

                  _buildNumberField("Basic Salary", basicSalaryController),
                  _buildNumberField("Bonus (Other)", bonusController),
                  _buildNumberField("Overtime", overtimeController),
                  const SizedBox(height: 8),

                  // --- Section: Deductions & Adjustments ---
                  Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 8),
                    child: Text("Deductions & Adjustments", style: theme.textTheme.titleMedium),
                  ),

                  // Deductions (Editable)
                  _buildNumberField("Deductions", deductionsController),
                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 🎯 SPLIT FIELD: Performance Bonus (Auto Value vs. Manual Price)
                  // ----------------------------------------------------
                  Text("Performance Bonus", style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Read-Only (Rating/Auto-Calculated Amount)
                      Expanded(
                        child: TextFormField(
                          // We now use a dummy controller or a simplified one, as the value is now driven by _employeeRating
                          controller: TextEditingController(text: _employeeRating),
                          decoration: InputDecoration(
                            labelText: "Performance Status",
                            suffixIcon: const Icon(Icons.star, color: Colors.amber),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: const OutlineInputBorder(),
                            // Removed the helperText as the label/value now clearly shows the status
                          ),
                          readOnly: true, // READ ONLY
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: Manual Input (Monetary Value)
                      Expanded(
                        child: TextFormField(
                          controller: manualPerformanceBonusController,
                          decoration: const InputDecoration(
                            labelText: "Final Bonus Amount",
                            prefixText: "\$",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}), // Recalculate Net Pay
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ----------------------------------------------------
                  // 🎯 SPLIT FIELD: Absent Days (Auto Count vs. Manual Price)
                  // ----------------------------------------------------
                  Text("Absentee Deduction", style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: Read-Only (Absent Days Count)
                      Expanded(
                        child: TextFormField(
                          controller: absentDaysController,
                          decoration: InputDecoration(
                            labelText: "Absent Days Count",
                            suffixText: " days",
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: const OutlineInputBorder(),
                          ),
                          readOnly: true,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Right: Manual Input (Deduction Amount)
                      Expanded(
                        child: TextFormField(
                          controller: manualAbsentDeductionController,
                          decoration: const InputDecoration(
                            labelText: "Final Deduction Amount",
                            prefixText: "\$",
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}), // Recalculate Net Pay
                        ),
                      ),
                    ],
                  ),

                  // Daily Rate Base Info
                  if (_totalExpectedWorkingDays > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(
                        "Daily Rate Base: $_totalExpectedWorkingDays expected working days.",
                        style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                      ),
                    ),

                  const SizedBox(height: 32),

                  // --- Net Pay Summary ---
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.primary.withOpacity(0.05),
                    ),
                    child: Center(
                      child: Text("NET PAY: \$${netPay.toStringAsFixed(2)}",
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: theme.colorScheme.primary)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // --- Save Button ---
                  ElevatedButton(
                    onPressed: savePayroll,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      elevation: 4,
                    ),
                    child: Text(widget.payroll != null ? "Update Payroll" : "Save Payroll"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
/// ---------------- JOB FORM ----------------
class JobFormScreen extends StatefulWidget {
  final Map<String, dynamic>? job;
  const JobFormScreen({super.key, this.job});

  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController titleController;
  late TextEditingController deptController;
  late TextEditingController locationController;
  late TextEditingController openingsController;

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.job?['title'] ?? '');
    deptController = TextEditingController(text: widget.job?['department'] ?? '');
    locationController = TextEditingController(text: widget.job?['location'] ?? '');
    openingsController = TextEditingController(text: widget.job?['openings']?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.job != null ? "Edit Job" : "Add Job")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: titleController, decoration: const InputDecoration(labelText: "Title"), validator: (v) => v!.isEmpty ? "Required" : null),
              TextFormField(controller: deptController, decoration: const InputDecoration(labelText: "Department"), validator: (v) => v!.isEmpty ? "Required" : null),
              TextFormField(controller: locationController, decoration: const InputDecoration(labelText: "Location"), validator: (v) => v!.isEmpty ? "Required" : null),
              TextFormField(controller: openingsController, decoration: const InputDecoration(labelText: "Openings"), keyboardType: TextInputType.number, validator: (v) => v!.isEmpty ? "Required" : null),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.pop(context, {
                      'title': titleController.text,
                      'department': deptController.text,
                      'location': locationController.text,
                      'openings': int.tryParse(openingsController.text) ?? 0,
                    });
                  }
                },
                child: const Text("Save"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
