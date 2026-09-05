import 'package:flutter/material.dart';

import 'tokens.dart';

/// The supplied Jentra artwork. The PNG remains byte-for-byte unchanged.
///
/// [size] is the rendered height. [compact] removes transparent canvas margins
/// through layout clipping, preserving the original artwork's aspect ratio.
/// [inverse] adds a light backing for standalone icons on dark surfaces.
class JentraBrandMark extends StatelessWidget {
  const JentraBrandMark({
    this.size = 40,
    this.compact = true,
    this.inverse = false,
    this.semanticsLabel = 'Jentra OS',
    super.key,
  }) : assert(size > 0);

  static const asset = 'assets/brand/jentra-mark.png';
  static const assetPackage = 'jentra_design_system';

  final double size;
  final bool compact;
  final bool inverse;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    // Transparent-only crop: x246..1008, y188..1112 in the 1254px original.
    // The additional clearspace keeps every antialiased edge inside the clip.
    final scale = compact ? size / 924 : size / 1254;
    final image = Image.asset(
      asset,
      package: assetPackage,
      width: 1254 * scale,
      height: 1254 * scale,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final mark = SizedBox(
      width: compact ? 762 * scale : size,
      height: size,
      child: compact
          ? ClipRect(
              child: OverflowBox(
                alignment: const Alignment(0, 0.1393939394),
                minWidth: 1254 * scale,
                maxWidth: 1254 * scale,
                minHeight: 1254 * scale,
                maxHeight: 1254 * scale,
                child: image,
              ),
            )
          : image,
    );
    return Semantics(
      image: semanticsLabel != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: inverse
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: JentraColors.appBackground,
                borderRadius: BorderRadius.circular(size * 0.22),
              ),
              child: Padding(padding: EdgeInsets.all(size * 0.14), child: mark),
            )
          : mark,
    );
  }
}

/// The exact lettering from the user's supplied logo board.
///
/// Layout clips the original image to the appropriate light/dark wordmark.
/// No font substitution or redrawing is involved, and the source is unchanged.
class JentraBrandWordmark extends StatelessWidget {
  const JentraBrandWordmark({
    this.height = 24,
    this.inverse = false,
    this.showTagline = false,
    this.semanticsLabel = 'Jentra OS',
    super.key,
  }) : assert(height > 0);

  static const asset = 'assets/brand/jentra-logo-board.png';
  final double height;
  final bool inverse;
  final bool showTagline;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final crop = inverse
        ? Rect.fromLTWH(266, 820, 310, showTagline ? 77 : 50)
        : Rect.fromLTWH(94, 509, 562, showTagline ? 126 : 81);
    // Height refers to the lettering; the original tagline adds its own space.
    final scale = height / (inverse ? 50 : 81);
    return Semantics(
      image: semanticsLabel != null,
      label: semanticsLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: crop.width * scale,
        height: crop.height * scale,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment(
              2 * crop.left / (1536 - crop.width) - 1,
              2 * crop.top / (1024 - crop.height) - 1,
            ),
            minWidth: 1536 * scale,
            maxWidth: 1536 * scale,
            minHeight: 1024 * scale,
            maxHeight: 1024 * scale,
            child: ColorFiltered(
              // Make the board's matte transparent at presentation time.
              // RGB and the original letter shapes remain sourced from the PNG.
              colorFilter: ColorFilter.matrix([
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                0,
                0,
                1,
                0,
                0,
                if (inverse) ...[
                  1,
                  1,
                  1,
                  0,
                  -76.5,
                ] else ...[
                  -1,
                  -1,
                  -1,
                  0,
                  765,
                ],
              ]),
              child: Image.asset(
                asset,
                package: JentraBrandMark.assetPackage,
                width: 1536 * scale,
                height: 1024 * scale,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The original symbol paired with the original artwork wordmark.
class JentraBrandLockup extends StatelessWidget {
  const JentraBrandLockup({
    this.size = 36,
    this.compact = false,
    this.inverse = false,
    this.showTagline = false,
    super.key,
  }) : assert(size > 0);

  final double size;
  final bool compact;
  final bool inverse;
  final bool showTagline;

  @override
  Widget build(BuildContext context) => Semantics(
    label: showTagline && !compact
        ? 'Jentra OS. Operate. Connect. Grow.'
        : 'Jentra OS',
    image: true,
    excludeSemantics: true,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          JentraBrandMark(size: size, semanticsLabel: null),
          if (!compact) ...[
            SizedBox(width: size * 0.30),
            JentraBrandWordmark(
              height: size * 0.58,
              inverse: inverse,
              showTagline: showTagline,
              semanticsLabel: null,
            ),
          ],
        ],
      ),
    ),
  );
}
