import 'campaign.dart';
import 'champion_progress.dart';
import 'endless_balance.dart';
import 'game_int.dart';

/// Revision 1: independent defense/encounter indices on the shared power curve.
/// Enemy damage never reads the victim's stats or the current room wave.
abstract final class ChampionHealthRules {
  static const revision = 1;
  static const protectionSeconds = 1.25;

  /// x = 4(L-1) + 2E. Both level and Endurance keep contributing without a cap.
  static GameInt defenseIndex(ChampionLoadout loadout) =>
      (loadout.progressionLevel.max(1) - 1) * 40 +
      GameInt(loadout.endurance).max(0) * 20;

  static GameInt maximum(ChampionLoadout loadout) =>
      EndlessBalance.scaled(const GameInt(100), defenseIndex(loadout));

  static GameInt incoming({
    required MonsterKind kind,
    required int depth,
    bool elite = false,
    bool charging = false,
    double variantDamage = 1,
  }) {
    final base = switch (kind) {
      MonsterKind.blind => 20,
      MonsterKind.tracker => 22,
      MonsterKind.charger => charging ? 40 : 24,
      MonsterKind.warden => 30,
    };
    // Content validation permits 0.25–1.5; sanitize direct runtime construction too.
    final variant = variantDamage.isFinite
        ? (variantDamage.clamp(.25, 1.5) * 10000).round()
        : 10000;
    final numerator =
        GameInt(base) *
        EndlessBalance.powerNumerator(EndlessBalance.waveIndex(depth)) *
        (elite ? 135 : 100) *
        variant;
    const denominator = EndlessBalance.powerDenominator * 100 * 10000;
    return ((numerator + denominator - 1) ~/ denominator).max(1);
  }

  /// Recovery remains useful at every level; exact ceil(25% maximum HP).
  static GameInt chestHealing(GameInt maximum) => (maximum.max(1) + 3) ~/ 4;
}
