import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class AppAnimations {
  // Page transition animations
  static Widget slideTransition({
    required Widget child,
    required Animation<double> animation,
    SlideDirection direction = SlideDirection.left,
  }) {
    Offset begin;
    switch (direction) {
      case SlideDirection.left:
        begin = const Offset(1.0, 0.0);
        break;
      case SlideDirection.right:
        begin = const Offset(-1.0, 0.0);
        break;
      case SlideDirection.up:
        begin = const Offset(0.0, 1.0);
        break;
      case SlideDirection.down:
        begin = const Offset(0.0, -1.0);
        break;
    }

    return SlideTransition(
      position: Tween<Offset>(
        begin: begin,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      )),
      child: child,
    );
  }

  // Fade transition
  static Widget fadeTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOut,
      ),
      child: child,
    );
  }

  // Scale transition
  static Widget scaleTransition({
    required Widget child,
    required Animation<double> animation,
    double scale = 0.8,
  }) {
    return ScaleTransition(
      scale: Tween<double>(
        begin: scale,
        end: 1.0,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.elasticOut,
      )),
      child: child,
    );
  }

  /// Plain list without stagger (avoids layout/paint overhead). Use scrollable: true for drawer/sidebar.
  static Widget staggeredList({
    required List<Widget> children,
    int duration = 300,
    int delay = 100,
    bool scrollable = true,
  }) {
    if (scrollable) {
      return ListView(children: children);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// Plain grid without stagger - avoids layout/paint overhead.
  static Widget staggeredGrid({
    required List<Widget> children,
    required int crossAxisCount,
    int duration = 300,
    int delay = 100,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.0,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: children.length,
      itemBuilder: (context, index) => children[index],
    );
  }

  /// Lightweight wrapper - no animation overhead.
  static Widget animatedCard({
    required Widget child,
    Duration duration = const Duration(milliseconds: 200),
    double hoverScale = 1.05,
  }) {
    return child;
  }

  // Loading shimmer animation
  static Widget shimmer({
    required Widget child,
    Color? baseColor,
    Color? highlightColor,
  }) {
    return Shimmer.fromColors(
      baseColor: baseColor ?? Colors.grey[300]!,
      highlightColor: highlightColor ?? Colors.grey[100]!,
      child: child,
    );
  }

  // Pulse animation
  static Widget pulse({
    required Widget child,
    Duration duration = const Duration(seconds: 1),
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.2),
      duration: duration,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: child,
    );
  }

  // Bounce animation
  static Widget bounce({
    required Widget child,
    Duration duration = const Duration(milliseconds: 600),
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: child,
    );
  }

  // Slide in from bottom
  static Widget slideInFromBottom({
    required Widget child,
    Duration duration = const Duration(milliseconds: 300),
  }) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(
        begin: const Offset(0.0, 1.0),
        end: Offset.zero,
      ),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: value,
          child: child,
        );
      },
      child: child,
    );
  }

  // Counter animation
  static Widget animatedCounter({
    required int value,
    Duration duration = const Duration(milliseconds: 500),
    TextStyle? style,
  }) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Text(
          value.toString(),
          style: style,
        );
      },
    );
  }
}

enum SlideDirection {
  left,
  right,
  up,
  down,
}

// Custom page route with animations
class AnimatedPageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedPageRoute({
    required this.child,
    this.direction = SlideDirection.left,
    this.duration = const Duration(milliseconds: 300),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return AppAnimations.slideTransition(
              child: child,
              animation: animation,
              direction: direction,
            );
          },
        );
}

// Responsive animation controller
class ResponsiveAnimationController {
  static bool shouldAnimate(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return screenWidth > 600; // Only animate on larger screens
  }

  static Duration getAnimationDuration(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth > 1200) {
      return const Duration(milliseconds: 400);
    } else if (screenWidth > 800) {
      return const Duration(milliseconds: 300);
    } else {
      return const Duration(milliseconds: 200);
    }
  }
}
