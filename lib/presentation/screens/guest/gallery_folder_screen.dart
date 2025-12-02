import 'package:flutter/material.dart';
import 'package:pzed_homes/data/models/gallery_item.dart';
import 'package:pzed_homes/presentation/screens/guest/gallery_viewer_screen.dart';

class GalleryCategory {
  final String name;
  final String path;
  final String prefix;
  bool isExpanded;
  List<GalleryItem>? items;

  GalleryCategory({
    required this.name,
    required this.path,
    required this.prefix,
    this.isExpanded = false,
    this.items,
  });
}

class GalleryFolderScreen extends StatefulWidget {
  const GalleryFolderScreen({super.key});

  @override
  State<GalleryFolderScreen> createState() => _GalleryFolderScreenState();
}

class _GalleryFolderScreenState extends State<GalleryFolderScreen> {
  final List<GalleryCategory> _categories = [
    GalleryCategory(name: 'Front View', path: 'Front View', prefix: 'Front View '),
    GalleryCategory(name: 'Reception', path: 'Reception', prefix: 'Reception '),
    GalleryCategory(name: 'VIP Bar', path: 'VIP Bar', prefix: 'VIP Bar '),
    GalleryCategory(name: 'Outside Bar', path: 'Outside bar', prefix: 'Outside Bar '),
    GalleryCategory(name: 'Restaurant', path: 'Restaurant', prefix: 'Restaurant '),
    GalleryCategory(name: 'Passage', path: 'Passage', prefix: 'Passage '),
    GalleryCategory(name: 'Standard Room', path: 'Standard Room', prefix: 'Standard '),
    GalleryCategory(name: 'Classic Room', path: 'Classic Room', prefix: 'Classic '),
    GalleryCategory(name: 'Deluxe Room', path: 'Deluxe Room', prefix: 'Deluxe '),
    GalleryCategory(name: 'Diplomatic Room', path: 'Diplomatic Room', prefix: 'Diplomatic '),
    GalleryCategory(name: 'Executive Room', path: 'Executive Room', prefix: 'Executive '),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Gallery'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _categories.length,
        itemBuilder: (context, index) => _buildCategory(_categories[index]),
      ),
    );
  }

  Widget _buildCategory(GalleryCategory category) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          ListTile(
            title: Text(
              category.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            trailing: Icon(
              category.isExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () {
              setState(() {
                category.isExpanded = !category.isExpanded;
                if (category.isExpanded && category.items == null) {
                  // Load images only when expanded for the first time
                  category.items = _getCategoryItems(category.path, category.prefix);
                }
              });
            },
          ),
          if (category.isExpanded && category.items != null)
            _buildImageGrid(category.items!),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<GalleryItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GalleryViewerScreen(
                  items: items,
                  initialIndex: index,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              item.url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, size: 32),
              ),
            ),
          ),
        );
      },
    );
  }

  List<GalleryItem> _getCategoryItems(String path, String prefix) {
    List<GalleryItem> items = [];
    // Try to add up to 20 images per category
    for (var i = 1; i <= 20; i++) {
      final imagePath = 'assets/images/$path/$prefix$i.jpg';
      try {
        // Verify the asset exists before adding
        final assetImage = AssetImage(imagePath);
        assetImage.resolve(createLocalImageConfiguration(context));
        items.add(GalleryItem(
          url: imagePath,
          title: '$prefix$i',
        ));
      } catch (e) {
        // Stop adding if we hit a non-existent image
        if (i == 1) continue; // Skip if first image doesn't exist
        break;
      }
    }
    return items;
  }
}
