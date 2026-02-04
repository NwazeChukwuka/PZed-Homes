import 'package:flutter/material.dart';

/// A reusable scrollable widget with visible scroll arrows (up/down buttons)
/// Automatically applies to any scrollable content
class ScrollableListWithArrows extends StatefulWidget {
  final Widget child;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final double scrollStep;
  final Color? arrowColor;
  final Color? arrowBackgroundColor;
  final double arrowSize;
  final bool showScrollbar;

  const ScrollableListWithArrows({
    super.key,
    required this.child,
    this.controller,
    this.padding,
    this.scrollStep = 100.0,
    this.arrowColor,
    this.arrowBackgroundColor,
    this.arrowSize = 32.0,
    this.showScrollbar = true,
  });

  @override
  State<ScrollableListWithArrows> createState() => _ScrollableListWithArrowsState();
}

class _ScrollableListWithArrowsState extends State<ScrollableListWithArrows> {
  late ScrollController _scrollController;
  bool _showUpArrow = false;
  bool _showDownArrow = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_updateArrowVisibility);
    // Initial check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrowVisibility());
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_updateArrowVisibility);
    }
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!_scrollController.hasClients) {
      setState(() {
        _showUpArrow = false;
        _showDownArrow = false;
      });
      return;
    }

    final position = _scrollController.position;
    final showUp = position.pixels > 0;
    final showDown = position.pixels < position.maxScrollExtent;

    if (showUp != _showUpArrow || showDown != _showDownArrow) {
      setState(() {
        _showUpArrow = showUp;
        _showDownArrow = showDown;
      });
    }
  }

  void _scrollUp() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        (_scrollController.offset - widget.scrollStep).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollDown() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        (_scrollController.offset + widget.scrollStep).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final arrowColor = widget.arrowColor ?? Colors.grey[700]!;
    final arrowBgColor = widget.arrowBackgroundColor ?? Colors.white.withOpacity(0.9);

    return Stack(
      children: [
        // Main scrollable content
        widget.showScrollbar
            ? Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: widget.padding,
                  child: widget.child,
                ),
              )
            : SingleChildScrollView(
                controller: _scrollController,
                padding: widget.padding,
                child: widget.child,
              ),
        // Up arrow button
        if (_showUpArrow)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(widget.arrowSize / 2),
              color: arrowBgColor,
              child: InkWell(
                onTap: _scrollUp,
                borderRadius: BorderRadius.circular(widget.arrowSize / 2),
                child: Container(
                  width: widget.arrowSize,
                  height: widget.arrowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: arrowColor.withOpacity(0.3), width: 1),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    color: arrowColor,
                    size: widget.arrowSize * 0.6,
                  ),
                ),
              ),
            ),
          ),
        // Down arrow button
        if (_showDownArrow)
          Positioned(
            bottom: 8,
            right: 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(widget.arrowSize / 2),
              color: arrowBgColor,
              child: InkWell(
                onTap: _scrollDown,
                borderRadius: BorderRadius.circular(widget.arrowSize / 2),
                child: Container(
                  width: widget.arrowSize,
                  height: widget.arrowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: arrowColor.withOpacity(0.3), width: 1),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: arrowColor,
                    size: widget.arrowSize * 0.6,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A scrollable ListView with arrows
class ScrollableListViewWithArrows extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final double scrollStep;
  final Color? arrowColor;
  final Color? arrowBackgroundColor;
  final double arrowSize;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const ScrollableListViewWithArrows({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.scrollStep = 100.0,
    this.arrowColor,
    this.arrowBackgroundColor,
    this.arrowSize = 32.0,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    return _ScrollableListViewWithArrowsStateful(
      itemCount: itemCount,
      itemBuilder: itemBuilder,
      controller: controller,
      padding: padding,
      scrollStep: scrollStep,
      arrowColor: arrowColor,
      arrowBackgroundColor: arrowBackgroundColor,
      arrowSize: arrowSize,
      shrinkWrap: shrinkWrap,
      physics: physics,
    );
  }
}

class _ScrollableListViewWithArrowsStateful extends StatefulWidget {
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;
  final ScrollController? controller;
  final EdgeInsets? padding;
  final double scrollStep;
  final Color? arrowColor;
  final Color? arrowBackgroundColor;
  final double arrowSize;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const _ScrollableListViewWithArrowsStateful({
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.scrollStep = 100.0,
    this.arrowColor,
    this.arrowBackgroundColor,
    this.arrowSize = 32.0,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  State<_ScrollableListViewWithArrowsStateful> createState() => _ScrollableListViewWithArrowsStatefulState();
}

class _ScrollableListViewWithArrowsStatefulState extends State<_ScrollableListViewWithArrowsStateful> {
  late ScrollController _scrollController;
  bool _showUpArrow = false;
  bool _showDownArrow = false;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_updateArrowVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrowVisibility());
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_updateArrowVisibility);
    }
    super.dispose();
  }

  void _updateArrowVisibility() {
    if (!_scrollController.hasClients) {
      setState(() {
        _showUpArrow = false;
        _showDownArrow = false;
      });
      return;
    }

    final position = _scrollController.position;
    final showUp = position.pixels > 0;
    final showDown = position.pixels < position.maxScrollExtent;

    if (showUp != _showUpArrow || showDown != _showDownArrow) {
      setState(() {
        _showUpArrow = showUp;
        _showDownArrow = showDown;
      });
    }
  }

  void _scrollUp() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        (_scrollController.offset - widget.scrollStep).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollDown() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        (_scrollController.offset + widget.scrollStep).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final arrowColor = widget.arrowColor ?? Colors.grey[700]!;
    final arrowBgColor = widget.arrowBackgroundColor ?? Colors.white.withOpacity(0.9);

    return Stack(
      children: [
        // Main ListView
        Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            padding: widget.padding,
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
            shrinkWrap: widget.shrinkWrap,
            physics: widget.physics ?? const AlwaysScrollableScrollPhysics(),
          ),
        ),
        // Up arrow button
        if (_showUpArrow)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(widget.arrowSize / 2),
              color: arrowBgColor,
              child: InkWell(
                onTap: _scrollUp,
                borderRadius: BorderRadius.circular(widget.arrowSize / 2),
                child: Container(
                  width: widget.arrowSize,
                  height: widget.arrowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: arrowColor.withOpacity(0.3), width: 1),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_up,
                    color: arrowColor,
                    size: widget.arrowSize * 0.6,
                  ),
                ),
              ),
            ),
          ),
        // Down arrow button
        if (_showDownArrow)
          Positioned(
            bottom: 8,
            right: 8,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(widget.arrowSize / 2),
              color: arrowBgColor,
              child: InkWell(
                onTap: _scrollDown,
                borderRadius: BorderRadius.circular(widget.arrowSize / 2),
                child: Container(
                  width: widget.arrowSize,
                  height: widget.arrowSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: arrowColor.withOpacity(0.3), width: 1),
                  ),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: arrowColor,
                    size: widget.arrowSize * 0.6,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
