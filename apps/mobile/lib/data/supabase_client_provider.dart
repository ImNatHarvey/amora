import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when `.env` is missing or incomplete.
///
/// This is the first thing that breaks on a fresh clone, so it fails with an
/// instruction rather than a null-dereference somewhere further in.
class MissingEnvException implements Exception {
  const MissingEnvException(this.key);

  final String key;

  @override
  String toString() =>
      'Missing $key. Copy apps/mobile/.env.example to apps/mobile/.env and '
      'fill it in from the Supabase dashboard (Project Settings > API).';
}

/// Reads and validates the app's environment configuration.
///
/// Only the Supabase URL and publishable key live here. The Gemini key is never
/// one of these — it stays in Supabase Edge Function secrets and never reaches
/// the device (CLAUDE.md invariant 4).
abstract final class AmoraEnv {
  static String get supabaseUrl => _require('SUPABASE_URL');

  /// The publishable (formerly "anon") key. Safe to ship in the APK: it is a
  /// public identifier, and Row Level Security is what actually guards the
  /// data.
  static String get supabasePublishableKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) throw MissingEnvException(key);
    return value;
  }
}

/// Loads `.env` and initialises Supabase. Call once, before `runApp`.
Future<void> initialiseSupabase() async {
  await dotenv.load();
  await Supabase.initialize(
    url: AmoraEnv.supabaseUrl,
    // `anonKey` is deprecated in supabase_flutter 2.16; `publishableKey` is the
    // supported parameter and accepts the newer `sb_publishable_` format.
    publishableKey: AmoraEnv.supabasePublishableKey,
  );
}

/// The single app-wide Supabase client.
///
/// Every repository in `lib/data/` takes its client from here. No widget reads
/// `Supabase.instance.client` directly — see `docs/00-architecture.md` §4.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
