import 'package:flutter/material.dart';

/// Layer B + C scroll contract for management screens:
/// - [topSection] scrolls away with the page.
/// - [content] keeps its own local scroll behavior.
class LayeredScrollBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (isLoading) {
      return loadingWidget ?? const Center(child: CircularProgressIndicator());
    }

    final scrollbarTheme = ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0xFFC9A227)),
      trackColor: WidgetStateProperty.all(const Color(0xFFF8E9B0)),
      trackBorderColor: WidgetStateProperty.all(const Color(0xFFE6C96A)),
      thickness: WidgetStateProperty.all(10),
      radius: const Radius.circular(8),
      thumbVisibility: WidgetStateProperty.all(true),
      trackVisibility: WidgetStateProperty.all(true),
    );

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior(),
      child: CustomScrollView(
        primary: true,
        slivers: [
          SliverToBoxAdapter(child: topSection),
          SliverFillRemaining(
            hasScrollBody: true,
            child: ScrollbarTheme(
              data: scrollbarTheme,
              child: Scrollbar(
                thumbVisibility: true,
                trackVisibility: true,
                interactive: true,
                notificationPredicate: (_) => true,
                child: PrimaryScrollController.none(
                  child: content,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
