// Location: lib/presentation/screens/admin/manage_gallery_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart'; // You'll need to run: flutter pub add image_picker
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

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item added successfully!')));
      setState(() {}); // Refresh the list
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                leading: Image.network(item['thumbnail_url'] ?? item['media_url'], width: 50, height: 50, fit: BoxFit.cover),
                title: Text(item['title']),
                subtitle: Text(item['is_video'] ? 'Video' : 'Image'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    // This should also delete from storage
                    await _supabase.from('gallery_media').delete().eq('id', item['id']);
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