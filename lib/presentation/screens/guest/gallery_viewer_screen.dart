import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:pzed_homes/data/models/gallery_item.dart';

class GalleryViewerScreen extends StatefulWidget {
  final List<GalleryItem> items;
  final int initialIndex;
  
  const GalleryViewerScreen({
    super.key, 
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<GalleryViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isVideoPlaying = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeMediaPlayer();
  }

  void _initializeMediaPlayer() {
    final currentItem = widget.items[_currentIndex];
    if (currentItem.isVideo) {
      _initializeVideoPlayer(currentItem);
    } else {
      _disposeVideoPlayer();
    }
  }

  void _initializeVideoPlayer(GalleryItem item) async {
    _disposeVideoPlayer();
    
    _videoPlayerController = item.url.startsWith('http')
        ? VideoPlayerController.network(item.url)
        : VideoPlayerController.asset(item.url);
        
    await _videoPlayerController?.initialize();
    
    if (mounted) {
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        aspectRatio: _videoPlayerController!.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
      
      setState(() {
        _isVideoPlaying = true;
      });
    }
  }

  void _disposeVideoPlayer() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    _videoPlayerController = null;
    _chewieController = null;
    _isVideoPlaying = false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeVideoPlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          '${_currentIndex + 1} of ${widget.items.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (widget.items[_currentIndex].isVideo)
            IconButton(
              icon: Icon(
                _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              onPressed: _toggleVideoPlayback,
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.items.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final item = widget.items[index];
              return item.isVideo
                  ? _buildVideoPlayer()
                  : _buildImageViewer(item);
            },
          ),
          
          // Navigation Arrows
          if (widget.items.length > 1) ...[
            // Left Arrow
            if (_currentIndex > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Right Arrow
            if (_currentIndex < widget.items.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Page Indicator Dots
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.items.length,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentIndex == index 
                          ? Colors.white 
                          : Colors.white.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isVideoPlaying = false;
    });
    _initializeMediaPlayer();
  }

  void _toggleVideoPlayback() {
    if (_videoPlayerController == null) return;
    
    if (_videoPlayerController!.value.isPlaying) {
      _videoPlayerController?.pause();
      setState(() => _isVideoPlaying = false);
    } else {
      _videoPlayerController?.play();
      setState(() => _isVideoPlaying = true);
    }
  }

  Widget _buildImageViewer(GalleryItem item) {
    return InteractiveViewer(
      panEnabled: true,
      minScale: 0.5,
      maxScale: 4.0,
      child: item.url.startsWith('http')
          ? Image.network(
              item.url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget('Failed to load image');
              },
            )
          : Image.asset(
              item.url,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget('Image not found');
              },
            ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_chewieController != null && _chewieController!.videoPlayerController.value.isInitialized) {
      return Chewie(controller: _chewieController!);
    }
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
  
  Widget _buildErrorWidget(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 48),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }
}