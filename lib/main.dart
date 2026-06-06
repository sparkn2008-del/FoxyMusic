import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter, lerpDouble;
import 'dart:io' show File;

import 'package:flutter/foundation.dart'
    show ValueListenable, kDebugMode, kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'foxy_startup_splash.dart';

part 'now_playing_surfaces.dart';
part 'now_playing_footer.dart';
part 'state_controllers.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

typedef _FoxyOnPlay =
    Future<void> Function(
      _Song song,
      List<_Song> queue, {
      bool radioTail,
      bool downloadsOnly,
    });

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;

/// Light black veil on transparent chrome (nav, controls, chips).
const double _kSubtleBlackTint = 0.10;

String _kAppVersionLabel = 'v1.2.1';
String _kAppVersionName = '1.2.1';
const String _kGitHubProjectUrl = 'https://github.com/sparkn2008-del/FoxyMusic';
const String _kAboutCreditLine =
    'Made with â¤ï¸ by Foxy Nish aka sparkn2008-del ðŸ¦Šâœ¨';
const String _kFoxyLogoAsset = 'assets/images/foxy_logo.png';

const Color _kFoxyNpTime = Color(0xFF9E9E9E);

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xE6000000),
    Color.lerp(const Color(0xFF4A4334), accent, 0.38)!,
  );
}

/// Parses catalog duration ("4:32", "1:23:04", or plain seconds / ms) when Exo [durationMs] is unknown.
int? _durationHintMsFromCatalog(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  if (RegExp(r'^\d+$').hasMatch(s)) {
    final n = int.tryParse(s);
    if (n == null) return null;
    if (n >= 10000) return n;
    return n * 1000;
  }
  final parts = s.split(':').map((e) => int.tryParse(e.trim()) ?? -1).toList();
  if (parts.isEmpty || parts.any((e) => e < 0)) return null;
  if (parts.length == 2) return (parts[0] * 60 + parts[1]) * 1000;
  if (parts.length >= 3) {
    return (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000;
  }
  return null;
}

class _PerfStats {
  _PerfStats();

  int hits = 0;
  int totalUs = 0;
  int maxUs = 0;

  void add(int elapsedUs) {
    hits += 1;
    totalUs += elapsedUs;
    if (elapsedUs > maxUs) maxUs = elapsedUs;
  }
}

class _FoxyPerfProbe {
  static bool get enabled => kDebugMode;

  static final Map<String, _PerfStats> _stats = <String, _PerfStats>{};
  static Timer? _flushTimer;
  static bool _frameTimingsInstalled = false;

  static void install() {
    if (!enabled || _frameTimingsInstalled) return;
    _frameTimingsInstalled = true;
    WidgetsBinding.instance.addTimingsCallback((timings) {
      if (timings.isEmpty) return;
      var worstBuildUs = 0;
      var worstRasterUs = 0;
      for (final timing in timings) {
        final buildUs = timing.buildDuration.inMicroseconds;
        final rasterUs = timing.rasterDuration.inMicroseconds;
        if (buildUs > worstBuildUs) worstBuildUs = buildUs;
        if (rasterUs > worstRasterUs) worstRasterUs = rasterUs;
      }
      if (worstBuildUs >= 9000 || worstRasterUs >= 9000) {
        developer.log(
          'Frame jank: build ${(worstBuildUs / 1000).toStringAsFixed(1)}ms, '
          'raster ${(worstRasterUs / 1000).toStringAsFixed(1)}ms',
          name: 'FoxyPerf',
        );
      }
    });
  }

  static T measure<T>(String label, T Function() action, {int warnUs = 5000}) {
    if (!enabled) return action();
    final stopwatch = Stopwatch()..start();
    final result = action();
    stopwatch.stop();
    final elapsedUs = stopwatch.elapsedMicroseconds;
    (_stats[label] ??= _PerfStats()).add(elapsedUs);
    _ensureFlush();
    if (elapsedUs >= warnUs) {
      developer.log(
        '$label took ${(elapsedUs / 1000).toStringAsFixed(2)}ms',
        name: 'FoxyPerf',
      );
    }
    return result;
  }

  static void event(String label) {
    if (!enabled) return;
    (_stats[label] ??= _PerfStats()).add(0);
    _ensureFlush();
  }

  static void _ensureFlush() {
    _flushTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_stats.isEmpty) return;
      final lines = _stats.entries.toList()
        ..sort((a, b) => b.value.totalUs.compareTo(a.value.totalUs));
      final summary = lines
          .take(8)
          .map((entry) {
            final avgUs = entry.value.hits == 0
                ? 0
                : entry.value.totalUs / entry.value.hits;
            return '${entry.key}: '
                '${entry.value.hits}x, '
                'avg ${(avgUs / 1000).toStringAsFixed(2)}ms, '
                'max ${(entry.value.maxUs / 1000).toStringAsFixed(2)}ms';
          })
          .join(' | ');
      developer.log(summary, name: 'FoxyPerf');
      _stats.clear();
    });
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _FoxyPerfProbe.install();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FoxyFlutterApp());
}

class FoxyFlutterApp extends StatefulWidget {
  const FoxyFlutterApp({super.key});

  @override
  State<FoxyFlutterApp> createState() => _FoxyFlutterAppState();
}

class _FoxyFlutterAppState extends State<FoxyFlutterApp> {
  final _rootNavKey = GlobalKey<NavigatorState>();
  _FlutterAppearance _appearance = const _FlutterAppearance();
  String? _homeBackgroundPath;
  bool _homeBackgroundEnabled = false;
  bool _dynamicSongColors = true;
  int? _songAccentArgb;
  int _paletteEpoch = 0;
  String _lastPlayerVideoId = '';
  StreamSubscription<dynamic>? _rootEventSub;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    unawaited(_loadAppVersion());
    _rootEventSub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          final nextDynamic = state['dynamicSongColors'] != false;
          final a = state['songAccentArgb'];
          final nextAccent = a is num ? a.toInt() : null;
          final pe = state['paletteEpoch'];
          final nextEpoch = pe is num ? pe.toInt() : _paletteEpoch;
          final accentChanged = nextAccent != _songAccentArgb;
          final epochChanged = nextEpoch != _paletteEpoch;
          final cs = _asMap(state['currentSong']);
          final vid = cs?['videoId']?.toString() ?? '';
          final videoChanged = vid != _lastPlayerVideoId;
          final dynamicChanged = nextDynamic != _dynamicSongColors;
          if (!dynamicChanged &&
              !accentChanged &&
              !epochChanged &&
              !videoChanged) {
            return;
          }
          setState(() {
            _dynamicSongColors = nextDynamic;
            _songAccentArgb = nextAccent;
            _paletteEpoch = nextEpoch;
            _lastPlayerVideoId = vid;
          });
          if (nextDynamic && (accentChanged || epochChanged || videoChanged)) {
            unawaited(_loadAppearance());
          }
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
      } else if (type == 'updateAvailable') {
        final update = _asMap(map['update']);
        if (update != null) {
          _promptUpdateAvailable(update);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPlayerThemeFromNative();
    });
  }

  Future<void> _syncPlayerThemeFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map == null || !mounted) return;
      final pe = map['paletteEpoch'];
      final nextDynamic = map['dynamicSongColors'] != false;
      final a = map['songAccentArgb'];
      final nextAccent = a is num ? a.toInt() : null;
      final nextEpoch = pe is num ? pe.toInt() : _paletteEpoch;
      final cs = _asMap(map['currentSong']);
      final nextVideoId = cs?['videoId']?.toString() ?? '';
      if (nextDynamic == _dynamicSongColors &&
          nextAccent == _songAccentArgb &&
          nextEpoch == _paletteEpoch &&
          nextVideoId == _lastPlayerVideoId) {
        return;
      }
      setState(() {
        _dynamicSongColors = nextDynamic;
        _songAccentArgb = nextAccent;
        _paletteEpoch = nextEpoch;
        _lastPlayerVideoId = nextVideoId;
      });
      if (_dynamicSongColors) {
        unawaited(_loadAppearance());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _rootEventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppearance'));
      if (map != null && mounted) {
        setState(() {
          _appearance = _FlutterAppearance.fromMap(map);
          final d = map['dynamicSongColors'];
          if (d is bool) {
            _dynamicSongColors = d;
          }
          final bg = map['homeBackgroundPath']?.toString().trim();
          _homeBackgroundPath = (bg != null && bg.isNotEmpty) ? bg : null;
          _homeBackgroundEnabled = map['homeBackgroundEnabled'] == true;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAppVersion() async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppVersion'));
      if (map == null || !mounted) return;
      final name = map['versionName']?.toString().trim() ?? '';
      if (name.isEmpty) return;
      setState(() {
        _kAppVersionName = name;
        _kAppVersionLabel = 'v$name';
      });
    } catch (_) {}
  }

  void _promptUpdateAvailable(Map<String, dynamic> map) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _rootNavKey.currentContext;
      if (ctx == null || !mounted) return;
      _showUpdateResultDialog(ctx, map, title: 'Update available');
    });
  }

  Color get _effectiveAccent {
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _effectiveAccent;
    return MaterialApp(
      navigatorKey: _rootNavKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _appearance.background,
        colorScheme: ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: _appearance.surface,
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return Colors.white.withValues(alpha: 0.55);
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return accent.withValues(alpha: 0.55);
            }
            return Colors.white.withValues(alpha: 0.12);
          }),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF141414),
          selectedColor: const Color(0xFF2C2C2C),
          disabledColor: const Color(0xFF141414),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          labelStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          showCheckmark: true,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: FoxyAppLaunchGate(
        child: FoxyHomeShell(
          homeBackgroundPath: _homeBackgroundEnabled
              ? _homeBackgroundPath
              : null,
        ),
      ),
    );
  }
}

class _FlutterAppearance {
  const _FlutterAppearance({
    this.accent = Colors.white,
    this.background = _kTrueBlack,
    this.surface = _kTrueBlack,
    this.surfaceHigh = const Color(0xFF121212),
    this.muted = const Color(0xFFB0B0B0),
  });

  factory _FlutterAppearance.fromMap(Map<String, dynamic> map) =>
      _FlutterAppearance(
        accent: _argbToColor(map['accentArgb']) ?? Colors.white,
        background: _argbToColor(map['backgroundArgb']) ?? _kTrueBlack,
        surface: _argbToColor(map['surfaceArgb']) ?? _kTrueBlack,
        surfaceHigh:
            _argbToColor(map['surfaceHighArgb']) ?? const Color(0xFF121212),
        muted: _argbToColor(map['mutedArgb']) ?? const Color(0xFFB0B0B0),
      );

  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color muted;
}

Color? _argbToColor(dynamic value) {
  if (value is num) return Color(value.toInt() & 0xFFFFFFFF);
  return null;
}

/// Warm fox-fur tones from the FoxyMusic logo (amber â†’ deep orange â†’ cream).
class _FoxyBrandPalette {
  static const foxAmber = Color(0xFFFF9A3C);
  static const foxDeep = Color(0xFFE85D04);
  static const foxCream = Color(0xFFFFD9B0);
}

enum _FoxyGradientVariant { home, player }

/// Large soft blooms â€” fox logo warmth + dynamic song accent.
class _FoxyBrandGradientBackdrop extends StatelessWidget {
  const _FoxyBrandGradientBackdrop({
    required this.child,
    this.variant = _FoxyGradientVariant.home,
  });

  final Widget child;
  final _FoxyGradientVariant variant;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final strong = variant == _FoxyGradientVariant.player;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(
                  const Color(0xFF201012),
                  accent,
                  strong ? 0.10 : 0.16,
                )!,
                const Color(0xFF0B0B0D),
                Color.lerp(surface, const Color(0xFF050505), 0.68)!,
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: strong ? 0.05 : 0.10),
                Colors.transparent,
                _FoxyBrandPalette.foxDeep.withValues(
                  alpha: strong ? 0.05 : 0.08,
                ),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Branded FoxyMusic logo (PNG with glow on black).
class _FoxyAppLogo extends StatelessWidget {
  const _FoxyAppLogo({
    this.size = 120,
    this.borderRadius = 20,
    this.showGlow = true,
  });

  final double size;
  final double borderRadius;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: showGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: [
                BoxShadow(
                  color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.22),
                  blurRadius: size * 0.28,
                  spreadRadius: size * 0.02,
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          _kFoxyLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.music_note_rounded,
            size: size * 0.5,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }
}

class _FoxyHomeBackdrop extends StatelessWidget {
  const _FoxyHomeBackdrop({required this.child, this.customPath});

  final Widget child;
  final String? customPath;

  @override
  Widget build(BuildContext context) {
    if (customPath != null &&
        customPath!.isNotEmpty &&
        !kIsWeb &&
        File(customPath!).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(customPath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            cacheWidth: 720,
            filterQuality: FilterQuality.low,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.10),
                  Colors.black.withValues(alpha: 0.36),
                  Colors.black.withValues(alpha: 0.64),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          child,
        ],
      );
    }
    return ColoredBox(color: _kTrueBlack, child: child);
  }
}

/// Translucent surface with optional clipped backdrop blur for individual panels.
class _FoxyGlassTint extends StatelessWidget {
  const _FoxyGlassTint({
    required this.child,
    this.borderRadius = 0,
    this.tintOpacity = 0.28,
    this.borderOpacity = 0.1,
    this.blur = true,
    this.blurSigma = 14,
  });

  final Widget child;
  final double borderRadius;
  final double tintOpacity;
  final double borderOpacity;
  final bool blur;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius > 0
        ? BorderRadius.circular(borderRadius)
        : null;
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: tintOpacity),
        borderRadius: radius,
        border: Border.all(
          color: Colors.white.withValues(alpha: borderOpacity),
        ),
      ),
      child: child,
    );
    if (!blur) return surface;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: radius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: surface,
        ),
      ),
    );
  }
}

/// Glass control surface. SimpMusic-style: scrolling lists use [blur] off (tint
/// only) so wallpaper is not re-sampled every frame; fixed chrome may use blur.
class _FoxyGlassButton extends StatelessWidget {
  const _FoxyGlassButton({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tintOpacity = 0.34,
    this.borderOpacity,
    this.blurSigma = 10,
    this.selected = false,
    this.padding = EdgeInsets.zero,
    this.blur = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double tintOpacity;
  final double? borderOpacity;
  final double blurSigma;
  final bool selected;
  final EdgeInsetsGeometry padding;

  /// Live clipped [BackdropFilter] for each transparent surface.
  final bool blur;

  @override
  Widget build(BuildContext context) {
    final effectiveTint = blur
        ? tintOpacity
        : (tintOpacity + 0.08).clamp(0.0, 0.52);
    final fill = selected
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: effectiveTint),
          )
        : Colors.black.withValues(alpha: effectiveTint);
    final outlineAlpha =
        borderOpacity ?? (selected ? 0.28 : (blur ? 0.16 : 0.14));
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(color: Colors.white.withValues(alpha: outlineAlpha)),
      ),
      child: Padding(padding: padding, child: child),
    );
    Widget core = ClipRRect(
      borderRadius: borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: surface,
            )
          : surface,
    );
    if (blur) {
      core = RepaintBoundary(child: core);
    }
    if (onTap != null) {
      core = Material(
        color: Colors.transparent,
        child: InkWell(onTap: onTap, borderRadius: borderRadius, child: core),
      );
    }
    return core;
  }
}

/// Text action styled as frosted glass (Play all, Retry, â€¦).
class _FoxyGlassTextButton extends StatelessWidget {
  const _FoxyGlassTextButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 14,
        ),
      ),
    );
  }
}

_HomeSectionLayout _homeSectionLayout(_SongSection section) {
  switch (section.layout) {
    case 'video':
      return _HomeSectionLayout.video;
    case 'grid':
      return _HomeSectionLayout.grid;
    case 'chart':
      return _HomeSectionLayout.chart;
    case 'artist':
      return _HomeSectionLayout.artist;
    case 'cards':
      return _HomeSectionLayout.cards;
    default:
      final t = section.title.toLowerCase();
      if (t.contains('video')) return _HomeSectionLayout.video;
      if (t.contains('chart')) return _HomeSectionLayout.chart;
      if (t.contains('artist') || t.contains('similar')) {
        return _HomeSectionLayout.artist;
      }
      if (t.contains('release') ||
          t.contains('discover') ||
          t.contains('cover') ||
          t.contains('remix') ||
          t.contains('daily') ||
          t.contains('fresh')) {
        return _HomeSectionLayout.grid;
      }
      return _HomeSectionLayout.cards;
  }
}

const _homeMoodChips = <String>[
  'All',
  'Focus',
  'Relax',
  'Sleep',
  'Drive',
  'Energize',
  'Bollywood',
  'Phonk',
  'Lofi',
  'Sad',
];

const _searchFilterChips = <String>[
  'All',
  'Songs',
  'Videos',
  'Albums',
  'Artists',
];

class _SearchPayload {
  const _SearchPayload({
    required this.songs,
    required this.videos,
    required this.albums,
    required this.artists,
  });

  final List<_Song> songs;
  final List<_Song> videos;
  final List<_Song> albums;
  final List<_Song> artists;

  static _SearchPayload fromResponse(Map<String, dynamic> response) {
    List<_Song> parseList(String key) => (response[key] as List? ?? const [])
        .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList();
    return _SearchPayload(
      songs: parseList('songs'),
      videos: parseList('videos'),
      albums: parseList('albums'),
      artists: parseList('artists'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SearchPayload &&
          runtimeType == other.runtimeType &&
          _idsOf(songs) == _idsOf(other.songs) &&
          _idsOf(videos) == _idsOf(other.videos) &&
          _idsOf(albums) == _idsOf(other.albums) &&
          _idsOf(artists) == _idsOf(other.artists);

  @override
  int get hashCode => Object.hash(
    _idsOf(songs),
    _idsOf(videos),
    _idsOf(albums),
    _idsOf(artists),
  );

  static String _idsOf(List<_Song> songs) =>
      songs.map((song) => song.videoId).join('|');
}

class _SearchUiState {
  const _SearchUiState({
    this.query = '',
    this.filter = 'All',
    this.loading = false,
    this.error,
    this.payload = const _SearchPayload(
      songs: [],
      videos: [],
      albums: [],
      artists: [],
    ),
  });

  final String query;
  final String filter;
  final bool loading;
  final String? error;
  final _SearchPayload payload;

  List<_Song> get songs => payload.songs;
  List<_Song> get videos => payload.videos;
  List<_Song> get albums => payload.albums;
  List<_Song> get artists => payload.artists;

  bool get hasResults =>
      songs.isNotEmpty ||
      videos.isNotEmpty ||
      albums.isNotEmpty ||
      artists.isNotEmpty;

  _SearchUiState copyWith({
    String? query,
    String? filter,
    bool? loading,
    Object? error = _searchStateNoChange,
    _SearchPayload? payload,
  }) {
    return _SearchUiState(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      loading: loading ?? this.loading,
      error: identical(error, _searchStateNoChange)
          ? this.error
          : error as String?,
      payload: payload ?? this.payload,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SearchUiState &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          filter == other.filter &&
          loading == other.loading &&
          error == other.error &&
          payload == other.payload;

  @override
  int get hashCode => Object.hash(query, filter, loading, error, payload);
}

const Object _searchStateNoChange = Object();

class _SearchCache {
  static const _maxEntries = 24;
  static final _entries = <String, _SearchPayload>{};

  static String _key(String query, int limit) =>
      '${query.trim().toLowerCase()}|$limit';

  static _SearchPayload? get(String query, int limit) {
    final value = _entries.remove(_key(query, limit));
    if (value != null) {
      _entries[_key(query, limit)] = value;
    }
    return value;
  }

  static void put(String query, int limit, _SearchPayload payload) {
    final key = _key(query, limit);
    _entries.remove(key);
    _entries[key] = payload;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

enum _HomeSectionLayout { cards, grid, video, chart, artist }

const double _kHomeSectionTopSpace = 8;
const double _kHomeSectionBottomSpace = 10;
const double _kHomeSectionTitleSpace = 8;

String _formatStorageBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class FoxyHomeShell extends StatefulWidget {
  const FoxyHomeShell({super.key, this.homeBackgroundPath});

  final String? homeBackgroundPath;

  @override
  State<FoxyHomeShell> createState() => _FoxyHomeShellState();
}

class _FoxyHomeShellState extends State<FoxyHomeShell>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  final GlobalKey<_SearchTabState> _searchTabKey = GlobalKey<_SearchTabState>();
  final GlobalKey<_LibraryTabState> _libraryTabKey =
      GlobalKey<_LibraryTabState>();
  final _playerController = _PlayerStateController();
  final _accountController = _AccountStateController();
  StreamSubscription<dynamic>? _sub;
  Timer? _miniPlayerSyncTimer;
  bool _playPauseBusy = false;
  int _lastPlayerEventAtMs = 0;

  /// Avoid mini player + expanded sheet stacking (and Hero flights from feed art).
  bool _nowPlayingSheetOpen = false;
  bool _openingPlayerSheet = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_accountController.loadFromNative());
    unawaited(_playerController.loadFromNative());
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null) {
          _lastPlayerEventAtMs = DateTime.now().millisecondsSinceEpoch;
          _playerController.applyExternal(state);
        }
      } else if (type == 'libraryFeedChanged') {
        _SongMenuContext.invalidate();
      } else if (type == 'accountChanged') {
        _SongMenuContext.invalidate();
        unawaited(_accountController.loadFromNative());
      }
    });
    _miniPlayerSyncTimer = Timer.periodic(const Duration(milliseconds: 900), (
      _,
    ) {
      if (!mounted || _nowPlayingSheetOpen) return;
      final current = _asMap(_playerController.value['currentSong']);
      if (current == null || current['videoId']?.toString().isEmpty != false) {
        return;
      }
      final timeline = _playerController.timelineListenable.value;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final recentlyUpdated = nowMs - _lastPlayerEventAtMs < 1800;
      if (recentlyUpdated) return;
      if (!timeline.isPlaying && !timeline.isBuffering) return;
      unawaited(_playerController.resync());
    });
  }

  Future<void> _openHomeSettings() async {
    Map<String, dynamic> appearance = const {};
    try {
      appearance =
          _asMap(await _method.invokeMethod('getAppearance')) ?? const {};
    } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _SettingsSheet(
        appearance: appearance,
        onSetAppearance: (patch) async {
          await _method.invokeMethod('setAppearance', patch);
        },
        account: _accountController.value,
        onAccountRefresh: _accountController.loadFromNative,
        onOpenAccountHub: () {
          Navigator.of(sheetCtx).pop();
          Future.microtask(() {
            if (mounted) unawaited(_openAccountHub());
          });
        },
      ),
    );
  }

  Future<void> _openAccountHub() async {
    final h = MediaQuery.sizeOf(context).height;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SizedBox(
        height: h * 0.9,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          child: ColoredBox(
            color: const Color(0xFF0B0B0B),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                Expanded(
                  child: _AccountHubBody(
                    onPlay: _playSong,
                    currentVideoIdListenable:
                        _playerController.currentVideoIdListenable,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) await _accountController.loadFromNative();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _miniPlayerSyncTimer?.cancel();
    _sub?.cancel();
    _playerController.dispose();
    _accountController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_playerController.loadFromNative());
    }
  }

  Future<void> _playSong(
    _Song song,
    List<_Song> queue, {
    bool radioTail = false,
    bool downloadsOnly = false,
  }) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    final start = math.max(index, 0);
    _playerController.setOptimistic(<String, dynamic>{
      ..._playerController.value,
      'currentSong': song.toMap(),
      'isBuffering': true,
      'isPlaying': false,
      'positionMs': 0,
      'durationMs': 0,
      'queue': songs.map((item) => item.toMap()).toList(),
      'queueIndex': start,
    });
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': start,
      'radioTail': downloadsOnly ? false : radioTail,
      'offlineQueueOnly': downloadsOnly,
    });
    if (mounted) await _playerController.loadFromNative();
  }

  void _openSearchWithQuery(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    setState(() => _tabIndex = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchTabKey.currentState?.applyExternalQuery(q);
    });
  }

  void _openPlayer({int initialTab = 0}) {
    if (!mounted || _nowPlayingSheetOpen || _openingPlayerSheet) return;
    _openingPlayerSheet = true;
    unawaited(_playerController.resync());
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _nowPlayingSheetOpen = true);
    final sheet = showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      builder: (sheetContext) {
        final top = MediaQuery.paddingOf(sheetContext).top;
        final height = MediaQuery.sizeOf(sheetContext).height - top;
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: height,
              child: _NowPlayingSheet(
                playerController: _playerController,
                initialTab: initialTab,
                homeBackgroundPath: widget.homeBackgroundPath,
                onNotifyHomePlayerSync: _playerController.resync,
                onPlay: _playSong,
                onTogglePlayPause: _togglePlayPauseOptimistic,
                onDiscoverSearch: _openSearchWithQuery,
              ),
            ),
          ),
        );
      },
    );
    sheet.whenComplete(() {
      _openingPlayerSheet = false;
      if (mounted) setState(() => _nowPlayingSheetOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final safeTab = _tabIndex.clamp(0, 2);
    if (safeTab != _tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tabIndex = safeTab);
      });
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
          return;
        }
        if (_libraryTabKey.currentState?.consumeAndroidBack() == true) {
          return;
        }
        if (safeTab == 1 &&
            (_searchTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab != 0) {
          setState(() => _tabIndex = 0);
          return;
        }
        unawaited(_method.invokeMethod('moveTaskToBack'));
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _FoxyHomeBackdrop(
              customPath: widget.homeBackgroundPath,
              child: const SizedBox.expand(),
            ),
            ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: _accountController,
              builder: (context, account, _) {
                final tabs = [
                  _HomeTab(
                    key: const PageStorageKey('home-tab'),
                    currentVideoIdListenable:
                        _playerController.currentVideoIdListenable,
                    onPlay: _playSong,
                    account: account,
                    onOpenSettings: _openHomeSettings,
                    onDiscoverSearch: _openSearchWithQuery,
                    homeBackgroundPath: widget.homeBackgroundPath,
                  ),
                  KeyedSubtree(
                    key: const PageStorageKey('search-tab'),
                    child: _SearchTab(
                      key: _searchTabKey,
                      onPlay: _playSong,
                      onDiscoverSearch: _openSearchWithQuery,
                    ),
                  ),
                  _LibraryTab(
                    key: _libraryTabKey,
                    onPlay: _playSong,
                    onOpenSearch: () => setState(() => _tabIndex = 1),
                    onDiscoverSearch: _openSearchWithQuery,
                    currentVideoIdListenable:
                        _playerController.currentVideoIdListenable,
                  ),
                ];
                return IndexedStack(index: safeTab, children: tabs);
              },
            ),
          ],
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<Map<String, dynamic>>(
              valueListenable: _playerController.visualListenable,
              builder: (context, player, _) {
                final currentSong = _Song.fromMap(
                  _asMap(player['currentSong']) ?? const {},
                );
                final hasSong =
                    currentSong.videoId.isNotEmpty &&
                    currentSong.title.isNotEmpty;
                if (!hasSong || _nowPlayingSheetOpen) {
                  return const SizedBox.shrink();
                }
                return _MiniPlayer(
                  key: ValueKey<Object>(
                    '${player['playerEpoch'] ?? 0}-${currentSong.videoId}-${player['queueIndex'] ?? -1}',
                  ),
                  player: player,
                  timelineListenable: _playerController.timelineListenable,
                  onOpen: () => _openPlayer(),
                  onTogglePlayPause: _togglePlayPauseOptimistic,
                  onResync: _playerController.resync,
                  glass: true,
                  safeArea: false,
                  outerPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                );
              },
            ),
            _FoxyBottomNav(
              selectedIndex: safeTab,
              onSelected: (index) => setState(() => _tabIndex = index),
              transparent: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _togglePlayPauseOptimistic() async {
    if (_playPauseBusy) return;
    final current = _asMap(_playerController.value['currentSong']) ?? const {};
    if ((current['videoId']?.toString().isEmpty ?? true)) return;
    _playPauseBusy = true;
    final wasPlaying = _playerController.timelineListenable.value.isPlaying;
    _playerController.patchTimeline(isPlaying: !wasPlaying, isBuffering: false);
    try {
      await _method.invokeMethod('togglePlayPause');
    } finally {
      _playPauseBusy = false;
      Future<void>.delayed(const Duration(milliseconds: 380), () async {
        if (!mounted) return;
        await _playerController.resync();
      });
    }
  }
}

