import 'package:flutter/material.dart';

/// Layout mode for hysteresis - prevents flicker when width oscillates near breakpoints.
enum _LayoutMode { mobile, tablet, desktop, largeDesktop }

class ResponsiveLayout extends StatefulWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;
  final Widget? largeDesktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
    this.largeDesktop,
  });

  @override
  State<ResponsiveLayout> createState() => _ResponsiveLayoutState();
}

class _ResponsiveLayoutState extends State<ResponsiveLayout> {
  _LayoutMode _mode = _LayoutMode.mobile;
  static const _hysteresis = 15.0; // px buffer to prevent flip at breakpoint edges

  /// Pure computation: derive next layout mode from current mode and width (hysteresis).
  _LayoutMode _computeNextMode(double w) {
    _LayoutMode next = _mode;
    switch (_mode) {
      case _LayoutMode.mobile:
        if (w >= 1200 + _hysteresis) {
          next = _LayoutMode.largeDesktop;
        } else if (w >= 800 + _hysteresis) next = _LayoutMode.desktop;
        else if (w >= 600 + _hysteresis) next = _LayoutMode.tablet;
        break;
      case _LayoutMode.tablet:
        if (w < 600 - _hysteresis) {
          next = _LayoutMode.mobile;
        } else if (w >= 800 + _hysteresis) next = _LayoutMode.desktop;
        else if (w >= 1200 + _hysteresis) next = _LayoutMode.largeDesktop;
        break;
      case _LayoutMode.desktop:
        if (w < 600 - _hysteresis) {
          next = _LayoutMode.mobile;
        } else if (w < 800 - _hysteresis) next = _LayoutMode.tablet;
        else if (w >= 1200 + _hysteresis) next = _LayoutMode.largeDesktop;
        break;
      case _LayoutMode.largeDesktop:
        if (w < 600 - _hysteresis) {
          next = _LayoutMode.mobile;
        } else if (w < 800 - _hysteresis) next = _LayoutMode.tablet;
        else if (w < 1200 - _hysteresis) next = _LayoutMode.desktop;
        break;
    }
    return next;
  }

  Widget _widgetForMode(_LayoutMode mode) {
    switch (mode) {
      case _LayoutMode.mobile:
        return widget.mobile;
      case _LayoutMode.tablet:
        return widget.tablet ?? widget.mobile;
      case _LayoutMode.desktop:
        return widget.desktop;
      case _LayoutMode.largeDesktop:
        return widget.largeDesktop ?? widget.desktop;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // Ignore invalid/transitional constraints to prevent Mobile flash on startup
        if (w <= 0) return _widgetForMode(_mode);

        final next = _computeNextMode(w);
        // Update state in post-frame callback to keep build pure (no mutation during build)
        if (next != _mode) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _mode = next);
          });
        }
        return _widgetForMode(next);
      },
    );
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, BoxConstraints constraints) builder;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: builder);
  }
}

class ResponsiveValue<T> {
  final T mobile;
  final T? tablet;
  final T? desktop;
  final T? largeDesktop;

  const ResponsiveValue({
    required this.mobile,
    this.tablet,
    this.desktop,
    this.largeDesktop,
  });

  T getValue(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1200) return largeDesktop ?? desktop ?? tablet ?? mobile;
    if (w >= 800) return desktop ?? tablet ?? mobile;
    if (w >= 600) return tablet ?? mobile;
    return mobile;
  }
}

class ResponsivePadding extends StatelessWidget {
  final Widget child;
  final EdgeInsets? mobile;
  final EdgeInsets? tablet;
  final EdgeInsets? desktop;
  final EdgeInsets? largeDesktop;

