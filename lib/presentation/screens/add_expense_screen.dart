import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedCategory;
  String? _selectedDepartment;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  List<String> _categories = [];
  List<String> _departments = [];
  final DataService _dataService = DataService();

  @override
  void initState() {
    super.initState();
    _fetchCategoriesAndDepartments();
  }

  Future<void> _fetchCategoriesAndDepartments() async {
    // Mock lists for presentation
    setState(() {
      _categories = [
        'utilities',
        'payroll',
        'maintenance',
        'supplies',
        'others',
      ];
      _departments = [
        'front_desk',
        'vip_bar',
        'outside_bar',
        'kitchen',
        'store',
        'all',
      ];
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final amount = double.tryParse(_amountController.text);
      if (amount == null) {
        throw Exception('Invalid amount format');
      }

      // Persist to mock storage via DataService
      await _dataService.addExpense({
        'id': 'exp_${DateTime.now().millisecondsSinceEpoch}',
        'description': _descriptionController.text,
        'amount': (amount * 100).round(),
        'category': _selectedCategory,
        'department': _selectedDepartment,
        'date': _selectedDate.toIso8601String().split('T').first,
        'payment_method': 'cash',
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Expense saved successfully!');
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save expense. Please try again.',
          onRetry: _saveExpense,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Record New Expense')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val!.isEmpty ? 'Please enter a description' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (₦)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (val) {
                  if (val!.isEmpty) return 'Please enter an amount';
                  if (double.tryParse(val) == null) return 'Please enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: _categories.map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c),
                )).toList(),
                onChanged: (val) => setState(() => _selectedCategory = val),
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null ? 'Please select a category' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment,
                items: _departments.map((d) => DropdownMenuItem(
                  value: d,
                  child: Text(d),
                )).toList(),
                onChanged: (val) => setState(() => _selectedDepartment = val),
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null ? 'Please select a department' : null,
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Date'),
                subtitle: Text(DateFormat.yMMMd().format(_selectedDate)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () => _selectDate(context),
              ),
              const SizedBox(height: 24),
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveExpense,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Save Expense'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}