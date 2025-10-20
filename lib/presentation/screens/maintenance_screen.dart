// Location: lib/presentation/screens/maintenance_screen.dart
import 'package:flutter/material.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _loading = false;
  final List<Map<String, dynamic>> _workOrders = [];

  @override
  void initState() {
    super.initState();
    _loadWorkOrders();
  }

  Future<void> _loadWorkOrders() async {
    setState(() => _loading = true);
    await Future.delayed(const Duration(milliseconds: 250));
    _workOrders
      ..clear()
      ..addAll([
        {
          'id': 1,
          'asset_name': 'Elevator A',
          'issue_description': 'Intermittent stopping between floors',
          'location': 'Main Lobby',
          'reported_by_name': 'Front Desk',
          'status': 'Pending',
        },
        {
          'id': 2,
          'asset_name': 'AC Unit 302',
          'issue_description': 'Not cooling sufficiently',
          'location': 'Room 302',
          'reported_by_name': 'Housekeeping',
          'status': 'In Progress',
        },
      ]);
    setState(() => _loading = false);
  }

  Future<void> _updateStatus(int id, String status) async {
    final idx = _workOrders.indexWhere((w) => w['id'] == id);
    if (idx != -1) {
      setState(() => _workOrders[idx]['status'] = status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('[Mock] Status updated to $status'), backgroundColor: Colors.green),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              final workOrders = _workOrders;
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
                            _updateStatus(workOrder['id'] as int, newStatus);
                          }
                        },
                      ),
                    ),
                  );
                },
              );
            }),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadWorkOrders,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
