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
    
    // Define the actual images that exist for each category
    // Only include images that are actually in the assets folder (from pubspec.yaml)
    final Map<String, List<String>> categoryImages = {
      'Front View': ['Front View 1.JPG', 'Front View 2.JPG', 'Front View 3.jpg', 'Front View 4.jpg', 'Front View 5.JPG', 'Front View 6.jpg'],
      'Reception': ['Reception 1.JPG', 'Reception 2.png', 'Reception 3.jpg', 'Reception 4.jpg'],
      'VIP Bar': ['VIP Bar 1.JPG', 'VIP Bar 2.JPG'],
      'Outside bar': ['Outside Bar 1.JPG', 'Outside Bar 2.jpg', 'Outside Bar 3.JPG'],
      'Restaurant': ['Restaurant 1.jpg'],
      'Passage': ['Passage 1.jpg'],
      'Standard Room': ['Standard 1.png', 'Standard 2.JPG', 'Standard 3.jpg'],
      'Classic Room': ['Classic 1.JPG', 'Classic 2.png', 'Classic 3.JPG'],
      'Deluxe Room': ['Deluxe 1.JPG', 'Deluxe 2.JPG', 'Deluxe 3.png'],
      'Diplomatic Room': ['Diplomatic 1.png', 'Diplomatic 2.JPG', 'Diplomatic 3.jpg'],
      'Executive Room': ['Executive 1.png', 'Executive 2.png', 'Executive 3.jpg'],
    };
    
    // Get the list of actual images for this category
    final imageFiles = categoryImages[path] ?? [];
    
    // Only add items for images that actually exist
    for (var imageFile in imageFiles) {
      final imagePath = 'assets/images/$path/$imageFile';
      items.add(GalleryItem(
        url: imagePath,
        title: imageFile.replaceAll(RegExp(r'\.[^.]*$'), ''), // Remove extension
      ));
    }
    
    return items;
  }
}
