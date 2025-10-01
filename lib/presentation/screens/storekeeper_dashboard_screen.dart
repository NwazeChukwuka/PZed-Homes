// Location: lib/presentation/screens/storekeeper_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/presentation/screens/confirm_purchases_screen.dart'; // We will reuse this screen

class StorekeeperDashboardScreen extends StatefulWidget {
  const StorekeeperDashboardScreen({super.key});
  @override
  State<StorekeeperDashboardScreen> createState() => _StorekeeperDashboardScreenState();
}

class _StorekeeperDashboardScreenState extends State<StorekeeperDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storekeeper Dashboard'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Confirm Purchases'),
            Tab(text: 'Direct Stock Entry'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ConfirmPurchasesScreen(), // The screen from our previous step
          DirectStockEntryForm(),   // The new form we're creating now
        ],
      ),
    );
  }
}

// --- The New Direct Stock Entry Form Widget ---
class DirectStockEntryForm extends StatefulWidget {
  const DirectStockEntryForm({super.key});
  @override
  State<DirectStockEntryForm> createState() => _DirectStockEntryFormState();
}

class _DirectStockEntryFormState extends State<DirectStockEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedItemId;
  String? _selectedLocationId;
  bool _isLoading = false;

  Future<void> _recordDirectEntry() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Directly insert a 'Purchase' transaction into the ledger
      await _supabase.from('stock_transactions').insert({
        'stock_item_id': _selectedItemId,
        'location_id': _selectedLocationId,
        'staff_profile_id': authService.currentUser!.id,
        'transaction_type': 'Purchase', // We use 'Purchase' as it represents stock coming in
        'quantity': int.parse(_quantityController.text),
        'notes': _notesController.text.isNotEmpty ? _notesController.text : 'Direct stock entry by storekeeper',
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock recorded successfully!'), backgroundColor: Colors.green));
      _formKey.currentState?.reset();
      _quantityController.clear();
      _notesController.clear();
      setState(() {
        _selectedItemId = null;
        _selectedLocationId = null;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Use this form to record stock that did not come from a purchaser (e.g., direct delivery from management).', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          // Dropdown to select a stock item
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _supabase.from('stock_items').select('id, name').order('name'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Stock Item', border: OutlineInputBorder()),
                items: snapshot.data!.map((item) => DropdownMenuItem<String>(value: item['id']?.toString(), child: Text(item['name']?.toString() ?? ''))).toList(),
                onChanged: (val) => setState(() => _selectedItemId = val),
                validator: (val) => val == null ? 'Please select an item' : null,
              );
            },
          ),
          const SizedBox(height: 16),
          // Dropdown to select the location where the stock is being added
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _supabase.from('locations').select('id, name').order('name'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Receiving Location', border: OutlineInputBorder()),
                items: snapshot.data!.map((loc) => DropdownMenuItem<String>(value: loc['id']?.toString(), child: Text(loc['name']?.toString() ?? ''))).toList(),
                onChanged: (val) => setState(() => _selectedLocationId = val),
                validator: (val) => val == null ? 'Please select a location' : null,
              );
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity Received', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (val) => (val == null || val.isEmpty || int.tryParse(val) == null || int.parse(val) <= 0) ? 'Enter a valid quantity' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (Optional)', hintText: 'e.g., Delivered by manager', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _recordDirectEntry,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Add to Stock Ledger'),
                ),
        ],
      ),
    );
  }
}