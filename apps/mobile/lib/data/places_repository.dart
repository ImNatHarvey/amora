import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/place.dart';
import '../models/place_note.dart';
import 'repository_exception.dart';
import 'supabase_client_provider.dart';

/// Reading one place, on its own.
///
/// §4's note said to split this out of `retrieval_repository.dart` "the day
/// something genuinely needs to read places on their own". Phase 4's place
/// detail is that day: retrieval returns the fields a plan needs, and detail
/// needs the ones it does not — address, contact, social, notes and provenance.
///
/// Still no raw queries in widgets (CLAUDE.md), and RLS still decides what comes
/// back: a `user_submitted` place belonging to someone else is simply not there.
class PlacesRepository {
  const PlacesRepository(this._client);

  final SupabaseClient _client;

  /// One place with everything the detail screen shows. Null when it does not
  /// exist or RLS hides it.
  Future<Place?> byId(String id) {
    return guard(
      () async {
        final row = await _client
            .from('places')
            .select('id, slug, name, category, lat, lng, barangay, address, '
                'opening_hours, price_min_php_cents, price_max_php_cents, '
                'contact_number, social_url, notes, verified_on, '
                'verified_method')
            .eq('id', id)
            .maybeSingle();

        return row == null ? null : Place.fromMap(row);
      },
      fallback: 'Could not open that place.',
    );
  }

  /// Its notes, newest first.
  ///
  /// A separate call rather than an embedded join: the notes are a list of
  /// unknown length and the place is one row, and combining them would make the
  /// place model carry a collection it does not need everywhere else.
  Future<List<PlaceNote>> notesFor(String placeId) {
    return guard(
      () async {
        final rows = await _client
            .from('place_notes')
            .select('id, body, source_label, added_at')
            .eq('place_id', placeId)
            .order('added_at', ascending: false);

        return rows.map(PlaceNote.fromMap).toList();
      },
      fallback: 'Could not load what people have said about this place.',
    );
  }
}

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => PlacesRepository(ref.watch(supabaseClientProvider)),
);

final placeProvider = FutureProvider.family<Place?, String>(
  (ref, id) => ref.watch(placesRepositoryProvider).byId(id),
);

final placeNotesProvider = FutureProvider.family<List<PlaceNote>, String>(
  (ref, id) => ref.watch(placesRepositoryProvider).notesFor(id),
);