  const ResponsivePadding({
    super.key,
    required this.child,
    this.mobile,
    this.tablet,
    this.desktop,
    this.largeDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    EdgeInsets padding;
    if (w >= 1200) {
      padding = largeDesktop ?? desktop ?? tablet ?? mobile ?? EdgeInsets.zero;
    } else if (w >= 800) padding = desktop ?? tablet ?? mobile ?? EdgeInsets.zero;
    else if (w >= 600) padding = tablet ?? mobile ?? EdgeInsets.zero;
    else padding = mobile ?? EdgeInsets.zero;
    return Padding(
      padding: padding,
      child: child,
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int? mobileColumns;
  final int? tabletColumns;
  final int? desktopColumns;
  final int? largeDesktopColumns;
  final double? spacing;
  final double? runSpacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns,
    this.tabletColumns,
    this.desktopColumns,
    this.largeDesktopColumns,
    this.spacing,
    this.runSpacing,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    int columns;
    if (w >= 1200) {
      columns = largeDesktopColumns ?? desktopColumns ?? tabletColumns ?? mobileColumns ?? 1;
    } else if (w >= 800) columns = desktopColumns ?? tabletColumns ?? mobileColumns ?? 1;
    else if (w >= 600) columns = tabletColumns ?? mobileColumns ?? 1;
    else columns = mobileColumns ?? 1;

    return Wrap(
      spacing: spacing ?? 16.0,
      runSpacing: runSpacing ?? 16.0,
      children: children.map((child) {
        return SizedBox(
          width: (MediaQuery.sizeOf(context).width - 
                 (columns - 1) * (spacing ?? 16.0)) / columns,
          child: child,
        );
      }).toList(),
    );
  }
}

class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? mobileStyle;
  final TextStyle? tabletStyle;
  final TextStyle? desktopStyle;
  final TextStyle? largeDesktopStyle;
  final TextAlign? textAlign;

  const ResponsiveText(
    this.text, {
    super.key,
    this.mobileStyle,
    this.tabletStyle,
    this.desktopStyle,
    this.largeDesktopStyle,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    TextStyle? style;
    if (w >= 1200) {
      style = largeDesktopStyle ?? desktopStyle ?? tabletStyle ?? mobileStyle;
    } else if (w >= 800) style = desktopStyle ?? tabletStyle ?? mobileStyle;
    else if (w >= 600) style = tabletStyle ?? mobileStyle;
    else style = mobileStyle;

    return Text(
      text,
      style: style,
      textAlign: textAlign,
    );
  }
}

class ResponsiveSpacing extends StatelessWidget {
  final Widget child;
  final double? mobile;
  final double? tablet;
  final double? desktop;
  final double? largeDesktop;
  final Axis direction;

  const ResponsiveSpacing({
    super.key,
    required this.child,
    this.mobile,
    this.tablet,
    this.desktop,
    this.largeDesktop,
    this.direction = Axis.vertical,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    double spacing;
    if (w >= 1200) {
      spacing = largeDesktop ?? desktop ?? tablet ?? mobile ?? 0.0;
    } else if (w >= 800) spacing = desktop ?? tablet ?? mobile ?? 0.0;
    else if (w >= 600) spacing = tablet ?? mobile ?? 0.0;
    else spacing = mobile ?? 0.0;

    if (direction == Axis.vertical) {
      return Column(
        children: [
          SizedBox(height: spacing),
          child,
          SizedBox(height: spacing),
        ],
      );
    } else {
      return Row(
        children: [
          SizedBox(width: spacing),
          child,
          SizedBox(width: spacing),
        ],
      );
    }
  }
}

// Breakpoint constants - standardized: 600 mobile, 800 tablet, 1200 desktop
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 800;
  static const double desktop = 1200;
  static const double largeDesktop = 1200;
}

// Responsive helper functions
class ResponsiveHelper {
  static bool isMobile(BuildContext context) {
    return MediaQuery.sizeOf(context).width < Breakpoints.mobile;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= Breakpoints.mobile && width < Breakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= Breakpoints.tablet && width < Breakpoints.desktop;
  }

  static bool isLargeDesktop(BuildContext context) {
    return MediaQuery.sizeOf(context).width >= Breakpoints.desktop;
  }

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
    T? largeDesktop,
  }) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= Breakpoints.desktop) return largeDesktop ?? desktop ?? tablet ?? mobile;
    if (w >= Breakpoints.tablet) return desktop ?? tablet ?? mobile;
    if (w >= Breakpoints.mobile) return tablet ?? mobile;
    return mobile;
  }
}
