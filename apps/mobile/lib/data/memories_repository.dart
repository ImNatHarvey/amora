import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/memory.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Completing a plan, listing what came of it, and reporting a shut door.
///
/// **No method here computes money.** `complete_plan` derives the plan total
/// from the per-stop figures server-side (invariant 3), and this class passes
/// through what the user typed without summing any of it.
///
/// **There are no ownership checks here.** RLS decides, in Postgres, and a second
/// implementation in Dart could only ever disagree with it — invariant 6.
class MemoriesRepository {
  const MemoriesRepository(this._client, this._picker);

  final SupabaseClient _client;
  final ImagePicker _picker;

  /// The bucket, named once. Private, so every read is a signed URL.
  static const photoBucket = 'memory-photos';

  /// Longest edge, in pixels, and JPEG quality, applied by `image_picker`
  /// natively before the bytes ever reach Dart.
  ///
  /// This is the whole of Phase 6's "compressed to ~150 KB", and it takes no new
  /// dependency: `flutter_image_compress` was removed at Phase 0 for applying the
  /// Kotlin Gradle Plugin, which future Flutter refuses to build, and re-adding it
  /// to do what the picker already does would spend a build risk on nothing.
  ///
  /// 1600 px is a generous long edge for a card that renders a few hundred
  /// logical pixels wide, and quality 70 is where JPEG stops being visibly
  /// lossy on photographs. The bucket carries a 2 MB hard ceiling as the guard
  /// against these two numbers ever being wrong — D7 has no card to fall back on
  /// if the free 1 GB fills with originals.
  static const photoMaxEdge = 1600.0;
  static const photoQuality = 70;

  /// Marks a plan completed and records what actually happened.
  ///
  /// [stopSpends] and [legFares] carry **one-based** `seq`, matching what
  /// `read_plan` emits and therefore what the screen is already holding.
  /// `complete_plan` does the conversion to the tables' zero-based columns in one
  /// place, and raises on a seq the plan does not have rather than dropping a
  /// figure the user typed.
  ///
  /// Every amount is what the **party** handed over, because that is the only
  /// figure a person actually knows. The server divides by `party_size` before
  /// storing a per-place report, so that it is comparable with the seeded
  /// per-person price (§9) — do not divide here, or it will happen twice.
  Future<Memory> complete({
    required String planId,
    required List<Map<String, dynamic>> stopSpends,
    required List<Map<String, dynamic>> legFares,
    int? rating,
    String? caption,
    String? photoPath,
  }) {
    return guard(
      () async {
        final payload = await _client.rpc<Map<String, dynamic>>(
          'complete_plan',
          params: {
            'p_plan_id': planId,
            'p_stop_spends': stopSpends,
            'p_leg_fares': legFares,
            'p_rating': rating,
            'p_caption': caption,
            'p_photo_path': photoPath,
          },
        );
        return Memory.fromMap(payload);
      },
      fallback: 'Could not save how it went.',
    );
  }

  /// The signed-in user's memories, newest first.
  ///
  /// The plan is embedded rather than fetched per row — a timeline of twenty
  /// memories would otherwise be twenty-one round trips for a title and a date.
  Future<List<Memory>> listMine() {
    return guard(
      () async {
        final rows = await _client
            .from('memories')
            .select('id, plan_id, photo_path, caption, actual_spend_php_cents, '
                'rating, created_at, plans(title, planned_for)')
            .order('created_at', ascending: false);

        return rows.map(Memory.fromMap).toList();
      },
      fallback: 'Could not load your memories.',
    );
  }

  /// Records that a place was shut.
  ///
  /// Deliberately possible from a plan that has not been completed, and from no
  /// plan at all. §10.2: the couple who finds a locked door abandons the plan and
  /// never completes it, so any precondition here blinds us to the failure that
  /// costs the most — and it is the one failure no amount of hand-verification
  /// can prevent, because a place can close the week after it was checked.
  Future<String> reportClosure({
    required String placeId,
    String? planId,
    String? note,
  }) {
    return guard(
      () async {
        return await _client.rpc<String>(
          'report_closure',
          params: {
            'p_place_id': placeId,
            'p_plan_id': planId,
            'p_note': note,
          },
        );
      },
      fallback: 'Could not report that.',
    );
  }

  /// Asks for a photo and compresses it. Null when the user backs out.
  ///
  /// Returns the [XFile] rather than uploading straight away so the sheet can
  /// show what was picked and let it be replaced before anything is written. An
  /// upload on pick would leave an orphaned object in the bucket every time
  /// somebody changed their mind.
  Future<XFile?> pickPhoto({required ImageSource source}) {
    return guard(
      () => _picker.pickImage(
        source: source,
        maxWidth: photoMaxEdge,
        maxHeight: photoMaxEdge,
        imageQuality: photoQuality,
      ),
      fallback: 'Could not open the camera.',
    );
  }

  /// Uploads [photo] and returns its object path — never a URL.
  ///
  /// The path is `<uid>/<planId>-<epoch>.jpg`, and the leading uid is not
  /// cosmetic: the bucket's policies compare it to `auth.uid()`, so the layout
  /// *is* the authorization rule. The epoch means picking a second photo for the
  /// same plan writes a new object instead of silently replacing one.
  Future<String> uploadPhoto({
    required String planId,
    required XFile photo,
  }) {
    return guard(
      () async {
        final uid = _client.auth.currentUser?.id;
        if (uid == null) {
          throw const RepositoryException('Sign in again to save a photo.');
        }

        final bytes = await photo.readAsBytes();
        final path = '$uid/$planId-${DateTime.now().millisecondsSinceEpoch}.jpg';

        await _client.storage.from(photoBucket).uploadBinary(
              path,
              bytes,
              // The bucket allows image/jpeg only, which is what the picker
              // emits. Stated rather than inferred: the default is
              // application/octet-stream, which the allowlist would refuse.
              fileOptions: const FileOptions(contentType: 'image/jpeg'),
            );

        return path;
      },
      fallback: 'Could not upload that photo.',
    );
  }

  /// A temporary URL for a stored photo.
  ///
  /// The bucket is private, so there is no permanent URL to keep — which is why
  /// `memories.photo_path` stores a path. Widgets rendering this **must** pass
  /// the path as `CachedNetworkImage`'s `cacheKey`: the cache keys on the URL by
  /// default, and a URL that rotates hourly would re-download every photo on
  /// every scroll while appearing to be cached.
  Future<String> signedPhotoUrl(String path, {int expiresInSeconds = 3600}) {
    return guard(
      () => _client.storage
          .from(photoBucket)
          .createSignedUrl(path, expiresInSeconds),
      fallback: 'Could not load that photo.',
    );
  }
}

final memoriesRepositoryProvider = Provider<MemoriesRepository>(
  (ref) => MemoriesRepository(ref.watch(supabaseClientProvider), ImagePicker()),
);
