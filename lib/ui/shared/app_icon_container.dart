import 'package:flutter/material.dart';

class AppIconContainer extends StatelessWidget {
  const AppIconContainer({
    super.key,
    required this.icon,
    this.semanticLabel,
    this.size = 44,
    this.iconSize = 20,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String? semanticLabel;
  final double size;
  final double iconSize;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? scheme.primaryContainer,
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: foregroundColor ?? scheme.onPrimaryContainer,
        ),
      ),
    );

    final label = semanticLabel;
    if (label == null) return child;
    return Semantics(
      label: label,
      child: ExcludeSemantics(child: child),
    );
  }
}
