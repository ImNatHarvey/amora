import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../theme/app_tokens.dart';

/// How a DIY activity's `tutorial_url` can be shown.
///
/// Three states rather than two, because "no embed" and "no tutorial" are
/// different facts and rendering them the same way would be a small lie either
/// direction — a missing link would grow a dead button, or a Vimeo link would
/// vanish because it is not YouTube.
enum TutorialRender {
  /// No link collected. Render nothing at all — not a disabled button, not an
  /// empty box. Place detail already sets this precedent for absent contact
  /// numbers: an absent row, never a blank label.
  none,

  /// A YouTube link. Play it in place, and still offer to open it externally.
  embed,

  /// A link we cannot embed — another host, or a URL that does not parse.
  /// The external action is the whole of it, and it is not a degraded state:
  /// it is also what an embed-disabled YouTube video falls back to, which is
  /// the case `FIELD-CHECKLIST.md` screens for at collection time.
  linkOnly,
}

/// Decides how [url] renders, without building anything.
///
/// Pure and separate for the same reason `format.dart` and `constraint_hash.ts`
/// are: the interesting rule here is a three-way branch on data that is null on
/// every row in the database today, so a test that could only reach it through
/// a widget could not reach it at all — the embed path needs a platform webview
/// that `flutter test` does not have.
TutorialRender tutorialRenderFor(String? url) {
  if (url == null || url.trim().isEmpty) return TutorialRender.none;
  return YoutubePlayerController.convertUrlToId(url) == null
      ? TutorialRender.linkOnly
      : TutorialRender.embed;
}

/// The tutorial for one DIY activity, or nothing.
class DiyTutorial extends StatelessWidget {
  const DiyTutorial({super.key, required this.tutorialUrl});

  final String? tutorialUrl;

  @override
  Widget build(BuildContext context) {
    switch (tutorialRenderFor(tutorialUrl)) {
      case TutorialRender.none:
        return const SizedBox.shrink();
      case TutorialRender.linkOnly:
        return _OpenExternally(url: tutorialUrl!);
      case TutorialRender.embed:
        return _Embed(url: tutorialUrl!);
    }
  }
}

/// The player, plus the escape hatch under it.
///
/// The external action stays even when the embed works. It is the only thing
/// that plays a video whose owner has disabled embedding — and that failure is
/// silent, showing an error inside the iframe rather than anything Flutter can
/// catch, so there is no way to swap to the fallback after the fact.
class _Embed extends StatefulWidget {
  const _Embed({required this.url});

  final String url;

  @override
  State<_Embed> createState() => _EmbedState();
}

class _EmbedState extends State<_Embed> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      // Non-null by construction: `tutorialRenderFor` returned `embed`, which
      // is exactly the case where this parse succeeds.
      videoId: YoutubePlayerController.convertUrlToId(widget.url)!,
      // Never autoplay. A list of ideas that starts talking is a list of ideas
      // the user closes, and mobile data is not free.
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        showControls: true,
      ),
    );
  }

  @override
  void dispose() {
    // Async, and dispose cannot await. Fire it and let it finish.
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: tokens.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusMedium),
          child: YoutubePlayer(controller: _controller),
        ),
        _OpenExternally(url: widget.url),
      ],
    );
  }
}

class _OpenExternally extends StatelessWidget {
  const _OpenExternally({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    return Padding(
      padding: EdgeInsets.only(top: tokens.xs),
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ),
        child: ConstrainedBox(
          // 48 dp minimum, no exceptions (`02-design-system.md` §5).
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Watch the tutorial',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
        ),
      ),
    );
  }
}
