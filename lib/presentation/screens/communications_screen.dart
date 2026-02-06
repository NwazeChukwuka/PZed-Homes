import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommunicationsScreen extends StatefulWidget {
  const CommunicationsScreen({super.key});

  @override
  State<CommunicationsScreen> createState() => _CommunicationsScreenState();
}

class _CommunicationsScreenState extends State<CommunicationsScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _dataService = DataService();
  SupabaseClient _requireSupabase() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }
  final List<Map<String, dynamic>> _posts = [];
  final List<Map<String, dynamic>> _staffProfiles = [];
  String? _selectedRecipientId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadStaffProfiles();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      // Always include the default "Welcome to PZED" announcement
      final defaultPost = {
        'id': 'welcome_post',
        'title': 'Welcome to P-ZED Luxury Hotels & Suites',
        'content': 'Team, let\'s ensure premium experience for all guests today.',
        'author_name': 'Management',
        'created_at': DateTime.now().toIso8601String(),
      };

      // Load announcements from database
      final dbPosts = await _dataService.getPosts(isAnnouncement: true);
      
      setState(() {
        _posts.clear();
        // Add default welcome post first
        _posts.add(defaultPost);
        // Add database posts
        _posts.addAll(dbPosts.map((post) {
          final profile = post['profiles'] as Map<String, dynamic>?;
          return {
            'id': post['id'],
            'title': post['title'] ?? 'No title',
            'content': post['content'] ?? '',
            'author_name': profile?['full_name'] ?? 'Unknown',
            'created_at': post['created_at'] ?? DateTime.now().toIso8601String(),
          };
        }).toList());
        _isLoading = false;
      });
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadPosts: $e\n$stack');
      setState(() {
        _posts.clear();
        _posts.add({
          'id': 'welcome_post',
          'title': 'Welcome to P-ZED Luxury Hotels & Suites',
          'content': 'Team, let\'s ensure premium experience for all guests today.',
          'author_name': 'Management',
          'created_at': DateTime.now().toIso8601String(),
        });
        _isLoading = false;
      });
    }
  }

  Future<void> _loadStaffProfiles() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isManagement = authService.currentUser?.roles.any(
            (role) => role == AppRole.owner || role == AppRole.manager,
          ) ??
          false;
      if (!isManagement) return;
      final profiles = await _dataService.getStaffProfiles();
      setState(() {
        _staffProfiles
          ..clear()
          ..addAll(profiles);
      });
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadStaffProfiles: $e\n$stack');
    }
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
                if (_staffProfiles.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _selectedRecipientId,
                    decoration: const InputDecoration(
                      labelText: 'Send To (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('All Staff'),
                      ),
                      ..._staffProfiles.map((p) {
                        final name = p['full_name'] ?? p['email'] ?? 'Staff';
                        return DropdownMenuItem<String>(
                          value: p['id'] as String,
                          child: Text(name),
                        );
                      }).toList(),
                    ],
                    onChanged: (value) => setState(() => _selectedRecipientId = value),
                  ),
                if (_staffProfiles.isNotEmpty) const SizedBox(height: 16),
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
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please fill in both title and message',
                    );
                  }
                  return;
                }

                try {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUser = authService.currentUser;
                  
                  if (currentUser == null) {
                    throw Exception('User not authenticated');
                  }

                  // Get user profile ID
                  final profileResponse = await _requireSupabase()
                      .from('profiles')
                      .select('id')
                      .eq('email', currentUser.email)
                      .maybeSingle();

                  final profileId = profileResponse?['id'] as String?;
                  if (profileId == null) {
                    throw Exception('User profile not found');
                  }

                  // Create post in database
                  await _dataService.createPost({
                    'author_profile_id': profileId,
                    'title': _titleController.text.trim(),
                    'content': _contentController.text.trim(),
                    'department': currentUser.role.name,
                    'is_announcement': true,
                    if (_selectedRecipientId != null)
                      'target_user_ids': [_selectedRecipientId],
                  });

                  _titleController.clear();
                  _contentController.clear();
                  _selectedRecipientId = null;
                  
                  if (mounted) {
                    Navigator.of(context).pop();
                    ErrorHandler.showSuccessMessage(
                      context,
                      'Announcement posted successfully!',
                    );
                    // Reload posts
                    await _loadPosts();
                  }
                } catch (e, stackTrace) {
                  if (kDebugMode) debugPrint('DEBUG post announcement: $e\n$stackTrace');
                  if (mounted) {
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: 'Failed to post announcement. Please try again.',
                      stackTrace: stackTrace,
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
    final authService = Provider.of<AuthService>(context, listen: false);
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