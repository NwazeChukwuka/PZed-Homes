import 'package:flutter/material.dart';

/// Lightweight guest shell.
/// It intentionally excludes staff navigation chrome and dashboard widgets.
class GuestScaffold extends StatelessWidget {
  final Widget child;

  const GuestScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // Most guest pages already provide their own Scaffold.
    if (child is Scaffold) return child;
    return Scaffold(body: child);
  }
}
