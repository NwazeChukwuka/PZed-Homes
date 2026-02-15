import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

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
  final _dataService = DataService();

  final List<String> _priorities = ['Low', 'Medium', 'High', 'Critical'];

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      
      if (currentUser == null) {
        throw Exception('User must be logged in to report issues');
      }

      // Save to database via DataService
      await _dataService.createMaintenanceWorkOrder({
        'asset_id': _selectedAssetId,
        'reported_by_id': currentUser.id,
        'issue_description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(),
        'priority': _selectedPriority ?? 'Medium',
        'status': 'Open',
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Issue reported successfully!');
        context.pop(true); // Return true to signal a refresh
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to submit issue report. Please try again.',
          onRetry: _submitReport,
        );
      }
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
              initialValue: _selectedAssetId,
              decoration: const InputDecoration(labelText: 'Asset *', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem<String>(value: 'asset_small_generator', child: Text('Small Generator')),
                DropdownMenuItem<String>(value: 'asset_ac_302', child: Text('AC Unit 302')),
                DropdownMenuItem<String>(value: 'asset_backup_generator', child: Text('Backup Generator')), 
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
              initialValue: _selectedPriority,
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