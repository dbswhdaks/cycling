import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/kcycle_video_service.dart';
import '../../../models/race_video.dart';

final kcycleVideoServiceProvider = Provider<KcycleVideoService>((ref) {
  return KcycleVideoService();
});

final raceVideoListProvider =
    FutureProvider.autoDispose<List<RaceVideo>>((ref) async {
  final service = ref.read(kcycleVideoServiceProvider);
  return service.fetchRaceVideos();
});

final videoUrlProvider = FutureProvider.autoDispose
    .family<String?, ({RaceVideo video, String mode})>((ref, params) async {
  final service = ref.read(kcycleVideoServiceProvider);
  return service.fetchVideoUrl(params.video, mode: params.mode);
});
