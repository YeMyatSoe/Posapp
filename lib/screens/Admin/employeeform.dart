import 'package:flutter/material.dart';

class EmployeeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  final Function(Map<String, dynamic>) onSave;

  const EmployeeFormScreen({
    super.key,
    this.employee,
    required this.onSave,
  });

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  late TextEditingController nameController;
  late TextEditingController roleController;
  late TextEditingController emailController;
  late TextEditingController phoneController;
  late TextEditingController addressController;

  late TextEditingController salaryController;

  DateTime? joinDate;
  bool isActive = true;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.employee?['name'] ?? '');
    roleController = TextEditingController(text: widget.employee?['role'] ?? '');
    emailController = TextEditingController(text: widget.employee?['email'] ?? '');
    phoneController = TextEditingController(text: widget.employee?['phone'] ?? '');
    addressController = TextEditingController(text: widget.employee?['address'] ?? '');
    salaryController = TextEditingController(text: widget.employee?['salary']?.toString() ?? '');
    joinDate = widget.employee?['joinDate'];
    isActive = widget.employee?['isActive'] ?? true;
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.employee != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? "Edit Employee" : "Add Employee"),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Personal Info
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Personal Information",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(controller: nameController, decoration: _inputDecoration("Full Name")),
                    const SizedBox(height: 12),
                    TextField(controller: phoneController, decoration: _inputDecoration("Phone Number")),
                    const SizedBox(height: 12),
                    TextField(controller: emailController, decoration: _inputDecoration("Email")),
                    const SizedBox(height: 12),
                    TextField(controller: addressController, decoration: _inputDecoration("Address")),
                  ],
                ),
              ),
            ),

            // Job Info
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Job Information",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(controller: roleController, decoration: _inputDecoration("Role / Position")),
                    const SizedBox(height: 12),
                    TextField(
                      controller: salaryController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration("Salary"),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            joinDate == null
                                ? "Join Date: Not Selected"
                                : "Join Date: ${joinDate!.toLocal().toString().split(' ')[0]}",
                          ),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text("Pick Date"),
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: joinDate ?? DateTime.now(),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => joinDate = picked);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      value: isActive,
                      title: const Text("Employee Active"),
                      subtitle: Text(isActive ? "Currently working" : "On leave / Left job"),
                      onChanged: (val) {
                        setState(() => isActive = val);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: Text(isEdit ? "Update Employee" : "Save Employee"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  final data = {
                    "id": widget.employee?['id'],
                    "name": nameController.text,
                    "role": roleController.text,
                    "email": emailController.text,
                    "phone": phoneController.text,
                    "address": addressController.text,
                    "salary": double.tryParse(salaryController.text) ?? 0.0,
                    "joinDate": joinDate ?? DateTime.now(),
                    "isActive": isActive,
                  };
                  widget.onSave(data);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
