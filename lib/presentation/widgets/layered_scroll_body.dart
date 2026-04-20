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
                onPointerDown: (_) => _setOuterScrollLock(true),
                onPointerUp: (_) => _setOuterScrollLock(false),
                onPointerCancel: (_) => _setOuterScrollLock(false),
                onPointerSignal: (_) => _setOuterScrollLock(true),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    // Lock parent while Layer C is actively scrolling, including
                    // overscroll momentum, then release immediately at rest.
                    if (notification is ScrollStartNotification ||
                        notification is ScrollUpdateNotification ||
                        notification is OverscrollNotification) {
                      _setOuterScrollLock(true);
                    } else if (notification is ScrollEndNotification ||
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
