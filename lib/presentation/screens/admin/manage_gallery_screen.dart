import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // You'll need to run: flutter pub add image_picker
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

class ManageGalleryScreen extends StatefulWidget {
  const ManageGalleryScreen({super.key});
  @override
  State<ManageGalleryScreen> createState() => _ManageGalleryScreenState();
}

class _ManageGalleryScreenState extends State<ManageGalleryScreen> {
  final _supabase = Supabase.instance.client;

  Future<void> _uploadNewItem() async {
    final picker = ImagePicker();
    // Allow picking image or video
    final XFile? file = await picker.pickMedia(); 
    if (file == null) return;

    final fileBytes = await file.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}-${file.name}';
    
    try {
      // 1. Upload file to Supabase Storage
      await _supabase.storage.from('gallery').uploadBinary(fileName, fileBytes);
      
      // 2. Get the public URL
      final mediaUrl = _supabase.storage.from('gallery').getPublicUrl(fileName);

      // 3. Save the record to the database table
      await _supabase.from('gallery_media').insert({
        'title': 'New Item - Edit Me',
        'media_url': mediaUrl,
        'is_video': file.mimeType?.startsWith('video/') ?? false,
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Item added successfully!');
        setState(() {}); // Refresh the list
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to upload item. Please try again.',
          onRetry: _uploadNewItem,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Gallery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate),
            onPressed: _uploadNewItem,
            tooltip: 'Add New Item',
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('gallery_media').stream(primaryKey: ['id']).order('sort_order'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return ErrorHandler.buildErrorWidget(
              context,
              snapshot.error,
              message: 'Error loading gallery items',
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return ErrorHandler.buildEmptyWidget(
              context,
              message: 'No gallery items available',
            );
          }
          
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: CachedNetworkImage(
                  imageUrl: item['thumbnail_url'] ?? item['media_url'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                    child: const Icon(Icons.broken_image, size: 24),
                  ),
                ),
                title: Text(item['title']),
                subtitle: Text(item['is_video'] ? 'Video' : 'Image'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    try {
                      // This should also delete from storage
                      await _supabase.from('gallery_media').delete().eq('id', item['id']);
                      if (mounted) {
                        ErrorHandler.showSuccessMessage(context, 'Item deleted successfully');
                      }
                    } catch (e) {
                      if (mounted) {
                        ErrorHandler.handleError(
                          context,
                          e,
                          customMessage: 'Failed to delete item. Please try again.',
                        );
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}