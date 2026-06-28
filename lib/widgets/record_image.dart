import 'package:flutter/material.dart';
import 'app_logo.dart';
import 'full_screen_image_dialog.dart';

class RecordImage extends StatelessWidget {
  const RecordImage({
    super.key,
    required this.imageUrl,
    this.width = 72,
    this.height = 72,
    this.onTap,
    this.enableFullScreen = true,
  });

  final String imageUrl;
  final double width;
  final double height;
  final VoidCallback? onTap;
  final bool enableFullScreen;

  bool get _hasImage => imageUrl.isNotEmpty;

  Widget _logoPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logoSize = width < height ? width : height;

    return Container(
      width: width,
      height: height,
      color: cs.secondaryContainer,
      alignment: Alignment.center,
      child: AppLogo(size: logoSize * 0.72),
    );
  }

  Widget _imageContent(BuildContext context) {
    if (!_hasImage) return _logoPlaceholder(context);

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return _logoPlaceholder(context);
      },
      errorBuilder: (_, __, ___) => _logoPlaceholder(context),
    );
  }

  void _handleTap(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    if (enableFullScreen) {
      FullScreenImageDialog.show(context, imageUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enableFullScreen || onTap != null
            ? () => _handleTap(context)
            : null,
        borderRadius: BorderRadius.circular(10),
        child: _imageContent(context),
      ),
    );
  }
}
