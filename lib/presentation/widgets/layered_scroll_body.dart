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

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior(),
      child: CustomScrollView(
        primary: true,
        slivers: [
          SliverToBoxAdapter(child: topSection),
          SliverFillRemaining(
            hasScrollBody: true,
            child: PrimaryScrollController.none(
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}
