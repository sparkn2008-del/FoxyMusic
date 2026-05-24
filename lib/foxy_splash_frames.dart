import 'package:flutter/services.dart';

/// Designer frame paths for the startup fox animation.
/// Drop PNGs under [root] — see `assets/images/splash/README.txt`.
class FoxySplashFrames {
  FoxySplashFrames._();

  static const logo = 'assets/images/foxy_splash.png';
  static const root = 'assets/images/splash';

  static const sleep = '$root/sleep.png';
  static const awake = '$root/awake.png';
  static const musicStar = '$root/music_star.png';

  static const wakeFrames = <String>[
    '$root/wake_01.png',
    '$root/wake_02.png',
    '$root/wake_03.png',
    '$root/wake_04.png',
  ];

  static const runFrames = <String>[
    '$root/run_01.png',
    '$root/run_02.png',
    '$root/run_03.png',
    '$root/run_04.png',
    '$root/run_05.png',
    '$root/run_06.png',
  ];

  /// True when at least sleep + one run frame exist (not just README placeholders).
  static Future<bool> hasDesignerFrames() async {
    if (!await _exists(sleep)) return false;
    if (!await _exists(runFrames.first)) return false;
    return true;
  }

  /// Maps timeline `t` (0–1) to the best frame asset.
  static String pathForTimeline(double t) {
    if (t < 0.2) return sleep;
    if (t < 0.38) {
      final i = ((t - 0.2) / 0.18 * wakeFrames.length).floor().clamp(0, wakeFrames.length - 1);
      return wakeFrames[i];
    }
    final runT = ((t - 0.38) / 0.52).clamp(0.0, 1.0);
    final i = (runT * runFrames.length).floor().clamp(0, runFrames.length - 1);
    return runFrames[i];
  }

  static Future<bool> _exists(String path) async {
    try {
      await rootBundle.load(path);
      return true;
    } catch (_) {
      return false;
    }
  }
}
