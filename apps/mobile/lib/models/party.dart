/// How many people a plan is for.
///
/// One constant, deliberately, because this is the multiplier that turns the
/// per-person prices in `places` and `activities` into what the outing actually
/// costs (`docs/00-architecture.md` §9). It briefly lived in two repositories,
/// which meant two sources of truth for the same arithmetic — and the whole
/// reason §9 was written was that two halves of the codebase had quietly
/// disagreed about what a price meant. Two copies of the fix would have been
/// the same bug wearing a different hat.
///
/// Two while D1 scopes the MVP to couples. When friends and families arrive
/// (§11) this stops being a constant and becomes `plans.party_size`, read per
/// plan — which is exactly why every call site already passes it as a value
/// rather than reaching for a global.
abstract final class Party {
  /// D1: couples. The server takes this as a parameter and defaults to the same
  /// number, so a request that omits it is not silently costed for one person.
  static const size = 2;
}
