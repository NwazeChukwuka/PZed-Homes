import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ManageGalleryScreen extends StatefulWidget {
  const ManageGalleryScreen({super.key});
  @override
  State<ManageGalleryScreen> createState() => _ManageGalleryScreenState();
}

class _ManageGalleryScreenState extends State<ManageGalleryScreen> {
  final _supabase = Supabase.instance.client;

  Future<void> _uploadNewItem() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickMedia();
    if (file == null) return;

    final fileBytes = await file.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}-${file.name}';
    
    try {
      await _supabase.storage.from('gallery').uploadBinary(fileName, fileBytes);
      
      final mediaUrl = _supabase.storage.from('gallery').getPublicUrl(fileName);

      await _supabase.from('gallery_media').insert({
        'title': 'New Item - Edit Me',
        'media_url': mediaUrl,
        'is_video': file.mimeType?.startsWith('video/') ?? false,
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Item added successfully!');
        setState(() {});
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

  Future<void> _deleteGalleryItem(String id) async {
    try {
      await _supabase.from('gallery_media').delete().eq('id', id);
      if (!mounted) return;
      ErrorHandler.showSuccessMessage(context, 'Item deleted successfully');
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.handleError(
        context,
        e,
        customMessage: 'Failed to delete item. Please try again.',
      );
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
        builder: (streamContext, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return ErrorHandler.buildErrorWidget(
              streamContext,
              snapshot.error,
              message: 'Error loading gallery items',
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return ErrorHandler.buildEmptyWidget(
              streamContext,
              message: 'No gallery items available',
            );
          }
          
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              return ListTile(
                leading: CachedNetworkImage(
                  imageUrl: item['thumbnail_url'] ?? item['media_url'],
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  memCacheWidth: 100,
                  memCacheHeight: 100,
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
                  onPressed: () => _deleteGalleryItem(item['id'].toString()),
                ),
              );
            },
          );
        },
      ),
    );
  }
}