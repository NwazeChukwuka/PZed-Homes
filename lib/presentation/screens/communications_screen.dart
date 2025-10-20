import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:intl/intl.dart';

class CommunicationsScreen extends StatefulWidget {
  const CommunicationsScreen({super.key});

  @override
  State<CommunicationsScreen> createState() => _CommunicationsScreenState();
}

class _CommunicationsScreenState extends State<CommunicationsScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final List<Map<String, dynamic>> _posts = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMockPosts();
  }

  Future<void> _loadMockPosts() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 250));
    final now = DateTime.now();
    _posts.clear();
    _posts.addAll([
      {
        'id': 'post1',
        'title': 'Welcome to P-ZED Luxury Hotels & Suites',
        'content': 'Team, let\'s ensure premium experience for all guests today. ',
        'author_name': 'Management',
        'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
      },
      {
        'id': 'post2',
        'title': 'VIP Bar Inventory Reminder',
        'content': 'Please reconcile VIP bar stock before 8PM.',
        'author_name': 'Storekeeper',
        'created_at': now.subtract(const Duration(hours: 6)).toIso8601String(),
      },
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _showCreatePostDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Create Announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  maxLength: 100,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 5,
                  maxLength: 500,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                _titleController.clear();
                _contentController.clear();
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Post'),
              onPressed: () async {
                if (_titleController.text.trim().isEmpty || 
                    _contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in both title and message'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final authService = Provider.of<MockAuthService>(context, listen: false);
                  final currentUser = authService.currentUser;
                  
                  if (currentUser == null) {
                    throw Exception('User not authenticated');
                  }

                  final post = {
                    'id': 'post_${DateTime.now().millisecondsSinceEpoch}',
                    'title': _titleController.text.trim(),
                    'content': _contentController.text.trim(),
                    'author_name': currentUser.name,
                    'created_at': DateTime.now().toIso8601String(),
                  };
                  setState(() => _posts.insert(0, post));

                  _titleController.clear();
                  _contentController.clear();
                  
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('[Mock] Announcement posted successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('[Mock] Error posting announcement: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<MockAuthService>(context, listen: false);
    final canPost = authService.currentUser?.role == AppRole.manager || 
                     authService.currentUser?.role == AppRole.owner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        backgroundColor: Colors.blueGrey.shade700,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
          final posts = _posts;
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.announcement, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text(
                    'No announcements yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = posts[index];
              final author = post['author_name'] ?? 'Unknown';
              final createdAt = DateTime.tryParse(post['created_at']?.toString() ?? '');
              
              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['title']?.toString() ?? 'No title',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        post['content']?.toString() ?? '',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'By: $author',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (createdAt != null)
                            Text(
                              DateFormat('MMM d, yyyy').format(createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      floatingActionButton: canPost
          ? FloatingActionButton(
              onPressed: () => _showCreatePostDialog(),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}