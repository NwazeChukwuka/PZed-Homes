// Location: lib/presentation/screens/smartlock_log_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class SmartLockLogScreen extends StatefulWidget {
  const SmartLockLogScreen({super.key});

  @override
  State<SmartLockLogScreen> createState() => _SmartLockLogScreenState();
}

class _SmartLockLogScreenState extends State<SmartLockLogScreen> {
  final _supabase = Supabase.instance.client;
  // Use a stream for real-time updates
  late final Stream<List<Map<String, dynamic>>> _logStream;

  @override
  void initState() {
    super.initState();
    // Fetch logs with room number, ordered by most recent
    // Note: Streams don't support joins, so we'll fetch room data separately if needed
    _logStream = _supabase
        .from('smartlock_logs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100); // Limit to recent logs for performance
  }

  // Helper to format the timestamp
  String _formatTimestamp(String? isoTimestamp) {
    if (isoTimestamp == null) return 'N/A';
    try {
      final dateTime = DateTime.parse(isoTimestamp).toLocal();
      // Example format: Oct 30, 2025 - 12:55 AM
      return DateFormat('MMM d, yyyy - h:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid Date';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Lock Activity Log'),
        backgroundColor: Colors.teal.shade800,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _logStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorHandler.buildErrorWidget(
              context,
              snapshot.error,
              message: 'Error loading smart lock logs',
            );
          }
          
          final logs = snapshot.data ?? [];

          if (logs.isEmpty) {
            return ErrorHandler.buildEmptyWidget(
              context,
              message: 'No smart lock activity recorded yet',
            );
          }

          return ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              // Fetch room number separately since streams don't support joins
              final roomId = log['room_id'];
              final roomNumber = roomId != null ? 'Room $roomId' : 'N/A';
              final eventType = log['event_type'] ?? 'UNKNOWN_EVENT';
              final userIdentifier = log['user_identifier'] ?? 'System';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.lock_clock),
                  title: Text('Room $roomNumber: $eventType'),
                  subtitle: Text('By: $userIdentifier'),
                  trailing: Text(
                    _formatTimestamp(log['created_at']),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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