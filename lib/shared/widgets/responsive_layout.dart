import 'package:flutter/material.dart';

class ResponsivePage extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ResponsivePage({super.key, required this.child, this.maxWidth = 1200});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SafeArea(
      top: false,
      bottom: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    ),
  );
}

class ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  final double breakpoint;
  final double spacing;
  const ResponsiveRow({
    super.key,
    required this.children,
    this.breakpoint = 600,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth <
          breakpoint * MediaQuery.textScalerOf(context).scale(14) / 14;
      return Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              SizedBox(
                width: stacked ? 0 : spacing,
                height: stacked ? spacing : 0,
              ),
            if (stacked) children[index] else Expanded(child: children[index]),
          ],
        ],
      );
    },
  );
}

class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 180,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scaledWidth =
          minItemWidth * MediaQuery.textScalerOf(context).scale(14) / 14;
      final columns = ((constraints.maxWidth + 12) / (scaledWidth + 12))
          .floor()
          .clamp(1, children.length.clamp(1, 6));
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class ScrollableEmptyState extends StatelessWidget {
  final Widget child;
  const ScrollableEmptyState({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  );
}
