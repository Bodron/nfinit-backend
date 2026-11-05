/// Exact growing game quantities. JSON keeps legacy small integers and stores
/// larger values as decimal strings, independently of native/web integer limits.
class GameInt implements Comparable<Object> {
  const GameInt(int value) : _value = value;
  const GameInt._(this._value);
  static const zero = GameInt(0);
  static const one = GameInt(1);
  static final _jsonLimit = BigInt.from(9007199254740991);
  final Object _value;
  BigInt get exact => _value is BigInt ? _value : BigInt.from(_value as int);

  factory GameInt.parse(Object? value) {
    if (value is GameInt) return value;
    if (value is BigInt) return GameInt._(value);
    if (value is num && value.isFinite) return GameInt._(BigInt.from(value));
    if (value is String) {
      return GameInt._(BigInt.tryParse(value) ?? BigInt.zero);
    }
    return zero;
  }
  GameInt operator +(Object other) =>
      GameInt._(exact + GameInt.parse(other).exact);
  GameInt operator -(Object other) =>
      GameInt._(exact - GameInt.parse(other).exact);
  GameInt operator -() => GameInt._(-exact);
  GameInt operator *(Object other) {
    if (other is double) {
      if (!other.isFinite) throw ArgumentError.value(other, 'factor');
      return GameInt._(
        exact * BigInt.from(other * 1000000000) ~/ BigInt.from(1000000000),
      );
    }
    return GameInt._(exact * GameInt.parse(other).exact);
  }

  GameInt operator %(Object other) =>
      GameInt._(exact % GameInt.parse(other).exact);
  GameInt operator ~/(Object other) =>
      GameInt._(exact ~/ GameInt.parse(other).exact);
  double operator /(Object other) {
    final a = exact, b = GameInt.parse(other).exact;
    if (b == BigInt.zero) {
      return a == BigInt.zero ? double.nan : (a.sign * double.infinity);
    }
    if (a == BigInt.zero) return 0;
    final shiftA = a.abs().bitLength > 52 ? a.abs().bitLength - 52 : 0;
    final shiftB = b.abs().bitLength > 52 ? b.abs().bitLength - 52 : 0;
    var ratio = (a >> shiftA).toDouble() / (b >> shiftB).toDouble();
    var exponent = shiftA - shiftB;
    while (exponent > 0) {
      final step = exponent > 512 ? 512 : exponent;
      ratio *= BigInt.two.pow(step).toDouble();
      exponent -= step;
    }
    while (exponent < 0) {
      final step = -exponent > 512 ? 512 : -exponent;
      ratio /= BigInt.two.pow(step).toDouble();
      exponent += step;
    }
    return ratio;
  }

  GameInt max(Object other) => this >= other ? this : GameInt.parse(other);
  GameInt min(Object other) => this <= other ? this : GameInt.parse(other);
  GameInt clamp(Object lower, Object upper) => max(lower).min(upper);
  GameInt floor() => this;
  GameInt ceil() => this;
  GameInt round() => this;
  int toInt() => exact.toInt();
  double toDouble() => exact.toDouble();
  bool operator <(Object other) => compareTo(other) < 0;
  bool operator <=(Object other) => compareTo(other) <= 0;
  bool operator >(Object other) => compareTo(other) > 0;
  bool operator >=(Object other) => compareTo(other) >= 0;
  @override
  int compareTo(Object other) => exact.compareTo(GameInt.parse(other).exact);
  @override
  bool operator ==(Object other) =>
      (other is GameInt || other is BigInt || other is int) &&
      compareTo(other) == 0;
  @override
  int get hashCode =>
      exact.abs() <= _jsonLimit ? toInt().hashCode : exact.hashCode;
  Object toJson() => exact.abs() <= _jsonLimit ? toInt() : exact.toString();
  String get decimal => exact.toString();
  @override
  String toString() {
    final text = decimal;
    if (text.length <= 13) return text;
    final sign = text.startsWith('-') ? '-' : '';
    final digits = sign.isEmpty ? text : text.substring(1);
    return '$sign${digits[0]}.${digits.substring(1, 3)}e${digits.length - 1}';
  }
}
