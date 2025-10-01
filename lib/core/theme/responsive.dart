// Location: lib/core/theme/responsive.dart

import 'package:flutter/material.dart';

class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double largeDesktop = 1600;
}

class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget? desktop;
  final Widget? largeDesktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
    this.largeDesktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= ResponsiveBreakpoints.largeDesktop) {
          return largeDesktop ?? desktop ?? tablet ?? mobile;
        } else if (constraints.maxWidth >= ResponsiveBreakpoints.desktop) {
          return desktop ?? tablet ?? mobile;
        } else if (constraints.maxWidth >= ResponsiveBreakpoints.tablet) {
          return tablet ?? mobile;
        } else {
          return mobile;
        }
      },
    );
  }
}

class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, ResponsiveBreakpoint breakpoint) builder;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breakpoint = _getBreakpoint(constraints.maxWidth);
        return builder(context, breakpoint);
      },
    );
  }

  ResponsiveBreakpoint _getBreakpoint(double width) {
    if (width >= ResponsiveBreakpoints.largeDesktop) {
      return ResponsiveBreakpoint.largeDesktop;
    } else if (width >= ResponsiveBreakpoints.desktop) {
      return ResponsiveBreakpoint.desktop;
    } else if (width >= ResponsiveBreakpoints.tablet) {
      return ResponsiveBreakpoint.tablet;
    } else {
      return ResponsiveBreakpoint.mobile;
    }
  }
}

enum ResponsiveBreakpoint {
  mobile,
  tablet,
  desktop,
  largeDesktop,
}

extension ResponsiveBreakpointExtension on ResponsiveBreakpoint {
  bool get isMobile => this == ResponsiveBreakpoint.mobile;
  bool get isTablet => this == ResponsiveBreakpoint.tablet;
  bool get isDesktop => this == ResponsiveBreakpoint.desktop;
  bool get isLargeDesktop => this == ResponsiveBreakpoint.largeDesktop;
  
  bool get isMobileOrTablet => isMobile || isTablet;
  bool get isDesktopOrLarger => isDesktop || isLargeDesktop;
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final int mobileColumns;
  final int? tabletColumns;
  final int? desktopColumns;
  final int? largeDesktopColumns;
  final double spacing;
  final double runSpacing;

  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns,
    this.desktopColumns,
    this.largeDesktopColumns,
    this.spacing = 16.0,
    this.runSpacing = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, breakpoint) {
        int columns = mobileColumns;
        
        switch (breakpoint) {
          case ResponsiveBreakpoint.mobile:
            columns = mobileColumns;
            break;
          case ResponsiveBreakpoint.tablet:
            columns = tabletColumns ?? (mobileColumns * 2).clamp(1, 4);
            break;
          case ResponsiveBreakpoint.desktop:
            columns = desktopColumns ?? (mobileColumns * 3).clamp(1, 6);
            break;
          case ResponsiveBreakpoint.largeDesktop:
            columns = largeDesktopColumns ?? (mobileColumns * 4).clamp(1, 8);
            break;
        }

        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: runSpacing,
            childAspectRatio: 1.0,
          ),
          itemCount: children.length,
          itemBuilder: (context, index) => children[index],
        );
      },
    );
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
    return ResponsiveBuilder(
      builder: (context, breakpoint) {
        EdgeInsets padding;
        
        switch (breakpoint) {
          case ResponsiveBreakpoint.mobile:
            padding = mobile ?? const EdgeInsets.all(16.0);
            break;
          case ResponsiveBreakpoint.tablet:
            padding = tablet ?? const EdgeInsets.all(24.0);
            break;
          case ResponsiveBreakpoint.desktop:
            padding = desktop ?? const EdgeInsets.all(32.0);
            break;
          case ResponsiveBreakpoint.largeDesktop:
            padding = largeDesktop ?? const EdgeInsets.all(40.0);
            break;
        }

        return Padding(
          padding: padding,
          child: child,
        );
      },
    );
  }
}

class ResponsiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const ResponsiveText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveBuilder(
      builder: (context, breakpoint) {
        TextStyle responsiveStyle = style ?? Theme.of(context).textTheme.bodyMedium!;
        
        // Scale font size based on screen size
        double scaleFactor = 1.0;
        switch (breakpoint) {
          case ResponsiveBreakpoint.mobile:
            scaleFactor = 1.0;
            break;
          case ResponsiveBreakpoint.tablet:
            scaleFactor = 1.1;
            break;
          case ResponsiveBreakpoint.desktop:
            scaleFactor = 1.2;
            break;
          case ResponsiveBreakpoint.largeDesktop:
            scaleFactor = 1.3;
            break;
        }

        return Text(
          text,
          style: responsiveStyle.copyWith(
            fontSize: (responsiveStyle.fontSize ?? 14.0) * scaleFactor,
          ),
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: overflow,
        );
      },
    );
  }
}
