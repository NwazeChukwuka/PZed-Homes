// Location: lib/core/layout/responsive_layout.dart

import 'package:flutter/material.dart';

class ResponsiveLayout extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1400) {
          return largeDesktop ?? desktop;
        } else if (constraints.maxWidth >= 1200) {
          return desktop;
        } else if (constraints.maxWidth >= 800) {
          return tablet ?? mobile;
        } else {
          return mobile;
        }
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
    final screenWidth = MediaQuery.of(context).size.width;
    
    if (screenWidth >= 1400) {
      return largeDesktop ?? desktop ?? tablet ?? mobile;
    } else if (screenWidth >= 1200) {
      return desktop ?? tablet ?? mobile;
    } else if (screenWidth >= 800) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
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
    final screenWidth = MediaQuery.of(context).size.width;
    
    EdgeInsets padding;
    if (screenWidth >= 1400) {
      padding = largeDesktop ?? desktop ?? tablet ?? mobile ?? EdgeInsets.zero;
    } else if (screenWidth >= 1200) {
      padding = desktop ?? tablet ?? mobile ?? EdgeInsets.zero;
    } else if (screenWidth >= 800) {
      padding = tablet ?? mobile ?? EdgeInsets.zero;
    } else {
      padding = mobile ?? EdgeInsets.zero;
    }

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
    final screenWidth = MediaQuery.of(context).size.width;
    
    int columns;
    if (screenWidth >= 1400) {
      columns = largeDesktopColumns ?? desktopColumns ?? tabletColumns ?? mobileColumns ?? 1;
    } else if (screenWidth >= 1200) {
      columns = desktopColumns ?? tabletColumns ?? mobileColumns ?? 1;
    } else if (screenWidth >= 800) {
      columns = tabletColumns ?? mobileColumns ?? 1;
    } else {
      columns = mobileColumns ?? 1;
    }

    return Wrap(
      spacing: spacing ?? 16.0,
      runSpacing: runSpacing ?? 16.0,
      children: children.map((child) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 
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
    final screenWidth = MediaQuery.of(context).size.width;
    
    TextStyle? style;
    if (screenWidth >= 1400) {
      style = largeDesktopStyle ?? desktopStyle ?? tabletStyle ?? mobileStyle;
    } else if (screenWidth >= 1200) {
      style = desktopStyle ?? tabletStyle ?? mobileStyle;
    } else if (screenWidth >= 800) {
      style = tabletStyle ?? mobileStyle;
    } else {
      style = mobileStyle;
    }

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
    final screenWidth = MediaQuery.of(context).size.width;
    
    double spacing;
    if (screenWidth >= 1400) {
      spacing = largeDesktop ?? desktop ?? tablet ?? mobile ?? 0.0;
    } else if (screenWidth >= 1200) {
      spacing = desktop ?? tablet ?? mobile ?? 0.0;
    } else if (screenWidth >= 800) {
      spacing = tablet ?? mobile ?? 0.0;
    } else {
      spacing = mobile ?? 0.0;
    }

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

// Breakpoint constants
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 800;
  static const double desktop = 1200;
  static const double largeDesktop = 1400;
}

// Responsive helper functions
class ResponsiveHelper {
  static bool isMobile(BuildContext context) {
    return MediaQuery.of(context).size.width < Breakpoints.mobile;
  }

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= Breakpoints.mobile && width < Breakpoints.tablet;
  }

  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= Breakpoints.tablet && width < Breakpoints.desktop;
  }

  static bool isLargeDesktop(BuildContext context) {
    return MediaQuery.of(context).size.width >= Breakpoints.desktop;
  }

  static T responsiveValue<T>(
    BuildContext context, {
    required T mobile,
    T? tablet,
    T? desktop,
    T? largeDesktop,
  }) {
    final width = MediaQuery.of(context).size.width;
    
    if (width >= Breakpoints.largeDesktop) {
      return largeDesktop ?? desktop ?? tablet ?? mobile;
    } else if (width >= Breakpoints.desktop) {
      return desktop ?? tablet ?? mobile;
    } else if (width >= Breakpoints.tablet) {
      return tablet ?? mobile;
    } else {
      return mobile;
    }
  }
}
