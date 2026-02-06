import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';

/// Performance optimization helpers for common UI patterns
class OptimizationHelpers {
  /// Maximum cache dimension for full-screen images (downscale oversized assets)
  static const int maxCacheDimension = 1200;

  /// Optimized asset image with downscaling (cacheWidth/cacheHeight) to reduce memory.
  /// Uses 2x display size for retina; caps at maxCacheDimension.
  static Widget buildAssetImage({
    required String assetPath,
    double? width,
    double? height,
    BoxFit fit = BoxFit.contain,
    Color? color,
    Widget? errorWidget,
  }) {
    final w = width ?? 256;
    final h = height ?? 256;
    final cacheW = (w * 2).round().clamp(1, maxCacheDimension);
    final cacheH = (h * 2).round().clamp(1, maxCacheDimension);
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      color: color,
      cacheWidth: cacheW,
      cacheHeight: cacheH,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) =>
          errorWidget ?? _buildErrorWidget(w, h),
    );
  }

  /// Optimized cached network image with shimmer loading and memory limits
  static Widget buildCachedImage({
    required String imageUrl,
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
    Widget? placeholder,
    Widget? errorWidget,
  }) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        placeholder: (context, url) => placeholder ?? _buildShimmerPlaceholder(width, height),
        errorWidget: (context, url, error) => errorWidget ?? _buildErrorWidget(width, height),
        memCacheWidth: width.round().clamp(1, maxCacheDimension),
        memCacheHeight: height.round().clamp(1, maxCacheDimension),
      ),
    );
  }

  /// Shimmer placeholder for loading states
  static Widget _buildShimmerPlaceholder(double width, double height) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        color: Colors.grey.shade300,
      ),
    );
  }

  /// Error widget for failed image loads
  static Widget _buildErrorWidget(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.error_outline, color: Colors.red),
    );
  }

  /// Optimized list view with performance flags
  static Widget buildOptimizedListView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    EdgeInsetsGeometry? padding,
    ScrollController? controller,
    bool shrinkWrap = false,
    double? cacheExtent,
  }) {
    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      padding: padding,
      controller: controller,
      shrinkWrap: shrinkWrap,
      cacheExtent: cacheExtent ?? 500,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
    );
  }

  /// Optimized grid view with performance flags
  static Widget buildOptimizedGridView({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
    required int crossAxisCount,
    double crossAxisSpacing = 0.0,
    double mainAxisSpacing = 0.0,
    double childAspectRatio = 1.0,
    EdgeInsetsGeometry? padding,
    ScrollController? controller,
    bool shrinkWrap = false,
  }) {
    return GridView.builder(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        childAspectRatio: childAspectRatio,
      ),
      padding: padding,
      controller: controller,
      shrinkWrap: shrinkWrap,
      addAutomaticKeepAlives: true,
      addRepaintBoundaries: true,
      addSemanticIndexes: false,
    );
  }

  /// Debounced function calls to prevent excessive API calls
  static void debounce({
    required String key,
    required Duration delay,
    required VoidCallback callback,
  }) {
    _DebounceManager.debounce(key, delay, callback);
  }

  /// Memoized builder for expensive computations
  static Widget memoizedBuilder({
    required String key,
    required Widget Function() builder,
  }) {
    return _MemoizedBuilder(memoKey: key, builder: builder);
  }
}

/// Internal debounce manager
class _DebounceManager {
  static final Map<String, Timer> _timers = {};

  static void debounce(String key, Duration delay, VoidCallback callback) {
    _timers[key]?.cancel();
    _timers[key] = Timer(delay, callback);
  }
}

/// Memoized builder widget
class _MemoizedBuilder extends StatefulWidget {
  final String memoKey;
  final Widget Function() builder;

  const _MemoizedBuilder({
    super.key,
    required this.memoKey,
    required this.builder,
  });

  @override
  State<_MemoizedBuilder> createState() => _MemoizedBuilderState();
}

class _MemoizedBuilderState extends State<_MemoizedBuilder> {
  Widget? _cachedWidget;

  @override
  void initState() {
    super.initState();
    _cachedWidget = widget.builder();
  }

  @override
  Widget build(BuildContext context) {
    return _cachedWidget!;
  }
}

/// Performance monitoring utilities
class PerformanceMonitor {
  static void trackWidgetBuild(String widgetName, VoidCallback buildFunction) {
    final stopwatch = Stopwatch()..start();
    buildFunction();
    stopwatch.stop();
    
    if (stopwatch.elapsedMilliseconds > 16) { // 60fps threshold
      debugPrint('Performance Warning: $widgetName took ${stopwatch.elapsedMilliseconds}ms to build');
    }
  }

  static void trackAsyncOperation(String operationName, Future<void> operation) async {
    final stopwatch = Stopwatch()..start();
    await operation;
    stopwatch.stop();
    
    debugPrint('$operationName completed in ${stopwatch.elapsedMilliseconds}ms');
  }
}
