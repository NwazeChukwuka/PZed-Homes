// Location: lib/presentation/screens/maintenance_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final supabase = Supabase.instance.client;

  Future<void> _updateStatus(int id, String status) async {
    try {
      await supabase.from('work_orders').update({'status': status}).eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Status updated to $status'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
        backgroundColor: Colors.orange[700],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: supabase
            .from('work_orders')
            .stream(primaryKey: ['id'])
            .order('created_at')
            .map((rows) => rows.map((row) {
                  // include joined fields for assets and profiles
                  return {
                    ...row,
                    'asset_name': row['assets']?['name'],
                    'reported_by_name': row['profiles']?['full_name'],
                  };
                }).toList()),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final workOrders = snapshot.data ?? [];
          if (workOrders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.build, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No work orders found',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Work orders will appear here when reported',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: workOrders.length,
            itemBuilder: (context, index) {
              final workOrder = workOrders[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(
                    workOrder['asset_name'] ?? 'Unknown Asset',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(workOrder['issue_description'] ?? ''),
                      if (workOrder['location'] != null)
                        Text('Location: ${workOrder['location']}'),
                      if (workOrder['reported_by_name'] != null)
                        Text('Reported by: ${workOrder['reported_by_name']}'),
                    ],
                  ),
                  trailing: DropdownButton<String>(
                    value: workOrder['status'],
                    items: ['Pending', 'In Progress', 'Completed']
                        .map((status) =>
                            DropdownMenuItem(value: status, child: Text(status)))
                        .toList(),
                    onChanged: (newStatus) {
                      if (newStatus != null) {
                        _updateStatus(workOrder['id'], newStatus);
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