class _FoxyBottomNav extends StatelessWidget {
  const _FoxyBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    this.transparent = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Home'),
      (Icons.search_rounded, 'Search'),
      (Icons.library_music_rounded, 'Library'),
    ];
    final navRow = SizedBox(
      height: 54,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: transparent
                    ? _FoxyGlassButton(
                        blur: true,
                        onTap: () => onSelected(i),
                        selected: selectedIndex == i,
                        borderRadius: BorderRadius.circular(999),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].$1,
                              color: selectedIndex == i
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.55),
                              size: 22,
                            ),
                            const SizedBox(height: 1),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                items[i].$2,
                                style: TextStyle(
                                  color: selectedIndex == i
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Material(
                        color: selectedIndex == i
                            ? _kNavPillFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSelected(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                items[i].$1,
                                color: selectedIndex == i
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                size: 22,
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  items[i].$2,
                                  style: TextStyle(
                                    color: selectedIndex == i
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: transparent
            ? _FoxyGlassTint(
                borderRadius: 20,
                tintOpacity: 0.22 + _kSubtleBlackTint,
                borderOpacity: 0.1,
                blur: true,
                blurSigma: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 5,
                  ),
                  child: navRow,
                ),
              )
            : _FoxySurface(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                cornerRadius: 20,
                child: navRow,
              ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    super.key,
    required this.currentVideoIdListenable,
    required this.onPlay,
    required this.account,
    required this.onOpenSettings,
    this.onDiscoverSearch,
    this.homeBackgroundPath,
  });

  final ValueListenable<Object?> currentVideoIdListenable;
  final _FoxyOnPlay onPlay;
  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final void Function(String query)? onDiscoverSearch;
  final String? homeBackgroundPath;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  List<_SongSection> _sections = _HomeCache.sections;
  bool _loading = _HomeCache.sections.isEmpty;
  String? _error = _HomeCache.error;
  final ValueNotifier<String> _homeChipListenable = ValueNotifier<String>(
    'All',
  );
  final ValueNotifier<_RecognitionUiState> _recognition =
      ValueNotifier<_RecognitionUiState>(const _RecognitionUiState.ready());
  StreamSubscription<dynamic>? _recognitionSub;
  bool _recognitionSheetOpen = false;
  _ResolvedRecognitionTrack? _resolvedRecognition;
  Future<_ResolvedRecognitionTrack?>? _resolveRecognitionFuture;
  String? _resolveRecognitionKey;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _recognitionSub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      if (map['type']?.toString() != 'recognitionState') return;
      final next = _RecognitionUiState.fromMap(
        _asMap(map['state']) ?? const {},
      );
      _recognition.value = next;
      if (next.isSuccess && next.result != null && !next.result!.isEmpty) {
        unawaited(_warmRecognitionResolution(next.result!));
      } else if (next.state != 'success') {
        _resolvedRecognition = null;
        _resolveRecognitionFuture = null;
        _resolveRecognitionKey = null;
      }
    });
    if (_HomeCache.sections.isEmpty) {
      _loadHome();
    }
  }

  @override
  void dispose() {
    _recognitionSub?.cancel();
    _homeChipListenable.dispose();
    _recognition.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account['isSignedIn'] != widget.account['isSignedIn']) {
      unawaited(_loadHome(force: true));
    }
  }

  Future<void> _loadHome({bool force = false}) async {
    if (!force && _HomeCache.sections.isNotEmpty) {
      setState(() {
        _sections = _HomeCache.sections;
        _error = _HomeCache.error;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(await _method.invokeMethod('homeFeed')) ?? const {};
      final sections = (response['sections'] as List? ?? const [])
          .map((item) => _SongSection.fromMap(_asMap(item) ?? const {}))
          .where((section) => section.songs.isNotEmpty)
          .toList();
      _HomeCache.sections = sections;
      _HomeCache.error = null;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (e) {
      _HomeCache.error = e.toString();
      if (!mounted) return;
      setState(() {
        _error = _HomeCache.error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMood(String mood) async {
    try {
      final cached = _HomeCache.moodSections[mood];
      final section =
          cached ??
          _SongSection.fromMap(
            _asMap(await _method.invokeMethod('moodMix', {'mood': mood})) ??
                const {},
          );
      if (cached == null) _HomeCache.moodSections[mood] = section;
      if (!mounted || section.songs.isEmpty) return;
      setState(() {
        _sections = [
          section,
          ..._sections.where((item) => item.title != section.title),
        ];
        _HomeCache.sections = _sections;
      });
    } catch (_) {}
  }

  void _onHomeChip(String label) {
    if (_homeChipListenable.value != label) {
      _homeChipListenable.value = label;
    }
    if (label == 'All') {
      _loadHome(force: true);
    } else {
      _loadMood(label);
    }
  }

  Future<void> _openRecognition() async {
    if (_recognitionSheetOpen) return;
    _recognition.value = const _RecognitionUiState.listening();
    try {
      await _method.invokeMethod('startRecognition');
    } catch (e) {
      if (!mounted) return;
      _recognition.value = _RecognitionUiState.error(e.toString());
    }
    if (!mounted || _recognitionSheetOpen) return;
    _recognitionSheetOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RecognitionSheet(
        stateListenable: _recognition,
        onOpenHistory: _openRecognitionHistory,
        resolvePreview: _resolveRecognizedTrack,
        onToggleLike: (recognized) => _toggleRecognitionLike(ctx, recognized),
        onAddToPlaylist: (recognized) =>
            _addRecognitionToPlaylist(ctx, recognized),
        onQueueNext: (recognized) => _queueRecognitionNext(ctx, recognized),
        onAddToQueue: (recognized) => _addRecognitionToQueue(ctx, recognized),
        onOpenTrackActions: (recognized) =>
            _openRecognitionTrackActions(ctx, recognized),
        onCancel: () async {
          await _method.invokeMethod('stopRecognition');
          if (ctx.mounted) Navigator.pop(ctx);
        },
        onRetry: () async {
          _resolvedRecognition = null;
          _resolveRecognitionFuture = null;
          _resolveRecognitionKey = null;
          _recognition.value = const _RecognitionUiState.listening();
          await _method.invokeMethod('startRecognition');
        },
        onPlayNow: (recognized) async {
          final match = await _resolveRecognizedTrack(recognized);
          final song = match?.song;
          if (song == null || song.videoId.isEmpty) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Could not find a playable match')),
            );
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
          await widget.onPlay(song, [song], radioTail: true);
        },
        onSearch: (query) {
          Navigator.pop(ctx);
          widget.onDiscoverSearch?.call(query);
        },
      ),
    );
    _recognitionSheetOpen = false;
  }

  Future<void> _openRecognitionHistory() async {
    final raw = await _method.invokeMethod('getRecognitionHistory');
    final items = (raw as List? ?? const [])
        .map((e) => _RecognitionHistoryItem.fromMap(_asMap(e) ?? const {}))
        .where((e) => !e.result.isEmpty)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RecognitionHistorySheet(
        items: items,
        onClear: () async {
          await _method.invokeMethod('clearRecognitionHistory');
          if (ctx.mounted) Navigator.pop(ctx);
        },
        resolvePreview: _resolveRecognizedTrack,
        onToggleLike: (recognized) => _toggleRecognitionLike(ctx, recognized),
        onAddToPlaylist: (recognized) =>
            _addRecognitionToPlaylist(ctx, recognized),
        onQueueNext: (recognized) => _queueRecognitionNext(ctx, recognized),
        onAddToQueue: (recognized) => _addRecognitionToQueue(ctx, recognized),
        onOpenTrackActions: (recognized) =>
            _openRecognitionTrackActions(ctx, recognized),
        onPlay: (recognized) async {
          final match = await _resolveRecognizedTrack(recognized);
          final song = match?.song;
          if (song == null || song.videoId.isEmpty) {
            if (!ctx.mounted) return;
            ScaffoldMessenger.of(ctx).showSnackBar(
              const SnackBar(content: Text('Could not find a playable match')),
            );
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx);
          await widget.onPlay(song, [song], radioTail: true);
        },
        onSearch: (recognized) {
          Navigator.pop(ctx);
          widget.onDiscoverSearch?.call(recognized.searchQuery);
        },
      ),
    );
  }

  String _recognitionKey(_RecognitionResult recognized) => [
    recognized.title.trim().toLowerCase(),
    recognized.artist.trim().toLowerCase(),
    (recognized.youtubeVideoId ?? '').trim().toLowerCase(),
  ].join('|');

  Future<void> _warmRecognitionResolution(_RecognitionResult recognized) async {
    final key = _recognitionKey(recognized);
    if (_resolveRecognitionKey == key &&
        (_resolvedRecognition != null || _resolveRecognitionFuture != null)) {
      return;
    }
    _resolveRecognitionKey = key;
    final future = _resolveRecognizedTrack(recognized, remember: false);
    _resolveRecognitionFuture = future;
    final resolved = await future;
    if (!mounted || _resolveRecognitionKey != key) return;
    _resolvedRecognition = resolved;
    _resolveRecognitionFuture = null;
  }

  Future<_ResolvedRecognitionTrack?> _resolveRecognizedTrack(
    _RecognitionResult recognized, {
    bool remember = true,
  }) async {
    final key = _recognitionKey(recognized);
    if (_resolveRecognitionKey == key && _resolvedRecognition != null) {
      return _resolvedRecognition;
    }
    if (_resolveRecognitionKey == key && _resolveRecognitionFuture != null) {
      final pending = await _resolveRecognitionFuture;
      if (remember) _resolvedRecognition = pending;
      return pending;
    }
    _resolveRecognitionKey = key;
    final future = () async {
      final raw = _asMap(
        await _method.invokeMethod('resolveRecognizedTrack', {
          'title': recognized.title,
          'artist': recognized.artist,
          'youtubeVideoId': recognized.youtubeVideoId,
        }),
      );
      final songMap = _asMap(raw?['song']);
      final song = songMap == null ? null : _Song.fromMap(songMap);
      if (song == null || song.videoId.isEmpty) return null;
      return _ResolvedRecognitionTrack(
        song: song,
        matchLabel: raw?['matchLabel']?.toString() ?? 'Best match',
      );
    }();
    _resolveRecognitionFuture = future;
    final resolved = await future;
    if (_resolveRecognitionKey == key) {
      _resolveRecognitionFuture = null;
      if (remember) _resolvedRecognition = resolved;
    }
    return resolved;
  }

  Future<_Song?> _resolveRecognitionSongOrNotify(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final match = await _resolveRecognizedTrack(recognized);
    final song = match?.song;
    if (song != null && song.videoId.isNotEmpty) return song;
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not find a playable match')),
    );
    return null;
  }

  Future<void> _toggleRecognitionLike(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final song = await _resolveRecognitionSongOrNotify(context, recognized);
    if (song == null) return;
    final menu = await _SongMenuContext.load();
    final liked = menu.likedIds.contains(song.videoId);
    await _method.invokeMethod(liked ? 'unlike' : 'like', {
      'song': song.toMap(),
    });
    _SongMenuContext.invalidate();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(liked ? 'Removed from Liked' : 'Added to Liked')),
    );
  }

  Future<void> _addRecognitionToPlaylist(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final song = await _resolveRecognitionSongOrNotify(context, recognized);
    if (song == null) return;
    final menu = await _SongMenuContext.load();
    if (!context.mounted) return;
    await _pickPlaylistToAddSong(
      context,
      song: song,
      playlists: menu.userPlaylists,
      onChanged: () async => _SongMenuContext.invalidate(),
    );
  }

  Future<void> _openRecognitionTrackActions(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final song = await _resolveRecognitionSongOrNotify(context, recognized);
    if (song == null || !context.mounted) return;
    await _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: [song],
      onDiscoverSearch: widget.onDiscoverSearch,
    );
  }

  Future<void> _queueRecognitionNext(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final song = await _resolveRecognitionSongOrNotify(context, recognized);
    if (song == null) return;
    await _method.invokeMethod('enqueuePlayNext', {'song': song.toMap()});
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${song.title} will play next')));
  }

  Future<void> _addRecognitionToQueue(
    BuildContext context,
    _RecognitionResult recognized,
  ) async {
    final song = await _resolveRecognitionSongOrNotify(context, recognized);
    if (song == null) return;
    await _method.invokeMethod('addToQueue', {'song': song.toMap()});
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Queued ${song.title}')));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    super.build(context);
    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF151515),
      onRefresh: () async {
        _homeChipListenable.value = 'All';
        await _loadHome(force: true);
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 480,
        slivers: [
          ValueListenableBuilder<String>(
            valueListenable: _homeChipListenable,
            builder: (context, homeChip, _) {
              return SliverToBoxAdapter(
                child: _HomeTopBar(
                  account: widget.account,
                  onOpenSettings: widget.onOpenSettings,
                  onOpenRecognition: _openRecognition,
                  selectedChip: homeChip,
                  onChipSelected: _onHomeChip,
                ),
              );
            },
          ),
          ValueListenableBuilder<String>(
            valueListenable: _homeChipListenable,
            builder: (context, homeChip, _) {
              if (_loading) {
                return const SliverToBoxAdapter(child: _HomeLoading());
              }
              if (_error != null) {
                return SliverToBoxAdapter(
                  child: _HomeError(
                    message: _error!,
                    onRetry: () {
                      unawaited(_loadHome(force: true));
                    },
                  ),
                );
              }
              if (homeChip == 'All' && _sections.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                    child: Column(
                      children: [
                        Icon(
                          Icons.queue_music_rounded,
                          size: 48,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No feed rows yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Pull to refresh or open Search to find music.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _FoxyGlassTextButton(
                          label: 'Retry',
                          onPressed: () => unawaited(_loadHome(force: true)),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (homeChip == 'All') {
                return SliverMainAxisGroup(
                  slivers: [
                    if (_sections.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: _HomeQuickPicks(
                          songs: _sections
                              .expand((s) => s.songs)
                              .take(24)
                              .toList(),
                          onPlay: widget.onPlay,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: _HomeFreshFindsRow(
                          sections: _sections,
                          onPlay: widget.onPlay,
                          onDiscoverSearch: widget.onDiscoverSearch,
                        ),
                      ),
                    ],
                    for (final sec in _sections)
                      SliverToBoxAdapter(
                        child: _HomeFeedSection(
                          section: sec,
                          layout: _homeSectionLayout(sec),
                          onPlay: widget.onPlay,
                        ),
                      ),
                  ],
                );
              }
              if (_sections.isNotEmpty) {
                return SliverToBoxAdapter(
                  child: _HomeSongCardsSection(
                    section: _sections.first,
                    onPlay: widget.onPlay,
                  ),
                );
              }
              return const SliverToBoxAdapter(child: SizedBox.shrink());
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
              child: Center(
                child: Text(
                  '@2026 FoxyMusic $_kAppVersionLabel',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeCache {
  static List<_SongSection> sections = const [];
  static String? error;
  static final Map<String, _SongSection> moodSections = {};
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.account,
    required this.onOpenSettings,
    required this.onOpenRecognition,
    required this.selectedChip,
    required this.onChipSelected,
  });

  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenRecognition;
  final String selectedChip;
  final ValueChanged<String> onChipSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _FoxyAppLogo(size: 38, borderRadius: 12, showGlow: false),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FoxyMusic',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _kAppVersionLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _GlassIconButton(
                  tooltip: 'Recognize music',
                  icon: Icons.mic_none_rounded,
                  onPressed: onOpenRecognition,
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Notifications',
                  icon: Icons.notifications_none_rounded,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No new notifications'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'History',
                  icon: Icons.history_rounded,
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Open the Library tab for History'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Settings',
                  icon: Icons.settings_rounded,
                  onPressed: onOpenSettings,
                ),
              ],
            ),
            Text(
              _homeGreeting(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final label in _homeMoodChips)
                    _TopFilterChip(
                      label: label,
                      selected: selectedChip == label,
                      onTap: () => onChipSelected(label),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: _FoxyGlassButton(
        blur: true,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white.withValues(alpha: 0.88)),
        ),
      ),
    );
  }
}

String _homeGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Up late';
  if (h < 12) return 'Good morning...';
  if (h < 17) return 'Good afternoon...';
  if (h < 22) return 'Good evening...';
  return 'Wind down...';
}

/// Plain header for Library / Downloads (not the YT-style home hero).
class _ScreenTopBar extends StatelessWidget {
  const _ScreenTopBar({
    this.leading,
    required this.title,
    this.onRefresh,
    this.subtitle,
    this.onSearch,
    this.onSparkle,
    this.onDownloads,
    this.onImport,
  });

  final Widget? leading;
  final String title;
  final VoidCallback? onRefresh;
  final String? subtitle;
  final VoidCallback? onSearch;
  final VoidCallback? onSparkle;
  final VoidCallback? onDownloads;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ?leading,
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onDownloads != null)
                  _GlassIconButton(
                    tooltip: 'Downloads',
                    icon: Icons.download_rounded,
                    onPressed: onDownloads!,
                  ),
                if (onImport != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Import audio',
                    icon: Icons.library_add_rounded,
                    onPressed: onImport!,
                  ),
                ],
                if (onSparkle != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Discovery',
                    icon: Icons.auto_awesome_rounded,
                    onPressed: onSparkle!,
                  ),
                ],
                if (onSearch != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Search',
                    icon: Icons.search_rounded,
                    onPressed: onSearch!,
                  ),
                ],
                if (onRefresh != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: onRefresh!,
                  ),
                ],
              ],
            ),
            if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopFilterChip extends StatelessWidget {
  const _TopFilterChip({
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: selected,
        blur: true,
        blurSigma: 12,
        borderRadius: BorderRadius.circular(28),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoxySurface extends StatelessWidget {
  const _FoxySurface({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.selected = false,
    this.onTap,
    this.cornerRadius = _kCardRadius,
    this.frosted = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  final VoidCallback? onTap;
  final double cornerRadius;
  final bool frosted;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Padding(
        padding: margin,
        child: _FoxyGlassTint(
          borderRadius: cornerRadius,
          tintOpacity: selected ? 0.34 : 0.22,
          borderOpacity: selected ? 0.2 : 0.1,
          blur: frosted,
          blurSigma: 12,
          child: Padding(padding: padding, child: child),
        ),
      );
    }
    return Padding(
      padding: margin,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: selected,
        borderRadius: BorderRadius.circular(cornerRadius),
        padding: padding,
        tintOpacity: frosted ? 0.34 : (selected ? 0.20 : 0.16),
        borderOpacity: frosted ? null : (selected ? 0.12 : 0.045),
        blur: frosted,
        blurSigma: 10,
        child: child,
      ),
    );
  }
}

class _FoxySectionHeader extends StatelessWidget {
  const _FoxySectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoxySongTile extends StatelessWidget {
  const _FoxySongTile({
    required this.song,
    required this.onTap,
    this.onMore,
    this.trailingIcon = Icons.play_circle_fill_rounded,
    this.active = false,
    this.index,
    this.thumbRadius = 6,
    this.showPlayAndMore = false,
    this.kind = 'song',
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final IconData trailingIcon;
  final bool active;
  final int? index;
  final double thumbRadius;
  final String kind;

  /// When true with [onMore], shows both play and overflow actions (e.g. Downloads tab).
  final bool showPlayAndMore;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isArtist = kind == 'artist';
    final isAlbum = kind == 'album';
    final subtitleLabel = isArtist
        ? song.artist.ifBlank(song.title)
        : isAlbum
        ? song.artist.ifBlank((song.album ?? '')).ifBlank('Album')
        : song.artist.ifBlank((song.album ?? '')).ifBlank('Unknown artist');
    final meta = <Widget>[
      if (song.isDownloaded)
        const _HomeMetaPill(
          label: 'Offline',
          icon: Icons.download_done_rounded,
        ),
      if ((song.localPath ?? '').isNotEmpty)
        const _HomeMetaPill(label: 'Local', icon: Icons.folder_rounded),
      if ((song.duration ?? '').isNotEmpty)
        _HomeMetaPill(label: song.duration!),
    ];
    Widget trailing;
    if (onMore != null && showPlayAndMore) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play',
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(
                alpha: active ? 0.14 : 0.08,
              ),
              foregroundColor: active ? accent : Colors.white,
              minimumSize: const Size(38, 38),
            ),
            icon: Icon(trailingIcon, size: 19),
          ),
          const SizedBox(width: 2),
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              foregroundColor: Colors.white.withValues(alpha: 0.9),
              minimumSize: const Size(38, 38),
            ),
            icon: const Icon(Icons.more_vert_rounded, size: 18),
          ),
        ],
      );
    } else if (onMore != null) {
      trailing = IconButton(
        tooltip: 'More',
        onPressed: onMore,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.06),
          foregroundColor: Colors.white.withValues(alpha: 0.9),
          minimumSize: const Size(38, 38),
        ),
        icon: const Icon(Icons.more_vert_rounded, size: 18),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: onTap,
        style: IconButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: active ? 0.14 : 0.08),
          foregroundColor: active ? accent : Colors.white,
          minimumSize: const Size(38, 38),
        ),
        icon: Icon(trailingIcon, size: 19),
      );
    }

    return _FoxySurface(
      selected: active,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      onTap: onTap,
      frosted: false,
      child: Row(
        children: [
          if (index != null) ...[
            SizedBox(
              width: 24,
              child: Text(
                '${index! + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? accent : Colors.white.withValues(alpha: 0.42),
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _Artwork(
            url: song.highQualityArtwork,
            size: 50,
            radius: thumbRadius,
            identityTag: song.videoId,
            offlineArtworkPath: song.offlineArtworkPath,
            useOfflineArtwork: song.isDownloaded,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _OverflowMarqueeText(
                  text: isArtist ? song.artist.ifBlank(song.title) : song.title,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                    fontSize: 13.7,
                    height: 1.06,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _HomeMetaPill(label: subtitleLabel),
                    ...meta,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          trailing,
        ],
      ),
    );
  }
}

class _OverflowMarqueeText extends StatefulWidget {
  const _OverflowMarqueeText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_OverflowMarqueeText> createState() => _OverflowMarqueeTextState();
}

class _OverflowMarqueeTextState extends State<_OverflowMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  double _overflowPx = 0;
  double _measuredWidth = -1;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _syncAnimation(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) return;
    if ((_measuredWidth - maxWidth).abs() < 1 && _ctrl.duration != null) return;
    _measuredWidth = maxWidth;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    final nextOverflow = math.max(0.0, painter.width - maxWidth).toDouble();
    _overflowPx = nextOverflow;
    if (_overflowPx <= 2) {
      _ctrl.stop();
      _ctrl.value = 0;
      return;
    }
    final durationMs = (3200 + (_overflowPx * 24)).round().clamp(3600, 9000);
    _ctrl.duration = Duration(milliseconds: durationMs);
    if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncAnimation(constraints.maxWidth);
        });
        if (_overflowPx <= 2) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }
        return ClipRect(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final dx = -_overflowPx * Curves.easeInOut.transform(_ctrl.value);
              return Transform.translate(
                offset: Offset(dx, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.text, maxLines: 1, style: widget.style),
                    const SizedBox(width: 28),
                    Text(widget.text, maxLines: 1, style: widget.style),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _FoxyFeatureTile extends StatelessWidget {
  const _FoxyFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _FoxySurface(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// SimpMusic-style full-screen results with Songs / Videos / Albums / Artists tabs.
class _SearchResultsPage extends StatefulWidget {
  const _SearchResultsPage({required this.query, required this.onPlay});

  final String query;
  final _FoxyOnPlay onPlay;

  @override
  State<_SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<_SearchResultsPage>
    with SingleTickerProviderStateMixin {
  static const _searchLimit = 28;
  late final TabController _tabs;
  _SearchUiState _state = const _SearchUiState(loading: true);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cached = _SearchCache.get(widget.query, _searchLimit);
    if (cached != null) {
      setState(() {
        _state = _state.copyWith(loading: false, error: null, payload: cached);
      });
      return;
    }
    setState(() {
      _state = _state.copyWith(loading: true, error: null);
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': widget.query,
              'limit': _searchLimit,
            }),
          ) ??
          const {};
      if (!mounted) return;
      final payload = _SearchPayload.fromResponse(response);
      _SearchCache.put(widget.query, _searchLimit, payload);
      setState(() {
        _state = _state.copyWith(loading: false, payload: payload);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(loading: false, error: e.toString());
      });
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onDiscoverSearch: null,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  void _openCollection(_Song item, String kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionDetailPage(
          seed: item,
          kind: kind,
          onPlay: widget.onPlay,
          onDiscoverSearch: null,
        ),
      ),
    );
  }

  Widget _tabBody(
    List<_Song> items, {
    bool videoStyle = false,
    String kind = 'song',
  }) {
    if (_state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_state.error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (items.isEmpty) {
      return const _EmptyTabBody(
        icon: Icons.search_off_rounded,
        title: 'Nothing here',
        subtitle: 'Try another spelling or category.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final song = items[index];
        final collection = kind == 'album' || kind == 'artist';
        return _FoxySongTile(
          song: song,
          kind: kind,
          index: index,
          thumbRadius: 12,
          showPlayAndMore: true,
          trailingIcon: collection
              ? Icons.arrow_forward_rounded
              : videoStyle
              ? Icons.play_circle_outline_rounded
              : Icons.play_circle_fill_rounded,
          onTap: collection
              ? () => _openCollection(song, kind)
              : () => widget.onPlay(song, items, radioTail: !videoStyle),
          onMore: () => _openMenu(song, items),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _FoxyBrandGradientBackdrop(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.query,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'Results',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Material(
              color: Colors.black.withValues(alpha: 0.35),
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                indicatorColor: accent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
                labelStyle: const TextStyle(fontWeight: FontWeight.w800),
                tabs: [
                  Tab(
                    text:
                        'Songs (${_state.loading ? 'â€¦' : _state.songs.length})',
                  ),
                  Tab(
                    text:
                        'Videos (${_state.loading ? 'â€¦' : _state.videos.length})',
                  ),
                  Tab(
                    text:
                        'Albums (${_state.loading ? 'â€¦' : _state.albums.length})',
                  ),
                  Tab(
                    text:
                        'Artists (${_state.loading ? 'â€¦' : _state.artists.length})',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _tabBody(_state.songs),
                  _tabBody(_state.videos, videoStyle: true),
                  _tabBody(_state.albums, kind: 'album'),
                  _tabBody(_state.artists, kind: 'artist'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionDetailPage extends StatefulWidget {
  const _CollectionDetailPage({
    required this.seed,
    required this.kind,
    required this.onPlay,
    this.onDiscoverSearch,
  });

  final _Song seed;
  final String kind;
  final _FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_CollectionDetailPage> createState() => _CollectionDetailPageState();
}

class _CollectionDetailPageState extends State<_CollectionDetailPage> {
  static const _searchLimit = 32;
  _SearchUiState _state = const _SearchUiState(loading: true);

  bool get _isArtist => widget.kind == 'artist';

  String get _title => _isArtist
      ? widget.seed.artist.ifBlank(widget.seed.title)
      : widget.seed.title;

  String get _subtitle =>
      _isArtist ? 'Artist' : widget.seed.artist.ifBlank('Album');

  String get _query {
    final base = _title.trim();
    if (_isArtist) return '$base top songs music videos albums';
    final artist = widget.seed.artist.trim();
    return [
      artist,
      base,
      'album songs',
    ].where((part) => part.isNotEmpty).join(' ');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _SearchCache.get(_query, _searchLimit);
    if (cached != null) {
      setState(() {
        _state = _state.copyWith(loading: false, error: null, payload: cached);
      });
      return;
    }
    setState(() {
      _state = _state.copyWith(loading: true, error: null);
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': _query,
              'limit': _searchLimit,
            }),
          ) ??
          const {};
      if (!mounted) return;
      final payload = _SearchPayload.fromResponse(response);
      _SearchCache.put(_query, _searchLimit, payload);
      setState(() {
        _state = _state.copyWith(loading: false, payload: payload);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _state.copyWith(loading: false, error: e.toString());
      });
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  Widget _section(
    String title,
    List<_Song> items, {
    bool horizontal = false,
    bool videoStyle = false,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    if (horizontal) {
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FoxySectionHeader(title: title),
            SizedBox(
              height: 184,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: items.take(12).length,
                separatorBuilder: (context, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return SizedBox(
                    width: 148,
                    child: _FoxyGlassButton(
                      onTap: () => widget.onPlay(item, [item], radioTail: true),
                      borderRadius: BorderRadius.circular(10),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: _Artwork(
                                url: item.highQualityArtwork,
                                size: 132,
                                radius: 0,
                                identityTag: item.videoId,
                                highQuality: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            item.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FoxySectionHeader(title: title),
        for (final entry in items.take(14).toList().asMap().entries)
          _FoxySongTile(
            song: entry.value,
            index: entry.key,
            thumbRadius: videoStyle ? 10 : 8,
            trailingIcon: videoStyle
                ? Icons.play_circle_outline_rounded
                : Icons.play_circle_fill_rounded,
            showPlayAndMore: true,
            onTap: () =>
                widget.onPlay(entry.value, items, radioTail: !videoStyle),
            onMore: () => _openMenu(entry.value, items),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playable = _state.songs.isNotEmpty ? _state.songs : _state.videos;
    return Scaffold(
      backgroundColor: Colors.black,
      body: _FoxyBrandGradientBackdrop(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                        _Artwork(
                          url: widget.seed.highQualityArtwork,
                          size: 72,
                          radius: _isArtist ? 999 : 12,
                          identityTag: widget.seed.videoId,
                          highQuality: true,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.58),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: playable.isEmpty
                              ? null
                              : () => widget.onPlay(
                                  playable.first,
                                  playable,
                                  radioTail: true,
                                ),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Play'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _FoxyGlassButton(
                        onTap: () => widget.onDiscoverSearch?.call(_query),
                        borderRadius: BorderRadius.circular(999),
                        padding: const EdgeInsets.all(12),
                        child: const Icon(Icons.search_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              if (_state.loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_state.error != null)
                SliverToBoxAdapter(
                  child: _HomeError(message: _state.error!, onRetry: _load),
                )
              else ...[
                SliverToBoxAdapter(
                  child: _section(
                    _isArtist ? 'Top songs' : 'Album tracks',
                    _state.songs,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _section('Videos', _state.videos, videoStyle: true),
                ),
                if (_isArtist)
                  SliverToBoxAdapter(
                    child: _section(
                      'Albums and playlists',
                      _state.albums,
                      horizontal: true,
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: _section(
                      'Related artists',
                      _state.artists,
                      horizontal: true,
                    ),
                  ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchTab extends StatefulWidget {
  const _SearchTab({
    super.key,
    required this.onPlay,
    required this.onDiscoverSearch,
  });

  final _FoxyOnPlay onPlay;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  static const _searchLimit = 36;
  final TextEditingController _controller = TextEditingController();
  late final _SearchController _searchController;
  _SearchUiState get _state => _searchController.state;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _searchController = _SearchController();
  }

  @override
  void dispose() {
    _searchController.disposeController();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void applyExternalQuery(String raw) {
    _searchController.applyExternalQuery(
      raw,
      syncText: () {
        _controller.text = raw.trim();
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      },
    );
  }

  bool consumeAndroidBack() {
    final consumed = _searchController.consumeBack();
    if (consumed) _controller.clear();
    return consumed;
  }

  void _onChanged(String value) {
    _searchController.updateQuery(value);
  }

  void _submitSearch(String value) {
    unawaited(_searchController.submitSearch(value));
  }

  void _openCollection(_Song item, String kind) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CollectionDetailPage(
          seed: item,
          kind: kind,
          onPlay: widget.onPlay,
          onDiscoverSearch: widget.onDiscoverSearch,
        ),
      ),
    );
  }

  void _openMenu(_Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  List<_Song> _queueForKind(String kind) {
    return switch (kind) {
      'video' => _state.videos,
      'album' => _state.albums,
      'artist' => _state.artists,
      _ => _state.songs,
    };
  }

  Widget _buildSearchResultRow(_Song song, String kind) {
    final collection = kind == 'artist' || kind == 'album';
    final queue = _queueForKind(kind);
    return _SimpMusicSearchRow(
      song: song,
      kind: kind,
      onTap: collection
          ? () => _openCollection(song, kind)
          : () => widget.onPlay(
              song,
              queue.isEmpty ? [song] : queue,
              radioTail: kind != 'video',
            ),
      onMore: () => _openMenu(song, queue.isEmpty ? [song] : queue),
    );
  }

  List<Widget> _searchSectionSlivers(
    String title,
    String kind,
    List<_Song> items,
  ) {
    if (items.isEmpty) return const [];
    return [
      SliverToBoxAdapter(child: _SearchSectionHeader(title: title)),
      SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final song = items[index];
          return RepaintBoundary(child: _buildSearchResultRow(song, kind));
        }, childCount: items.length),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  List<Widget> _groupedResultSlivers() {
    final previewAlbums = _state.albums.take(3).toList(growable: false);
    return [
      ..._searchSectionSlivers('Albums', 'album', previewAlbums),
      ..._searchSectionSlivers('Songs', 'song', _state.songs),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final suggestions = const [
      'Arijit Singh',
      'Punjabi hits',
      'Lo-fi Hindi',
      'Workout mix',
      'New music',
      'Romantic songs',
    ];
    return CustomScrollView(
      key: const PageStorageKey('search-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 400,
      slivers: [
        ValueListenableBuilder<_SearchUiState>(
          valueListenable: _searchController.stateListenable,
          builder: (context, state, _) {
            final accent = Theme.of(context).colorScheme.primary;
            final showResults = state.query.trim().length >= 2;
            return SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FoxyGlassTint(
                        borderRadius: 28,
                        tintOpacity: 0.52,
                        borderOpacity: 0.16,
                        blur: true,
                        blurSigma: 16,
                        child: TextField(
                          controller: _controller,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          onChanged: _onChanged,
                          onSubmitted: _submitSearch,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search songs, artists, albums',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                            ),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              color: Colors.white.withValues(alpha: 0.55),
                            ),
                            suffixIcon: state.query.isNotEmpty
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: _FoxyGlassButton(
                                      onTap: () {
                                        _controller.clear();
                                        _onChanged('');
                                      },
                                      borderRadius: BorderRadius.circular(999),
                                      padding: EdgeInsets.zero,
                                      child: const SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white70,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  )
                                : null,
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide(
                                color: accent.withValues(alpha: 0.55),
                                width: 1.2,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(28),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      if (showResults) ...[
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final label in _searchFilterChips)
                                _TopFilterChip(
                                  label: label,
                                  selected: state.filter == label,
                                  onTap: () =>
                                      _searchController.setFilter(label),
                                ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final item in suggestions)
                              _FoxyGlassButton(
                                onTap: () {
                                  _controller.text = item;
                                  _controller.selection =
                                      TextSelection.collapsed(
                                        offset: item.length,
                                      );
                                  _submitSearch(item);
                                },
                                borderRadius: BorderRadius.circular(28),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Text(
                                  item,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (state.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          state.error!,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        ValueListenableBuilder<_SearchUiState>(
          valueListenable: _searchController.stateListenable,
          builder: (context, state, _) {
            final showResults = state.query.trim().length >= 2;
            if (showResults && state.loading) {
              return const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              );
            }
            if (showResults && state.filter == 'All') {
              return SliverMainAxisGroup(slivers: _groupedResultSlivers());
            }
            final rows = switch (state.filter) {
              'Songs' =>
                state.songs.map((s) => (song: s, kind: 'song')).toList(),
              'Videos' =>
                state.videos.map((s) => (song: s, kind: 'video')).toList(),
              'Albums' =>
                state.albums.map((s) => (song: s, kind: 'album')).toList(),
              'Artists' =>
                state.artists.map((s) => (song: s, kind: 'artist')).toList(),
              _ => <({_Song song, String kind})>[],
            };
            if (showResults && rows.isEmpty && state.error == null) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No results for â€œ${state.query.trim()}â€',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }
            if (showResults) {
              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final row = rows[index];
                  return RepaintBoundary(
                    child: _buildSearchResultRow(row.song, row.kind),
                  );
                }, childCount: rows.length),
              );
            }
            return const SliverToBoxAdapter(child: SizedBox.shrink());
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _SimpMusicSearchRow extends StatelessWidget {
  const _SimpMusicSearchRow({
    required this.song,
    required this.kind,
    required this.onTap,
    required this.onMore,
  });

  final _Song song;
  final String kind;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isArtist = kind == 'artist';
    final isCollection = kind == 'artist' || kind == 'album';
    final thumbSize = 50.0;
    final secondaryLabel = switch (kind) {
      'artist' => 'Artist',
      'album' => song.artist.ifBlank((song.album ?? '')).ifBlank('Album'),
      'video' => song.artist.ifBlank('Video'),
      _ => song.artist.ifBlank((song.album ?? '')).ifBlank('Unknown artist'),
    };
    Widget leading;
    if (isArtist) {
      leading = ClipOval(
        child: _Artwork(
          url: song.highQualityArtwork,
          size: thumbSize,
          radius: 0,
          identityTag: song.videoId,
        ),
      );
    } else {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: _Artwork(
          url: song.highQualityArtwork,
          size: thumbSize,
          radius: 0,
          identityTag: song.videoId,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        tintOpacity: 0.13,
        borderOpacity: 0.04,
        blurSigma: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Row(
          children: [
            Stack(
              children: [
                leading,
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isArtist ? 999 : 12),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OverflowMarqueeText(
                    text: isArtist
                        ? song.artist.ifBlank(song.title)
                        : song.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.7,
                      height: 1.06,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _HomeMetaPill(label: secondaryLabel),
                      if (!isArtist && (song.duration ?? '').trim().isNotEmpty)
                        _HomeMetaPill(label: song.duration ?? ''),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (isCollection)
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: 0.76),
                  size: 18,
                ),
              )
            else
              _FoxyGlassButton(
                onTap: onMore,
                borderRadius: BorderRadius.circular(999),
                tintOpacity: 0.10,
                borderOpacity: 0.06,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white.withValues(alpha: 0.86),
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchSectionHeader extends StatelessWidget {
  const _SearchSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _LibraryRichTile extends StatelessWidget {
  const _LibraryRichTile({
    required this.color,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      tintOpacity: 0.16,
      borderOpacity: 0.05,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.26)),
            ),
            child: Icon(icon, color: color, size: 23),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15.2,
                    height: 1.1,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward_ios_rounded,
            color: Colors.white.withValues(alpha: 0.42),
            size: 14,
          ),
        ],
      ),
    );
  }
}

class _PlaylistCollectionCard extends StatelessWidget {
  const _PlaylistCollectionCard({
    required this.playlist,
    required this.onOpen,
    required this.onPlay,
    this.onMore,
  });

  final _UserPlaylist playlist;
  final VoidCallback onOpen;
  final VoidCallback onPlay;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _FoxyGlassButton(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        tintOpacity: 0.16,
        borderOpacity: 0.05,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
          child: Row(
            children: [
              _PlaylistArtwork(playlist: playlist, size: 58, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _PlaylistMetaPill(playlist: playlist),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _FoxyGlassButton(
                onTap: onPlay,
                borderRadius: BorderRadius.circular(999),
                tintOpacity: 0.10,
                borderOpacity: 0.06,
                padding: EdgeInsets.zero,
                child: const SizedBox(
                  width: 38,
                  height: 38,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              if (onMore != null) ...[
                const SizedBox(width: 6),
                _FoxyGlassButton(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(999),
                  tintOpacity: 0.10,
                  borderOpacity: 0.06,
                  padding: EdgeInsets.zero,
                  child: const SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.more_horiz_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Foxy-style downloads summary (storage + offline count).
class _FoxyDownloadsHeader extends StatefulWidget {
  const _FoxyDownloadsHeader({
    required this.songCount,
    required this.activeCount,
    this.onPlayAll,
  });

  final int songCount;
  final int activeCount;
  final VoidCallback? onPlayAll;

  @override
  State<_FoxyDownloadsHeader> createState() => _FoxyDownloadsHeaderState();
}

class _FoxyDownloadsHeaderState extends State<_FoxyDownloadsHeader> {
  Map<String, dynamic> _storage = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw =
          _asMap(await _method.invokeMethod('storageStats')) ?? const {};
      if (!mounted) return;
      setState(() {
        _storage = raw;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final bytes = ((_storage['downloadBytes'] ?? 0) as num).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: _FoxyGlassTint(
        borderRadius: _kCardRadius,
        tintOpacity: 0.5,
        borderOpacity: 0.1,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_done_rounded, color: accent, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Downloads',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          _loading
                              ? 'Calculating storageâ€¦'
                              : '${widget.songCount} songs offline | ${_formatStorageBytes(bytes)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onPlayAll != null)
                    FilledButton.icon(
                      onPressed: widget.onPlayAll,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('Play all'),
                    ),
                ],
              ),
              if (widget.activeCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${widget.activeCount} active download${widget.activeCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: accent.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    super.key,
    required this.onPlay,
    required this.onOpenSearch,
    required this.onDiscoverSearch,
    required this.currentVideoIdListenable,
  });

  final _FoxyOnPlay onPlay;
  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;
  final ValueListenable<Object?> currentVideoIdListenable;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin {
  static const int _scopeHub = 0;
  static const int _scopeLiked = 1;
  static const int _scopeHistory = 2;
  static const int _scopeDownloads = 3;
  static const int _scopeMostPlayed = 4;
  static const int _scopePlaylists = 5;
  static const int _scopeLocal = 6;

  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _downloads = const [];
  List<_Song> _local = const [];
  List<_Song> _mostPlayed = const [];
  List<_Song> _recentlyAdded = const [];
  List<_Song> _explore = const [];
  List<_UserPlaylist> _userPlaylists = const [];
  int _scope = _scopeHub;
  final Map<String, double> _downloadProgress = {};
  final ValueNotifier<Map<String, double>> _downloadProgressListenable =
      ValueNotifier<Map<String, double>>(const {});
  StreamSubscription<dynamic>? _libraryEvents;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _libraryEvents = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null || !mounted) return;
      final type = map['type']?.toString();
      if (type == 'libraryDownloadProgress') {
        final raw = _asMap(map['downloadProgress']);
        if (raw == null) return;
        final next = <String, double>{};
        raw.forEach((k, v) {
          if (v is num) next[k.toString()] = v.toDouble();
        });
        _downloadProgress
          ..clear()
          ..addAll(next);
        _downloadProgressListenable.value = Map<String, double>.unmodifiable(
          _downloadProgress,
        );
      } else if (type == 'libraryDownloadsChanged' ||
          type == 'libraryFeedChanged' ||
          type == 'accountChanged') {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _libraryEvents?.cancel();
    _downloadProgressListenable.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final response =
        _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;

    List<_Song> downloads = _songsFrom(response['downloads']);

    // Sort downloads by newest first (descending order) - newest at top
    downloads.sort((a, b) {
      // Simple stable sort: reverse order of videoId (newer IDs tend to be larger)
      return b.videoId.compareTo(a.videoId);
    });

    setState(() {
      _liked = _songsFrom(response['liked']);
      _history = _songsFrom(response['history']);
      _downloads = downloads;
      _local = _songsFrom(response['local']);
      _mostPlayed = _songsFrom(response['mostPlayed']);
      _recentlyAdded = _songsFrom(response['recentlyAdded']);
      _explore = _songsFrom(response['explore']);
      _userPlaylists = _userPlaylistsFrom(response['userPlaylists']);
      _loading = false;
    });
  }

  bool get _hub => _scope == _scopeHub;

  List<_Song> get _activeSongs {
    switch (_scope) {
      case _scopeLiked:
        return _liked;
      case _scopeHistory:
        return _history;
      case _scopeDownloads:
        return _downloads;
      case _scopeLocal:
        return _local;
      case _scopeMostPlayed:
        return _mostPlayed;
      case _scopePlaylists:
        return const [];
      default:
        return _recentlyAdded.isNotEmpty ? _recentlyAdded : _explore;
    }
  }

  String get _sectionTitle {
    switch (_scope) {
      case _scopeLiked:
        return 'Liked';
      case _scopeHistory:
        return 'History';
      case _scopeDownloads:
        return 'Downloaded';
      case _scopeLocal:
        return 'Local files';
      case _scopeMostPlayed:
        return 'Most played';
      case _scopePlaylists:
        return 'Your playlists';
      default:
        return _recentlyAdded.isNotEmpty
            ? 'Recently played'
            : 'Recommended for you';
    }
  }

  void _goHub() => setState(() => _scope = _scopeHub);

  /// Used from Home to jump into Library drill-ins.
  void openAtScope(int scope) {
    if (!mounted) return;
    setState(() {
      _scope = scope.clamp(_scopeHub, _scopeLocal);
    });
  }

  /// System back: leave a library drill-in (Liked, History, â€¦) before tabs handle back.
  bool consumeAndroidBack() {
    if (_hub) return false;
    _goHub();
    return true;
  }

  void _openSongOverflow(BuildContext context, _Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: _load,
      downloadsOnlyPlayback: _scope == _scopeDownloads,
    );
  }

  Future<void> _playUserPlaylist(
    BuildContext snackContext,
    _UserPlaylist p,
  ) async {
    await _playFetchedUserPlaylist(snackContext, p, widget.onPlay);
  }

  Future<void> _shuffleUserPlaylist(
    BuildContext snackContext,
    _UserPlaylist p,
  ) async {
    var songs = p.songs;
    if (p.isYoutube && songs.isEmpty) {
      final raw = await _method.invokeMethod('playlistFetchSongs', {
        'playlistId': p.id,
      });
      songs = _songsFrom(raw);
    }
    if (songs.isEmpty) {
      if (snackContext.mounted) {
        ScaffoldMessenger.of(
          snackContext,
        ).showSnackBar(const SnackBar(content: Text('This playlist is empty')));
      }
      return;
    }
    final shuffled = List<_Song>.from(songs)..shuffle();
    widget.onPlay(shuffled.first, shuffled);
  }

  Future<void> _promptCreatePlaylist() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('New playlist'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'Late-night mix'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, c.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _method.invokeMethod('playlistCreate', {'name': name});
    await _load();
  }

  Future<void> _renamePlaylist(_UserPlaylist playlist) async {
    final c = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Rename playlist'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == playlist.name || !mounted) {
      return;
    }
    await _method.invokeMethod('playlistRename', {
      'playlistId': playlist.id,
      'name': name,
    });
    await _load();
  }

  Future<void> _deletePlaylist(_UserPlaylist playlist) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete playlist?'),
        content: Text(
          'Delete "${playlist.name}" from your library? Songs themselves will stay available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _method.invokeMethod('playlistDelete', {'playlistId': playlist.id});
    await _load();
  }

  Future<void> _showPlaylistActions(_UserPlaylist playlist) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF151515),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Play playlist'),
              onTap: () => Navigator.pop(ctx, 'play'),
            ),
            ListTile(
              leading: const Icon(Icons.shuffle_rounded),
              title: const Text('Shuffle play'),
              onTap: () => Navigator.pop(ctx, 'shuffle'),
            ),
            if (!playlist.isYoutube)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
            if (!playlist.isYoutube)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'play':
        await _playUserPlaylist(context, playlist);
        break;
      case 'shuffle':
        await _shuffleUserPlaylist(context, playlist);
        break;
      case 'rename':
        await _renamePlaylist(playlist);
        break;
      case 'delete':
        await _deletePlaylist(playlist);
        break;
    }
  }

  Future<void> _openPlaylistSheet(_UserPlaylist p) async {
    var songs = p.songs;
    if (p.isYoutube && songs.isEmpty) {
      final raw = await _method.invokeMethod('playlistFetchSongs', {
        'playlistId': p.id,
      });
      songs = _songsFrom(raw);
    }
    final parentContext = context;
    if (!parentContext.mounted) return;
    await showModalBottomSheet<void>(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.68,
          maxChildSize: 0.92,
          builder: (_, scroll) => CustomScrollView(
            controller: scroll,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _PlaylistArtwork(
                          playlist: _UserPlaylist(
                            id: p.id,
                            name: p.name,
                            songs: songs,
                            source: p.source,
                            songCount: p.songCount,
                          ),
                          size: 62,
                          radius: 16,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              p.isYoutube
                                  ? '${songs.length} songs | YouTube Music'
                                  : '${songs.length} songs | On device',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _PlaylistMetaPill(playlist: p),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _showPlaylistActions(p),
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                      const SizedBox(width: 2),
                      FilledButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => widget.onPlay(songs.first, songs),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Play'),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () {
                                final shuffled = List<_Song>.from(songs)
                                  ..shuffle();
                                widget.onPlay(shuffled.first, shuffled);
                              },
                        icon: const Icon(Icons.shuffle_rounded, size: 18),
                        label: const Text('Shuffle'),
                      ),
                    ],
                  ),
                ),
              ),
              if (songs.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyTabBody(
                    icon: Icons.queue_music_rounded,
                    title: 'Playlist is empty',
                    subtitle: 'Add songs from the track menu.',
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: songs.length,
                    onReorder: (oldIndex, newIndex) async {
                      final adjusted = newIndex > oldIndex
                          ? newIndex - 1
                          : newIndex;
                      final next = List<_Song>.from(songs);
                      final moved = next.removeAt(oldIndex);
                      next.insert(adjusted, moved);
                      setSheetState(() => songs = next);
                      if (!p.isYoutube) {
                        await _method.invokeMethod('playlistMoveSong', {
                          'playlistId': p.id,
                          'fromIndex': oldIndex,
                          'toIndex': adjusted,
                        });
                        await _load();
                      }
                    },
                    itemBuilder: (context, j) {
                      final song = songs[j];
                      return Row(
                        key: ValueKey('playlist-${p.id}-${song.videoId}'),
                        children: [
                          if (!p.isYoutube)
                            ReorderableDragStartListener(
                              index: j,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 12),
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.white.withValues(alpha: 0.42),
                                ),
                              ),
                            )
                          else
                            const SizedBox(width: 12),
                          Expanded(
                            child: _FoxySongTile(
                              song: song,
                              index: j,
                              thumbRadius: 10,
                              showPlayAndMore: true,
                              onTap: () => widget.onPlay(song, songs),
                              onMore: () =>
                                  _openSongOverflow(parentContext, song, songs),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  void _shuffleCurrent() {
    final s = _activeSongs;
    if (s.isEmpty) return;
    final list = List<_Song>.from(s)..shuffle(math.Random());
    widget.onPlay(list.first, list, downloadsOnly: _scope == _scopeDownloads);
  }

  Future<void> _importLocalAudio() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final raw = await _method.invokeMethod('importLocalAudio');
      final map = _asMap(raw) ?? const {};
      final imported = ((map['imported'] ?? 0) as num).toInt();
      await _load();
      if (!mounted) return;
      setState(() => _scope = _scopeLocal);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Imported $imported local track${imported == 1 ? '' : 's'}.'
                : 'No new local audio was imported.',
          ),
        ),
      );
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not import local audio.')),
      );
    }
  }

  Widget _librarySectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildPlaylistEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 18),
      child: _FoxyGlassButton(
        onTap: _promptCreatePlaylist,
        borderRadius: BorderRadius.circular(20),
        tintOpacity: 0.28,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.queue_music_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'No playlists yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start a mix of your own, then add songs from the track menu or bring in YouTube Music playlists from Account.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _promptCreatePlaylist,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Create playlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaylistList() {
    if (_userPlaylists.isEmpty) return _buildPlaylistEmptyState();
    return RepaintBoundary(
      child: Column(
        children: [
          for (final p in _userPlaylists)
            _PlaylistCollectionCard(
              playlist: p,
              onOpen: () => _openPlaylistSheet(p),
              onPlay: () => _playUserPlaylist(context, p),
              onMore: () => _showPlaylistActions(p),
            ),
        ],
      ),
    );
  }

  Widget _buildScopeSongTile(List<_Song> songs, int index) {
    final song = songs[index];
    final downloadsOnly = _scope == _scopeDownloads;
    final radioTail = !downloadsOnly && _scope != _scopeLocal;
    return RepaintBoundary(
      child: ValueListenableBuilder<Object?>(
        valueListenable: widget.currentVideoIdListenable,
        builder: (context, currentVideoIdValue, _) {
          final currentVideoId = currentVideoIdValue?.toString() ?? '';
          return _FoxySongTile(
            song: song,
            index: index,
            active: song.videoId == currentVideoId,
            thumbRadius: 12,
            trailingIcon: Icons.play_circle_fill_rounded,
            showPlayAndMore: true,
            onTap: () => widget.onPlay(
              song,
              radioTail ? [song] : songs,
              radioTail: radioTail,
              downloadsOnly: downloadsOnly,
            ),
            onMore: () => _openSongOverflow(context, song, songs),
          );
        },
      ),
    );
  }

  Widget _hubGrid() {
    void pick(String q) => widget.onDiscoverSearch(q);
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _librarySectionTitle('PICKS FOR YOU'),
            Row(
              children: [
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFFFB74D),
                    icon: Icons.auto_awesome_rounded,
                    title: 'Quick picks',
                    subtitle: 'Fresh mixes',
                    onTap: () => pick('quick pick music'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFF80DEEA),
                    icon: Icons.explore_rounded,
                    title: 'Your Daily Discover',
                    subtitle: 'Personal blend',
                    onTap: () => pick('discover mix today'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFF48FB1),
                    icon: Icons.new_releases_rounded,
                    title: 'New releases',
                    subtitle: 'Latest drops',
                    onTap: () => pick('new release music'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFCE93D8),
                    icon: Icons.stacked_line_chart_rounded,
                    title: 'Charts',
                    subtitle: "What's trending",
                    onTap: () => pick('top songs charts today'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFA1887F),
                    icon: Icons.shuffle_rounded,
                    title: 'Mixed for you',
                    subtitle: 'Genre blend',
                    onTap: () => pick('mixed pop hits playlist'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFF7986CB),
                    icon: Icons.local_fire_department_rounded,
                    title: 'Trending now',
                    subtitle: 'Hot tracks',
                    onTap: () => pick('trending songs now'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFFF8A65),
                    icon: Icons.bolt_rounded,
                    title: 'Energy boost',
                    subtitle: 'Workout & drive',
                    onTap: () => pick('high energy workout music'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFF81C784),
                    icon: Icons.spa_rounded,
                    title: 'Chill & focus',
                    subtitle: 'Wind down',
                    onTap: () => pick('chill relax focus music'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFF64B5F6),
                    icon: Icons.nightlight_round,
                    title: 'Sleep sounds',
                    subtitle: 'Soft & calm',
                    onTap: () => pick('sleep ambient music'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LibraryRichTile(
                    color: const Color(0xFFFFD54F),
                    icon: Icons.wb_sunny_rounded,
                    title: 'Feel-good',
                    subtitle: 'Sunshine vibes',
                    onTap: () => pick('feel good happy songs'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _LibraryRichTile(
              color: const Color(0xFF4FC3F7),
              icon: Icons.podcasts_rounded,
              title: 'Deep cuts',
              subtitle: 'Hidden gems & live',
              onTap: () => pick('deep cuts live sessions'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final songs = _activeSongs;
    final chips = <(IconData, String, int)>[
      (Icons.explore_rounded, 'Discover', _scopeHub),
      (Icons.favorite_rounded, 'Liked', _scopeLiked),
      (Icons.history_rounded, 'History', _scopeHistory),
      (Icons.download_rounded, 'Downloads', _scopeDownloads),
      (Icons.folder_rounded, 'Local', _scopeLocal),
      (Icons.trending_up_rounded, 'Most played', _scopeMostPlayed),
      (Icons.playlist_play_rounded, 'Playlists', _scopePlaylists),
    ];

    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 400,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            leading: !_hub
                ? _GlassIconButton(
                    tooltip: 'Back to Discover',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _goHub,
                  )
                : null,
            title: 'Library',
            subtitle: _hub
                ? '${_liked.length} liked | ${_downloads.length} offline | ${_local.length} local | ${_userPlaylists.length} playlists'
                : _sectionTitle,
            onRefresh: _load,
            onSearch: widget.onOpenSearch,
            onDownloads: _hub
                ? () => setState(() => _scope = _scopeDownloads)
                : null,
            onImport: _hub || _scope == _scopeLocal ? _importLocalAudio : null,
            onSparkle: () => widget.onDiscoverSearch('top songs charts today'),
          ),
        ),
        if (_scope == _scopeDownloads)
          ValueListenableBuilder<Map<String, double>>(
            valueListenable: _downloadProgressListenable,
            builder: (context, downloadProgress, _) {
              return SliverToBoxAdapter(
                child: _FoxyDownloadsHeader(
                  songCount: _downloads.length,
                  activeCount: downloadProgress.length,
                  onPlayAll: _downloads.isEmpty
                      ? null
                      : () => widget.onPlay(
                          _downloads.first,
                          _downloads,
                          downloadsOnly: true,
                        ),
                ),
              );
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final chip in chips)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FoxyGlassButton(
                        onTap: () => setState(() => _scope = chip.$3),
                        selected: _scope == chip.$3,
                        tintOpacity: _scope == chip.$3 ? 0.26 : 0.14,
                        borderRadius: BorderRadius.circular(20),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(chip.$1, size: 18, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              chip.$2,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_hub) ...[
          SliverToBoxAdapter(child: _hubGrid()),
          if (_userPlaylists.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                child: Row(
                  children: [
                    Text(
                      'Playlists',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _promptCreatePlaylist,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('New'),
                    ),
                  ],
                ),
              ),
            ),
          if (_userPlaylists.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 118,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _userPlaylists.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = _userPlaylists[i];
                    return _PlaylistCard(
                      playlist: p,
                      width: 222,
                      onTap: () => _openPlaylistSheet(p),
                      onMore: () => _showPlaylistActions(p),
                    );
                  },
                ),
              ),
            ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
            child: Row(
              children: [
                Text(
                  _hub ? 'Recently added' : _sectionTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                if (songs.isNotEmpty && _scope != _scopePlaylists) ...[
                  IconButton.filledTonal(
                    tooltip: 'Shuffle',
                    onPressed: _shuffleCurrent,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => widget.onPlay(
                      songs.first,
                      songs,
                      downloadsOnly: _scope == _scopeDownloads,
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_scope == _scopeDownloads)
          ValueListenableBuilder<Map<String, double>>(
            valueListenable: _downloadProgressListenable,
            builder: (context, downloadProgress, _) {
              if (downloadProgress.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _FoxyGlassTint(
                    borderRadius: _kCardRadius,
                    tintOpacity: 0.2,
                    borderOpacity: 0.08,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Active downloads',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const SizedBox(height: 10),
                          for (final e in downloadProgress.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _songTitleForVideoId(
                                          e.key,
                                          _liked,
                                          _history,
                                          _downloads,
                                          _recentlyAdded,
                                          _mostPlayed,
                                        ) ??
                                        'Track ${e.key}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: e.value.clamp(0.0, 1.0),
                                      minHeight: 5,
                                      backgroundColor: Colors.black.withValues(
                                        alpha: 0.25,
                                      ),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        if (_scope == _scopePlaylists)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildPlaylistList(),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (songs.isEmpty && _scope != _scopePlaylists)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_sectionTitle),
              title: 'Nothing here yet',
              subtitle: _scope == _scopeLocal
                  ? 'Import FLAC, MP3, M4A, OGG, WAV, or Opus files from this device.'
                  : 'Play music, like tracks, and download for offline â€” your library grows automatically.',
            ),
          )
        else if (_scope != _scopePlaylists && songs.isNotEmpty)
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) => _buildScopeSongTile(songs, index),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _AccountHubBody extends StatefulWidget {
  const _AccountHubBody({
    required this.onPlay,
    required this.currentVideoIdListenable,
  });

  final _FoxyOnPlay onPlay;
  final ValueListenable<Object?> currentVideoIdListenable;

  @override
  State<_AccountHubBody> createState() => _AccountHubBodyState();
}

class _AccountHubBodyState extends State<_AccountHubBody>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _appearance = const {};
  Map<String, dynamic> _account = const {};
  Map<String, List<_Song>> _library = const {};
  List<_UserPlaylist> _playlists = const [];
  int _section = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('getAppearance'),
      _method.invokeMethod('accountInfo'),
      _method.invokeMethod('libraryFeed'),
    ]);
    final appearance = _asMap(values[0]) ?? const {};
    final account = _asMap(values[1]) ?? const {};
    final libraryMap = _asMap(values[2]) ?? const {};
    final library = <String, List<_Song>>{
      'Liked': _songsFrom(libraryMap['liked']),
      'Playlists': _songsFrom(libraryMap['playlists'] ?? libraryMap['saved']),
      'History': _songsFrom(libraryMap['history']),
      'Downloads': _songsFrom(libraryMap['downloads']),
      'Local': _songsFrom(libraryMap['local']),
    };
    final playlists = _userPlaylistsFrom(
      libraryMap['userPlaylists'] ?? libraryMap['playlistsMeta'],
    );
    if (mounted) {
      setState(() {
        _appearance = appearance;
        _account = account;
        _library = library;
        _playlists = playlists;
      });
    }
  }

  Widget _buildAccountSongTile(List<_Song> songs, int index) {
    final song = songs[index];
    return RepaintBoundary(
      child: ValueListenableBuilder<Object?>(
        valueListenable: widget.currentVideoIdListenable,
        builder: (context, currentVideoIdValue, _) {
          final currentVideoId = currentVideoIdValue?.toString() ?? '';
          return _FoxySongTile(
            song: song,
            index: index,
            active: song.videoId == currentVideoId,
            thumbRadius: 10,
            onTap: () => widget.onPlay(song, songs, radioTail: true),
          );
        },
      ),
    );
  }

  Widget _buildAccountPlaylists() {
    if (_playlists.isEmpty) {
      return _EmptyTabBody(
        icon: Icons.playlist_play_rounded,
        title: 'No Playlists yet',
        subtitle: 'Your synced and on-device playlists will show up here.',
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          for (final playlist in _playlists)
            _PlaylistCollectionCard(
              playlist: playlist,
              onOpen: () =>
                  _playFetchedUserPlaylist(context, playlist, widget.onPlay),
              onPlay: () =>
                  _playFetchedUserPlaylist(context, playlist, widget.onPlay),
              onMore: null,
            ),
        ],
      ),
    );
  }

  Future<void> _setAppearance(Map<String, dynamic> patch) async {
    await _method.invokeMethod('setAppearance', patch);
    await _load();
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettingsSheet(
        appearance: _appearance,
        onSetAppearance: _setAppearance,
        account: _account,
        onAccountRefresh: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final signedIn = _account['isSignedIn'] == true;
    final displayName =
        _account['displayName']?.toString().ifBlank('Guest listener') ??
        'Guest listener';
    final email = _account['email']?.toString() ?? '';
    final avatar = _account['avatarUrl']?.toString() ?? '';
    final sections = _library.keys.toList();
    final selectedTitle = sections.isEmpty
        ? 'Liked'
        : sections[_section.clamp(0, sections.length - 1).toInt()];
    final songs = _library[selectedTitle] ?? const [];
    final showingPlaylists =
        selectedTitle == 'Playlists' && _playlists.isNotEmpty;
    return CustomScrollView(
      key: const PageStorageKey('me-scroll'),
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  _AccountAvatar(name: displayName, imageUrl: avatar, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          signedIn
                              ? email.ifBlank('YouTube Music connected')
                              : 'Connect YouTube Music for your library',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_rounded),
                    tooltip: 'Settings',
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AccountSummaryCard(
                  signedIn: signedIn,
                  liked: ((_account['likedCount'] ?? 0) as num).toInt(),
                  playlists: ((_account['playlistCount'] ?? 0) as num).toInt(),
                  downloads: ((_account['downloadCount'] ?? 0) as num).toInt(),
                ),
                const SizedBox(height: 12),
                _FoxyFeatureTile(
                  icon: signedIn ? Icons.verified_rounded : Icons.login_rounded,
                  title: signedIn
                      ? 'Account connected'
                      : 'Connect YouTube Music',
                  subtitle: signedIn
                      ? 'Personalized home, account library, and recommendations are active.'
                      : 'Sign in for personalized home, library sync foundation, and better results.',
                  onTap: () async {
                    await _showYoutubeAccountSheet(
                      context,
                      account: _account,
                      onAccountRefresh: _load,
                    );
                    if (!mounted) return;
                    await _load();
                  },
                ),
                _FoxyFeatureTile(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Player and audio',
                  subtitle:
                      'Equalizer, queue memory, crossfade, sleep timer, and stream quality.',
                  onTap: _openSettings,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemCount: sections.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final label = sections[index];
                      return ChoiceChip(
                        selected: _section == index,
                        label: Text(label),
                        avatar: Icon(_sectionIcon(label), size: 18),
                        onSelected: (_) => setState(() => _section = index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showingPlaylists)
          SliverToBoxAdapter(child: _buildAccountPlaylists())
        else if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(selectedTitle),
              title: 'No $selectedTitle yet',
              subtitle: selectedTitle == 'Playlists'
                  ? 'Saved playlists and library collections will appear here.'
                  : 'Your $selectedTitle songs will show up here.',
            ),
          )
        else
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) =>
                _buildAccountSongTile(songs, index),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 172)),
      ],
    );
  }
}

List<_Song> _songsFrom(dynamic value) => (value as List? ?? const [])
    .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
    .where((song) => song.videoId.isNotEmpty)
    .toList();

class _UserPlaylist {
  const _UserPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    this.source = 'local',
    this.songCount,
  });

  factory _UserPlaylist.fromMap(Map<String, dynamic> map) => _UserPlaylist(
    id: map['id']?.toString() ?? '',
    name: map['name']?.toString() ?? 'Playlist',
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList(),
    source: map['source']?.toString() ?? 'local',
    songCount: (map['songCount'] as num?)?.toInt(),
  );

  final String id;
  final String name;
  final List<_Song> songs;
  final String source;
  final int? songCount;

  bool get isYoutube => source == 'youtube';

  int get displayTrackCount =>
      songs.isNotEmpty ? songs.length : (songCount ?? 0);
}

class _PlaylistMetaPill extends StatelessWidget {
  const _PlaylistMetaPill({required this.playlist});

  final _UserPlaylist playlist;

  @override
  Widget build(BuildContext context) {
    final accent = playlist.isYoutube
        ? const Color(0xFFFF6B3D)
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            playlist.isYoutube
                ? Icons.cloud_queue_rounded
                : Icons.queue_music_rounded,
            size: 14,
            color: accent.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              playlist.isYoutube
                  ? '${playlist.displayTrackCount} songs â€¢ YouTube Music'
                  : '${playlist.displayTrackCount} songs â€¢ On device',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.74),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({
    required this.playlist,
    required this.size,
    this.radius = 14,
  });

  final _UserPlaylist playlist;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final arts = playlist.songs
        .map((song) => song.artwork)
        .where((art) => art.isNotEmpty)
        .take(4)
        .toList();
    final base = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: playlist.isYoutube
            ? [const Color(0xFF5A2A20), const Color(0xFF1B1B1B)]
            : [const Color(0xFF2B2B2B), const Color(0xFF121212)],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
    if (arts.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: base,
        child: Icon(
          playlist.isYoutube
              ? Icons.library_music_rounded
              : Icons.queue_music_rounded,
          color: Colors.white.withValues(alpha: 0.88),
          size: size * 0.34,
        ),
      );
    }
    final gap = size * 0.04;
    final tile = (size - gap) / 2;
    return Container(
      width: size,
      height: size,
      decoration: base,
      padding: EdgeInsets.all(gap / 2),
      child: Wrap(
        spacing: gap,
        runSpacing: gap,
        children: List.generate(4, (index) {
          final art = index < arts.length ? arts[index] : '';
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius * 0.36),
            child: art.isEmpty
                ? Container(
                    width: tile,
                    height: tile,
                    color: Colors.white.withValues(alpha: 0.06),
                  )
                : Image.network(
                    art,
                    width: tile,
                    height: tile,
                    fit: BoxFit.cover,
                  ),
          );
        }),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.width,
    required this.onTap,
    required this.onMore,
  });

  final _UserPlaylist playlist;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassButton(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      tintOpacity: 0.28,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PlaylistArtwork(playlist: playlist, size: 50, radius: 13),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        playlist.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    splashRadius: 18,
                    onPressed: onMore,
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  ),
                ],
              ),
              const Spacer(),
              _PlaylistMetaPill(playlist: playlist),
            ],
          ),
        ),
      ),
    );
  }
}

List<_UserPlaylist> _userPlaylistsFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _UserPlaylist.fromMap(_asMap(e) ?? const {}))
        .where((p) => p.id.isNotEmpty)
        .toList();

/// Lightweight menu state (no full [libraryFeed] / network).
class _SongMenuContext {
  const _SongMenuContext({
    required this.likedIds,
    required this.downloadedIds,
    required this.userPlaylists,
    required this.lrclib,
    required this.lyricsRoman,
    required this.crossfadeMs,
    required this.normalizeOn,
  });

  final Set<String> likedIds;
  final Set<String> downloadedIds;
  final List<_UserPlaylist> userPlaylists;
  final bool lrclib;
  final bool lyricsRoman;
  final int crossfadeMs;
  final bool normalizeOn;

  static _SongMenuContext? _cached;
  static int _cachedAtMs = 0;

  static void invalidate() {
    _cached = null;
    _cachedAtMs = 0;
  }

  bool get crossfadeOn => crossfadeMs > 0;

  static Future<_SongMenuContext> load() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cached;
    if (cached != null && now - _cachedAtMs < 12000) return cached;
    final map =
        _asMap(await _method.invokeMethod('songMenuContext')) ?? const {};
    final loaded = _SongMenuContext(
      likedIds: Set<String>.from(
        (map['likedIds'] as List? ?? const []).map((e) => e.toString()),
      ),
      downloadedIds: Set<String>.from(
        (map['downloadedIds'] as List? ?? const []).map((e) => e.toString()),
      ),
      userPlaylists: _userPlaylistsFrom(map['userPlaylists']),
      lrclib: map['lyricsPreferLrclib'] != false,
      lyricsRoman: map['lyricsRomanize'] == true,
      crossfadeMs: ((map['crossfadeMs'] ?? 0) as num).toInt(),
      normalizeOn: map['normalizeVolume'] == true,
    );
    _cached = loaded;
    _cachedAtMs = now;
    return loaded;
  }
}

Future<void> _playFetchedUserPlaylist(
  BuildContext context,
  _UserPlaylist p,
  _FoxyOnPlay onPlay,
) async {
  if (p.songs.isNotEmpty) {
    onPlay(p.songs.first, p.songs);
    return;
  }
  if (!p.isYoutube) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('This playlist is empty')));
    return;
  }
  final raw = await _method.invokeMethod('playlistFetchSongs', {
    'playlistId': p.id,
  });
  final songs = _songsFrom(raw);
  if (!context.mounted) return;
  if (songs.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Could not load tracks from YouTube Music. Try signing in again on the Account tab.',
        ),
      ),
    );
    return;
  }
  onPlay(songs.first, songs);
}

String? _songTitleForVideoId(
  String videoId,
  List<_Song> liked,
  List<_Song> history,
  List<_Song> downloads,
  List<_Song> recent,
  List<_Song> mostPlayed,
) {
  for (final list in [downloads, liked, recent, mostPlayed, history]) {
    for (final s in list) {
      if (s.videoId == videoId) return s.title;
    }
  }
  return null;
}

Future<void> _showFoxySongOverflowMenu(
  BuildContext context, {
  required _Song song,
  required _FoxyOnPlay onPlay,
  required List<_Song> queueForPlay,
  void Function(String query)? onDiscoverSearch,
  Future<void> Function()? onLibraryChanged,
  List<_Song>? searchResultsForExtras,
  String bulkQueuePlayTitle = 'Play all search results',
  String bulkQueuePlaySubtitle = 'Keeps the current result order',
  bool downloadsOnlyPlayback = false,
  VoidCallback? onOpenLyricsTabInPlayer,
  bool showRemoveFromQueue = false,
}) async {
  if (!context.mounted) return;
  final menuFuture = _SongMenuContext.load();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FutureBuilder<_SongMenuContext>(
      future: menuFuture,
      builder: (context, snap) {
        final menu = snap.data;
        final likedIds = menu?.likedIds ?? const <String>{};
        final downloadedIds =
            menu?.downloadedIds ??
            (song.isDownloaded ? {song.videoId} : const <String>{});
        final userPlaylists = menu?.userPlaylists ?? const <_UserPlaylist>[];
        final crossfadeMs = menu?.crossfadeMs ?? 0;
        final crossfadeOn = menu?.crossfadeOn ?? false;
        final lrclib = menu?.lrclib ?? true;
        final lyricsRoman = menu?.lyricsRoman ?? false;
        final normalizeOn = menu?.normalizeOn ?? false;
        final loading = menu == null;

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    leading: _Artwork(
                      url: song.artwork,
                      size: 52,
                      radius: 10,
                      identityTag: song.videoId,
                    ),
                    title: Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    subtitle: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        backgroundColor: Color(0xFF2A2A2A),
                        color: Colors.white54,
                      ),
                    ),
                  if (!loading) ...[
                    const Divider(height: 1),
                    if (!downloadsOnlyPlayback &&
                        searchResultsForExtras != null &&
                        searchResultsForExtras.length > 1) ...[
                      ListTile(
                        leading: const Icon(Icons.podcasts_outlined),
                        title: const Text('Play with smart radio'),
                        subtitle: const Text(
                          'Builds a station from this track',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onPlay(song, [song], radioTail: true);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.playlist_play_rounded),
                        title: Text(bulkQueuePlayTitle),
                        subtitle: Text(bulkQueuePlaySubtitle),
                        onTap: () {
                          Navigator.pop(ctx);
                          onPlay(song, searchResultsForExtras);
                        },
                      ),
                      const Divider(height: 1),
                    ],
                    ListTile(
                      leading: Icon(
                        likedIds.contains(song.videoId)
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: likedIds.contains(song.videoId)
                            ? const Color(0xFFE53935)
                            : Colors.white,
                      ),
                      title: Text(
                        likedIds.contains(song.videoId) ? 'Liked' : 'Like',
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod(
                          likedIds.contains(song.videoId) ? 'unlike' : 'like',
                          {'song': song.toMap()},
                        );
                        await onLibraryChanged?.call();
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        downloadedIds.contains(song.videoId) ||
                                song.isDownloaded
                            ? Icons.offline_pin_rounded
                            : Icons.download_outlined,
                      ),
                      title: Text(
                        downloadedIds.contains(song.videoId) ||
                                song.isDownloaded
                            ? 'Downloaded'
                            : 'Download',
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (downloadedIds.contains(song.videoId) ||
                            song.isDownloaded) {
                          await _method.invokeMethod('removeDownload', {
                            'song': song.toMap(),
                          });
                        } else {
                          await _method.invokeMethod('download', {
                            'song': song.toMap(),
                          });
                        }
                        await onLibraryChanged?.call();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.playlist_add_rounded),
                      title: const Text('Add to a playlist'),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _pickPlaylistToAddSong(
                          context,
                          song: song,
                          playlists: userPlaylists,
                          onChanged: onLibraryChanged,
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.queue_play_next_rounded),
                      title: const Text('Play next'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _method.invokeMethod('enqueuePlayNext', {
                          'song': song.toMap(),
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.queue_music_rounded),
                      title: const Text('Add to queue'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _method.invokeMethod('addToQueue', {
                          'song': song.toMap(),
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline_rounded),
                      title: const Text('Artists'),
                      subtitle: Text(
                        song.artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onDiscoverSearch?.call(song.artist);
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.album_rounded),
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        downloadsOnlyPlayback
                            ? 'Play in downloads queue'
                            : 'Play this track',
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (downloadsOnlyPlayback) {
                          onPlay(song, queueForPlay, downloadsOnly: true);
                        } else {
                          onPlay(song, [song], radioTail: true);
                        }
                      },
                    ),
                    if (!downloadsOnlyPlayback)
                      ListTile(
                        leading: const Icon(Icons.radio_rounded),
                        title: const Text('Start smart radio'),
                        subtitle: const Text(
                          'Genre-aware station from this track (Foxy-style)',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onPlay(song, [song], radioTail: true);
                        },
                      ),
                    ListTile(
                      leading: Icon(
                        lrclib ? Icons.lyrics_rounded : Icons.subtitles_rounded,
                      ),
                      title: const Text('Lyrics source'),
                      subtitle: Text(
                        lrclib
                            ? 'LRCLIB first, then YouTube captions'
                            : 'YouTube captions first, then LRCLIB',
                      ),
                      trailing: Switch(
                        value: lrclib,
                        onChanged: (v) async {
                          Navigator.pop(ctx);
                          await _method.invokeMethod('setAppearance', {
                            'lyricsPreferLrclib': v,
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? 'Synced lyrics will prefer LRCLIB.'
                                    : 'Synced lyrics will prefer YouTube captions.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod('setAppearance', {
                          'lyricsPreferLrclib': !lrclib,
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.translate_rounded),
                      title: const Text('Lyrics in English letters'),
                      subtitle: const Text('Romanize non-Latin synced lyrics'),
                      trailing: Switch(
                        value: lyricsRoman,
                        onChanged: (v) async {
                          Navigator.pop(ctx);
                          await _method.invokeMethod('setAppearance', {
                            'lyricsRomanize': v,
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? 'Lyrics will show in Latin letters.'
                                    : 'Lyrics will show in original script.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod('setAppearance', {
                          'lyricsRomanize': !lyricsRoman,
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.sync_rounded),
                      title: const Text('Crossfade'),
                      subtitle: Text(
                        crossfadeOn
                            ? '${(crossfadeMs / 1000).round()}s fade between tracks'
                            : 'Off â€” enable for smooth transitions',
                      ),
                      trailing: Switch(
                        value: crossfadeOn,
                        onChanged: (v) async {
                          Navigator.pop(ctx);
                          await _method.invokeMethod('setAppearance', {
                            'crossfadeMs': v ? 5000 : 0,
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? 'Crossfade on (5s) â€” volume ramps at track ends.'
                                    : 'Crossfade off.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod('setAppearance', {
                          'crossfadeMs': crossfadeOn ? 0 : 5000,
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.graphic_eq_rounded),
                      title: const Text('Normalize volume'),
                      subtitle: Text(
                        normalizeOn
                            ? 'On â€” quieter peaks for steadier loudness'
                            : 'Off â€” original stream levels',
                      ),
                      trailing: Switch(
                        value: normalizeOn,
                        onChanged: (v) async {
                          Navigator.pop(ctx);
                          await _method.invokeMethod('setAppearance', {
                            'normalizeVolume': v,
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                v
                                    ? 'Volume normalization on.'
                                    : 'Volume normalization off.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _method.invokeMethod('setAppearance', {
                          'normalizeVolume': !normalizeOn,
                        });
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.bedtime_rounded),
                      title: const Text('Sleep timer'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _method.invokeMethod('sleepTimer', {'minutes': 30});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.speed_rounded),
                      title: const Text('Playback speed & pitch'),
                      subtitle: Text(
                        crossfadeOn
                            ? 'Crossfade is on â€” speed changes may sound uneven.'
                            : 'Quick presets (applies to the native player)',
                      ),
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (!context.mounted) return;
                        final speed = await showDialog<double>(
                          context: context,
                          builder: (dCtx) => SimpleDialog(
                            title: const Text('Playback speed'),
                            children: [
                              for (final v in [0.75, 1.0, 1.25, 1.5])
                                SimpleDialogOption(
                                  onPressed: () => Navigator.pop(dCtx, v),
                                  child: Text('${v}x'),
                                ),
                            ],
                          ),
                        );
                        if (speed != null && context.mounted) {
                          await _method.invokeMethod('setPlaybackSpeed', {
                            'speed': speed,
                            'pitch': 1.0,
                          });
                        }
                      },
                    ),
                    if (onOpenLyricsTabInPlayer != null)
                      ListTile(
                        leading: const Icon(Icons.open_in_new_rounded),
                        title: const Text('Open synced lyrics tab'),
                        subtitle: const Text(
                          'Full-width lyrics in this player',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          onOpenLyricsTabInPlayer();
                        },
                      ),
                    if (showRemoveFromQueue)
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: const Text('Remove from queue'),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _method.invokeMethod('removeFromQueue', {
                            'song': song.toMap(),
                          });
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: const Text('Share'),
                      onTap: () async {
                        final link =
                            'https://music.youtube.com/watch?v=${song.videoId}';
                        await Clipboard.setData(ClipboardData(text: link));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied to clipboard'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  _SongMenuContext.invalidate();
}

Future<void> _pickPlaylistToAddSong(
  BuildContext context, {
  required _Song song,
  required List<_UserPlaylist> playlists,
  Future<void> Function()? onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF151515),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            onTap: () async {
              Navigator.pop(ctx);
              final nameCtrl = TextEditingController();
              final name = await showDialog<String>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Playlist name'),
                  content: TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(hintText: 'My mix'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(dCtx, nameCtrl.text.trim()),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty && context.mounted) {
                await _method.invokeMethod('playlistCreate', {'name': name});
                await onChanged?.call();
                if (!context.mounted) return;
                final menuCtx = await _SongMenuContext.load();
                if (!context.mounted) return;
                await _pickPlaylistToAddSong(
                  context,
                  song: song,
                  playlists: menuCtx.userPlaylists,
                  onChanged: onChanged,
                );
              }
            },
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                'No playlists yet. Tap â€œNew playlistâ€ above.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.42,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (c, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: Icon(
                      p.isYoutube
                          ? Icons.cloud_queue_rounded
                          : Icons.queue_music_rounded,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.isYoutube
                          ? '${p.displayTrackCount} songs | YouTube Music'
                          : '${p.displayTrackCount} songs | On device',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('playlistAddSong', {
                        'playlistId': p.id,
                        'song': song.toMap(),
                      });
                      await onChanged?.call();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Added to ${p.name}')),
                        );
                      }
                    },
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

Future<void> _pickPlaylistToAddSongs(
  BuildContext context, {
  required List<_Song> songs,
  required List<_UserPlaylist> playlists,
  Future<void> Function()? onChanged,
  String suggestedName = 'New mix',
}) async {
  final uniqueSongs = <_Song>[];
  final seen = <String>{};
  for (final song in songs) {
    if (song.videoId.isEmpty || !seen.add(song.videoId)) continue;
    uniqueSongs.add(song);
  }
  if (uniqueSongs.isEmpty) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Nothing to save yet')));
    return;
  }

  Future<void> addAllToPlaylist(String playlistId, String playlistName) async {
    for (final song in uniqueSongs) {
      await _method.invokeMethod('playlistAddSong', {
        'playlistId': playlistId,
        'song': song.toMap(),
      });
    }
    await onChanged?.call();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${uniqueSongs.length} song${uniqueSongs.length == 1 ? '' : 's'} to $playlistName',
          ),
        ),
      );
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF151515),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('New playlist'),
            subtitle: Text(
              '${uniqueSongs.length} song${uniqueSongs.length == 1 ? '' : 's'} from this collection',
            ),
            onTap: () async {
              Navigator.pop(ctx);
              final nameCtrl = TextEditingController(text: suggestedName);
              final name = await showDialog<String>(
                context: context,
                builder: (dCtx) => AlertDialog(
                  title: const Text('Playlist name'),
                  content: TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(hintText: 'Night drive'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dCtx),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(dCtx, nameCtrl.text.trim()),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name == null || name.isEmpty || !context.mounted) return;
              final created = await _method.invokeMethod('playlistCreate', {
                'name': name,
              });
              final playlistId = _asMap(created)?['id']?.toString() ?? '';
              if (playlistId.isEmpty || !context.mounted) return;
              await addAllToPlaylist(playlistId, name);
              _SongMenuContext.invalidate();
            },
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                'No playlists yet. Tap "New playlist" above.',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.42,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (c, i) {
                  final p = playlists[i];
                  return ListTile(
                    leading: Icon(
                      p.isYoutube
                          ? Icons.cloud_queue_rounded
                          : Icons.queue_music_rounded,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.isYoutube
                          ? '${p.displayTrackCount} songs | YouTube Music'
                          : '${p.displayTrackCount} songs | On device',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await addAllToPlaylist(p.id, p.name);
                      _SongMenuContext.invalidate();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}

IconData _sectionIcon(String label) {
  switch (label) {
    case 'Playlists':
      return Icons.playlist_play_rounded;
    case 'History':
      return Icons.history_rounded;
    case 'Downloaded':
    case 'Downloads':
      return Icons.download_rounded;
    case 'Local files':
    case 'Local':
      return Icons.folder_rounded;
    case 'Most played':
      return Icons.trending_up_rounded;
    case 'Recently added':
      return Icons.library_add_rounded;
    default:
      return Icons.favorite_rounded;
  }
}

bool _isYoutubeAppMode(String mode) =>
    mode == 'ytmapp' || mode == 'ytm_app' || mode == 'app';

Future<void> _launchYoutubeLogin(
  BuildContext context, {
  String mode = 'webview',
}) async {
  final ok = await _method.invokeMethod('openWebLogin', {'mode': mode}) == true;
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isYoutubeAppMode(mode)
              ? 'Could not open YouTube Music on this device'
              : 'Could not open sign-in on this device',
        ),
      ),
    );
    return;
  }
  if (_isYoutubeAppMode(mode)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Use the YouTube Music app first, then come back and finish with Sign in inside FoxyMusic.',
        ),
        duration: Duration(seconds: 6),
      ),
    );
  }
}

Future<void> _signOutYoutubeAccount(
  BuildContext context, {
  Future<void> Function()? onAccountRefresh,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sign out of YouTube?'),
      content: const Text(
        'You can still use FoxyMusic as a guest, and reconnect whenever you want.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sign out'),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  try {
    await _method.invokeMethod('accountSignOut');
  } catch (_) {}
  await onAccountRefresh?.call();
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Signed out of YouTube')));
}

Future<void> _showYoutubeAccountSheet(
  BuildContext context, {
  required Map<String, dynamic> account,
  Future<void> Function()? onAccountRefresh,
  VoidCallback? onOpenAccountHub,
}) {
  final signedIn = account['isSignedIn'] == true;
  final displayName =
      account['displayName']?.toString().ifBlank('Guest listener') ??
      'Guest listener';
  final email = account['email']?.toString() ?? '';
  final avatar = account['avatarUrl']?.toString() ?? '';
  final stats = <({IconData icon, String label, int value})>[
    (
      icon: Icons.favorite_rounded,
      label: 'Liked',
      value: ((account['likedCount'] ?? 0) as num).toInt(),
    ),
    (
      icon: Icons.playlist_play_rounded,
      label: 'Playlists',
      value: ((account['playlistCount'] ?? 0) as num).toInt(),
    ),
    (
      icon: Icons.download_rounded,
      label: 'Downloads',
      value: ((account['downloadCount'] ?? 0) as num).toInt(),
    ),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      Future<void> closeAndRun(Future<void> Function() action) async {
        Navigator.of(sheetContext).pop();
        await action();
      }

      return DraggableScrollableSheet(
        initialChildSize: 0.62,
        minChildSize: 0.42,
        maxChildSize: 0.82,
        builder: (context, controller) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: ColoredBox(
              color: const Color(0xFF08080A),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'YouTube account',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    signedIn
                        ? 'Your account is connected and ready for personalized music.'
                        : 'Sign in the FoxyMusic way to unlock your YouTube Music library and recommendations.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FoxyGlassTint(
                    borderRadius: 24,
                    tintOpacity: 0.48,
                    borderOpacity: 0.08,
                    blur: true,
                    blurSigma: 16,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _AccountAvatar(
                                name: displayName,
                                imageUrl: avatar,
                                size: 58,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 18,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      signedIn
                                          ? email.ifBlank(
                                              'YouTube Music connected',
                                            )
                                          : 'Guest mode',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.62,
                                        ),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (signedIn
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.primary
                                              : Colors.white)
                                          .withValues(
                                            alpha: signedIn ? 0.18 : 0.08,
                                          ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: Text(
                                  signedIn ? 'Connected' : 'Guest',
                                  style: TextStyle(
                                    color: signedIn
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.82),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              for (final stat in stats)
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.04,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.05,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Icon(
                                            stat.icon,
                                            size: 18,
                                            color: Colors.white.withValues(
                                              alpha: 0.88,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '${stat.value}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            stat.label,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.54,
                                              ),
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => closeAndRun(
                      () => _launchYoutubeLogin(context, mode: 'webview'),
                    ),
                    icon: Icon(
                      signedIn
                          ? Icons.manage_accounts_rounded
                          : Icons.lock_open_rounded,
                      size: 20,
                    ),
                    label: Text(
                      signedIn
                          ? 'Reconnect inside FoxyMusic'
                          : 'Sign in inside FoxyMusic',
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => closeAndRun(
                      () => _launchYoutubeLogin(context, mode: 'ytmapp'),
                    ),
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 20,
                    ),
                    label: const Text('Open YouTube Music app'),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => closeAndRun(
                      () => _launchYoutubeLogin(context, mode: 'browser'),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: const Text('Open in browser'),
                  ),
                  if (onOpenAccountHub != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onOpenAccountHub();
                      },
                      icon: const Icon(Icons.person_search_rounded, size: 18),
                      label: const Text('Open account overview'),
                    ),
                  ],
                  if (signedIn) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => closeAndRun(
                        () => _signOutYoutubeAccount(
                          context,
                          onAccountRefresh: onAccountRefresh,
                        ),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Sign out'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.name,
    required this.imageUrl,
    required this.size,
  });

  final String name;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final initial = name.trim().isEmpty ? 'F' : name.trim()[0].toUpperCase();
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: accent,
      foregroundImage: imageUrl.isBlank ? null : NetworkImage(imageUrl),
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.signedIn,
    required this.liked,
    required this.playlists,
    required this.downloads,
  });

  final bool signedIn;
  final int liked;
  final int playlists;
  final int downloads;

  @override
  Widget build(BuildContext context) {
    return _FoxyGlassTint(
      borderRadius: _kCardRadius,
      tintOpacity: 0.48,
      borderOpacity: 0.065,
      blur: true,
      blurSigma: 16,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: _StatTile(value: liked, label: 'Liked'),
              ),
              Expanded(
                child: _StatTile(value: playlists, label: 'Playlists'),
              ),
              Expanded(
                child: _StatTile(value: downloads, label: 'Downloads'),
              ),
              Icon(
                signedIn ? Icons.verified_rounded : Icons.login_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.58),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

void _showUpdateResultDialog(
  BuildContext context,
  Map<String, dynamic> map, {
  String? title,
}) {
  final ok = map['ok'] == true;
  final newer = map['updateAvailable'] == true;
  final installed =
      map['installedVersionName']?.toString().trim() ?? _kAppVersionName;
  final tag = map['tagName']?.toString() ?? map['latestTag']?.toString() ?? '';
  final html = map['htmlUrl']?.toString() ?? '';
  final apk = map['downloadUrl']?.toString() ?? '';
  final err = map['error']?.toString() ?? '';
  final notes = map['body']?.toString().trim() ?? '';
  final dialogTitle =
      title ??
      (ok
          ? (newer ? 'Update available' : 'You are up to date')
          : 'Update check failed');
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(dialogTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!ok) Text(err.isEmpty ? 'Could not reach GitHub.' : err),
            if (ok) ...[
              Text('Installed: v$installed'),
              if (tag.isNotEmpty) Text('Latest: $tag'),
              if (ok && !newer && tag.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('No newer release than your installed build.'),
                ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  notes,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
        if (html.isNotEmpty)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openExternalUrl(context, html);
            },
            child: const Text('Release page'),
          ),
        if (apk.isNotEmpty)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openExternalUrl(context, apk);
            },
            child: const Text('Download APK'),
          ),
      ],
    ),
  );
}

Future<void> _openExternalUrl(BuildContext context, String url) async {
  try {
    final ok =
        await _method.invokeMethod<bool>('openExternalUrl', {'url': url}) ==
        true;
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link on this device')),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open link on this device')),
    );
  }
}

/// Dedicated About Us panel inside Settings (logo, credits, links).
class _AboutUsPanel extends StatelessWidget {
  const _AboutUsPanel({required this.onOpenExternal});

  final Future<void> Function(String url) onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final muted = Colors.white.withValues(alpha: 0.62);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(child: _FoxyAppLogo(size: 148, borderRadius: 28)),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'FoxyMusic',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _FoxyBrandPalette.foxAmber.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _kAppVersionLabel,
              style: TextStyle(
                color: _FoxyBrandPalette.foxCream,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'A foss YouTube Music client with Soundcloud integration  â€” playback, queues, and '
          'library on-device with a Flutter UI and Kotlin engine',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, height: 1.4, fontSize: 14),
        ),
        const SizedBox(height: 22),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            gradient: LinearGradient(
              colors: [
                _FoxyBrandPalette.foxDeep.withValues(alpha: 0.45),
                const Color(0xFF1A1410),
              ],
            ),
            border: Border.all(
              color: _FoxyBrandPalette.foxAmber.withValues(alpha: 0.35),
            ),
          ),
          child: Text(
            _kAboutCreditLine,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsCard(
          title: 'Developer',
          subtitle: 'Source & releases',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                _kGitHubProjectUrl,
                style: TextStyle(
                  color: _FoxyBrandPalette.foxCream.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => onOpenExternal(_kGitHubProjectUrl),
                icon: const Icon(Icons.code_rounded, size: 20),
                label: const Text('Open GitHub project'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    onOpenExternal('https://github.com/sparkn2008-del'),
                icon: const Icon(Icons.person_outline_rounded, size: 20),
                label: const Text('sparkn2008-del on GitHub'),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => showLicensePage(context: context),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_kCardRadius),
            ),
          ),
          child: const Text('Open-source licenses'),
        ),
        const SizedBox(height: 12),
        Text(
          'Release $_kAppVersionName | FoxyMusic',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.appearance,
    required this.onSetAppearance,
    this.account = const <String, dynamic>{},
    this.onAccountRefresh,
    this.onOpenAccountHub,
  });

  final Map<String, dynamic> appearance;
  final Future<void> Function(Map<String, dynamic> patch) onSetAppearance;
  final Map<String, dynamic> account;
  final Future<void> Function()? onAccountRefresh;
  final VoidCallback? onOpenAccountHub;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet>
    with SingleTickerProviderStateMixin {
  late Map<String, dynamic> _m;
  late Map<String, dynamic> _account;
  late TextEditingController _contentLang;
  late TextEditingController _appLang;
  late TextEditingController _proxyEp;
  late TabController _settingsTabs;

  @override
  void initState() {
    super.initState();
    _settingsTabs = TabController(length: 2, vsync: this);
    _m = Map<String, dynamic>.from(widget.appearance);
    _account = Map<String, dynamic>.from(widget.account);
    _contentLang = TextEditingController(
      text: _m['contentLanguageTag']?.toString() ?? 'en-US',
    );
    _appLang = TextEditingController(
      text: _m['appLanguageTag']?.toString() ?? '',
    );
    _proxyEp = TextEditingController(
      text: _m['proxyEndpoint']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _settingsTabs.dispose();
    _contentLang.dispose();
    _appLang.dispose();
    _proxyEp.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.account, widget.account)) {
      _account = Map<String, dynamic>.from(widget.account);
    }
  }

  Future<void> _apply(Map<String, dynamic> patch) async {
    await widget.onSetAppearance(patch);
    if (!mounted) return;
    setState(() => _m.addAll(patch));
  }

  Future<void> _refreshAccount() async {
    await widget.onAccountRefresh?.call();
    try {
      final account = _asMap(await _method.invokeMethod('accountInfo'));
      if (account == null || !mounted) return;
      setState(() => _account = account);
    } catch (_) {}
  }

  bool _bool(String key, [bool def = false]) {
    final v = _m[key];
    if (v == null) return def;
    return v == true;
  }

  int _int(String key, int def) => ((_m[key] ?? def) as num).toInt();

  Future<void> _openExternal(String url) async {
    try {
      final ok =
          await _method.invokeMethod<bool>('openExternalUrl', {'url': url}) ==
          true;
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link on this device')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link on this device')),
      );
    }
  }

  Future<void> _checkUpdate() async {
    final rootNav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: CircularProgressIndicator(),
          ),
        ),
      ),
    );
    try {
      final raw = await _method.invokeMethod('checkGitHubRelease');
      rootNav.pop();
      if (!mounted) return;
      _showUpdateResult(_asMap(raw) ?? const {});
    } catch (e) {
      rootNav.pop();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update check failed: $e')));
    }
  }

  void _showUpdateResult(Map<String, dynamic> map) {
    _showUpdateResultDialog(context, map);
  }

  Future<void> _openEqualizer() async {
    final ok = await _method.invokeMethod('openSystemEqualizer') == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Opened system audio effects'
              : 'No system equalizer panel on this device',
        ),
      ),
    );
  }

  Future<void> _createBackup() async {
    try {
      final raw =
          _asMap(await _method.invokeMethod('createBackup')) ?? const {};
      if (!mounted) return;
      final name = raw['fileName']?.toString() ?? 'backup';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup saved: $name')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _clearStreamCache() async {
    try {
      final raw =
          _asMap(await _method.invokeMethod('clearStreamCache')) ?? const {};
      if (!mounted) return;
      final cleared = ((raw['clearedBytes'] ?? 0) as num).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleared ${_formatStorageBytes(cleared)} stream cache'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cache clear failed: $e')));
    }
  }

  Future<void> _restoreLatestBackup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore latest backup?'),
        content: const Text(
          'This replaces local playlists, liked songs, history, and app settings with the latest FoxyMusic backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      final raw =
          _asMap(await _method.invokeMethod('restoreLatestBackup')) ?? const {};
      if (!mounted) return;
      final ok = raw['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Backup restored'
                : (raw['error']?.toString() ?? 'No backup found'),
          ),
        ),
      );
      if (ok) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  Future<void> _applyLanguages() async {
    final c = _contentLang.text.trim();
    final a = _appLang.text.trim();
    await _apply({
      'contentLanguageTag': c.isEmpty ? 'en-US' : c,
      'appLanguageTag': a,
    });
  }

  Future<void> _applyProxyEndpoint() async {
    await _apply({'proxyEndpoint': _proxyEp.text.trim()});
  }

  Future<void> _pickHomeBackground() async {
    try {
      final raw = _asMap(await _method.invokeMethod('pickHomeBackground'));
      if (!mounted) return;
      if (raw?['ok'] == true) {
        final path = raw?['path']?.toString().trim();
        if (path != null && path.isNotEmpty) {
          setState(() => _m['homeBackgroundPath'] = path);
        }
        await _apply({'homeBackgroundEnabled': true});
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom background enabled')),
        );
      } else if (raw?['cancelled'] != true && raw?['ok'] != false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not set background')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Background picker failed: $e')));
    }
  }

  Future<void> _resetHomeBackground() async {
    try {
      await _method.invokeMethod('clearHomeBackground');
      if (!mounted) return;
      await _apply({'homeBackgroundEnabled': false});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom background cleared')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final persistent = _bool('persistentQueue', true);
    final playWhenDismissed = _bool('continuePlaybackWhenDismissed');
    final saveHistory = _bool('saveHistory', true);
    final sponsor = _bool('sponsorBlockEnabled', true);
    final lrclib = _bool('lyricsPreferLrclib', true);
    final lyricsRoman = _bool('lyricsRomanize');
    final proxyOn = _bool('proxyEnabled');
    final norm = _bool('normalizeVolume');
    final skipSil = _bool('skipSilence');
    final backup = _bool('autoBackupEnabled');
    final customBg = _bool('homeBackgroundEnabled');
    final hasCustomBg =
        (_m['homeBackgroundPath']?.toString().trim().isNotEmpty ?? false);
    final tier = _int('streamQualityTier', 2).clamp(0, 4);
    final downloadTier = _int('downloadQualityTier', 2).clamp(0, 4);
    final sourcePriority = _int('streamSourcePriority', 0).clamp(0, 2);
    final cross = _int('crossfadeMs', 0);
    final playerBg = _int('playerBackgroundStyle', 0).clamp(0, 3);
    final playerProgressStyle = switch (_int('playerProgressStyle', 0)) {
      2 => 2,
      _ => 0,
    };
    final playerStyle = _int('playerStyle', 0).clamp(0, 2);
    final playerButtons = _int('playerButtonsStyle', 0).clamp(0, 2);
    final playerShape = _int('playerArtworkShape', 0).clamp(0, 2);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ColoredBox(
            color: const Color(0xFF08080A),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 46,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Expanded(
                            child: Text(
                              'Settings',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          Text(
                            _kAppVersionLabel,
                            style: TextStyle(
                              color: _FoxyBrandPalette.foxCream.withValues(
                                alpha: 0.75,
                              ),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TabBar(
                        controller: _settingsTabs,
                        indicatorColor: Colors.white,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        dividerColor: Colors.white12,
                        tabs: const [
                          Tab(text: 'General'),
                          Tab(text: 'About Us'),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _settingsTabs,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      ListView(
                        controller: controller,
                        cacheExtent: 1200,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                        children: [
                          const _SettingsSectionLabel(
                            icon: Icons.account_circle_rounded,
                            label: 'Account',
                          ),
                          Builder(
                            builder: (context) {
                              final signedIn = _account['isSignedIn'] == true;
                              final email = _account['email']?.toString() ?? '';
                              final name =
                                  _account['displayName']?.toString().ifBlank(
                                    'Guest listener',
                                  ) ??
                                  'Guest listener';
                              final avatar =
                                  _account['avatarUrl']?.toString() ?? '';
                              return _SettingsCard(
                                title: 'YouTube',
                                subtitle: signedIn
                                    ? (email.isNotEmpty ? email : 'Signed in')
                                    : 'A cleaner FoxyMusic sign-in flow inspired by SimpMusic.',
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        _AccountAvatar(
                                          name: name,
                                          imageUrl: avatar,
                                          size: 44,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15.5,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                signedIn
                                                    ? email.ifBlank(
                                                        'YouTube Music connected',
                                                      )
                                                    : 'Guest mode',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.6),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 7,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (signedIn
                                                        ? Theme.of(
                                                            context,
                                                          ).colorScheme.primary
                                                        : Colors.white)
                                                    .withValues(
                                                      alpha: signedIn
                                                          ? 0.16
                                                          : 0.06,
                                                    ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            signedIn ? 'Connected' : 'Guest',
                                            style: TextStyle(
                                              color: signedIn
                                                  ? Theme.of(
                                                      context,
                                                    ).colorScheme.primary
                                                  : Colors.white.withValues(
                                                      alpha: 0.8,
                                                    ),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    FilledButton.icon(
                                      onPressed: () async {
                                        await _showYoutubeAccountSheet(
                                          context,
                                          account: _account,
                                          onAccountRefresh: _refreshAccount,
                                          onOpenAccountHub:
                                              widget.onOpenAccountHub,
                                        );
                                        if (!mounted) return;
                                        await _refreshAccount();
                                      },
                                      icon: const Icon(
                                        Icons.manage_accounts_rounded,
                                        size: 20,
                                      ),
                                      label: Text(
                                        signedIn
                                            ? 'Manage your YouTube account'
                                            : 'Open YouTube account',
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      signedIn
                                          ? 'Reconnect, switch back to guest mode, or finish sign-in from one place.'
                                          : 'Use the account sheet for in-app sign-in, guest mode, and fallback login options.',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.56,
                                        ),
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          const _SettingsSectionLabel(
                            icon: Icons.wallpaper_rounded,
                            label: 'Background',
                          ),
                          _SettingsCard(
                            title: 'App background',
                            subtitle:
                                'Default stays plain black. Custom image is lets you choose your own Backgorund.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: customBg && hasCustomBg,
                                  title: const Text('Use custom background'),
                                  subtitle: Text(
                                    hasCustomBg
                                        ? 'Enabled on Home, Search, and Library Tabs'
                                        : 'Choose an image first',
                                  ),
                                  onChanged: hasCustomBg
                                      ? (v) =>
                                            _apply({'homeBackgroundEnabled': v})
                                      : null,
                                ),
                                FilledButton.icon(
                                  onPressed: _pickHomeBackground,
                                  icon: const Icon(
                                    Icons.image_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    hasCustomBg
                                        ? 'Change image'
                                        : 'Choose image',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: _resetHomeBackground,
                                  icon: const Icon(
                                    Icons.restart_alt_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('Remove custom Background'),
                                ),
                              ],
                            ),
                          ),
                          const _SettingsSectionLabel(
                            icon: Icons.graphic_eq_rounded,
                            label: 'Audio quality',
                          ),
                          _SettingsCard(
                            title: 'Stream quality',
                            subtitle:
                                'Low stays below 128 kbps, Balanced sits between Low and Normal, Normal targets 128 kbps, High prefers 250+ kbps, and Ultra pushes 320+ kbps or true lossless when a source really has it.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in const [
                                  (0, 'Low'),
                                  (1, 'Balanced'),
                                  (2, 'Normal'),
                                  (3, 'High'),
                                  (4, 'Ultra'),
                                ])
                                  ChoiceChip(
                                    selected: tier == item.$1,
                                    label: Text(item.$2),
                                    onSelected: (_) =>
                                        _apply({'streamQualityTier': item.$1}),
                                  ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'Download quality',
                            subtitle:
                                'Uses the same quality targets as streaming, but stores the best downloadable audio the source actually exposes.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in const [
                                  (0, 'Small'),
                                  (0, 'Low'),
                                  (1, 'Balanced'),
                                  (2, 'Normal'),
                                  (3, 'High'),
                                  (4, 'Ultra'),
                                ])
                                  ChoiceChip(
                                    selected: downloadTier == item.$1,
                                    label: Text(item.$2),
                                    onSelected: (_) => _apply({
                                      'downloadQualityTier': item.$1,
                                    }),
                                  ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'Stream source',
                            subtitle:
                                'Ultra can compare alternate matches when the primary source has no lossless stream.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in const [
                                  (0, 'YouTube'),
                                  (1, 'YouTube + SC'),
                                  (2, 'SC first'),
                                ])
                                  ChoiceChip(
                                    selected: sourcePriority == item.$1,
                                    label: Text(item.$2),
                                    onSelected: (_) => _apply({
                                      'streamSourcePriority': item.$1,
                                    }),
                                  ),
                              ],
                            ),
                          ),
                          const _SettingsSectionLabel(
                            icon: Icons.play_circle_fill_rounded,
                            label: 'Playback',
                          ),
                          _SettingsCard(
                            title: 'Player customisations',
                            subtitle:
                                'Choose the player layout, artwork background, and controls.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Background',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in const [
                                      (0, 'Blurred img'),
                                      (1, 'Dark & glow'),
                                      (2, 'Pure black'),
                                      (3, 'Clips'),
                                    ])
                                      ChoiceChip(
                                        selected: playerBg == item.$1,
                                        label: Text(item.$2),
                                        onSelected: (_) => _apply({
                                          'playerBackgroundStyle': item.$1,
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Style',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in const [
                                      (0, 'Style 1'),
                                      (2, 'Style 2'),
                                    ])
                                      ChoiceChip(
                                        selected: playerStyle == item.$1,
                                        label: Text(item.$2),
                                        onSelected: (_) =>
                                            _apply({'playerStyle': item.$1}),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Seek bar',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in const [
                                      (0, 'Default'),
                                      (2, 'Slim'),
                                    ])
                                      ChoiceChip(
                                        selected:
                                            playerProgressStyle == item.$1,
                                        label: Text(item.$2),
                                        onSelected: (_) => _apply({
                                          'playerProgressStyle': item.$1,
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Buttons',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in const [
                                      (0, 'White glow'),
                                      (1, 'Outline'),
                                      (2, 'Clean solid'),
                                    ])
                                      ChoiceChip(
                                        selected: playerButtons == item.$1,
                                        label: Text(item.$2),
                                        onSelected: (_) => _apply({
                                          'playerButtonsStyle': item.$1,
                                        }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Artwork',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final item in const [
                                      (0, 'Rounded cover'),
                                      (1, 'Vinyl circle'),
                                      (2, 'Compact cover'),
                                    ])
                                      ChoiceChip(
                                        selected: playerShape == item.$1,
                                        label: Text(item.$2),
                                        onSelected: (_) => _apply({
                                          'playerArtworkShape': item.$1,
                                        }),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'Crossfade',
                            subtitle: '(Beta) Also in â‹® song menu.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final item in const [
                                  (0, 'Off'),
                                  (3000, '3s'),
                                  (5000, '5s'),
                                  (8000, '8s'),
                                  (12000, '12s'),
                                ])
                                  ChoiceChip(
                                    selected: cross == item.$1,
                                    label: Text(item.$2),
                                    onSelected: (_) =>
                                        _apply({'crossfadeMs': item.$1}),
                                  ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'Playback & data',
                            subtitle:
                                'Queue persistence, history, and SponsorBlock-style skips',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: persistent,
                                  title: const Text(
                                    'Restore queue after restart',
                                  ),
                                  onChanged: (v) =>
                                      _apply({'persistentQueue': v}),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: playWhenDismissed,
                                  title: const Text(
                                    'Play when app is dismissed',
                                  ),
                                  subtitle: const Text(
                                    'Keep music playing after swiping FoxyMusic away from recents',
                                  ),
                                  onChanged: (v) => _apply({
                                    'continuePlaybackWhenDismissed': v,
                                  }),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: saveHistory,
                                  title: const Text('Save listening history'),
                                  onChanged: (v) => _apply({'saveHistory': v}),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: sponsor,
                                  title: const Text('SponsorBlock auto-skip'),
                                  onChanged: (v) =>
                                      _apply({'sponsorBlockEnabled': v}),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: lrclib,
                                  title: const Text('Prefer LRCLIB for lyrics'),
                                  subtitle: const Text(
                                    'LRCLIB first, YouTube captions as fallback. Also in â‹® song menu.',
                                  ),
                                  onChanged: (v) =>
                                      _apply({'lyricsPreferLrclib': v}),
                                ),
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: lyricsRoman,
                                  title: const Text(
                                    'Lyrics in English letters',
                                  ),
                                  subtitle: const Text(
                                    'Romanize non-Latin synced lyrics (SimpMusic-style).',
                                  ),
                                  onChanged: (v) =>
                                      _apply({'lyricsRomanize': v}),
                                ),
                              ],
                            ),
                          ),
                          const _SettingsSectionLabel(
                            icon: Icons.tune_rounded,
                            label: 'Advanced',
                          ),
                          _SettingsCard(
                            title: 'HTTP proxy',
                            subtitle:
                                'host:port applied to stream extraction and ExoPlayer (OkHttp), like a desktop music client.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: proxyOn,
                                  title: const Text('Enable proxy'),
                                  onChanged: (v) => _apply({'proxyEnabled': v}),
                                ),
                                TextField(
                                  controller: _proxyEp,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: 'Proxy endpoint',
                                    hintText: '127.0.0.1:8080',
                                    filled: true,
                                    fillColor: const Color(0xFF141414),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                  onSubmitted: (_) => _applyProxyEndpoint(),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: _applyProxyEndpoint,
                                    child: const Text('Save proxy host'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'Languages',
                            subtitle:
                                'Catalogue bias (BCP-47) and optional UI language tag (blank = system)',
                            child: Column(
                              children: [
                                TextField(
                                  controller: _contentLang,
                                  decoration: InputDecoration(
                                    labelText: 'Content / catalogue',
                                    hintText: 'en-US',
                                    filled: true,
                                    fillColor: const Color(0xFF141414),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _appLang,
                                  decoration: InputDecoration(
                                    labelText: 'App UI (optional)',
                                    filled: true,
                                    fillColor: const Color(0xFF141414),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                      borderSide: BorderSide(
                                        color: Colors.white.withValues(
                                          alpha: 0.1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: FilledButton(
                                    onPressed: _applyLanguages,
                                    child: const Text('Apply languages'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: norm,
                            title: const Text(
                              'Normalize volume',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Lowers loud tracks for steadier playback â€” applies immediately.',
                            ),
                            onChanged: (v) => _apply({'normalizeVolume': v}),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: skipSil,
                            title: const Text(
                              'Skip silence',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Uses ExoPlayer silence skipping when supported by the device.',
                            ),
                            onChanged: (v) => _apply({'skipSilence': v}),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: backup,
                            title: const Text(
                              'Auto backup',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Keeps local JSON snapshots of playlists, liked songs, history, and settings.',
                            ),
                            onChanged: (v) => _apply({'autoBackupEnabled': v}),
                          ),
                          const _SettingsSectionLabel(
                            icon: Icons.storage_rounded,
                            label: 'Storage & updates',
                          ),
                          _SettingsCard(
                            title: 'Backup & restore',
                            subtitle:
                                'Local snapshots stay inside FoxyMusic storage; downloads remain on disk.',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  onPressed: _createBackup,
                                  icon: const Icon(
                                    Icons.backup_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('Back up now'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _restoreLatestBackup,
                                  icon: const Icon(
                                    Icons.restore_rounded,
                                    size: 20,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                  ),
                                  label: const Text('Restore latest'),
                                ),
                              ],
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _bool('autoCheckUpdates', true),
                            title: const Text(
                              'Check for updates automatically',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Looks for new GitHub releases about once per day.',
                            ),
                            onChanged: (v) => _apply({'autoCheckUpdates': v}),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _bool('updateNotifications', true),
                            title: const Text(
                              'Update notifications',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text(
                              'Shows a system notification when a newer APK is published.',
                            ),
                            onChanged: (v) =>
                                _apply({'updateNotifications': v}),
                          ),
                          _SettingsCard(
                            title: 'App updates',
                            subtitle:
                                'GitHub releases | sparkn2008-del/FoxyMusic',
                            child: OutlinedButton.icon(
                              onPressed: _checkUpdate,
                              icon: const Icon(
                                Icons.system_update_alt_rounded,
                                size: 20,
                              ),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    _kCardRadius,
                                  ),
                                ),
                              ),
                              label: const Text('Check for updates now'),
                            ),
                          ),
                          _SettingsCard(
                            title: 'Shortcuts',
                            subtitle: 'System integrations',
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: _openEqualizer,
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                  ),
                                  child: const Text('System equalizer'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _clearStreamCache,
                                  icon: const Icon(
                                    Icons.cleaning_services_rounded,
                                    size: 18,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                        _kCardRadius,
                                      ),
                                    ),
                                  ),
                                  label: const Text('Clear stream cache'),
                                ),
                              ],
                            ),
                          ),
                          _SettingsCard(
                            title: 'About FoxyMusic',
                            subtitle: 'Logo, credits & GitHub',
                            child: FilledButton.icon(
                              onPressed: () => _settingsTabs.animateTo(1),
                              icon: const Icon(
                                Icons.info_outline_rounded,
                                size: 20,
                              ),
                              label: const Text('Open About Us'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Tip: open the â‹® menu on the full player for sleep timer and queue tools.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                      ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                        children: [
                          _AboutUsPanel(onOpenExternal: _openExternal),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF101010),
            borderRadius: BorderRadius.circular(_kCardRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                    ),
                  ),
                  if (child is! SizedBox) ...[
                    const SizedBox(height: 12),
                    child,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTabBody extends StatelessWidget {
  const _EmptyTabBody({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Icon(icon, size: 40, color: accent),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeQuickPicks extends StatefulWidget {
  const _HomeQuickPicks({required this.songs, required this.onPlay});

  final List<_Song> songs;
  final _FoxyOnPlay onPlay;

  @override
  State<_HomeQuickPicks> createState() => _HomeQuickPicksState();
}

class _HomeQuickPicksState extends State<_HomeQuickPicks> {
  late final PageController _bannerController;
  int _bannerPage = 0;

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.9);
  }

  @override
  void dispose() {
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final songs = widget.songs.take(16).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "LET'S START WITH A RADIO",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Quick picks',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _FoxyGlassTextButton(
                      label: 'Play all',
                      onPressed: () =>
                          widget.onPlay(songs.first, songs, radioTail: false),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 184,
            child: PageView.builder(
              controller: _bannerController,
              itemCount: songs.length,
              onPageChanged: (i) => setState(() => _bannerPage = i),
              itemBuilder: (context, index) {
                final song = songs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _QuickPickBannerCard(
                    song: song,
                    active: false,
                    onTap: () => widget.onPlay(song, [song], radioTail: true),
                  ),
                );
              },
            ),
          ),
          if (songs.length > 1) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < songs.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _bannerPage ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _bannerPage
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Swipable song banner for Quick picks (one track per page).
class _QuickPickBannerCard extends StatelessWidget {
  const _QuickPickBannerCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.highQualityArtwork,
                size: 600,
                radius: 0,
                identityTag: song.videoId,
                highQuality: true,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                  ),
                ),
              ),
              if (active)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: accent.withValues(alpha: 0.85),
                      width: 2,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (active)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(
                              Icons.equalizer_rounded,
                              color: accent,
                              size: 18,
                            ),
                          ),
                        Text(
                          'QUICK PICK',
                          style: TextStyle(
                            color: accent.withValues(alpha: 0.95),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Material(
                          color: Colors.white.withValues(alpha: 0.96),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onTap,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.black87,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Tap to play',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeFreshFindsRow extends StatelessWidget {
  const _HomeFreshFindsRow({
    required this.sections,
    required this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_SongSection> sections;
  final _FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    final mixSongs = sections
        .expand((s) => s.songs)
        .where((s) => s.artwork.isNotEmpty)
        .take(4)
        .toList();
    _SongSection? replaySection;
    for (final s in sections) {
      if (s.title.toLowerCase().contains('fresh')) {
        replaySection = s;
        break;
      }
    }
    replaySection ??= sections.isNotEmpty ? sections.first : null;
    final replaySongs = replaySection?.songs.take(4).toList() ?? mixSongs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fresh finds, old favorites',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 156,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _HomeGradientMixCard(
                  title: 'Liked Music',
                  subtitle: 'Auto playlist',
                  gradient: const [Color(0xFFE91E8C), Color(0xFF9C27B0)],
                  icon: Icons.thumb_up_alt_rounded,
                  onTap: () => onDiscoverSearch?.call('liked songs playlist'),
                ),
                const SizedBox(width: 12),
                _HomeReplayMixCard(
                  title: 'Replay Mix',
                  songs: replaySongs,
                  onTap: () {
                    if (replaySongs.isNotEmpty) {
                      onPlay(replaySongs.first, [
                        replaySongs.first,
                      ], radioTail: true);
                    }
                  },
                ),
                const SizedBox(width: 12),
                _HomeGradientMixCard(
                  title: 'Discover Mix',
                  subtitle: 'Made for you',
                  gradient: const [Color(0xFF1565C0), Color(0xFF283593)],
                  icon: Icons.explore_rounded,
                  onTap: () => onDiscoverSearch?.call('discover mix music'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeGradientMixCard extends StatelessWidget {
  const _HomeGradientMixCard({
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final List<Color> gradient;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                  ),
                  child: Center(
                    child: Icon(icon, color: Colors.white, size: 52),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeReplayMixCard extends StatelessWidget {
  const _HomeReplayMixCard({
    required this.title,
    required this.songs,
    required this.onTap,
  });

  final String title;
  final List<_Song> songs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        blurSigma: 12,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (songs.length >= 4)
                      Column(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Artwork(
                                    url: songs[0].highQualityArtwork,
                                    size: 84,
                                    radius: 0,
                                    identityTag: songs[0].videoId,
                                  ),
                                ),
                                Expanded(
                                  child: _Artwork(
                                    url: songs[1].highQualityArtwork,
                                    size: 84,
                                    radius: 0,
                                    identityTag: songs[1].videoId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: _Artwork(
                                    url: songs[2].highQualityArtwork,
                                    size: 84,
                                    radius: 0,
                                    identityTag: songs[2].videoId,
                                  ),
                                ),
                                Expanded(
                                  child: _Artwork(
                                    url: songs[3].highQualityArtwork,
                                    size: 84,
                                    radius: 0,
                                    identityTag: songs[3].videoId,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    else
                      _Artwork(
                        url: songs.isNotEmpty
                            ? songs.first.highQualityArtwork
                            : '',
                        size: 168,
                        radius: 0,
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.1),
                            Colors.black.withValues(alpha: 0.55),
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (songs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                songs
                    .map((s) => s.artist)
                    .where((a) => a.isNotEmpty)
                    .take(3)
                    .join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HomeFeedSection extends StatelessWidget {
  const _HomeFeedSection({
    required this.section,
    required this.layout,
    required this.onPlay,
  });

  final _SongSection section;
  final _HomeSectionLayout layout;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final titleLower = section.title.toLowerCase();
    if (titleLower.contains('fresh finds')) {
      return const SizedBox.shrink();
    }
    return switch (layout) {
      _HomeSectionLayout.grid => _HomeGridShelf(
        section: section,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.video => _HomeVideoShelf(
        section: section,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.chart => _HomeChartShelf(
        section: section,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.artist => _HomeArtistShelf(
        section: section,
        onPlay: onPlay,
      ),
      _HomeSectionLayout.cards => _HomeSongCardsSection(
        section: section,
        onPlay: onPlay,
      ),
    };
  }
}

class _HomeSectionTitle extends StatelessWidget {
  const _HomeSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _HomeHorizontalShelf extends StatelessWidget {
  const _HomeHorizontalShelf({
    required this.title,
    required this.height,
    required this.itemCount,
    required this.separatorWidth,
    required this.itemBuilder,
  });

  final String title;
  final double height;
  final int itemCount;
  final double separatorWidth;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: _kHomeSectionTopSpace,
        bottom: _kHomeSectionBottomSpace,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeSectionTitle(title),
          const SizedBox(height: _kHomeSectionTitleSpace),
          SizedBox(
            height: height,
            child: RepaintBoundary(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: itemCount,
                separatorBuilder: (context, index) =>
                    SizedBox(width: separatorWidth),
                itemBuilder: itemBuilder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSongCardsSection extends StatelessWidget {
  const _HomeSongCardsSection({required this.section, required this.onPlay});

  final _SongSection section;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final songs = section.songs.take(14).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.only(
        top: _kHomeSectionTopSpace,
        bottom: _kHomeSectionBottomSpace,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeSectionTitle(section.title),
          const SizedBox(height: _kHomeSectionTitleSpace),
          Column(
            children: [
              for (var i = 0; i < songs.length; i++) ...[
                _HomeSongCard(
                  song: songs[i],
                  active: false,
                  onTap: () => onPlay(songs[i], [songs[i]], radioTail: true),
                ),
                if (i != songs.length - 1) const SizedBox(height: 2),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeMetaPill extends StatelessWidget {
  const _HomeMetaPill({required this.label, this.icon, this.active = false});

  final String label;
  final IconData? icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final fg = active ? accent : Colors.white.withValues(alpha: 0.72);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: active ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSongCard extends StatelessWidget {
  const _HomeSongCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(18),
        tintOpacity: 0.15,
        borderOpacity: active ? 0.18 : 0.045,
        blurSigma: 12,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: 70,
                      radius: 0,
                      identityTag: song.videoId,
                      offlineArtworkPath: song.offlineArtworkPath,
                      useOfflineArtwork: song.isDownloaded,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.20),
                            Colors.black.withValues(alpha: 0.40),
                          ],
                        ),
                      ),
                    ),
                    if (active)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    song.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? accent : Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                      height: 1.08,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 12.8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (song.isDownloaded) ...[
                        const _HomeMetaPill(
                          label: 'Offline',
                          icon: Icons.download_done_rounded,
                        ),
                        const SizedBox(width: 6),
                      ],
                      if ((song.duration ?? '').trim().isNotEmpty)
                        _HomeMetaPill(label: song.duration ?? ''),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? accent.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.08),
                border: Border.all(
                  color: active
                      ? accent.withValues(alpha: 0.28)
                      : Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Icon(
                active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                color: active ? accent : Colors.white.withValues(alpha: 0.84),
                size: 21,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeGridShelf extends StatelessWidget {
  const _HomeGridShelf({required this.section, required this.onPlay});

  final _SongSection section;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs
        .where(
          (song) => song.videoId.isNotEmpty && song.title.trim().isNotEmpty,
        )
        .take(8)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(
        top: _kHomeSectionTopSpace,
        bottom: _kHomeSectionBottomSpace,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HomeSectionTitle(section.title),
          const SizedBox(height: _kHomeSectionTitleSpace),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: RepaintBoundary(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 0.82,
                ),
                itemCount: songs.length,
                itemBuilder: (context, index) {
                  final song = songs[index];
                  return _HomeGridTile(
                    song: song,
                    active: false,
                    onTap: () => onPlay(song, [song], radioTail: true),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeGridTile extends StatelessWidget {
  const _HomeGridTile({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _FoxyGlassButton(
      onTap: onTap,
      selected: active,
      borderRadius: BorderRadius.circular(18),
      tintOpacity: 0.15,
      borderOpacity: active ? 0.18 : 0.045,
      blurSigma: 12,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(
                    url: song.highQualityArtwork,
                    size: 200,
                    radius: 0,
                    identityTag: song.videoId,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.06),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.42),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: _HomeMetaPill(
                      label: (song.duration ?? '').ifBlank('Radio'),
                      active: active,
                    ),
                  ),
                  if (active)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        color: accent,
                        size: 36,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            song.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? accent : Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeVideoShelf extends StatelessWidget {
  const _HomeVideoShelf({required this.section, required this.onPlay});

  final _SongSection section;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return _HomeHorizontalShelf(
      title: section.title,
      height: 156,
      itemCount: section.songs.length,
      separatorWidth: 12,
      itemBuilder: (context, index) {
        final song = section.songs[index];
        return _HomeVideoCard(
          song: song,
          active: false,
          onTap: () => onPlay(song, [song], radioTail: true),
        );
      },
    );
  }
}

class _HomeVideoCard extends StatelessWidget {
  const _HomeVideoCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const w = 248.0;
    const h = 128.0;
    return SizedBox(
      width: w,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(18),
        tintOpacity: 0.15,
        borderOpacity: active ? 0.18 : 0.045,
        blurSigma: 12,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: w - 20,
                height: h,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: w,
                      radius: 0,
                      identityTag: song.videoId,
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.08),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.44),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: _HomeMetaPill(
                        label: (song.duration ?? '').ifBlank('Video'),
                        icon: Icons.play_circle_fill_rounded,
                        active: active,
                      ),
                    ),
                    if (active)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeChartShelf extends StatelessWidget {
  const _HomeChartShelf({required this.section, required this.onPlay});

  final _SongSection section;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(12).toList();
    return _HomeHorizontalShelf(
      title: section.title,
      height: 176,
      itemCount: songs.length,
      separatorWidth: 12,
      itemBuilder: (context, index) {
        final song = songs[index];
        return SizedBox(
          width: 152,
          child: _FoxyGlassButton(
            onTap: () => onPlay(song, [song], radioTail: true),
            borderRadius: BorderRadius.circular(10),
            blurSigma: 12,
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _Artwork(
                          url: song.highQualityArtwork,
                          size: 136,
                          radius: 0,
                          identityTag: song.videoId,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.48),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          bottom: 6,
                          child: Text(
                            '#${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  song.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Chart â€¢ YouTube Music',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeArtistShelf extends StatelessWidget {
  const _HomeArtistShelf({required this.section, required this.onPlay});

  final _SongSection section;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    return _HomeHorizontalShelf(
      title: section.title,
      height: 154,
      itemCount: section.songs.length,
      separatorWidth: 16,
      itemBuilder: (context, index) {
        final song = section.songs[index];
        return SizedBox(
          width: 120,
          child: _FoxyGlassButton(
            onTap: () => onPlay(song, [song], radioTail: true),
            borderRadius: BorderRadius.circular(14),
            blurSigma: 12,
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ClipOval(
                  child: _Artwork(
                    url: song.highQualityArtwork,
                    size: 104,
                    radius: 0,
                    identityTag: song.videoId,
                    highQuality: true,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  song.artist.ifBlank(song.title),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Artists',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    super.key,
    required this.player,
    required this.timelineListenable,
    required this.onOpen,
    required this.onTogglePlayPause,
    this.onResync,
    this.glass = false,
    this.safeArea = true,
    this.outerPadding = const EdgeInsets.fromLTRB(12, 0, 12, 6),
  });

  final Map<String, dynamic> player;
  final ValueListenable<_PlayerTimelineState> timelineListenable;
  final VoidCallback onOpen;
  final Future<void> Function() onTogglePlayPause;
  final Future<void> Function()? onResync;
  final bool glass;
  final bool safeArea;
  final EdgeInsetsGeometry outerPadding;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  late _PlayerTimelineState _timeline;
  late final VoidCallback _timelineListener;

  @override
  void initState() {
    super.initState();
    _timeline = widget.timelineListenable.value;
    final p = _progressFrom(_timeline);
    _progressCtrl = AnimationController(
      vsync: this,
      value: p,
      duration: const Duration(milliseconds: 320),
      lowerBound: 0,
      upperBound: 1,
    );
    _timelineListener = () {
      if (!mounted) return;
      final previous = _timeline;
      final next = widget.timelineListenable.value;
      _timeline = next;
      final target = _progressFrom(next);
      final d = (target - _progressCtrl.value).abs();
      if (d > 0.0005) {
        if (next.isPlaying) {
          _progressCtrl.stop();
          if (d > 0.035) {
            _progressCtrl.animateTo(
              target,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          } else {
            _progressCtrl.value = target;
          }
        } else {
          _progressCtrl.animateTo(
            target,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      }
      if (previous.isPlaying != next.isPlaying ||
          previous.isBuffering != next.isBuffering ||
          previous.positionMs != next.positionMs ||
          previous.durationMs != next.durationMs) {
        setState(() {});
      }
    };
    widget.timelineListenable.addListener(_timelineListener);
  }

  double _progressFrom(_PlayerTimelineState timeline) {
    final duration = timeline.durationMs.toDouble();
    final position = timeline.positionMs.toDouble();
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timelineListenable != widget.timelineListenable) {
      oldWidget.timelineListenable.removeListener(_timelineListener);
      _timeline = widget.timelineListenable.value;
      widget.timelineListenable.addListener(_timelineListener);
      _progressCtrl.value = _progressFrom(_timeline);
    }
  }

  @override
  void dispose() {
    widget.timelineListenable.removeListener(_timelineListener);
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dynamicOn = widget.player['dynamicSongColors'] != false;
    final barColor = dynamicOn
        ? _miniPlayerTint(accent)
        : _kMiniPlayerFallbackTint;
    final song = _Song.fromMap(
      _asMap(widget.player['currentSong']) ?? const {},
    );
    final liked = widget.player['songIsLiked'] == true;
    final playing = _timeline.isPlaying;
    final buffering = _timeline.isBuffering;

    final playerBody = SizedBox(
      height: 64,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: widget.onOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                child: Row(
                  children: [
                    _Artwork(
                      url: song.highQualityArtwork,
                      size: 48,
                      radius: 8,
                      identityTag: song.videoId,
                      offlineArtworkPath: song.offlineArtworkPath,
                      useOfflineArtwork: song.isDownloaded,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: liked ? 'Unlike' : 'Like',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () async {
              try {
                await _method.invokeMethod(liked ? 'unlike' : 'like', {
                  'song': song.toMap(),
                });
              } finally {
                await widget.onResync?.call();
              }
            },
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked
                  ? const Color(0xFFE53935)
                  : Colors.white.withValues(alpha: 0.78),
              size: 24,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: _FoxyMiniPlayRing(
              progress: _progressCtrl,
              playing: playing,
              buffering: buffering,
              accent: accent,
              onPressed: () async {
                await widget.onTogglePlayPause();
                await widget.onResync?.call();
              },
            ),
          ),
        ],
      ),
    );

    final Widget shell;
    if (widget.glass) {
      shell = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _FoxyGlassTint(
          borderRadius: 16,
          tintOpacity: 0.64,
          borderOpacity: 0.22,
          child: playerBody,
        ),
      );
    } else {
      shell = Material(
        color: barColor,
        elevation: 8,
        shadowColor: Colors.black54,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: playerBody,
      );
    }

    final content = Padding(padding: widget.outerPadding, child: shell);
    if (!widget.safeArea) return content;
    return SafeArea(top: false, child: content);
  }
}

/// Foxy / SimpMusic-style circular progress around the mini-player play control.
class _FoxyMiniPlayRing extends StatelessWidget {
  const _FoxyMiniPlayRing({
    required this.progress,
    required this.playing,
    required this.buffering,
    required this.accent,
    required this.onPressed,
  });

  final Animation<double> progress;
  final bool playing;
  final bool buffering;
  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        return CustomPaint(
          painter: _FoxyMiniRingPainter(
            progress: progress.value.clamp(0.0, 1.0),
            accent: accent,
          ),
          child: child,
        );
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Center(
              child: buffering
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FoxyMiniRingPainter extends CustomPainter {
  _FoxyMiniRingPainter({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = accent.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);
    if (progress > 0.001) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        active,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FoxyMiniRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _FoxyPlayerSectionLabel extends StatelessWidget {
  const _FoxyPlayerSectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final upper = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.25,
      color: Colors.white.withValues(alpha: 0.42),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(text.toUpperCase(), style: upper)),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.playerController,
    this.initialTab = 0,
    this.homeBackgroundPath,
    this.onNotifyHomePlayerSync,
    this.onPlay,
    this.onTogglePlayPause,
    this.onDiscoverSearch,
  });

  final _PlayerStateController playerController;
  final int initialTab;
  final String? homeBackgroundPath;
  final Future<void> Function()? onNotifyHomePlayerSync;
  final _FoxyOnPlay? onPlay;
  final Future<void> Function()? onTogglePlayPause;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  late Map<String, dynamic> _player = _detachPlayerState(
    widget.playerController.value,
  );
  final ScrollController _scrollController = ScrollController();
  late int _tab = widget.initialTab;
  List<_LyricLine> _lyrics = const [];
  String? _lyricsFor;
  bool _lyricsPreferLrclib = true;
  bool _lyricsRomanize = false;
  bool _lyricsLoading = false;
  bool _clipsBackdropReady = false;
  double _artworkSwipeDx = 0;
  bool _blurPlayerBackdrop = true;
  late final VoidCallback _playerListener;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    _playerListener = () {
      _FoxyPerfProbe.event('player.listener');
      if (!mounted) return;
      _FoxyPerfProbe.measure('player.listener.work', () {
        final previous = _player;
        final detached = _detachPlayerState(widget.playerController.value);
        final nextStyle = ((detached['playerBackgroundStyle'] ?? 0) as num)
            .toInt();
        _armClipsBackdropIfNeeded(nextStyle);
        if (_shouldSkipLightPlayerUpdate(previous, detached)) {
          _player = detached;
          _loadLyricsIfNeeded(detached);
          return;
        }
        setState(() => _player = detached);
        _loadLyricsIfNeeded(detached);
      });
    };
    widget.playerController.addListener(_playerListener);
    _armClipsBackdropIfNeeded(
      ((_player['playerBackgroundStyle'] ?? 0) as num).toInt(),
    );
    _loadLyricsIfNeeded(_player);
  }

  bool _shouldSkipLightPlayerUpdate(
    Map<String, dynamic> previous,
    Map<String, dynamic> next,
  ) {
    if (_queueSignature(previous['queue']) != _queueSignature(next['queue'])) {
      return false;
    }
    if (_playerVisualSignature(previous) != _playerVisualSignature(next)) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    if (((_player['playerBackgroundStyle'] ?? 0) as num).toInt() == 3) {
      unawaited(
        _method.invokeMethod('setAppearance', {'playerBackgroundStyle': 0}),
      );
    }
    widget.playerController.removeListener(_playerListener);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    final nextBlur = map['blurEffects'] != false;
    if (_blurPlayerBackdrop == nextBlur) return;
    setState(() => _blurPlayerBackdrop = nextBlur);
  }

  Future<void> _refreshPlayerSettings() async {
    await widget.playerController.loadFromNative();
    if (!mounted) return;
    final detached = _detachPlayerState(widget.playerController.value);
    if (mapEquals(_player, detached)) return;
    setState(() => _player = detached);
  }

  void _armClipsBackdropIfNeeded(int style) {
    if (style != 3) {
      if (_clipsBackdropReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _clipsBackdropReady = false);
        });
      }
      return;
    }
    if (_clipsBackdropReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(const Duration(milliseconds: 180), () {
        if (!mounted) return;
        final currentStyle = ((_player['playerBackgroundStyle'] ?? 0) as num)
            .toInt();
        if (currentStyle == 3) {
          setState(() => _clipsBackdropReady = true);
        }
      });
    });
  }

  Future<void> _setPlayerBackgroundStyle(int style) async {
    if (mounted && style != 3 && _clipsBackdropReady) {
      setState(() => _clipsBackdropReady = false);
    }
    await _method.invokeMethod('setAppearance', {
      'playerBackgroundStyle': style,
    });
    if (!mounted) return;
    await _loadAppearance();
    await _refreshPlayerSettings();
    _armClipsBackdropIfNeeded(style);
  }

  Future<void> _seekToPosition(int positionMs) async {
    final next = positionMs.clamp(0, 1 << 31);
    widget.playerController.patchTimeline(positionMs: next);
    setState(() {
      _player = Map<String, dynamic>.from(_player)..['positionMs'] = next;
    });
    await _method.invokeMethod('seekTo', {'positionMs': next});
  }

  Future<void> _seekToLyricsLine(int positionMs) async {
    final next = positionMs.clamp(0, 1 << 31);
    widget.playerController.patchTimeline(positionMs: next);
    setState(() {
      _player = Map<String, dynamic>.from(_player)..['positionMs'] = next;
    });
    await _method.invokeMethod('seekTo', {'positionMs': next});
  }

  Future<void> _switchPlayerTab(int tab) async {
    if (!mounted) return;
    final currentBg = ((_player['playerBackgroundStyle'] ?? 0) as num).toInt();
    if (tab != 0 && currentBg == 3) {
      await _setPlayerBackgroundStyle(0);
    }
    if (!mounted) return;
    setState(() => _tab = tab);
    if (tab == 0) {
      _armClipsBackdropIfNeeded(
        ((_player['playerBackgroundStyle'] ?? 0) as num).toInt(),
      );
    }
  }

  Future<void> _addCurrentSongToPlaylist(_Song song) async {
    final menu = await _SongMenuContext.load();
    if (!mounted) return;
    await _pickPlaylistToAddSong(
      context,
      song: song,
      playlists: menu.userPlaylists,
      onChanged: () async => _SongMenuContext.invalidate(),
    );
  }

  Future<void> _saveQueueToPlaylist(_Song seed) async {
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList();
    if (queue.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Queue is empty')));
      return;
    }
    final menu = await _SongMenuContext.load();
    if (!mounted) return;
    await _pickPlaylistToAddSongs(
      context,
      songs: queue,
      playlists: menu.userPlaylists,
      suggestedName: '${seed.title} queue',
      onChanged: () async => _SongMenuContext.invalidate(),
    );
  }

  Future<void> _playQueueFromTop() async {
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList();
    if (queue.isEmpty) return;
    onPlay(queue.first, queue);
  }

  Future<void> _shuffleCurrentQueue() async {
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList();
    if (queue.isEmpty) return;
    final shuffled = List<_Song>.from(queue)..shuffle();
    onPlay(shuffled.first, shuffled);
  }

  Future<void> _setVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    widget.playerController.patchTimeline(volume: next);
    await _method.invokeMethod('setVolume', {'volume': next});
  }

  Future<void> _downloadCurrentSong(_Song song) async {
    await _method.invokeMethod('download', {'song': song.toMap()});
    if (!mounted) return;
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap != null) {
      setState(() => _player = _detachPlayerState(snap));
    }
  }

  Future<void> _toggleLikeCurrentSong(_Song song) async {
    final method = _player['songIsLiked'] == true ? 'unlike' : 'like';
    await _method.invokeMethod(method, {'song': song.toMap()});
    if (!mounted) return;
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap != null) {
      setState(() => _player = _detachPlayerState(snap));
    }
  }

  Future<void> _loadLyricsIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final preferLrclib = player['lyricsPreferLrclib'] != false;
    final romanize = player['lyricsRomanize'] == true;
    if (song.videoId.isEmpty ||
        (_lyricsFor == song.videoId &&
            _lyricsPreferLrclib == preferLrclib &&
            _lyricsRomanize == romanize) ||
        _lyricsLoading) {
      return;
    }
    _lyricsFor = song.videoId;
    _lyricsPreferLrclib = preferLrclib;
    _lyricsRomanize = romanize;
    setState(() {
      _lyricsLoading = true;
      _lyrics = const [];
    });
    try {
      final response = await _method.invokeMethod('lyrics', {
        'song': song.toMap(),
      });
      final lines = (response as List? ?? const [])
          .map((item) => _LyricLine.fromMap(_asMap(item) ?? const {}))
          .where((line) => line.text.isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _lyrics = lines;
        _lyricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _lyricsLoading = false);
    }
  }

  void _openMenu(_Song song) {
    final parent = context;
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList();
    _showFoxySongOverflowMenu(
      parent,
      song: song,
      onPlay: onPlay,
      queueForPlay: queue.isEmpty ? <_Song>[song] : queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: widget.onNotifyHomePlayerSync,
      searchResultsForExtras: queue.length > 1 ? queue : null,
      bulkQueuePlayTitle: 'Play full queue',
      bulkQueuePlaySubtitle: 'Keeps the current player queue order',
      onOpenLyricsTabInPlayer: () {
        unawaited(_switchPlayerTab(1));
      },
    );
  }

  void _showTrackInfo(_Song song) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Track info'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              song.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SelectableText(song.artist),
            const SizedBox(height: 8),
            SelectableText('Video ID: ${song.videoId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(
                  text: 'https://music.youtube.com/watch?v=${song.videoId}',
                ),
              );
              Navigator.pop(ctx);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('YouTube Music link copied')),
              );
            },
            child: const Text('Copy link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSystemEqualizer() async {
    final ok = await _method.invokeMethod('openSystemEqualizer') == true;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Opened system audio effects'
              : 'No system equalizer panel on this device',
        ),
      ),
    );
  }

  Future<void> _togglePlayPause() async {
    final handler = widget.onTogglePlayPause;
    if (handler == null) return;
    await handler();
  }

  Future<void> _invokePlayerNavWithFallback(String method) async {
    await _method.invokeMethod(method);
    Future<void>.delayed(const Duration(milliseconds: 420), () async {
      if (!mounted) return;
      await widget.playerController.resync();
    });
  }

  Future<void> _showSleepTimerSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.stop_circle_outlined),
                title: const Text('Turn off sleep timer'),
                onTap: () {
                  _method.invokeMethod('cancelSleepTimer');
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('End of this track'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 0});
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('In 15 minutes'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 15});
                  Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('In 30 minutes'),
                onTap: () {
                  _method.invokeMethod('sleepTimer', {'minutes': 30});
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerFooter({
    required BuildContext context,
    required _Song song,
    required String streamLabel,
    required _PlayerTimelineState timeline,
    required int effectiveDurMs,
    required double progress,
    required double position,
    required String endTimeLabel,
    required int playerProgressStyle,
    required int playerButtonsStyle,
    required int playerBackgroundStyle,
    required bool style2,
    required double shownVolume,
    required double padBottom,
  }) {
    return _FoxyPerfProbe.measure(
      'player.footer.build',
      () => _NowPlayingFooter(
        song: song,
        streamLabel: streamLabel,
        timeline: timeline,
        effectiveDurMs: effectiveDurMs,
        progress: progress,
        position: position,
        endTimeLabel: endTimeLabel,
        playerProgressStyle: playerProgressStyle,
        playerButtonsStyle: playerButtonsStyle,
        playerBackgroundStyle: playerBackgroundStyle,
        style2: style2,
        volume: shownVolume,
        songIsLiked: _player['songIsLiked'] == true,
        padBottom: padBottom,
        onAddToPlaylist: () => unawaited(_addCurrentSongToPlaylist(song)),
        onDownload: song.isDownloaded
            ? null
            : () => unawaited(_downloadCurrentSong(song)),
        onToggleLike: () => unawaited(_toggleLikeCurrentSong(song)),
        onSeek: (value) =>
            unawaited(_seekToPosition((effectiveDurMs * value).round())),
        onVolumeChanged: (value) => unawaited(_setVolume(value)),
        onShowTrackInfo: () => _showTrackInfo(song),
        onOpenLyrics: () => unawaited(_switchPlayerTab(1)),
        onOpenQueue: () => unawaited(_switchPlayerTab(2)),
        onShowSleepTimer: () => _showSleepTimerSheet(context),
        onOpenEqualizer: _openSystemEqualizer,
        onPrevious: () => unawaited(_invokePlayerNavWithFallback('previous')),
        onNext: () => unawaited(_invokePlayerNavWithFallback('next')),
        onTogglePlayPause: () => unawaited(_togglePlayPause()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _FoxyPerfProbe.measure('player.sheet.build', () {
      final accent = Theme.of(context).colorScheme.primary;
      final timelineListenable = widget.playerController.timelineListenable;
      final queueListenable = widget.playerController.queueListenable;
      final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
      final streamLabel = _streamQualityLabel(_player);
      final playerBackgroundStyle =
          ((_player['playerBackgroundStyle'] ?? 0) as num).toInt().clamp(0, 3);
      final effectiveBackgroundStyle =
          playerBackgroundStyle == 3 && !_clipsBackdropReady
          ? 0
          : playerBackgroundStyle;
      final playerStyle = ((_player['playerStyle'] ?? 0) as num).toInt().clamp(
        0,
        2,
      );
      final style2 = playerStyle == 2;
      final playerButtonsStyle = ((_player['playerButtonsStyle'] ?? 0) as num)
          .toInt()
          .clamp(0, 2);
      final playerProgressStyle =
          switch (((_player['playerProgressStyle'] ?? 0) as num).toInt()) {
            2 => 2,
            _ => 0,
          };
      final playerArtworkShape = ((_player['playerArtworkShape'] ?? 0) as num)
          .toInt()
          .clamp(0, 2);
      final padL = 14.0 + MediaQuery.paddingOf(context).left;
      final padR = 14.0 + MediaQuery.paddingOf(context).right;
      final padBottom = MediaQuery.paddingOf(context).bottom;
      return Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: _BlurBackdrop(
                url: song.highQualityArtwork,
                videoId: song.videoId,
                title: song.title,
                artist: song.artist,
                blurEnabled: _blurPlayerBackdrop,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
                fullBleed: true,
                backgroundStyle: effectiveBackgroundStyle,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padL, 4, padR, 6),
                  child: RepaintBoundary(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(top: 2, bottom: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                              ),
                              color: Colors.white,
                              onPressed: () {
                                if (playerBackgroundStyle == 3) {
                                  unawaited(_setPlayerBackgroundStyle(0));
                                }
                                Navigator.pop(context);
                              },
                            ),
                            Expanded(
                              child: style2
                                  ? const SizedBox.shrink()
                                  : Center(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: _NowPlayingBrandHeader(
                                          subtitle: _tab == 0
                                              ? 'Now Playing'
                                              : (_tab == 1
                                                    ? 'Lyrics'
                                                    : 'Queue'),
                                        ),
                                      ),
                                    ),
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 44,
                                minHeight: 44,
                              ),
                              icon: const Icon(Icons.more_vert_rounded),
                              color: Colors.white,
                              tooltip: 'More',
                              onPressed: () => _openMenu(song),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padL, 0, padR, 0),
                      child: Column(
                        children: [
                          if (style2) ...[
                            RepaintBoundary(
                              child: _PlayerTopToolCluster(
                                activeTab: _tab,
                                clipsEnabled: playerBackgroundStyle == 3,
                                onLyrics: () => unawaited(_switchPlayerTab(1)),
                                onArtwork: () => unawaited(_switchPlayerTab(0)),
                                onQueue: () => unawaited(_switchPlayerTab(2)),
                                onClips: () => unawaited(
                                  _setPlayerBackgroundStyle(
                                    playerBackgroundStyle == 3 ? 0 : 3,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 0),
                          ],
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 240),
                              child: switch (_tab) {
                                1 => LayoutBuilder(
                                  key: const ValueKey('lyrics'),
                                  builder: (context, c) {
                                    return Stack(
                                      children: [
                                        Positioned.fill(
                                          child:
                                              ValueListenableBuilder<
                                                _PlayerTimelineState
                                              >(
                                                valueListenable:
                                                    timelineListenable,
                                                builder: (context, timeline, _) {
                                                  return _LyricsBackdropStage(
                                                    lines: _lyrics,
                                                    loading: _lyricsLoading,
                                                    positionMs:
                                                        timeline.positionMs,
                                                    accent: accent,
                                                    preferLrclib:
                                                        _player['lyricsPreferLrclib'] !=
                                                        false,
                                                    romanized:
                                                        _player['lyricsRomanize'] ==
                                                        true,
                                                    onSeekToLine: (ms) =>
                                                        unawaited(
                                                          _seekToLyricsLine(ms),
                                                        ),
                                                  );
                                                },
                                              ),
                                        ),
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child:
                                              ValueListenableBuilder<
                                                _PlayerTimelineState
                                              >(
                                                valueListenable:
                                                    timelineListenable,
                                                builder: (context, timeline, _) {
                                                  final hintMs =
                                                      _durationHintMsFromCatalog(
                                                        song.duration,
                                                      );
                                                  final effectiveDurMs =
                                                      timeline.durationMs > 750
                                                      ? timeline.durationMs
                                                      : (hintMs ?? 0);
                                                  final position = timeline
                                                      .positionMs
                                                      .toDouble();
                                                  final progress =
                                                      effectiveDurMs <= 0
                                                      ? 0.0
                                                      : (position /
                                                                effectiveDurMs)
                                                            .clamp(0.0, 1.0);
                                                  final remMs =
                                                      effectiveDurMs <= 750
                                                      ? null
                                                      : math.min(
                                                          effectiveDurMs,
                                                          math.max(
                                                            0,
                                                            effectiveDurMs -
                                                                timeline
                                                                    .positionMs,
                                                          ),
                                                        );
                                                  final endTimeLabel =
                                                      remMs == null
                                                      ? 'â€”'
                                                      : '-${_fmt(remMs)}';
                                                  return RepaintBoundary(
                                                    child: _buildPlayerFooter(
                                                      context: context,
                                                      song: song,
                                                      streamLabel: streamLabel,
                                                      timeline: timeline,
                                                      effectiveDurMs:
                                                          effectiveDurMs,
                                                      progress: progress,
                                                      position: position,
                                                      endTimeLabel:
                                                          endTimeLabel,
                                                      playerProgressStyle:
                                                          playerProgressStyle,
                                                      playerButtonsStyle:
                                                          playerButtonsStyle,
                                                      playerBackgroundStyle:
                                                          playerBackgroundStyle,
                                                      style2: style2,
                                                      shownVolume:
                                                          timeline.volume,
                                                      padBottom: padBottom,
                                                    ),
                                                  );
                                                },
                                              ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                2 => ValueListenableBuilder<_PlayerQueueState>(
                                  valueListenable: queueListenable,
                                  builder: (context, queueState, _) {
                                    return SingleChildScrollView(
                                      key: const ValueKey('queue'),
                                      controller: _scrollController,
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: EdgeInsets.only(
                                        bottom: padBottom + 8,
                                      ),
                                      child: _QueueTab(
                                        queue: queueState.queue,
                                        currentIndex: queueState.queueIndex,
                                        onPlay: widget.onPlay,
                                        onDiscoverSearch:
                                            widget.onDiscoverSearch,
                                        onPlayFromTop: () =>
                                            unawaited(_playQueueFromTop()),
                                        onShuffleQueue: () =>
                                            unawaited(_shuffleCurrentQueue()),
                                        onSaveAsPlaylist: () => unawaited(
                                          _saveQueueToPlaylist(song),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _ => KeyedSubtree(
                                  key: ValueKey(
                                    'player-${song.videoId}-$effectiveBackgroundStyle',
                                  ),
                                  child: LayoutBuilder(
                                    builder: (context, c) {
                                      return Column(
                                        children: [
                                          Flexible(
                                            fit: FlexFit.loose,
                                            child: LayoutBuilder(
                                              builder: (context, artBox) {
                                                final artSide = math
                                                    .min(
                                                      artBox.maxWidth - 12,
                                                      artBox.maxHeight - 8,
                                                    )
                                                    .clamp(200.0, 380.0);
                                                return Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 26,
                                                        ),
                                                    child: AnimatedSwitcher(
                                                      duration: const Duration(
                                                        milliseconds: 220,
                                                      ),
                                                      child:
                                                          effectiveBackgroundStyle ==
                                                              3
                                                          ? SizedBox(
                                                              key: const ValueKey(
                                                                'hidden-artwork',
                                                              ),
                                                              width: artSide,
                                                              height: artSide,
                                                            )
                                                          : ValueListenableBuilder<
                                                              _PlayerTimelineState
                                                            >(
                                                              valueListenable:
                                                                  timelineListenable,
                                                              builder:
                                                                  (
                                                                    context,
                                                                    timeline,
                                                                    _,
                                                                  ) => GestureDetector(
                                                                    key: ValueKey(
                                                                      'visible-artwork-${song.videoId}',
                                                                    ),
                                                                    onHorizontalDragUpdate: (d) {
                                                                      _artworkSwipeDx += d
                                                                          .delta
                                                                          .dx;
                                                                    },
                                                                    onHorizontalDragEnd: (_) {
                                                                      if (_artworkSwipeDx >
                                                                          64) {
                                                                        unawaited(
                                                                          _invokePlayerNavWithFallback(
                                                                            'previous',
                                                                          ),
                                                                        );
                                                                      } else if (_artworkSwipeDx <
                                                                          -64) {
                                                                        unawaited(
                                                                          _invokePlayerNavWithFallback(
                                                                            'next',
                                                                          ),
                                                                        );
                                                                      }
                                                                      _artworkSwipeDx =
                                                                          0;
                                                                    },
                                                                    child: _PlayerArtwork(
                                                                      url: song
                                                                          .highQualityArtwork,
                                                                      playing:
                                                                          timeline
                                                                              .isPlaying &&
                                                                          !timeline
                                                                              .isBuffering,
                                                                      tag:
                                                                          'art-${song.videoId}',
                                                                      offlineArtworkPath:
                                                                          song.offlineArtworkPath,
                                                                      useOfflineArtwork:
                                                                          song.isDownloaded,
                                                                      maxSide:
                                                                          artSide,
                                                                      shape:
                                                                          playerArtworkShape,
                                                                      onTogglePlayback: () =>
                                                                          unawaited(
                                                                            _togglePlayPause(),
                                                                          ),
                                                                    ),
                                                                  ),
                                                            ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          ValueListenableBuilder<
                                            _PlayerTimelineState
                                          >(
                                            valueListenable: timelineListenable,
                                            builder: (context, timeline, _) {
                                              final hintMs =
                                                  _durationHintMsFromCatalog(
                                                    song.duration,
                                                  );
                                              final effectiveDurMs =
                                                  timeline.durationMs > 750
                                                  ? timeline.durationMs
                                                  : (hintMs ?? 0);
                                              final position = timeline
                                                  .positionMs
                                                  .toDouble();
                                              final progress =
                                                  effectiveDurMs <= 0
                                                  ? 0.0
                                                  : (position / effectiveDurMs)
                                                        .clamp(0.0, 1.0);
                                              final remMs =
                                                  effectiveDurMs <= 750
                                                  ? null
                                                  : math.min(
                                                      effectiveDurMs,
                                                      math.max(
                                                        0,
                                                        effectiveDurMs -
                                                            timeline.positionMs,
                                                      ),
                                                    );
                                              final endTimeLabel = remMs == null
                                                  ? 'â€”'
                                                  : '-${_fmt(remMs)}';
                                              return _buildPlayerFooter(
                                                context: context,
                                                song: song,
                                                streamLabel: streamLabel,
                                                timeline: timeline,
                                                effectiveDurMs: effectiveDurMs,
                                                progress: progress,
                                                position: position,
                                                endTimeLabel: endTimeLabel,
                                                playerProgressStyle:
                                                    playerProgressStyle,
                                                playerButtonsStyle:
                                                    playerButtonsStyle,
                                                playerBackgroundStyle:
                                                    playerBackgroundStyle,
                                                style2: style2,
                                                shownVolume: timeline.volume,
                                                padBottom: padBottom,
                                              );
                                            },
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class _NowPlayingBrandHeader extends StatelessWidget {
  const _NowPlayingBrandHeader({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _FoxyAppLogo(size: 32, borderRadius: 10, showGlow: false),
          const SizedBox(width: 11),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 3.0,
                    color: Colors.white,
                  ),
                  children: const [
                    TextSpan(text: 'Foxy'),
                    TextSpan(text: 'Music'),
                  ],
                ),
              ),
              const SizedBox(height: 3.0),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact frosted-glass action on the now-playing title row (SimpMusic-style).
class _NpIconAction extends StatelessWidget {
  const _NpIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.iconColor,
    this.style = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;
  final int style;

  @override
  Widget build(BuildContext context) {
    final tint = switch (style) {
      1 => Colors.black.withValues(alpha: 0.16),
      2 => Colors.white.withValues(alpha: 0.94),
      _ => Colors.black.withValues(alpha: 0.10),
    };
    final borderOpacity = style == 1 ? 0.34 : 0.20;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: borderOpacity),
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: style == 2
                  ? Colors.black
                  : (iconColor ?? Colors.white.withValues(alpha: 0.92)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom tool row on the now-playing sheet (info, lyrics, queue, â€¦).
class _PlayerBottomToolButton extends StatelessWidget {
  const _PlayerBottomToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.whiteGlow = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  /// Lyrics control: soft white glow only (no tinted tile).
  final bool whiteGlow;

  static const double _tapSize = 50;
  static const double _iconSize = 28;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(
      icon,
      size: _iconSize,
      color: Colors.white.withValues(alpha: 0.94),
    );
    Widget child;
    if (whiteGlow) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.55),
              blurRadius: 18,
              spreadRadius: 1,
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.28),
              blurRadius: 32,
              spreadRadius: 2,
            ),
          ],
        ),
        child: iconWidget,
      );
    } else {
      child = iconWidget;
    }
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: _tapSize,
            height: _tapSize,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _PlayerTopToolCluster extends StatelessWidget {
  const _PlayerTopToolCluster({
    required this.activeTab,
    required this.clipsEnabled,
    required this.onLyrics,
    required this.onArtwork,
    required this.onQueue,
    required this.onClips,
  });

  final int activeTab;
  final bool clipsEnabled;
  final VoidCallback onLyrics;
  final VoidCallback onArtwork;
  final VoidCallback onQueue;
  final VoidCallback onClips;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: const Offset(0, -6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.26),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.24),
                  width: 2.4,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlayerTopToolButton(
                      tooltip: 'Lyrics',
                      icon: Icons.lyrics_outlined,
                      selected: activeTab == 1,
                      onPressed: onLyrics,
                    ),
                    _PlayerTopToolButton(
                      tooltip: 'Artwork',
                      icon: Icons.album_outlined,
                      selected: activeTab == 0,
                      onPressed: onArtwork,
                    ),
                    _PlayerTopToolButton(
                      tooltip: 'Queue',
                      icon: Icons.queue_music_rounded,
                      selected: activeTab == 2,
                      onPressed: onQueue,
                    ),
                    _PlayerTopToolButton(
                      tooltip: clipsEnabled ? 'Clips on' : 'Clips',
                      icon: Icons.movie_creation_outlined,
                      selected: clipsEnabled,
                      onPressed: onClips,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerTopToolButton extends StatelessWidget {
  const _PlayerTopToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.transparent,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
      ),
    );
  }
}

class _FoxySeekBar extends StatefulWidget {
  const _FoxySeekBar({
    required this.progress,
    required this.enabled,
    required this.playing,
    required this.style,
    required this.motion,
    required this.onSeek,
  });

  final double progress;
  final bool enabled;
  final bool playing;
  final int style;
  final int motion;
  final ValueChanged<double> onSeek;

  @override
  State<_FoxySeekBar> createState() => _FoxySeekBarState();
}

class _FoxySeekBarState extends State<_FoxySeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase;
  bool _dragging = false;
  double? _visualProgress;

  @override
  void initState() {
    super.initState();
    _phase = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _FoxySeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing ||
        oldWidget.style != widget.style ||
        oldWidget.motion != widget.motion ||
        oldWidget.enabled != widget.enabled) {
      _syncMotion();
    }
    if (!_dragging) {
      _visualProgress = widget.progress.clamp(0.0, 1.0);
    }
  }

  void _syncMotion() {
    final animatedStyle = widget.style == 1 || widget.style == 3;
    final canMove =
        widget.enabled && widget.playing && widget.motion != 2 && animatedStyle;
    if (canMove) {
      _phase.repeat(
        period: Duration(milliseconds: widget.motion == 1 ? 3600 : 1900),
      );
    } else {
      _phase.stop();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  void _seek(BuildContext context, double dx) {
    if (!widget.enabled) return;
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    if (width <= 0) return;
    final next = (dx / width).clamp(0.0, 1.0);
    if (_visualProgress != next) {
      setState(() => _visualProgress = next);
    }
    widget.onSeek(next);
  }

  @override
  Widget build(BuildContext context) {
    final barHeight = switch (widget.style) {
      2 => 40.0,
      _ => 44.0,
    };
    final shownProgress =
        (_dragging ? _visualProgress : widget.progress)?.clamp(0.0, 1.0) ??
        widget.progress.clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      onHorizontalDragStart: widget.enabled
          ? (_) => setState(() {
              _dragging = true;
              _visualProgress = widget.progress.clamp(0.0, 1.0);
            })
          : null,
      onHorizontalDragUpdate: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      onHorizontalDragEnd: widget.enabled
          ? (_) => setState(() => _dragging = false)
          : null,
      onHorizontalDragCancel: widget.enabled
          ? () => setState(() => _dragging = false)
          : null,
      child: SizedBox(
        height: barHeight,
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 1.0,
            child: SizedBox(
              height: barHeight,
              width: double.infinity,
              child: AnimatedBuilder(
                animation: _phase,
                builder: (context, _) => CustomPaint(
                  painter: _FoxySeekBarPainter(
                    progress: shownProgress,
                    enabled: widget.enabled,
                    playing: widget.playing,
                    dragging: _dragging,
                    style: widget.style,
                    motion: widget.motion,
                    phase: _phase.value,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FoxySeekBarPainter extends CustomPainter {
  const _FoxySeekBarPainter({
    required this.progress,
    required this.enabled,
    required this.playing,
    required this.dragging,
    required this.style,
    required this.motion,
    required this.phase,
  });

  final double progress;
  final bool enabled;
  final bool playing;
  final bool dragging;
  final int style;
  final int motion;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final activeColor = enabled ? Colors.white : Colors.white38;
    final inactiveColor = const Color(
      0xFF5C5C5C,
    ).withValues(alpha: enabled ? 1 : 0.55);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final progressX = size.width * clampedProgress;
    final trackWidth = switch (style) {
      2 => 4.0,
      3 => 6.6,
      _ => 5.5,
    };
    final trackPaint = Paint()
      ..color = inactiveColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = trackWidth;
    final activePaint = Paint()
      ..color = activeColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = trackWidth;

    if (style == 1 || style == 3) {
      final calm = motion == 1;
      final shouldWave = enabled && playing && !dragging && motion != 2;
      final amplitude = shouldWave
          ? (style == 3 ? (calm ? 14.0 : 20.0) : (calm ? 10.0 : 14.0))
          : 0.0;
      final wavelength = style == 3 ? 72.0 : 64.0;
      final phasePx = phase * wavelength;
      Path buildPath() {
        final path = Path();
        final waveStart = -phasePx - wavelength / 2;
        final waveEnd = size.width + wavelength / 2;
        final dist = wavelength / 2;

        double amplitudeAt(double x, double sign) {
          if (style != 3 || !shouldWave) {
            return sign * amplitude;
          }
          final fadeLength = wavelength * 1.3;
          final coeff = ((progressX + fadeLength / 2 - x) / fadeLength).clamp(
            0.0,
            1.0,
          );
          return sign * amplitude * coeff;
        }

        var currentX = waveStart;
        var waveSign = 1.0;
        var currentAmp = amplitudeAt(currentX, waveSign);
        path.moveTo(currentX, y);

        while (currentX < waveEnd) {
          waveSign = -waveSign;
          final nextX = currentX + dist;
          final midX = currentX + dist / 2;
          final nextAmp = amplitudeAt(nextX, waveSign);

          path.cubicTo(
            midX,
            y + currentAmp,
            midX,
            y + nextAmp,
            nextX,
            y + nextAmp,
          );

          currentAmp = nextAmp;
          currentX = nextX;
        }
        return path;
      }

      final path = buildPath();
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(progressX, 0, size.width, size.height));
      canvas.drawPath(path, trackPaint);
      canvas.restore();
      if (clampedProgress > 0.001) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, progressX, size.height));
        canvas.drawPath(path, activePaint);
        canvas.restore();
      }
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);
      if (clampedProgress > 0.001) {
        canvas.drawLine(Offset(0, y), Offset(progressX, y), activePaint);
      }
    }

    final x = progressX.clamp(2.0, math.max(2.0, size.width - 2.0)).toDouble();
    final thumbPaint = Paint()..color = activeColor;
    if (style == 1) {
      canvas.drawCircle(Offset(x, y), dragging ? 8.0 : 7.0, thumbPaint);
    } else {
      final thumbHeight = style == 2 ? 14.0 : 24.0;
      final thumbWidth = style == 2 ? 4.5 : 6.5;
      final thumb = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, y),
          width: thumbWidth,
          height: thumbHeight,
        ),
        const Radius.circular(2),
      );
      canvas.drawRRect(thumb, thumbPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FoxySeekBarPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.enabled != enabled ||
      oldDelegate.playing != playing ||
      oldDelegate.dragging != dragging ||
      oldDelegate.style != style ||
      oldDelegate.motion != motion ||
      oldDelegate.phase != phase;
}

/// SimpMusic-style transport row: shuffle | previous | large play/pause | next | repeat.
/// Play circle is stacked above a compact side-icon row so the layout stays packed.
class _SimpMusicPlayerControlLayout extends StatelessWidget {
  const _SimpMusicPlayerControlLayout({
    required this.shuffle,
    required this.repeatMode,
    required this.playing,
    required this.buffering,
    required this.prevEnabled,
    required this.nextEnabled,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayPause,
    this.buttonStyle = 0,
  });

  /// SimpMusic-scale main play control (~72dp), not an oversized FAB.
  static const double _playDiameter = 72;
  static const double _centerGap = 80;

  final bool shuffle;
  final String repeatMode;
  final bool playing;
  final bool buffering;
  final bool prevEnabled;
  final bool nextEnabled;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayPause;
  final int buttonStyle;

  @override
  Widget build(BuildContext context) {
    final repeatOn = repeatMode != 'Off';
    final activeColor = Colors.white;
    final whiteOn = activeColor.withValues(alpha: 0.95);
    final whiteOff = Colors.white.withValues(alpha: 0.55);
    final playFill = switch (buttonStyle) {
      1 => Colors.white.withValues(alpha: 0.03),
      2 => Colors.white.withValues(alpha: 0.06),
      _ => Colors.white.withValues(alpha: 0.05),
    };
    final playBorderOpacity = switch (buttonStyle) {
      1 => 0.44,
      2 => 0.52,
      _ => 0.38,
    };

    Widget sideSlot(Widget child) => Expanded(child: Center(child: child));

    Widget iconOnlyBtn({required VoidCallback? onTap, required Widget icon}) {
      return IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 24,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: icon,
      );
    }

    final playCircle = Material(
      color: playFill,
      elevation: 0,
      shadowColor: Colors.white.withValues(alpha: 0.24),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTogglePlayPause,
        child: SizedBox(
          width: _playDiameter,
          height: _playDiameter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.22),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.10),
                  blurRadius: 38,
                  spreadRadius: 2,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: playBorderOpacity),
                width: 1.4,
              ),
            ),
            child: buffering
                ? Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: playing ? 36 : 40,
                    color: Colors.white.withValues(alpha: 0.97),
                  ),
          ),
        ),
      ),
    );

    return SizedBox(
      height: _playDiameter,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                sideSlot(
                  iconOnlyBtn(
                    onTap: () => _method.invokeMethod('toggleShuffle'),
                    icon: Icon(
                      Icons.shuffle_rounded,
                      size: 28,
                      color: shuffle ? whiteOn : whiteOff,
                    ),
                  ),
                ),
                sideSlot(
                  iconOnlyBtn(
                    onTap: prevEnabled ? onPrevious : null,
                    icon: Icon(
                      Icons.skip_previous_rounded,
                      size: 34,
                      color: prevEnabled
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white30,
                    ),
                  ),
                ),
                const SizedBox(width: _centerGap),
                sideSlot(
                  iconOnlyBtn(
                    onTap: nextEnabled ? onNext : null,
                    icon: Icon(
                      Icons.skip_next_rounded,
                      size: 34,
                      color: nextEnabled
                          ? Colors.white.withValues(alpha: 0.95)
                          : Colors.white30,
                    ),
                  ),
                ),
                sideSlot(
                  iconOnlyBtn(
                    onTap: () => _method.invokeMethod('cycleRepeatMode'),
                    icon: Icon(
                      repeatMode == 'One'
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      size: 28,
                      color: repeatOn ? whiteOn : whiteOff,
                    ),
                  ),
                ),
              ],
            ),
          ),
          playCircle,
        ],
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.currentIndex,
    this.onPlay,
    this.onDiscoverSearch,
    this.onPlayFromTop,
    this.onShuffleQueue,
    this.onSaveAsPlaylist,
  });

  final List<_Song> queue;
  final int currentIndex;
  final _FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;
  final VoidCallback? onPlayFromTop;
  final VoidCallback? onShuffleQueue;
  final VoidCallback? onSaveAsPlaylist;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _FoxyPlayerSectionLabel(
          'Queue',
          trailing: Padding(
            padding: const EdgeInsets.only(bottom: 1, right: 2),
            child: Text(
              '${queue.length} songs',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        if (queue.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QueueActionChip(
                icon: Icons.play_arrow_rounded,
                label: 'From top',
                onPressed: onPlayFromTop,
              ),
              _QueueActionChip(
                icon: Icons.shuffle_rounded,
                label: 'Shuffle',
                onPressed: onShuffleQueue,
              ),
              _QueueActionChip(
                icon: Icons.playlist_add_rounded,
                label: 'Save queue',
                onPressed: onSaveAsPlaylist,
              ),
            ],
          ),
        ],
        if (queue.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 48),
            child: _EmptyTabBody(
              icon: Icons.queue_music_rounded,
              title: 'Queue is empty',
              subtitle: 'Play a song to build your queue, then open this tab.',
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            proxyDecorator: (child, index, animation) => Material(
              color: Colors.transparent,
              child: FadeTransition(opacity: animation, child: child),
            ),
            onReorder: (oldIndex, newIndex) {
              final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
              _method.invokeMethod('moveQueueItem', {
                'fromIndex': oldIndex,
                'toIndex': adjusted,
              });
            },
            itemCount: queue.length,
            itemBuilder: (context, index) {
              final item = queue[index];
              final active = index == currentIndex;
              return Row(
                key: ValueKey('queue-${item.videoId}'),
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: Colors.white.withValues(alpha: 0.42),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: active
                              ? Colors.white.withValues(alpha: 0.42)
                              : Colors.white.withValues(alpha: 0.07),
                        ),
                      ),
                      child: _FoxySongTile(
                        song: item,
                        index: index,
                        thumbRadius: 10,
                        active: active,
                        onMore: () {
                          final play = onPlay;
                          if (play != null) {
                            _showFoxySongOverflowMenu(
                              context,
                              song: item,
                              onPlay: play,
                              queueForPlay: queue,
                              onDiscoverSearch: onDiscoverSearch,
                              onLibraryChanged: () async {},
                              showRemoveFromQueue: true,
                            );
                          } else {
                            showModalBottomSheet<void>(
                              context: context,
                              backgroundColor: const Color(0xFF111111),
                              builder: (_) => _QueueSongMenu(song: item),
                            );
                          }
                        },
                        onTap: () => _method.invokeMethod('skipToQueueIndex', {
                          'index': index,
                        }),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _QueueActionChip extends StatelessWidget {
  const _QueueActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.88),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _QueueSongMenu extends StatelessWidget {
  const _QueueSongMenu({required this.song});

  final _Song song;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: _Artwork(
              url: song.artwork,
              size: 52,
              radius: 10,
              identityTag: song.videoId,
            ),
            title: Text(song.title, maxLines: 1),
            subtitle: Text(song.artist, maxLines: 1),
          ),
          _MenuAction(
            icon: Icons.queue_play_next_rounded,
            label: 'Play next',
            onTap: () =>
                _method.invokeMethod('enqueuePlayNext', {'song': song.toMap()}),
          ),
          _MenuAction(
            icon: Icons.delete_rounded,
            label: 'Remove from queue',
            onTap: () =>
                _method.invokeMethod('removeFromQueue', {'song': song.toMap()}),
          ),
        ],
      ),
    );
  }
}

class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      onTap: () async {
        await onTap();
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}

class _LyricLine {
  const _LyricLine({required this.timeMs, required this.text});

  factory _LyricLine.fromMap(Map<String, dynamic> map) => _LyricLine(
    timeMs: ((map['timeMs'] ?? 0) as num).toInt(),
    text: map['text']?.toString() ?? '',
  );

  final int timeMs;
  final String text;
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.url,
    required this.playing,
    required this.tag,
    required this.onTogglePlayback,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.maxSide,
    this.shape = 0,
  });

  final String url;
  final bool playing;
  final String tag;
  final VoidCallback onTogglePlayback;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  /// Caps artwork so transport rows never collide on narrow devices.
  final double? maxSide;
  final int shape;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final base = math.min(w - 4, h * 0.52).clamp(360.0, 960.0);
    final side = maxSide ?? base;
    final artSide = shape == 2 ? side * 0.88 : side;
    final radius = switch (shape) {
      1 => artSide / 2,
      2 => 16.0,
      _ => (artSide * 0.075).clamp(18.0, 28.0),
    };
    final discSize = artSide * 0.22;
    final accent = Theme.of(context).colorScheme.primary;
    final identity = tag.startsWith('art-') ? tag.substring(4) : tag;

    return SizedBox(
      width: artSide,
      height: artSide,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.55),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius - 1),
              child: SizedBox(
                width: artSide,
                height: artSide,
                child: _Artwork(
                  url: url,
                  size: artSide,
                  radius: 0,
                  highQuality: true,
                  identityTag: identity,
                  offlineArtworkPath: offlineArtworkPath,
                  useOfflineArtwork: useOfflineArtwork,
                ),
              ),
            ),
          ),
          if (shape != 1)
            Positioned(
              top: 8,
              right: 8,
              child: _SpinningDiscOverlay(
                size: discSize,
                playing: playing,
                accent: accent,
                artworkUrl: url,
                identityTag: identity,
                onTogglePlayback: () async => onTogglePlayback(),
                offlineArtworkPath: offlineArtworkPath,
                useOfflineArtwork: useOfflineArtwork,
              ),
            ),
        ],
      ),
    );
  }
}

/// Small vinyl disc badge â€” spins in the upper-right corner of the artwork.
/// Small vinyl disc badge â€” spins automatically when song is playing
class _SpinningDiscOverlay extends StatefulWidget {
  const _SpinningDiscOverlay({
    required this.size,
    required this.playing,
    required this.accent,
    required this.artworkUrl,
    required this.identityTag,
    required this.onTogglePlayback,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
  });

  final double size;
  final bool playing;
  final Color accent;
  final String artworkUrl;
  final String identityTag;
  final Future<void> Function() onTogglePlayback;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  @override
  State<_SpinningDiscOverlay> createState() => _SpinningDiscOverlayState();
}

class _SpinningDiscOverlayState extends State<_SpinningDiscOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl;
  bool? _manualPlaying;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6), // Smooth speed
    );
    _syncSpinState();
  }

  @override
  void didUpdateWidget(covariant _SpinningDiscOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) {
      if (_manualPlaying == widget.playing) {
        _manualPlaying = null;
      }
      _syncSpinState();
    }
  }

  bool get _effectivePlaying => _manualPlaying ?? widget.playing;

  void _syncSpinState() {
    if (_effectivePlaying) {
      if (!_spinCtrl.isAnimating) {
        _spinCtrl.repeat();
      }
    } else {
      _spinCtrl.stop();
    }
  }

  Future<void> _togglePlaybackFromDisc() async {
    final next = !_effectivePlaying;
    setState(() => _manualPlaying = next);
    _syncSpinState();
    try {
      await widget.onTogglePlayback();
    } catch (_) {
      if (!mounted) return;
      setState(() => _manualPlaying = null);
      _syncSpinState();
    }
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(_togglePlaybackFromDisc()),
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RotationTransition(
                turns: _spinCtrl,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RepaintBoundary(
                      child: ClipOval(
                        child: _Artwork(
                          url: widget.artworkUrl,
                          size: widget.size,
                          radius: 0,
                          highQuality: true,
                          identityTag: 'disc-${widget.identityTag}',
                          offlineArtworkPath: widget.offlineArtworkPath,
                          useOfflineArtwork: widget.useOfflineArtwork,
                        ),
                      ),
                    ),
                    CustomPaint(
                      painter: const _VinylDiskPainter(compact: true),
                    ),
                    Center(child: _FoxyAppIconBadge(size: widget.size * 0.36)),
                  ],
                ),
              ),
              IgnorePointer(
                child: CustomPaint(
                  painter: const _VinylTonearmPainter(compact: true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Vinyl ring overlay (full disc or compact corner badge).
class _VinylDiskPainter extends CustomPainter {
  const _VinylDiskPainter({this.compact = false});

  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final labelR = outerR * (compact ? 0.34 : 0.43);

    if (!compact) {
      final vinyl = Paint()..color = const Color(0xFF101010);
      canvas.drawCircle(center, outerR, vinyl);
    }

    final groove = Paint()
      ..color = Colors.white.withValues(alpha: compact ? 0.1 : 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 0.6 : 0.8;
    final step = compact ? 3.5 : 5.0;
    for (var r = labelR + (compact ? 3 : 6); r < outerR - 1; r += step) {
      canvas.drawCircle(center, r, groove);
    }

    if (compact) {
      final edge = Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1;
      canvas.drawCircle(center, outerR - 0.5, edge);
      canvas.drawCircle(
        center,
        labelR,
        Paint()..color = Colors.black.withValues(alpha: 0.3),
      );
    } else {
      const accentColor = _FoxyBrandPalette.foxAmber;
      final ring = Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.55),
            _FoxyBrandPalette.foxDeep.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.92),
          ],
          stops: const [0.5, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: outerR));
      canvas.drawCircle(center, outerR, ring);
      canvas.drawCircle(
        center,
        labelR + 3,
        Paint()..color = const Color(0xFF080808),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VinylDiskPainter oldDelegate) =>
      oldDelegate.compact != compact;
}

/// FoxyMusic logo badge on the vinyl outer ring.
class _FoxyAppIconBadge extends StatelessWidget {
  const _FoxyAppIconBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 6),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          _kFoxyLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.music_note_rounded,
            color: Colors.white,
            size: size * 0.58,
          ),
        ),
      ),
    );
  }
}

/// Fixed gramophone tonearm at the upper-right of the artwork.
class _VinylTonearmPainter extends CustomPainter {
  const _VinylTonearmPainter({this.compact = false});

  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (compact) {
      final pivot = Offset(size.width * 0.82, size.height * 0.18);
      final elbow = Offset(size.width * 0.73, size.height * 0.31);
      final tip = Offset(size.width * 0.62, size.height * 0.45);
      final arm = Paint()
        ..color = Colors.white.withValues(alpha: 0.88)
        ..strokeWidth = size.width * 0.032
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final armPath = Path()
        ..moveTo(pivot.dx, pivot.dy)
        ..quadraticBezierTo(
          size.width * 0.79,
          size.height * 0.23,
          elbow.dx,
          elbow.dy,
        )
        ..quadraticBezierTo(
          size.width * 0.68,
          size.height * 0.38,
          tip.dx,
          tip.dy,
        );
      canvas.drawPath(armPath, arm);
      canvas.drawCircle(
        pivot,
        size.width * 0.042,
        Paint()..color = Colors.white.withValues(alpha: 0.94),
      );
      canvas.drawCircle(
        pivot,
        size.width * 0.020,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      canvas.drawLine(
        Offset(size.width * 0.76, size.height * 0.21),
        pivot,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.62)
          ..strokeWidth = size.width * 0.016
          ..strokeCap = StrokeCap.round,
      );
      final head = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width * 0.59, size.height * 0.485),
          width: size.width * 0.15,
          height: size.height * 0.062,
        ),
        Radius.circular(size.width * 0.022),
      );
      canvas.drawRRect(
        head,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawRRect(
        head,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7,
      );
      canvas.drawLine(
        Offset(size.width * 0.555, size.height * 0.505),
        Offset(size.width * 0.535, size.height * 0.548),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..strokeWidth = size.width * 0.012
          ..strokeCap = StrokeCap.round,
      );
      return;
    }
    final pivot = Offset(size.width * 0.88, size.height * 0.12);
    final tip = Offset(size.width * 0.18, size.height * 0.78);
    final arm = Paint()
      ..color = Colors.white.withValues(alpha: 0.86)
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pivot, tip, arm);
    canvas.drawCircle(
      pivot,
      size.width * 0.1,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: tip,
        width: size.width * 0.34,
        height: size.height * 0.16,
      ),
      Radius.circular(size.width * 0.05),
    );
    canvas.drawRRect(
      head,
      Paint()..color = Colors.black.withValues(alpha: 0.88),
    );
    canvas.drawRRect(
      head,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(covariant _VinylTonearmPainter oldDelegate) =>
      oldDelegate.compact != compact;
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.size,
    required this.radius,
    this.identityTag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.highQuality = false,
  });

  final String url;
  final double size;
  final double radius;

  /// When set, combined with [url] for [Image.network] keys so artwork swaps on track change.
  final String? identityTag;

  /// Native-resolved JPEG path (embedded / cached) for offline artwork.
  final String? offlineArtworkPath;

  /// Only read [offlineArtworkPath] when true (downloaded tracks); streaming keeps network thumb.
  final bool useOfflineArtwork;

  /// Decode more pixels for large now-playing artwork.
  final bool highQuality;

  @override
  Widget build(BuildContext context) {
    File? offlineFile() {
      if (!useOfflineArtwork || kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      final f = File(p);
      if (f.existsSync()) return f;
      return null;
    }

    File? localPathFile() {
      if (kIsWeb) return null;
      final u = url.trim();
      if (u.isEmpty) return null;
      if (u.startsWith('http://') || u.startsWith('https://')) return null;
      final path = u.startsWith('file://') ? u.substring(7) : u;
      final f = File(path);
      if (f.existsSync() && f.lengthSync() > 0) return f;
      return null;
    }

    final of = offlineFile() ?? localPathFile();
    if (url.isBlank && of == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white.withValues(alpha: 0.42),
        ),
      );
    }
    final cacheKey = identityTag != null && identityTag!.isNotEmpty
        ? '${identityTag!}|${of?.path ?? url}|${offlineArtworkPath ?? ''}'
        : '${of?.path ?? url}|${offlineArtworkPath ?? ''}';
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.42),
      ),
    );

    final cacheMax = highQuality ? 1024 : 384;
    if (of != null) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(64, cacheMax);
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          of,
          key: ValueKey<String>(cacheKey),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: false,
          filterQuality: highQuality ? FilterQuality.high : FilterQuality.low,
          cacheWidth: cachePx,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    }

    if (url.isBlank) {
      return placeholder;
    }

    final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, cacheMax);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        key: ValueKey<String>(cacheKey),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: false,
        filterQuality: highQuality ? FilterQuality.high : FilterQuality.low,
        cacheWidth: cachePx,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _ClipBackdrop extends StatefulWidget {
  const _ClipBackdrop({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.fallback,
  });

  final String videoId;
  final String title;
  final String artist;
  final Widget fallback;

  @override
  State<_ClipBackdrop> createState() => _ClipBackdropState();
}

class _ClipBackdropState extends State<_ClipBackdrop> {
  VideoPlayerController? _controller;
  String? _loadedClipKey;
  String? _failedClipKey;
  int _loadToken = 0;
  int _scheduleToken = 0;

  @override
  void initState() {
    super.initState();
    _scheduleClipLoad();
  }

  @override
  void didUpdateWidget(covariant _ClipBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.title != widget.title ||
        oldWidget.artist != widget.artist) {
      _scheduleClipLoad();
    }
  }

  void _scheduleClipLoad() {
    final scheduled = ++_scheduleToken;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 320));
      if (!mounted || scheduled != _scheduleToken) return;
      unawaited(_loadClip());
    });
  }

  Future<void> _loadClip() async {
    final videoId = widget.videoId.trim();
    final clipKey = '$videoId|${widget.title.trim()}|${widget.artist.trim()}';
    if (videoId.isEmpty ||
        _loadedClipKey == clipKey ||
        _failedClipKey == clipKey) {
      return;
    }
    final token = ++_loadToken;
    final prev = _controller;
    try {
      final response = _asMap(
        await _method.invokeMethod('getVideoClipStream', {
          'videoId': videoId,
          'title': widget.title,
          'artist': widget.artist,
        }),
      );
      final url = response?['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        throw StateError(
          response?['error']?.toString().trim().isNotEmpty == true
              ? response!['error'].toString()
              : 'No video clip stream',
        );
      }
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted || token != _loadToken) {
        await controller.dispose();
        return;
      }
      await controller.play();
      setState(() {
        _controller = controller;
        _loadedClipKey = clipKey;
        _failedClipKey = null;
      });
      await prev?.dispose();
    } catch (e) {
      if (mounted) {
        setState(() {
          _failedClipKey = clipKey;
        });
      }
      await prev?.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      return Positioned.fill(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }
    return widget.fallback;
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.62)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _RecognitionUiState {
  const _RecognitionUiState({required this.state, this.message, this.result});

  const _RecognitionUiState.ready() : this(state: 'ready');
  const _RecognitionUiState.listening() : this(state: 'listening');
  const _RecognitionUiState.error(String message)
    : this(state: 'error', message: message);

  factory _RecognitionUiState.fromMap(Map<String, dynamic> map) {
    final state = map['state']?.toString() ?? 'ready';
    return _RecognitionUiState(
      state: state,
      message: map['message']?.toString(),
      result: _RecognitionResult.fromMap(_asMap(map['result']) ?? const {}),
    );
  }

  final String state;
  final String? message;
  final _RecognitionResult? result;

  bool get isListening => state == 'listening';
  bool get isProcessing => state == 'processing';
  bool get isReady => state == 'ready';
  bool get isSuccess => state == 'success' && result != null;
}

class _RecognitionResult {
  const _RecognitionResult({
    required this.title,
    required this.artist,
    this.album,
    this.coverArtUrl,
    this.coverArtHqUrl,
    this.genre,
    this.releaseDate,
    this.label,
    this.lyrics = const [],
    this.shazamUrl,
    this.appleMusicUrl,
    this.spotifyUrl,
    this.youtubeVideoId,
  });

  factory _RecognitionResult.fromMap(Map<String, dynamic> map) {
    final title = map['title']?.toString() ?? '';
    if (title.isEmpty) return const _RecognitionResult(title: '', artist: '');
    return _RecognitionResult(
      title: title,
      artist: map['artist']?.toString() ?? '',
      album: map['album']?.toString(),
      coverArtUrl: map['coverArtUrl']?.toString(),
      coverArtHqUrl: map['coverArtHqUrl']?.toString(),
      genre: map['genre']?.toString(),
      releaseDate: map['releaseDate']?.toString(),
      label: map['label']?.toString(),
      lyrics: (map['lyrics'] as List? ?? const [])
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      shazamUrl: map['shazamUrl']?.toString(),
      appleMusicUrl: map['appleMusicUrl']?.toString(),
      spotifyUrl: map['spotifyUrl']?.toString(),
      youtubeVideoId: map['youtubeVideoId']?.toString(),
    );
  }

  final String title;
  final String artist;
  final String? album;
  final String? coverArtUrl;
  final String? coverArtHqUrl;
  final String? genre;
  final String? releaseDate;
  final String? label;
  final List<String> lyrics;
  final String? shazamUrl;
  final String? appleMusicUrl;
  final String? spotifyUrl;
  final String? youtubeVideoId;

  bool get isEmpty => title.trim().isEmpty;
  String get artwork {
    final hq = coverArtHqUrl?.trim() ?? '';
    if (hq.isNotEmpty) return hq;
    return coverArtUrl?.trim() ?? '';
  }

  String get searchQuery =>
      [title, artist].where((e) => e.trim().isNotEmpty).join(' ');
}

class _RecognitionHistoryItem {
  const _RecognitionHistoryItem({
    required this.id,
    required this.recognizedAt,
    required this.result,
  });

  factory _RecognitionHistoryItem.fromMap(Map<String, dynamic> map) =>
      _RecognitionHistoryItem(
        id: (map['id'] as num?)?.toInt() ?? 0,
        recognizedAt: (map['recognizedAt'] as num?)?.toInt() ?? 0,
        result: _RecognitionResult.fromMap(_asMap(map['result']) ?? const {}),
      );

  final int id;
  final int recognizedAt;
  final _RecognitionResult result;
}

class _ResolvedRecognitionTrack {
  const _ResolvedRecognitionTrack({
    required this.song,
    required this.matchLabel,
  });

  final _Song song;
  final String matchLabel;
}

class _RecognitionSheet extends StatelessWidget {
  const _RecognitionSheet({
    required this.stateListenable,
    required this.onOpenHistory,
    required this.resolvePreview,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onQueueNext,
    required this.onAddToQueue,
    required this.onOpenTrackActions,
    required this.onCancel,
    required this.onRetry,
    required this.onPlayNow,
    required this.onSearch,
  });

  final ValueListenable<_RecognitionUiState> stateListenable;
  final Future<void> Function() onOpenHistory;
  final Future<_ResolvedRecognitionTrack?> Function(_RecognitionResult result)
  resolvePreview;
  final Future<void> Function(_RecognitionResult result) onToggleLike;
  final Future<void> Function(_RecognitionResult result) onAddToPlaylist;
  final Future<void> Function(_RecognitionResult result) onQueueNext;
  final Future<void> Function(_RecognitionResult result) onAddToQueue;
  final Future<void> Function(_RecognitionResult result) onOpenTrackActions;
  final Future<void> Function() onCancel;
  final Future<void> Function() onRetry;
  final Future<void> Function(_RecognitionResult result) onPlayNow;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: _FoxyGlassButton(
          borderRadius: BorderRadius.circular(26),
          tintOpacity: 0.3,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: ValueListenableBuilder<_RecognitionUiState>(
              valueListenable: stateListenable,
              builder: (context, state, _) {
                final accent = Theme.of(context).colorScheme.primary;
                final result = state.result;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Recognize music',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Spacer(),
                        _GlassIconButton(
                          tooltip: 'History',
                          icon: Icons.history_rounded,
                          onPressed: () => unawaited(onOpenHistory()),
                        ),
                        const SizedBox(width: 6),
                        _GlassIconButton(
                          tooltip: 'Close',
                          icon: Icons.close_rounded,
                          onPressed: () => unawaited(onCancel()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          axisAlignment: -1,
                          child: child,
                        ),
                      ),
                      child: state.isListening || state.isProcessing
                          ? Center(
                              key: ValueKey('recognition-${state.state}'),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Column(
                                  children: [
                                    RepaintBoundary(
                                      child: _RecognitionListeningPulse(
                                        accent: accent,
                                        listening: state.isListening,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    Text(
                                      state.isListening
                                          ? 'Listening to the room...'
                                          : 'Matching that fingerprint...',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Keep Foxy open for a few seconds and let the track play clearly.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.66,
                                        ),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    FilledButton.icon(
                                      onPressed: () => unawaited(onCancel()),
                                      icon: const Icon(Icons.stop_rounded),
                                      label: const Text('Stop'),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : (state.isSuccess &&
                                result != null &&
                                !result.isEmpty)
                          ? Column(
                              key: const ValueKey('recognition-success'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Recognized this track',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.56),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                    ),
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.08),
                                        Colors.white.withValues(alpha: 0.03),
                                      ],
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        RepaintBoundary(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            child: _Artwork(
                                              url: result.artwork,
                                              size: 108,
                                              radius: 20,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                result.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w900,
                                                  height: 1.05,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                result.artist.ifBlank(
                                                  'Unknown artist',
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.76),
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if ((result.album ?? '')
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  result.album!,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.52,
                                                        ),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 12),
                                              Wrap(
                                                spacing: 8,
                                                runSpacing: 8,
                                                children: [
                                                  FutureBuilder<
                                                    _ResolvedRecognitionTrack?
                                                  >(
                                                    future: resolvePreview(
                                                      result,
                                                    ),
                                                    builder: (context, snapshot) {
                                                      final matchLabel =
                                                          snapshot
                                                              .data
                                                              ?.matchLabel;
                                                      if (matchLabel == null ||
                                                          matchLabel.isEmpty) {
                                                        return const SizedBox.shrink();
                                                      }
                                                      return _RecognitionPill(
                                                        label: matchLabel,
                                                      );
                                                    },
                                                  ),
                                                  if ((result.genre ?? '')
                                                      .isNotEmpty)
                                                    _RecognitionPill(
                                                      label: result.genre!,
                                                    ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if ((result.releaseDate ?? '').isNotEmpty)
                                      _RecognitionPill(
                                        label: result.releaseDate!,
                                      ),
                                    if ((result.label ?? '').isNotEmpty)
                                      _RecognitionPill(label: result.label!),
                                  ],
                                ),
                                if (result.lyrics.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      color: Colors.white.withValues(
                                        alpha: 0.04,
                                      ),
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.05,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      result.lyrics.take(3).join('\n'),
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.8,
                                        ),
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () =>
                                            unawaited(onPlayNow(result)),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: const Text('Play now'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            onSearch(result.searchQuery),
                                        icon: const Icon(Icons.search_rounded),
                                        label: const Text('Find in Foxy'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            unawaited(onQueueNext(result)),
                                        icon: const Icon(
                                          Icons.queue_play_next_rounded,
                                        ),
                                        label: const Text('Next'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            unawaited(onAddToQueue(result)),
                                        icon: const Icon(
                                          Icons.queue_music_rounded,
                                        ),
                                        label: const Text('Queue'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            unawaited(onToggleLike(result)),
                                        icon: const Icon(
                                          Icons.favorite_border_rounded,
                                        ),
                                        label: const Text('Like'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            unawaited(onAddToPlaylist(result)),
                                        icon: const Icon(
                                          Icons.playlist_add_rounded,
                                        ),
                                        label: const Text('Playlist'),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => unawaited(
                                          onOpenTrackActions(result),
                                        ),
                                        icon: const Icon(
                                          Icons.more_horiz_rounded,
                                        ),
                                        label: const Text('More'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: () => unawaited(onRetry()),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Listen again'),
                                ),
                              ],
                            )
                          : Center(
                              key: ValueKey(
                                'recognition-${state.state}-fallback',
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 18,
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      state.state == 'noMatch'
                                          ? Icons.music_off_rounded
                                          : Icons.error_outline_rounded,
                                      color: Colors.white.withValues(
                                        alpha: 0.86,
                                      ),
                                      size: 34,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      state.message?.ifBlank(
                                            state.state == 'noMatch'
                                                ? 'No match found'
                                                : 'Recognition failed',
                                          ) ??
                                          (state.state == 'noMatch'
                                              ? 'No match found'
                                              : 'Recognition failed'),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Try again with the music louder and background noise lower.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.64,
                                        ),
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      onPressed: () => unawaited(onRetry()),
                                      icon: const Icon(Icons.mic_rounded),
                                      label: const Text('Listen again'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RecognitionHistorySheet extends StatelessWidget {
  const _RecognitionHistorySheet({
    required this.items,
    required this.onClear,
    required this.resolvePreview,
    required this.onToggleLike,
    required this.onAddToPlaylist,
    required this.onQueueNext,
    required this.onAddToQueue,
    required this.onOpenTrackActions,
    required this.onPlay,
    required this.onSearch,
  });

  final List<_RecognitionHistoryItem> items;
  final Future<void> Function() onClear;
  final Future<_ResolvedRecognitionTrack?> Function(_RecognitionResult result)
  resolvePreview;
  final Future<void> Function(_RecognitionResult result) onToggleLike;
  final Future<void> Function(_RecognitionResult result) onAddToPlaylist;
  final Future<void> Function(_RecognitionResult result) onQueueNext;
  final Future<void> Function(_RecognitionResult result) onAddToQueue;
  final Future<void> Function(_RecognitionResult result) onOpenTrackActions;
  final Future<void> Function(_RecognitionResult result) onPlay;
  final ValueChanged<_RecognitionResult> onSearch;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        child: _FoxyGlassButton(
          borderRadius: BorderRadius.circular(26),
          tintOpacity: 0.3,
          onTap: () {},
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recognition history',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            items.isEmpty
                                ? 'Your recent matches will land here.'
                                : '${items.length} recent match${items.length == 1 ? '' : 'es'}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.56),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (items.isNotEmpty)
                      _GlassIconButton(
                        tooltip: 'Clear history',
                        icon: Icons.delete_outline_rounded,
                        onPressed: () => unawaited(onClear()),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Nothing recognized yet.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                    ),
                    child: RepaintBoundary(
                      child: ListView.separated(
                        shrinkWrap: true,
                        cacheExtent: 320,
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final result = item.result;
                          return _FoxyGlassButton(
                            onTap: () => onSearch(result),
                            borderRadius: BorderRadius.circular(18),
                            tintOpacity: 0.22,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: _Artwork(
                                          url: result.artwork,
                                          size: 58,
                                          radius: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              result.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              result.artist.ifBlank(
                                                'Unknown artist',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.66,
                                                ),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            FutureBuilder<
                                              _ResolvedRecognitionTrack?
                                            >(
                                              future: resolvePreview(result),
                                              builder: (context, snapshot) {
                                                final pieces = <String>[
                                                  _formatRecognitionTime(
                                                    item.recognizedAt,
                                                  ),
                                                ];
                                                final matchLabel =
                                                    snapshot.data?.matchLabel;
                                                if (matchLabel != null &&
                                                    matchLabel.isNotEmpty) {
                                                  pieces.add(matchLabel);
                                                }
                                                return Text(
                                                  pieces.join('  â€¢  '),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.46,
                                                        ),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _RecognitionHistoryIconButton(
                                        icon: Icons.play_arrow_rounded,
                                        onPressed: () =>
                                            unawaited(onPlay(result)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _RecognitionActionChip(
                                        icon: Icons.queue_play_next_rounded,
                                        label: 'Next',
                                        onPressed: () =>
                                            unawaited(onQueueNext(result)),
                                      ),
                                      _RecognitionActionChip(
                                        icon: Icons.queue_music_rounded,
                                        label: 'Queue',
                                        onPressed: () =>
                                            unawaited(onAddToQueue(result)),
                                      ),
                                      _RecognitionActionChip(
                                        icon: Icons.playlist_add_rounded,
                                        label: 'Playlist',
                                        onPressed: () =>
                                            unawaited(onAddToPlaylist(result)),
                                      ),
                                      _RecognitionActionChip(
                                        icon: Icons.favorite_border_rounded,
                                        label: 'Like',
                                        onPressed: () =>
                                            unawaited(onToggleLike(result)),
                                      ),
                                      _RecognitionActionChip(
                                        icon: Icons.search_rounded,
                                        label: 'Search',
                                        onPressed: () => onSearch(result),
                                      ),
                                      _RecognitionActionChip(
                                        icon: Icons.more_horiz_rounded,
                                        label: 'More',
                                        onPressed: () => unawaited(
                                          onOpenTrackActions(result),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatRecognitionTime(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  final sameDay =
      dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final hour24 = dt.hour;
  final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
  final minute = dt.minute.toString().padLeft(2, '0');
  final suffix = hour24 >= 12 ? 'PM' : 'AM';
  if (sameDay) return '$hour12:$minute $suffix';
  return '${dt.day}/${dt.month} $hour12:$minute $suffix';
}

class _RecognitionListeningPulse extends StatelessWidget {
  const _RecognitionListeningPulse({
    required this.accent,
    required this.listening,
  });

  final Color accent;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.96, end: listening ? 1.08 : 1.02),
      duration: Duration(milliseconds: listening ? 900 : 1200),
      curve: Curves.easeInOut,
      builder: (context, scale, _) {
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.14),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: listening ? 0.18 : 0.1),
                        blurRadius: listening ? 22 : 14,
                        spreadRadius: listening ? 1.5 : 0.5,
                      ),
                    ],
                  ),
                ),
                Icon(
                  listening ? Icons.mic_rounded : Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecognitionHistoryIconButton extends StatelessWidget {
  const _RecognitionHistoryIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      splashRadius: 16,
      iconSize: 18,
      icon: Icon(icon),
    );
  }
}

class _RecognitionActionChip extends StatelessWidget {
  const _RecognitionActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white.withValues(alpha: 0.86),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icon, size: 16),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _RecognitionPill extends StatelessWidget {
  const _RecognitionPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SongSection {
  const _SongSection({
    required this.title,
    required this.songs,
    this.layout = 'cards',
  });

  factory _SongSection.fromMap(Map<String, dynamic> map) => _SongSection(
    title: map['title']?.toString() ?? 'For you',
    layout: map['layout']?.toString() ?? 'cards',
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList(),
  );

  final String title;
  final String layout;
  final List<_Song> songs;
}

class _Song {
  const _Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artwork,
    this.album,
    this.duration,
    this.isDownloaded = false,
    this.localPath,
    this.offlineArtworkPath,
  });

  factory _Song.fromMap(Map<String, dynamic> map) {
    final artwork = [map['artworkUrl'], map['thumbnail']]
        .map((value) => value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final lp = map['localPath']?.toString();
    final oap = map['offlineArtworkPath']?.toString();
    return _Song(
      videoId: map['videoId']?.toString() ?? '',
      title: map['title']?.toString().ifBlank('Untitled') ?? 'Untitled',
      artist:
          map['artist']?.toString().ifBlank('Unknown artist') ??
          'Unknown artist',
      artwork: artwork,
      album: map['album']?.toString().ifBlank('') ?? '',
      duration: map['duration']?.toString(),
      isDownloaded: map['isDownloaded'] == true,
      localPath: (lp != null && lp.isNotEmpty) ? lp : null,
      offlineArtworkPath: (oap != null && oap.isNotEmpty) ? oap : null,
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final String artwork;
  final String? album;
  final String? duration;
  final bool isDownloaded;
  final String? localPath;
  final String? offlineArtworkPath;

  String get highQualityArtwork => _upgradeYouTubeArtworkUrl(artwork, videoId);

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': artwork,
    'artworkUrl': artwork,
    'isDownloaded': isDownloaded,
    if (album != null && album!.isNotEmpty) 'album': album,
    if (duration != null) 'duration': duration,
    if (localPath != null && localPath!.isNotEmpty) 'localPath': localPath,
    if (offlineArtworkPath != null && offlineArtworkPath!.isNotEmpty)
      'offlineArtworkPath': offlineArtworkPath,
  };
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, dynamic item) => MapEntry(key.toString(), _normalize(item)),
    );
  }
  return null;
}

/// Fresh maps for [currentSong] / [queue] so the mini player always reflects the latest track.
Map<String, dynamic> _detachPlayerState(Map<String, dynamic> state) {
  final out = Map<String, dynamic>.from(state);
  final cs = state['currentSong'];
  if (cs is Map) {
    final m = _asMap(cs);
    if (m != null) out['currentSong'] = Map<String, dynamic>.from(m);
  }
  final q = state['queue'];
  if (q is List) {
    out['queue'] = q.map((dynamic e) {
      final m = _asMap(e);
      return m != null ? Map<String, dynamic>.from(m) : e;
    }).toList();
  }
  return out;
}

Map<String, dynamic> _mergePlayerState(
  Map<String, dynamic> previous,
  Map<String, dynamic> incoming,
) {
  final next = _detachPlayerState(incoming);
  if (next['queue'] == null && previous['queue'] != null) {
    next['queue'] = previous['queue'];
  }
  return next;
}

String _queueSignature(dynamic queue) {
  if (queue is! List) return '';
  return queue
      .map((dynamic item) => _asMap(item)?['videoId']?.toString() ?? '')
      .join('|');
}

String _playerVisualSignature(Map<String, dynamic> player) {
  final song = _asMap(player['currentSong']) ?? const {};
  return [
    song['videoId']?.toString() ?? '',
    song['title']?.toString() ?? '',
    song['artist']?.toString() ?? '',
    _songArtworkKey(song),
    player['songIsLiked'] == true ? '1' : '0',
    player['streamBitrate']?.toString() ?? '',
    player['streamCodec']?.toString() ?? '',
    player['streamSampleRate']?.toString() ?? '',
    player['streamItag']?.toString() ?? '',
    player['streamSource']?.toString() ?? '',
    player['streamQualityLabel']?.toString() ?? '',
    player['playerBackgroundStyle']?.toString() ?? '',
    player['playerStyle']?.toString() ?? '',
    player['playerButtonsStyle']?.toString() ?? '',
    player['playerArtworkShape']?.toString() ?? '',
    player['lyricsPreferLrclib']?.toString() ?? '',
    player['lyricsRomanize']?.toString() ?? '',
  ].join('|');
}

String _songArtworkKey(Map<String, dynamic> song) {
  return [
    song['artwork']?.toString() ?? '',
    song['artworkUrl']?.toString() ?? '',
    song['thumbnail']?.toString() ?? '',
    song['offlineArtworkPath']?.toString() ?? '',
  ].join('|');
}

dynamic _normalize(dynamic value) {
  if (value is Map) return _asMap(value);
  if (value is List) return value.map(_normalize).toList();
  return value;
}

String _upgradeYouTubeArtworkUrl(String url, String videoId) {
  var u = url.trim();
  if (u.isEmpty && videoId.isNotEmpty) {
    return 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';
  }
  if (u.isEmpty) return u;
  u = u
      .replaceAll('=s88-', '=s800-')
      .replaceAll('=s120-', '=s800-')
      .replaceAll('=s180-', '=s800-')
      .replaceAll('=s360-', '=s800-')
      .replaceAll('=w88-h88', '=w800-h800')
      .replaceAll('=w120-h120', '=w800-h800')
      .replaceAll('=w360-h360', '=w800-h800');
  u = u.replaceAll(
    RegExp(r'/(hqdefault|mqdefault|default)\.jpg'),
    '/maxresdefault.jpg',
  );
  return u;
}

List<String> _backdropArtworkCandidates(String url, String videoId) {
  final upgraded = _upgradeYouTubeArtworkUrl(url, videoId);
  final candidates = <String>[
    if (videoId.isNotEmpty)
      'https://i.ytimg.com/vi_webp/$videoId/maxresdefault.webp',
    if (videoId.isNotEmpty) 'https://i.ytimg.com/vi/$videoId/maxresdefault.jpg',
    if (videoId.isNotEmpty) 'https://i.ytimg.com/vi/$videoId/sddefault.jpg',
    if (videoId.isNotEmpty)
      'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
    if (videoId.isNotEmpty) 'https://img.youtube.com/vi/$videoId/sddefault.jpg',
    if (upgraded.isNotEmpty) upgraded,
    if (url.trim().isNotEmpty) url.trim(),
  ];
  return candidates.toSet().toList();
}

String _fmt(int ms) {
  final total = (ms ~/ 1000).clamp(0, 999999);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

String _streamQualityLabel(Map<String, dynamic> player) {
  final qualityLabel = player['streamQualityLabel']?.toString() ?? '';
  final codec = player['streamCodec']?.toString() ?? '';
  final source = player['streamSource']?.toString() ?? '';
  final bitrate = ((player['streamBitrate'] ?? 0) as num).toInt();
  final sampleRate = ((player['streamSampleRate'] ?? 0) as num).toInt();
  final itag = ((player['streamItag'] ?? 0) as num).toInt();
  final parts = <String>[];
  final actualTier = _actualStreamTierLabel(
    codec: codec,
    qualityLabel: qualityLabel,
    bitrate: bitrate,
  );
  if (actualTier.isNotEmpty) parts.add(actualTier);
  if (qualityLabel.isNotEmpty) {
    parts.add(qualityLabel);
  } else if (codec.isNotEmpty) {
    parts.add(codec);
  }
  if (bitrate > 0) parts.add('${(bitrate / 1000).round()} kbps');
  if (sampleRate > 0) {
    parts.add('${(sampleRate / 1000).toStringAsFixed(1)} kHz');
  }
  if (itag > 0) parts.add('itag $itag');
  if (source.isNotEmpty) parts.add(source);
  return parts.join(' | ');
}

String _actualStreamTierLabel({
  required String codec,
  required String qualityLabel,
  required int bitrate,
}) {
  final blob = '$codec $qualityLabel'.toLowerCase();
  final isLossless =
      blob.contains('flac') ||
      blob.contains('alac') ||
      blob.contains('wav') ||
      blob.contains('pcm') ||
      blob.contains('lossless');
  if (isLossless) return 'Lossless';
  if (bitrate >= 320000) return 'Ultra';
  if (bitrate >= 250000) return 'High';
  if (bitrate >= 128000) return 'Normal';
  if (bitrate >= 96000) return 'Balanced';
  if (bitrate > 0) return 'Low';
  return '';
}

extension on String {
  bool get isBlank => trim().isEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
