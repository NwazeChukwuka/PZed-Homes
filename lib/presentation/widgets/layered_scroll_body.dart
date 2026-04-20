import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Layer B + C scroll contract for management screens:
/// - [topSection] scrolls away with the page.
/// - [content] keeps its own local scroll behavior.
class LayeredScrollBody extends StatefulWidget {
  final Widget topSection;
  final Widget content;
  final bool isLoading;
  final Widget? loadingWidget;

  const LayeredScrollBody({
    super.key,
    required this.topSection,
    required this.content,
    this.isLoading = false,
    this.loadingWidget,
  });

  @override
  State<LayeredScrollBody> createState() => _LayeredScrollBodyState();
}

class _LayeredScrollBodyState extends State<LayeredScrollBody> {
  bool _lockOuterScroll = false;

  void _setOuterScrollLock(bool locked) {
    if (_lockOuterScroll == locked || !mounted) return;
    setState(() => _lockOuterScroll = locked);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return widget.loadingWidget ?? const Center(child: CircularProgressIndicator());
    }

    final outerPhysics = _lockOuterScroll
        ? const NeverScrollableScrollPhysics()
        : const ClampingScrollPhysics();

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior(),
      child: CustomScrollView(
        physics: outerPhysics,
        primary: true,
        slivers: [
          SliverToBoxAdapter(child: widget.topSection),
          SliverFillRemaining(
            hasScrollBody: true,
            child: PrimaryScrollController.none(
              child: Listener(
                onPointerCancel: (_) => _setOuterScrollLock(false),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification) {
                      _setOuterScrollLock(true);
                      return false;
                    }

                    if (notification is ScrollUpdateNotification) {
                      final metrics = notification.metrics;
                      final delta = notification.scrollDelta ?? 0;
                      final atTop = metrics.pixels <= metrics.minScrollExtent + 0.5;
                      final atBottom = metrics.pixels >= metrics.maxScrollExtent - 0.5;

                      // Keep parent locked while Layer C can still scroll.
                      // But when at an edge and user keeps pushing in that same
                      // direction, unlock parent so Layer B can move.
                      final canHandoffToParent =
                          (atTop && delta < 0) || (atBottom && delta > 0);
                      _setOuterScrollLock(!canHandoffToParent);
                      return false;
                    }

                    if (notification is OverscrollNotification) {
                      final metrics = notification.metrics;
                      final overscroll = notification.overscroll;
                      final atTop = metrics.pixels <= metrics.minScrollExtent + 0.5;
                      final atBottom = metrics.pixels >= metrics.maxScrollExtent - 0.5;
                      final canHandoffToParent =
                          (atTop && overscroll < 0) || (atBottom && overscroll > 0);
                      _setOuterScrollLock(!canHandoffToParent);
                      return false;
                    }

                    if (notification is ScrollEndNotification ||
                        (notification is UserScrollNotification &&
                            notification.direction == ScrollDirection.idle)) {
                      _setOuterScrollLock(false);
                    }

                    return false;
                  },
                  child: widget.content,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
