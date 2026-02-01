import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';

class StockCountApprovalScreen extends StatefulWidget {
  const StockCountApprovalScreen({super.key});

  @override
  State<StockCountApprovalScreen> createState() => _StockCountApprovalScreenState();
}

class _StockCountApprovalScreenState extends State<StockCountApprovalScreen> {
  final DataService _dataService = DataService();
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }

  bool _isLoading = true;
  List<Map<String, dynamic>> _pendingCounts = [];
  Map<String, List<Map<String, dynamic>>> _countItemsByCountId = {};
  Map<String, Map<String, dynamic>> _locationsById = {};
  Map<String, Map<String, dynamic>> _stockItemsById = {};
  Map<String, Map<String, dynamic>> _submittersById = {};

  @override
  void initState() {
    super.initState();
    _loadPendingCounts();
  }

  Future<void> _loadPendingCounts() async {
    setState(() => _isLoading = true);
    try {
      // Load pending stock counts
      final counts = await _supabase
          .from('pending_stock_counts')
          .select('*, profiles!submitted_by(id, full_name)')
          .eq('status', 'pending')
          .order('submitted_at', ascending: false);

      _pendingCounts = List<Map<String, dynamic>>.from(counts);

      // Load locations
      final locations = await _supabase.from('locations').select();
      _locationsById = {
        for (var loc in locations) loc['id'] as String: loc as Map<String, dynamic>
      };

      // Load stock items
      final stockItems = await _supabase.from('stock_items').select();
      _stockItemsById = {
        for (var item in stockItems) item['id'] as String: item as Map<String, dynamic>
      };

      // Extract submitter info
      for (var count in _pendingCounts) {
        final submitter = count['profiles'] as Map<String, dynamic>?;
        if (submitter != null) {
          _submittersById[count['id'] as String] = submitter;
        }
      }

      // Load count items for each pending count
      if (_pendingCounts.isNotEmpty) {
        final countIds = _pendingCounts.map((c) => c['id'] as String).toList();
        final items = await _supabase
            .from('stock_count_items')
            .select()
            .inFilter('stock_count_id', countIds);

        _countItemsByCountId = {};
        for (var item in items) {
          final countId = item['stock_count_id'] as String;
          if (!_countItemsByCountId.containsKey(countId)) {
            _countItemsByCountId[countId] = [];
          }
          _countItemsByCountId[countId]!.add(item as Map<String, dynamic>);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load pending stock counts.',
          onRetry: _loadPendingCounts,
        );
      }
    }
  }

  Future<void> _approveCount(String countId, {String? notes}) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final approverId = authService.currentUser?.id;
      if (approverId == null) {
        throw Exception('User must be logged in to approve counts');
      }

      // Call the approval function
      await _supabase.rpc('approve_stock_count', params: {
        'count_id': countId,
        'approver_id': approverId,
        'approval_notes': notes,
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Stock count approved successfully!',
        );
        await _loadPendingCounts();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to approve stock count.',
        );
      }
    }
  }

  Future<void> _rejectCount(String countId, {String? reason}) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final rejectorId = authService.currentUser?.id;
      if (rejectorId == null) {
        throw Exception('User must be logged in to reject counts');
      }

      await _supabase
          .from('pending_stock_counts')
          .update({
            'status': 'rejected',
            'rejected_by': rejectorId,
            'rejected_at': DateTime.now().toIso8601String(),
            'notes': reason ?? 'Rejected by management',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', countId);

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Stock count rejected.',
        );
        await _loadPendingCounts();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to reject stock count.',
        );
      }
    }
  }

  void _showApprovalDialog(String countId) {
    final notesController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Stock Count'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Are you sure you want to approve this stock count? This will update the actual stock levels.'),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Add any notes about this approval',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _approveCount(countId, notes: notesController.text.trim().isEmpty ? null : notesController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
  }

  void _showRejectionDialog(String countId) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Stock Count'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejecting this stock count.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Enter reason for rejection',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ErrorHandler.showWarningMessage(context, 'Please provide a reason');
                return;
              }
              Navigator.pop(context);
              _rejectCount(countId, reason: reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Count Approvals'),
        backgroundColor: Colors.brown[700],
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingCounts,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingCounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No pending stock counts',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'All stock counts have been processed',
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPendingCounts,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingCounts.length,
                    itemBuilder: (context, index) {
                      final count = _pendingCounts[index];
                      final countId = count['id'] as String;
                      final locationId = count['location_id'] as String;
                      final location = _locationsById[locationId];
                      final locationName = location?['name'] as String? ?? 'Unknown Location';
                      final countType = count['count_type'] as String? ?? 'Opening';
                      final countDate = count['count_date'] as String? ?? '';
                      final submittedAt = count['submitted_at'] as String? ?? '';
                      final submitter = _submittersById[countId];
                      final submitterName = submitter?['full_name'] as String? ?? 'Unknown';
                      final items = _countItemsByCountId[countId] ?? [];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        elevation: 2,
                        child: ExpansionTile(
                          initiallyExpanded: index == 0, // Expand first item
                          title: Text(
                            locationName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$countType Stock - ${countDate.isNotEmpty ? DateFormat('MMM dd, yyyy').format(DateTime.parse(countDate)) : 'N/A'}'),
                              Text('Submitted by: $submitterName'),
                              if (submittedAt.isNotEmpty)
                                Text(
                                  'Submitted: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(submittedAt))}',
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              Text(
                                '${items.length} item(s)',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Stock Count Details:',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 12),
                                  if (items.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('No items in this count'),
                                    )
                                  else
                                    Table(
                                      border: TableBorder.all(color: Colors.grey[300]!),
                                      children: [
                                        TableRow(
                                          decoration: BoxDecoration(color: Colors.grey[200]),
                                          children: const [
                                            Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Text('Item', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Text('System', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Text('Counted', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(8),
                                              child: Text('Difference', style: TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                            ),
                                          ],
                                        ),
                                        ...items.map((item) {
                                          final stockItemId = item['stock_item_id'] as String;
                                          final stockItem = _stockItemsById[stockItemId];
                                          final itemName = stockItem?['name'] as String? ?? 'Unknown';
                                          final systemQty = item['system_quantity'] as int? ?? 0;
                                          final countedQty = item['counted_quantity'] as int? ?? 0;
                                          final difference = countedQty - systemQty;
                                          final diffColor = difference == 0
                                              ? Colors.grey
                                              : difference > 0
                                                  ? Colors.green
                                                  : Colors.red;

                                          return TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Text(itemName),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Text(
                                                  systemQty.toString(),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Text(
                                                  countedQty.toString(),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(8),
                                                child: Text(
                                                  difference > 0 ? '+$difference' : difference.toString(),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: diffColor,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        }).toList(),
                                      ],
                                    ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () => _showRejectionDialog(countId),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(color: Colors.red),
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                      const SizedBox(width: 12),
                                      ElevatedButton(
                                        onPressed: () => _showApprovalDialog(countId),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        child: const Text('Approve'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
