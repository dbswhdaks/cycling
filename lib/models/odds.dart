/// 배당률 (단승, 복승, 쌍승 등)
class Odds {
  final Map<int, double> win;      // 단승: 1번 -> 배당
  final Map<String, double> place;  // 복승: "1-2" -> 배당
  final Map<String, double> quinella; // 쌍승
  final Map<String, double> trio;   // 삼복승
  final Map<String, double> trifecta; // 삼쌍승

  const Odds({
    this.win = const {},
    this.place = const {},
    this.quinella = const {},
    this.trio = const {},
    this.trifecta = const {},
  });
}
