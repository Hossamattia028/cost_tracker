import 'package:flutter/material.dart';

import 'app_logo.dart';

/// Shared logo + title sizing used on home, login, and splash screens.
abstract final class AppBranding {
  static const double logoSize = 28;
  static const double titleSpacing = 10;
}

class AppLogoTitle extends StatelessWidget {
  final String title;
  final TextStyle? titleStyle;
  final bool vertical;

  const AppLogoTitle({
    super.key,
    required this.title,
    this.titleStyle,
    this.vertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = titleStyle ?? _defaultTitleStyle(context);

    final gap = vertical
        ? const SizedBox(height: AppBranding.titleSpacing)
        : const SizedBox(width: AppBranding.titleSpacing);

    final children = [
      const AppLogo(size: AppBranding.logoSize),
      gap,
      Text(title, style: style),
    ];

    if (vertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }

  TextStyle? _defaultTitleStyle(BuildContext context) {
    if (vertical) {
      return Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          );
    }
    return Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;
  }
}
