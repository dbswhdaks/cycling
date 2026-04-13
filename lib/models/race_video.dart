class RaceVideo {
  final String title;
  final String date;
  final String thumbnailUrl;
  final String year;
  final String meetNo;
  final String day;
  final String venueCode;
  final String raceNo;

  const RaceVideo({
    required this.title,
    required this.date,
    required this.thumbnailUrl,
    required this.year,
    required this.meetNo,
    required this.day,
    required this.venueCode,
    required this.raceNo,
  });

  String popupPath(String mode) =>
      '/broadcast/popup/race/$year/$meetNo/$day/$venueCode/$raceNo/$mode';

  String get venueName {
    return switch (venueCode) {
      '001' => '광명',
      '002' => '창원',
      '003' => '부산',
      _ => '경륜',
    };
  }

  int get raceNumber => int.tryParse(raceNo) ?? 0;
}
