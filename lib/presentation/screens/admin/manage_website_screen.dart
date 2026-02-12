import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ManageWebsiteScreen extends StatefulWidget {
  const ManageWebsiteScreen({super.key});
  @override
  State<ManageWebsiteScreen> createState() => _ManageWebsiteScreenState();
}

class _ManageWebsiteScreenState extends State<ManageWebsiteScreen> {
  final _supabase = Supabase.instance.client;

  Future<void> _replaceImage(String contentKey) async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;

    final fileBytes = await file.readAsBytes();
    final fileName = '${contentKey}-${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // 1. Upload new image to a 'site_assets' bucket
      // (You must create a public bucket named 'site_assets' in Supabase Storage)
      await _supabase.storage.from('site_assets').uploadBinary(fileName, fileBytes);
      
      // 2. Get the new public URL
      final newUrl = _supabase.storage.from('site_assets').getPublicUrl(fileName);

      // 3. Update the database table with the new URL
      await _supabase
          .from('site_media')
          .update({'media_url': newUrl})
          .eq('content_key', contentKey);

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Image updated successfully!');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update image. Please try again.',
          onRetry: () => _replaceImage(contentKey),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Website Content')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('site_media').stream(primaryKey: ['content_key']).order('title'),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return ErrorHandler.buildErrorWidget(
              context,
              snapshot.error,
              message: 'Error loading website content',
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return ErrorHandler.buildEmptyWidget(
              context,
              message: 'No website content available',
            );
          }
          
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final key = item['content_key'];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: CachedNetworkImage(
                    imageUrl: item['media_url'],
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    memCacheWidth: 120,
                    memCacheHeight: 120,
                    placeholder: (context, url) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[300],
                      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: 60,
                      height: 60,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 30),
                    ),
                  ),
                  title: Text(item['title']),
                  subtitle: Text(item['description'] ?? 'No description'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _replaceImage(key),
                    tooltip: 'Replace Image',
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