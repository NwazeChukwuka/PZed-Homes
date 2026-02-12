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
  List<Map<String, dynamic>> _historicalCounts = [];
  Map<String, List<Map<String, dynamic>>> _countItemsByCountId = {};
  Map<String, List<Map<String, dynamic>>> _customItemsByCountId = {};
  Map<String, Map<String, dynamic>> _locationsById = {};
  Map<String, Map<String, dynamic>> _stockItemsById = {};
  Map<String, Map<String, dynamic>> _submittersById = {};
  String _viewMode = 'pending'; // 'pending' or 'historical'

  @override
  void initState() {
    super.initState();
    _loadPendingCounts();
    _loadHistoricalCounts();
  }

  Future<void> _loadHistoricalCounts() async {
    try {
      // Load approved counts
      final approved = await _supabase
          .from('pending_stock_counts')
          .select('*, submitted_by_profile:profiles!submitted_by(id, full_name), approved_by_profile:profiles!approved_by(id, full_name)')
          .eq('status', 'approved')
          .order('submitted_at', ascending: false)
          .limit(25);
      
      // Load rejected counts
      final rejected = await _supabase
          .from('pending_stock_counts')
          .select('*, submitted_by_profile:profiles!submitted_by(id, full_name), rejected_by_profile:profiles!rejected_by(id, full_name)')
          .eq('status', 'rejected')
          .order('submitted_at', ascending: false)
          .limit(25);

      _historicalCounts = [
        ...List<Map<String, dynamic>>.from(approved),
        ...List<Map<String, dynamic>>.from(rejected),
      ]..sort((a, b) {
          final aDate = a['submitted_at'] as String? ?? '';
          final bDate = b['submitted_at'] as String? ?? '';
          return bDate.compareTo(aDate);
        });

      // Load custom items for historical counts
      if (_historicalCounts.isNotEmpty) {
        final countIds = _historicalCounts.map((c) => c['id'] as String).toList();
        final customItems = await _supabase
            .from('stock_count_custom_items')
            .select()
            .inFilter('stock_count_id', countIds);

        _customItemsByCountId = {};
        for (var item in customItems) {
          final countId = item['stock_count_id'] as String;
          if (!_customItemsByCountId.containsKey(countId)) {
            _customItemsByCountId[countId] = [];
          }
          _customItemsByCountId[countId]!.add(item as Map<String, dynamic>);
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('Error loading historical counts: $e');
      }
    }
  }

  Future<void> _loadPendingCounts() async {
    setState(() => _isLoading = true);
    try {
      // Load pending stock counts
      final counts = await _supabase
          .from('pending_stock_counts')
          .select('*, submitted_by_profile:profiles!submitted_by(id, full_name)')
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

      // Extract submitter info for pending counts (alias: submitted_by_profile)
      for (var count in _pendingCounts) {
        final submitter = count['submitted_by_profile'] as Map<String, dynamic>?;
        if (submitter != null) {
          _submittersById[count['id'] as String] = submitter;
        }
      }

      // Extract submitter info for historical counts (alias: submitted_by_profile)
      for (var count in _historicalCounts) {
        final submitter = count['submitted_by_profile'] as Map<String, dynamic>?;
        if (submitter != null && !_submittersById.containsKey(count['id'] as String)) {
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

        // Load custom items for pending counts
        final customItems = await _supabase
            .from('stock_count_custom_items')
            .select()
            .inFilter('stock_count_id', countIds);

        _customItemsByCountId = {};
        for (var item in customItems) {
          final countId = item['stock_count_id'] as String;
          if (!_customItemsByCountId.containsKey(countId)) {
            _customItemsByCountId[countId] = [];
          }
          _customItemsByCountId[countId]!.add(item as Map<String, dynamic>);
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
        await _loadHistoricalCounts();
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
        await _loadHistoricalCounts();
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

  String _getApproverName(Map<String, dynamic> count) {
    final approverProfile = count['approved_by_profile'] as Map<String, dynamic>?;
    if (approverProfile != null) {
      return approverProfile['full_name'] as String? ?? 'Unknown';
    }
    return 'Unknown';
  }

  String _getRejectorName(Map<String, dynamic> count) {
    final rejectorProfile = count['rejected_by_profile'] as Map<String, dynamic>?;
    if (rejectorProfile != null) {
      return rejectorProfile['full_name'] as String? ?? 'Unknown';
    }
    return 'Unknown';
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'historical', label: Text('History')),
            ],
            selected: {_viewMode},
            onSelectionChanged: (selection) {
              setState(() {
                _viewMode = selection.first;
              });
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadPendingCounts();
              _loadHistoricalCounts();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _viewMode == 'pending'
              ? _pendingCounts.isEmpty
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
                      onRefresh: () async {
                        await _loadPendingCounts();
                        await _loadHistoricalCounts();
                      },
                      child: _buildCountsList(_pendingCounts, showActions: true),
                    )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadPendingCounts();
                    await _loadHistoricalCounts();
                  },
                  child: _historicalCounts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No historical stock counts',
                                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : _buildCountsList(_historicalCounts, showActions: false),
                ),
    );
  }

  Widget _buildCountsList(List<Map<String, dynamic>> counts, {required bool showActions}) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: counts.length,
      itemBuilder: (context, index) {
        final count = counts[index];
        final countId = count['id'] as String;
        final locationId = count['location_id'] as String;
        final location = _locationsById[locationId];
        final locationName = location?['name'] as String? ?? 'Unknown Location';
        final countType = count['count_type'] as String? ?? 'Opening';
        final countDate = count['count_date'] as String? ?? '';
        final submittedAt = count['submitted_at'] as String? ?? '';
        final status = count['status'] as String? ?? 'pending';
        final submitter = _submittersById[countId];
        final submitterName = submitter?['full_name'] as String? ?? 'Unknown';
        final items = _countItemsByCountId[countId] ?? [];
        final customItems = _customItemsByCountId[countId] ?? [];

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
                                  // Custom Items Section
                                  if (customItems.isNotEmpty) ...[
                                    const SizedBox(height: 24),
                                    const Text(
                                      'Custom Items (Not in Database):',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 12),
                                    Card(
                                      color: Colors.blue.shade50,
                                      child: Column(
                                        children: customItems.map((customItem) {
                                          return ListTile(
                                            title: Text(
                                              customItem['item_name'] as String? ?? 'Unknown',
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            subtitle: Text(
                                              'Quantity: ${customItem['quantity']} ${customItem['unit'] ?? 'units'}',
                                            ),
                                            trailing: customItem['notes'] != null && (customItem['notes'] as String).isNotEmpty
                                                ? Tooltip(
                                                    message: customItem['notes'] as String,
                                                    child: const Icon(Icons.info_outline, color: Colors.blue),
                                                  )
                                                : null,
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  if (showActions && status == 'pending')
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
                                  if (!showActions && status == 'rejected') ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Rejected by: ${_getRejectorName(count)}',
                                      style: TextStyle(fontSize: 12, color: Colors.red[700], fontStyle: FontStyle.italic),
                                    ),
                                    if (count['notes'] != null && (count['notes'] as String).isNotEmpty)
                                      Text(
                                        'Reason: ${count['notes']}',
                                        style: TextStyle(fontSize: 12, color: Colors.red[600]),
                                      ),
                                  ],
                                  if (!showActions && status == 'approved') ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Approved by: ${_getApproverName(count)}',
                                      style: TextStyle(fontSize: 12, color: Colors.green[700], fontStyle: FontStyle.italic),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
  }
}
