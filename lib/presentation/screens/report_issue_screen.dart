// Location: lib/presentation/screens/report_issue_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});
  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedAssetId; // FIX: We will link to an asset, not a free-text location.
  String? _selectedPriority = 'Medium';
  bool _isLoading = false;
  final List<Map<String, dynamic>> _mockReports = [];

  final List<String> _priorities = ['Low', 'Medium', 'High', 'Critical'];

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<MockAuthService>(context, listen: false);
      final report = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'reported_by_id': authService.currentUser?.id,
        'asset_id': _selectedAssetId,
        'issue_description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'priority': _selectedPriority,
        'created_at': DateTime.now().toIso8601String(),
      };
      await Future.delayed(const Duration(milliseconds: 200));
      _mockReports.insert(0, report);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('[Mock] Issue reported successfully!'), backgroundColor: Colors.green));
        context.pop(true); // Return true to signal a refresh
      }
    } catch (e) {
      // ... error handling ...
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // INFO: The UI from the refactor is good. We are keeping it but connecting it to the correct logic.
    return Scaffold(
      appBar: AppBar(title: const Text('Report Maintenance Issue')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Dropdown to select an asset from the 'assets' table
            DropdownButtonFormField<String>(
              value: _selectedAssetId,
              decoration: const InputDecoration(labelText: 'Asset *', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem<String>(value: 'asset_elevator_a', child: Text('Elevator A')),
                DropdownMenuItem<String>(value: 'asset_ac_302', child: Text('AC Unit 302')),
                DropdownMenuItem<String>(value: 'asset_generator', child: Text('Generator')), 
                DropdownMenuItem<String>(value: 'asset_kitchen_oven', child: Text('Kitchen Oven')), 
              ],
              onChanged: (val) => setState(() => _selectedAssetId = val),
              validator: (val) => val == null ? 'Please select an asset' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Issue Description *', border: OutlineInputBorder()),
              maxLines: 4,
              validator: (val) => val!.isEmpty ? 'Please describe the issue' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Specific Location (e.g., hallway)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedPriority,
              decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
              items: _priorities.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
              onChanged: (val) => setState(() => _selectedPriority = val),
            ),
            const SizedBox(height: 24),
            _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(onPressed: _submitReport, child: const Text('Submit Report')),
          ],
        ),
      ),
    );
  }
}