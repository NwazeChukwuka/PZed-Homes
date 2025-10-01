// Location: lib/presentation/screens/report_issue_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({super.key});
  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String? _selectedAssetId; // FIX: We will link to an asset, not a free-text location.
  String? _selectedPriority = 'Medium';
  bool _isLoading = false;

  final List<String> _priorities = ['Low', 'Medium', 'High', 'Critical'];

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<MockAuthService>(context, listen: false);
      
      await _supabase.from('maintenance_work_orders').insert({
        'reported_by_id': authService.currentUser!.id,
        'asset_id': _selectedAssetId, // FIX: Use the correct asset_id column
        'issue_description': _descriptionController.text.trim(),
        'location': _locationController.text.trim(), // This column now exists
        'priority': _selectedPriority, // This column now exists
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Issue reported successfully!'), backgroundColor: Colors.green));
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
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _supabase.from('assets').select('id, name'),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final assets = snapshot.data!;
                return DropdownButtonFormField<String>(
                  value: _selectedAssetId,
                  decoration: const InputDecoration(labelText: 'Asset *', border: OutlineInputBorder()),
                  items: assets.map((a) => DropdownMenuItem<String>(value: a['id'], child: Text(a['name']))).toList(),
                  onChanged: (val) => setState(() => _selectedAssetId = val),
                  validator: (val) => val == null ? 'Please select an asset' : null,
                );
              },
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