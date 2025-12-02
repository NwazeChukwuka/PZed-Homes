class GalleryItem {
  final String url;
  final String title;
  final bool isVideo;

  const GalleryItem({
    required this.url,
    required this.title,
    this.isVideo = false,
  });
}
