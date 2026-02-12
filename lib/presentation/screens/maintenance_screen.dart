import 'package:flutter/material.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _loading = false;
  final List<Map<String, dynamic>> _workOrders = [];
  final _dataService = DataService();

  @override
  void initState() {
    super.initState();
    _loadWorkOrders();
  }

  Future<void> _loadWorkOrders() async {
    setState(() => _loading = true);
    try {
      final orders = await _dataService.getMaintenanceWorkOrders();
      setState(() {
        _workOrders.clear();
        _workOrders.addAll(orders.map((order) {
          final asset = order['assets'] as Map<String, dynamic>?;
          final reportedBy = order['reported_by'] as Map<String, dynamic>?;
          return {
            'id': order['id'],
            'asset_name': asset?['name'] ?? 'Unknown Asset',
            'issue_description': order['issue_description'] ?? '',
            'location': order['location'] ?? '',
            'reported_by_name': reportedBy?['full_name'] ?? 'Unknown',
            'status': order['status'] ?? 'Open',
            'priority': order['priority'] ?? 'Medium',
          };
        }).toList());
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load work orders. Please check your connection and try again.',
          onRetry: _loadWorkOrders,
        );
      }
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await _dataService.updateMaintenanceWorkOrderStatus(id, status);
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Status updated to $status',
        );
        await _loadWorkOrders(); // Reload to get updated data
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update status. Please try again.',
          onRetry: () => _updateStatus(id, status),
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
                        items: ['Open', 'In Progress', 'Completed', 'Cancelled']
                            .map((status) =>
                                DropdownMenuItem(value: status, child: Text(status)))
                            .toList(),
                        onChanged: (newStatus) {
                          if (newStatus != null) {
                            _updateStatus(workOrder['id'] as String, newStatus);
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
