import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';

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
          .update({'media_url': newUrl, 'updated_at': DateTime.now().toIso8601String()})
          .eq('content_key', contentKey);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image updated successfully!'), backgroundColor: Colors.green));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Website Content')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('site_media').stream(primaryKey: ['content_key']).order('title'),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final items = snapshot.data!;
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final key = item['content_key'];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: Image.network(item['media_url'], width: 60, height: 60, fit: BoxFit.cover),
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