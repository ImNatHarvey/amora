import 'package:flutter/material.dart';

/// Which piece of brand art to draw.
enum BrandArt {
  /// The wordless mark. Used wherever the app has to identify itself in a
  /// small space — the splash, an empty state's header.
  logo('assets/brand/logo.png'),

  /// The character. Used where the app is speaking to the user rather than
  /// labelling itself — the splash's animation, a friendly empty state.
  mascot('assets/brand/mascot.png');

  const BrandArt(this.asset);

  final String asset;
}

/// Brand art in a box of a fixed size.
///
/// **This exists so that replacing the placeholder art is one file and no
/// layout change.** The box is sized by [size] and the image is drawn with
/// `BoxFit.contain`, so art of any aspect ratio lands inside the same square
/// and nothing around it moves. Drop a new PNG at the same path, keep it
/// square, and every screen that uses it is already correct.
///
/// Both files are 512×512 transparent PNGs. See `assets/brand/README.md`.
///
/// The current art is a generated placeholder — a monogram and a round face —
/// and is meant to be replaced.
class BrandMark extends StatelessWidget {
  const BrandMark({
    required this.art,
    this.size = 96,
    this.semanticLabel,
    super.key,
  });

  final BrandArt art;

  /// The side of the square the art is drawn into. The art never exceeds it in
  /// either dimension, whatever its aspect ratio.
  final double size;

  /// Null for decoration, which is the usual case — the logo beside the word
  /// "Amora" is not information a screen reader needs twice.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        art.asset,
        fit: BoxFit.contain,
        semanticLabel: semanticLabel,
        excludeFromSemantics: semanticLabel == null,
        // A missing asset must not take the screen down — it is art, and the
        // app is legible without it. Reserving the box keeps the layout
        // identical either way, which is the same promise BoxFit.contain makes
        // about a differently-shaped replacement.
        errorBuilder: (context, error, stack) => const SizedBox.shrink(),
      ),
    );
  }
}
