/// 승식별 배당
///
/// 키는 선수 번호(배번) 기준이며, 조합 키는 `"4-1"`처럼 착순대로 나열한다.
/// 공공데이터 경주결과 API의 pool 필드와 1:1 대응한다.
class Odds {
  /// 단승식 (pool1): 1착 선수번호 → 배당
  final Map<int, double> win;

  /// 연승식 (pool2): 1·2착 선수번호 각각 → 배당
  final Map<int, double> place;

  /// 쌍승식 (pool4): 1·2착 순서까지 일치
  final Map<String, double> exacta;

  /// 복승식 (pool5): 1·2착 순서 무관
  final Map<String, double> quinella;

  /// 삼복승식 (pool6): 1·2·3착 순서 무관
  final Map<String, double> trio;

  /// 쌍복승식 (pool8): 1·2착 순서 일치 + 3착 포함
  final Map<String, double> exactaTrio;

  /// 삼쌍승식 (pool7): 1·2·3착 순서까지 일치
  final Map<String, double> trifecta;

  const Odds({
    this.win = const {},
    this.place = const {},
    this.exacta = const {},
    this.quinella = const {},
    this.trio = const {},
    this.exactaTrio = const {},
    this.trifecta = const {},
  });

  bool get isEmpty =>
      win.isEmpty &&
      place.isEmpty &&
      exacta.isEmpty &&
      quinella.isEmpty &&
      trio.isEmpty &&
      exactaTrio.isEmpty &&
      trifecta.isEmpty;

  bool get isNotEmpty => !isEmpty;

  double? exactaFor(int first, int second) => exacta['$first-$second'];

  /// 복승식은 순서를 가리지 않으므로 두 방향 모두 조회한다.
  double? quinellaFor(int first, int second) =>
      quinella['$first-$second'] ?? quinella['$second-$first'];

  /// 삼복승식은 순서를 가리지 않으므로 모든 순열을 조회한다.
  double? trioFor(int first, int second, int third) =>
      _anyPermutation(trio, [first, second, third]);

  double? exactaTrioFor(int first, int second, int third) =>
      exactaTrio['$first-$second-$third'];

  double? trifectaFor(int first, int second, int third) =>
      trifecta['$first-$second-$third'];

  static double? _anyPermutation(Map<String, double> source, List<int> nos) {
    for (final key in _permutationKeys(nos)) {
      final value = source[key];
      if (value != null) return value;
    }
    return null;
  }

  static List<String> _permutationKeys(List<int> nos) {
    if (nos.length != 3) return [nos.join('-')];
    final [a, b, c] = nos;
    return ['$a-$b-$c', '$a-$c-$b', '$b-$a-$c', '$b-$c-$a', '$c-$a-$b', '$c-$b-$a'];
  }
}
