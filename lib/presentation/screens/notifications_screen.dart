import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/state/app_state_manager.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = Provider.of<AppStateManager>(context, listen: false);
      stateManager.markAllNotificationsAsRead();
    });
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) return '';
    return DateFormat('MMM d, h:mm a').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateManager>(
      builder: (context, state, _) {
        final notifications = state.notifications;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Notifications'),
            actions: [
              if (notifications.isNotEmpty)
                TextButton(
                  onPressed: () => state.markAllNotificationsAsRead(),
                  child: const Text('Mark all read'),
                ),
            ],
          ),
          body: notifications.isEmpty
              ? const Center(child: Text('No notifications'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    final isRead = n['is_read'] == true;
                    final title = n['title'] ?? 'Notification';
                    final message = n['message'] ?? '';
                    final createdAt = n['created_at'] as String?;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isRead ? Icons.notifications : Icons.notifications_active,
                          color: isRead ? Colors.grey : Colors.orange[700],
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.toString().isNotEmpty) Text(message),
                            const SizedBox(height: 4),
                            Text(
                              _formatTime(createdAt),
                              style: TextStyle(color: Colors.grey[600], fontSize: 12),
                            ),
                          ],
                        ),
                        onTap: () {
                          final id = n['id'] as String?;
                          if (id != null && !isRead) {
                            state.markNotificationAsRead(id);
                          }
                        },
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
