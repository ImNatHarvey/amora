import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../models/memory.dart';
import '../../theme/app_tokens.dart';
import '../../ui/error_retry.dart';
import '../../util/format.dart';
import '../../util/manila_time.dart';
import 'memory_providers.dart';

/// What actually happened, newest first.
///
/// Photo-forward per `02-design-system.md` §5 — the chrome stays quiet because
/// the user's own photographs supply the colour. This is the one screen in Amora
/// whose content the user made.
class MemoryTimelineScreen extends ConsumerWidget {
  const MemoryTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final memories = ref.watch(memoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Your memories')),
      body: SafeArea(
        child: memories.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Padding(
            padding: EdgeInsets.all(tokens.md),
            child: ErrorRetry(
              message: '$error',
              onRetry: () => ref.invalidate(memoriesProvider),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              // Never a bare "No results" (`02-design-system.md` §5): explain,
              // and offer the action that fixes it.
              return Padding(
                padding: EdgeInsets.all(tokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nothing here yet.',
                      style: theme.textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.sm),
                    Text(
                      'When you finish a plan, mark it done — what you spent '
                      'goes here, and it corrects the prices for everyone else.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    SizedBox(height: tokens.md),
                    OutlinedButton(
                      onPressed: () => context.push(Routes.plans),
                      child: const Text('Your plans'),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: EdgeInsets.all(tokens.md),
              itemCount: rows.length,
              itemBuilder: (context, i) => _MemoryCard(memory: rows[i]),
            );
          },
        ),
      ),
    );
  }
}

class _MemoryCard extends ConsumerWidget {
  const _MemoryCard({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final plannedFor = memory.plannedForUtc ?? memory.createdAtUtc;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.md),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('${Routes.plan}/${memory.planId}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (memory.photoPath != null)
                _MemoryPhoto(path: memory.photoPath!),
              Padding(
                padding: EdgeInsets.all(tokens.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      memory.planTitle ?? 'An outing',
                      style: theme.textTheme.titleMedium,
                    ),
                    SizedBox(height: tokens.xs),
                    Text(
                      formatManila(toManila(plannedFor)),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (memory.actualSpendPhpCents != null) ...[
                      SizedBox(height: tokens.sm),
                      Text(
                        // The cost of something, so ₱0 reads as "free" — the
                        // design system's position that free is good news
                        // (§2), and the rule `pesos` encodes.
                        'Spent ${pesos(memory.actualSpendPhpCents!)}',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                    if (memory.rating != null) ...[
                      SizedBox(height: tokens.xs),
                      Row(
                        children: [
                          for (var star = 1; star <= 5; star += 1)
                            Icon(
                              star <= memory.rating!
                                  ? Icons.star
                                  : Icons.star_border,
                              size: 16,
                              color: star <= memory.rating!
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                    if (memory.caption != null) ...[
                      SizedBox(height: tokens.sm),
                      Text(memory.caption!, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A stored photo, fetched through a signed URL.
///
/// **`cacheKey` is the object path, not the URL.** The bucket is private so every
/// read is a URL that expires; `CachedNetworkImage` keys its cache on the URL by
/// default, which would re-download every photo each time one was signed afresh
/// while looking for all the world like a cache.
class _MemoryPhoto extends ConsumerWidget {
  const _MemoryPhoto({required this.path});

  final String path;

  /// Fixed ratio, so a column of cards has a rhythm rather than jumping to each
  /// photo's own proportions (`02-design-system.md` §5: consistent aspect ratios).
  static const _aspect = 4 / 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = ref.watch(memoryPhotoUrlProvider(path));

    return AspectRatio(
      aspectRatio: _aspect,
      child: url.when(
        // A graceful placeholder rather than a spinner: the card's shape should
        // not change when the image lands.
        loading: () => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
        // A photo that will not load is not worth an error message on a keepsake.
        error: (_, _) => ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        data: (signed) => CachedNetworkImage(
          imageUrl: signed,
          cacheKey: path,
          fit: BoxFit.cover,
          placeholder: (_, _) =>
              ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
          errorWidget: (_, _, _) =>
              ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
        ),
      ),
    );
  }
}
