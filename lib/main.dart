import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'dart:ui' as ui;
import 'dart:io' show File, HttpClient;

import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb, mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'foxy_startup_splash.dart';

part 'player_now_playing.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');
final Stream<dynamic> _foxyEvents = _events
    .receiveBroadcastStream()
    .asBroadcastStream();

typedef _FoxyOnPlay =
    Future<void> Function(_Song song, List<_Song> queue, {bool radioTail});

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;

/// Vertical gap between home feed shelves (spotlight, rails, song rows).
const double _kHomeShelfGap = 28.0;

/// Space between a shelf title and its content.
const double _kHomeShelfTitleGap = 14.0;

String _kAppVersionLabel = 'v1.3';
String _kAppVersionName = '1.3';
const String _kGitHubProjectUrl = 'https://github.com/sparkn2008-del/FoxyMusic';
const String _kRemoteConfigUrl =
    'https://raw.githubusercontent.com/sparkn2008-del/FoxyMusic/main/foxy_remote_config.json';
const String _kAboutCreditLine =
    'Made in shape by Foxy-Nish aka "sparkn2008-del"';
const String _kFoxyLogoAsset = 'assets/images/app_art.png';

/// Metrolist-style now playing foreground (backdrop stays full-bleed [_BlurBackdrop]).
const Color _kMetrolistNpTime = Color(0xFF9E9E9E);

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xCC000000),
    Color.lerp(const Color.fromARGB(139, 192, 16, 16), accent, 0.28)!,
  );
}

bool _effectivePlayerBuffering(Map<String, dynamic> player) {
  return player['isBuffering'] == true && player['isPlaying'] != true;
}

class _FoxyRemoteConfig {
  const _FoxyRemoteConfig({
    this.version = 1,
    this.enabled = true,
    this.homeSignedInHeroMode = 'quickPicks',
    this.homeSectionOrder = const <String>[
      'quickPicks',
      'newReleases',
      'artists',
      'categories',
    ],
    this.homeMaxGridItems = 6,
    this.homeCardScale = 1.0,
    this.homeGradientStrength = 0.95,
    this.enableSoundCloudSearch = true,
    this.enableVideoBackground = true,
    this.thumbnailSize = 480,
    this.searchTimeoutMs = 2600,
    this.fetchedAtMs = 0,
  });

  factory _FoxyRemoteConfig.fromJsonLike(
    Map<String, dynamic> map, {
    _FoxyRemoteConfig fallback = const _FoxyRemoteConfig(),
    int fetchedAtMs = 0,
  }) {
    final home = _asMap(map['home']) ?? const <String, dynamic>{};
    final features = _asMap(map['features']) ?? const <String, dynamic>{};
    final search = _asMap(map['search']) ?? const <String, dynamic>{};
    final media = _asMap(map['media']) ?? const <String, dynamic>{};
    List<String> stringList(dynamic raw, List<String> old) {
      if (raw is! List) return old;
      final values = raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      return values.isEmpty ? old : values;
    }

    double doubleValue(dynamic raw, double old, double min, double max) {
      final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
      if (n == null || !n.isFinite) return old;
      return n.clamp(min, max).toDouble();
    }

    int intValue(dynamic raw, int old, int min, int max) {
      final n = raw is num ? raw.toInt() : int.tryParse('$raw');
      if (n == null) return old;
      return n.clamp(min, max).toInt();
    }

    bool boolValue(dynamic raw, bool old) => raw is bool ? raw : old;

    return _FoxyRemoteConfig(
      version: intValue(map['version'], fallback.version, 1, 999999),
      enabled: boolValue(map['enabled'], fallback.enabled),
      homeSignedInHeroMode:
          home['signedInHeroMode']?.toString().trim().ifBlank(
            fallback.homeSignedInHeroMode,
          ) ??
          fallback.homeSignedInHeroMode,
      homeSectionOrder: stringList(
        home['sectionOrder'],
        fallback.homeSectionOrder,
      ),
      homeMaxGridItems: intValue(
        home['maxGridItems'],
        fallback.homeMaxGridItems,
        2,
        12,
      ),
      homeCardScale: doubleValue(
        home['cardScale'],
        fallback.homeCardScale,
        0.8,
        1.25,
      ),
      homeGradientStrength: doubleValue(
        home['gradientStrength'],
        fallback.homeGradientStrength,
        0.45,
        1.2,
      ),
      enableSoundCloudSearch: boolValue(
        features['soundCloudSearch'],
        fallback.enableSoundCloudSearch,
      ),
      enableVideoBackground: boolValue(
        features['videoBackground'],
        fallback.enableVideoBackground,
      ),
      thumbnailSize: intValue(
        media['thumbnailSize'],
        fallback.thumbnailSize,
        240,
        720,
      ),
      searchTimeoutMs: intValue(
        search['timeoutMs'],
        fallback.searchTimeoutMs,
        800,
        6000,
      ),
      fetchedAtMs: fetchedAtMs == 0 ? fallback.fetchedAtMs : fetchedAtMs,
    );
  }

  final int version;
  final bool enabled;
  final String homeSignedInHeroMode;
  final List<String> homeSectionOrder;
  final int homeMaxGridItems;
  final double homeCardScale;
  final double homeGradientStrength;
  final bool enableSoundCloudSearch;
  final bool enableVideoBackground;
  final int thumbnailSize;
  final int searchTimeoutMs;
  final int fetchedAtMs;

  Map<String, dynamic> toJson() => {
    'version': version,
    'enabled': enabled,
    'home': {
      'signedInHeroMode': homeSignedInHeroMode,
      'sectionOrder': homeSectionOrder,
      'maxGridItems': homeMaxGridItems,
      'cardScale': homeCardScale,
      'gradientStrength': homeGradientStrength,
    },
    'features': {
      'soundCloudSearch': enableSoundCloudSearch,
      'videoBackground': enableVideoBackground,
    },
    'media': {'thumbnailSize': thumbnailSize},
    'search': {'timeoutMs': searchTimeoutMs},
  };
}

class _FoxyRemoteConfigController {
  static Future<_FoxyRemoteConfig> loadAndRefresh({
    ValueChanged<_FoxyRemoteConfig>? onRemote,
  }) async {
    final cached = await _loadCached();
    unawaited(_refresh(onRemote: onRemote));
    return cached;
  }

  static Future<_FoxyRemoteConfig> forceRefresh() =>
      _refresh(onRemote: null, force: true);

  static Future<_FoxyRemoteConfig> _loadCached() async {
    final raw = _asMap(await _method.invokeMethod('getRemoteConfigCache'));
    final cachedJson = raw?['cachedJson']?.toString() ?? '';
    final overrideJson = raw?['overrideJson']?.toString() ?? '';
    final fetchedAt = ((raw?['fetchedAtMs'] ?? 0) as num).toInt();
    var config = const _FoxyRemoteConfig();
    if (cachedJson.isNotEmpty) {
      config = _decodeConfig(cachedJson, config, fetchedAt);
    }
    if (overrideJson.isNotEmpty) {
      config = _decodeConfig(overrideJson, config, fetchedAt);
    }
    return config;
  }

  static Future<_FoxyRemoteConfig> _refresh({
    ValueChanged<_FoxyRemoteConfig>? onRemote,
    bool force = false,
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(_kRemoteConfigUrl));
      request.headers.set('cache-control', force ? 'no-cache' : 'max-age=300');
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        client.close(force: true);
        return _loadCached();
      }
      final body = await utf8.decoder.bind(response).join();
      client.close(force: true);
      final config = _decodeConfig(
        body,
        const _FoxyRemoteConfig(),
        DateTime.now().millisecondsSinceEpoch,
      );
      await _method.invokeMethod('setRemoteConfigCache', {
        'cachedJson': jsonEncode(config.toJson()),
        'fetchedAtMs': config.fetchedAtMs,
      });
      onRemote?.call(config);
      return config;
    } catch (_) {
      return _loadCached();
    }
  }

  static _FoxyRemoteConfig _decodeConfig(
    String raw,
    _FoxyRemoteConfig fallback,
    int fetchedAtMs,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return fallback;
      return _FoxyRemoteConfig.fromJsonLike(
        decoded.cast<String, dynamic>(),
        fallback: fallback,
        fetchedAtMs: fetchedAtMs,
      );
    } catch (_) {
      return fallback;
    }
  }
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 900;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const FoxyAppLaunchGate(child: FoxyFlutterApp()));
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
  _FoxyRemoteConfig _remoteConfig = const _FoxyRemoteConfig();
  bool _dynamicSongColors = true;
  int? _songAccentArgb;
  int _paletteEpoch = 0;
  String _lastPlayerVideoId = '';
  StreamSubscription<dynamic>? _rootEventSub;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    unawaited(_loadRemoteConfig());
    unawaited(_loadAppVersion());
    _rootEventSub = _foxyEvents.listen((dynamic event) {
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
          final shouldUpdateShell =
              nextDynamic != _dynamicSongColors ||
              accentChanged ||
              epochChanged ||
              videoChanged;
          if (shouldUpdateShell) {
            setState(() {
              _dynamicSongColors = nextDynamic;
              _songAccentArgb = nextAccent;
              _paletteEpoch = nextEpoch;
              _lastPlayerVideoId = vid;
            });
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
      setState(() {
        _dynamicSongColors = map['dynamicSongColors'] != false;
        final a = map['songAccentArgb'];
        _songAccentArgb = a is num ? a.toInt() : null;
        if (pe is num) {
          _paletteEpoch = pe.toInt();
        }
        final cs = _asMap(map['currentSong']);
        _lastPlayerVideoId = cs?['videoId']?.toString() ?? '';
      });
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
          final bgEnabled = map['homeBackgroundEnabled'] == true;
          _homeBackgroundPath = bgEnabled && bg != null && bg.isNotEmpty
              ? bg
              : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadRemoteConfig({bool force = false}) async {
    try {
      final config = force
          ? await _FoxyRemoteConfigController.forceRefresh()
          : await _FoxyRemoteConfigController.loadAndRefresh(
              onRemote: (config) {
                if (mounted) setState(() => _remoteConfig = config);
              },
            );
      if (mounted) setState(() => _remoteConfig = config);
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
    if (_dynamicSongColors && _songAccentArgb != null) {
      return Color(_songAccentArgb! & 0xFFFFFFFF);
    }
    return _appearance.accent;
  }

  @override
  @override
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
      home: _FoxyHomeShell(
        homeBackgroundPath: _homeBackgroundPath,
        remoteConfig: _remoteConfig,
        onRemoteConfigChanged: (config) {
          if (mounted) setState(() => _remoteConfig = config);
        },
      ),
    );
  }
}

class _FlutterAppearance {
  const _FlutterAppearance({
    this.accent = const Color(0xFFFF2D55),
    this.background = _kTrueBlack,
    this.surface = _kTrueBlack,
    this.surfaceHigh = const Color(0xFF121212),
    this.muted = const Color(0xFFB0B0B0),
  });

  factory _FlutterAppearance.fromMap(Map<String, dynamic> map) =>
      _FlutterAppearance(
        accent: _argbToColor(map['accentArgb']) ?? const Color(0xFFFF2D55),
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

String _cleanDisplayText(dynamic value, {String fallback = ''}) {
  var text = value?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  const replacements = <String, String>{
    'Ã‚Â·': ' - ',
    'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¢': ' - ',
    'Ãƒâ€šÃ‚Â¢': ' - ',
    'ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â': ' - ',
    'Ãƒâ€šÃ‚Â': '"',
    'Ãƒâ€¦Ã¢â‚¬Å“': '"',
    'Ãƒâ€šÃ‚Â¦': '...',
    'Ã¢â‚¬Â¦': '...',
    'Ã¢â‚¬Â¢': ' - ',
    'Ã¢â‚¬â€œ': ' - ',
    'Ã¢â‚¬â€': ' - ',
    'Ã¢â‚¬Å“': '"',
    'Ã¢â‚¬Â': '"',
    'Ã¢â‚¬Ëœ': "'",
    'Ã¢â‚¬â„¢': "'",
    'Ã¢â€šÂ¬': '',
    'Ã‚': '',
    'Â·': ' - ',
  };
  for (final entry in replacements.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  text = text
      .replaceAll(RegExp(r'Ã\S*'), '')
      .replaceAll(RegExp(r'[\uFFFD]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return text.isEmpty ? fallback : text;
}

String _primaryArtistNameForLookup(String value) {
  final cleaned = value.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ').trim();
  final parts = cleaned.split(
    RegExp(
      r'\s*(?:,|&|/|\+|\bx\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b)\s*',
      caseSensitive: false,
    ),
  );
  return parts
      .firstWhere((part) => part.trim().isNotEmpty, orElse: () => value)
      .trim();
}

String _normalizeArtistLookupKey(String value) =>
    _primaryArtistNameForLookup(value)
        .toLowerCase()
        .replaceAll(RegExp(r'\b(official|topic|vevo|artist|channel)\b'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

int _normalizePlayerProgressStyle(int raw) {
  return 0;
}

int _normalizePlayerBackgroundStyle(int raw) {
  final value = raw.clamp(0, 3);
  if (value == 1 || value == 2 || value == 3) return value;
  return 0;
}

/// Warm fox-fur tones from the FoxyMusic logo (amber, deep orange, cream).
class _FoxyBrandPalette {
  static const foxAmber = Color(0xFFFF9A3C);
  static const foxDeep = Color(0xFFE85D04);
  static const foxCream = Color(0xFFFFD9B0);
  static const foxEmber = Color(0xFFFF1744);
}

enum _FoxyGradientVariant { home, player }

/// Large soft blooms: fox logo warmth + dynamic song accent.
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
    // Foxy-style: dark base with one soft accent bloom (player is subtler than home).
    final topH = strong ? 440.0 : 460.0;
    final bottomH = strong ? 320.0 : 340.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF000000),
                Color.lerp(
                  const Color(0xFF1A0E08),
                  const Color(0xFF0A0A0A),
                  0.5,
                )!,
                Color.lerp(const Color(0xFF120808), surface, 0.55)!,
              ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          left: -100,
          right: -100,
          height: topH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.15, -0.2),
                  radius: 1.35,
                  colors: [
                    Color.lerp(
                      _FoxyBrandPalette.foxCream,
                      accent,
                      0.35,
                    )!.withValues(alpha: strong ? 0.22 : 0.34),
                    _FoxyBrandPalette.foxAmber.withValues(
                      alpha: strong ? 0.14 : 0.22,
                    ),
                    _FoxyBrandPalette.foxDeep.withValues(
                      alpha: strong ? 0.06 : 0.1,
                    ),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.35, 0.62, 1.0],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 40,
          right: -90,
          left: 120,
          height: topH * 0.85,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.2,
                  colors: [
                    _FoxyBrandPalette.foxEmber.withValues(
                      alpha: strong ? 0.1 : 0.18,
                    ),
                    accent.withValues(alpha: strong ? 0.08 : 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -140,
          left: -110,
          right: -110,
          height: bottomH,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.bottomCenter,
                  radius: 1.25,
                  colors: [
                    _FoxyBrandPalette.foxDeep.withValues(
                      alpha: strong ? 0.14 : 0.16,
                    ),
                    accent.withValues(alpha: strong ? 0.06 : 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
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
          errorBuilder: (_, _, _) => Icon(
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
  const _FoxyHomeBackdrop({
    required this.child,
    this.customPath,
    this.adaptiveAccentSong,
    this.showAdaptiveAccent = false,
  });

  final Widget child;
  final String? customPath;
  final _Song? adaptiveAccentSong;
  final bool showAdaptiveAccent;

  @override
  Widget build(BuildContext context) {
    final hasCustom =
        customPath != null &&
        customPath!.isNotEmpty &&
        !kIsWeb &&
        File(customPath!).existsSync();
    Widget bg = const ColoredBox(color: Color(0xFF000000));
    if (hasCustom) {
      bg = Image.file(
        File(customPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        bg,
        if (!hasCustom && showAdaptiveAccent && adaptiveAccentSong != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _HomeAdaptiveSectionGradient(song: adaptiveAccentSong!),
            ),
          ),
        if (hasCustom)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.22),
                  Colors.black.withValues(alpha: 0.42),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// Translucent surface ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â does **not** blur the wallpaper (cards, bars, sheets).
class _FoxyGlassTint extends StatelessWidget {
  const _FoxyGlassTint({
    required this.child,
    this.borderRadius = 0,
    this.tintOpacity = 0.28,
    this.borderOpacity = 0.1,
    this.showBottomBorder = false,
  });

  final Widget child;
  final double borderRadius;
  final double tintOpacity;
  final double borderOpacity;
  final bool showBottomBorder;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius > 0
        ? BorderRadius.circular(borderRadius)
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: tintOpacity),
        borderRadius: radius,
        border: showBottomBorder
            ? Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: borderOpacity),
                ),
              )
            : Border.all(color: Colors.white.withValues(alpha: borderOpacity)),
      ),
      child: child,
    );
  }
}

/// Glass control surface. Foxy-style: scrolling lists use [blur] off (tint
/// only) so wallpaper is not re-sampled every frame; fixed chrome may use blur.
class _FoxyGlassButton extends StatelessWidget {
  const _FoxyGlassButton({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.tintOpacity = 0.34,
    this.blurSigma = 10,
    this.selected = false,
    this.padding = EdgeInsets.zero,
    this.blur = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final double tintOpacity;
  final double blurSigma;
  final bool selected;
  final EdgeInsetsGeometry padding;

  /// Live [BackdropFilter] ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â only for small fixed chrome (nav, header icons).
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
    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: borderRadius,
        border: Border.all(
          color: Colors.white.withValues(
            alpha: selected ? 0.28 : (blur ? 0.16 : 0.14),
          ),
        ),
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

/// Text action styled as frosted glass (Play all, Retry, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦).
const ScrollPhysics _kFoxyHorizontalScrollPhysics = BouncingScrollPhysics();
const ScrollPhysics _kFoxyPlayerSheetPhysics = ClampingScrollPhysics(
  parent: AlwaysScrollableScrollPhysics(),
);

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

class _FoxyLiquidChromeShell extends StatelessWidget {
  const _FoxyLiquidChromeShell({
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.clear = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool clear;

  @override
  Widget build(BuildContext context) {
    final gradientColors = clear
        ? [
            Colors.white.withValues(alpha: 0.0032),
            Colors.white.withValues(alpha: 0.0008),
            Colors.transparent,
          ]
        : [
            Colors.white.withValues(alpha: 0.08),
            Colors.black.withValues(alpha: 0.18),
            Colors.black.withValues(alpha: 0.32),
          ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        blendMode: BlendMode.src,
        filter: ImageFilter.blur(
          sigmaX: clear ? 8 : 28,
          sigmaY: clear ? 8 : 28,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
              stops: const [0, 0.18, 1],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: clear ? 0.2 : 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: clear ? 0.012 : 0.32),
                blurRadius: clear ? 3 : 24,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: clear ? 0.011 : 0.035),
                blurRadius: clear ? 5 : 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Stack(
            children: [
              if (clear) ...[
                Positioned(
                  left: -18,
                  top: -10,
                  child: IgnorePointer(
                    child: Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.021),
                            Colors.white.withValues(alpha: 0.004),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.34, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 22,
                  bottom: -16,
                  child: IgnorePointer(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.014),
                            Colors.white.withValues(alpha: 0.0032),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.28, 1],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: const Alignment(-0.95, -0.25),
                          end: const Alignment(0.65, 0.45),
                          colors: [
                            Colors.transparent,
                            Colors.white.withValues(alpha: 0.0072),
                            Colors.transparent,
                          ],
                          stops: const [0.12, 0.38, 0.72],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              Positioned(
                left: 14,
                right: 14,
                top: 0,
                child: Container(
                  height: 1.2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: clear ? 0.14 : 0.24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoxyTintedChromeShell extends StatelessWidget {
  const _FoxyTintedChromeShell({
    required this.child,
    required this.radius,
    this.padding = EdgeInsets.zero,
    this.tintAlpha = 0.07,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double tintAlpha;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        blendMode: BlendMode.src,
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.012),
                Colors.black.withValues(alpha: tintAlpha),
                Colors.black.withValues(alpha: tintAlpha * 0.82),
              ],
              stops: const [0, 0.26, 1],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 14,
                right: 14,
                top: 0,
                child: Container(
                  height: 1.1,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Padding(padding: padding, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

_HomeSectionLayout _homeSectionLayout(_SongSection section) {
  final t = section.title.toLowerCase();
  if (t.contains('quick pick')) return _HomeSectionLayout.cards;
  if (t.contains('release')) return _HomeSectionLayout.grid;
  if (t.contains('chart') || t.contains('trending')) {
    return _HomeSectionLayout.chart;
  }
  if (t.contains('resume') ||
      t.contains('replayed') ||
      t.contains('downloaded')) {
    return _HomeSectionLayout.square;
  }
  if (t.contains('today on foxy') ||
      t.contains('india pulse') ||
      t.contains('hidden gem')) {
    return _HomeSectionLayout.square;
  }
  switch (section.layout) {
    case 'square':
      return _HomeSectionLayout.square;
    case 'radio':
      return _HomeSectionLayout.radio;
    case 'mixes':
      return _HomeSectionLayout.mixes;
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
      if (t.contains('replayed') ||
          t.contains('radio') ||
          t.contains('starter')) {
        return _HomeSectionLayout.square;
      }
      if (t.contains('mix')) return _HomeSectionLayout.mixes;
      if (t.contains('chart') || t.contains('trending')) {
        return _HomeSectionLayout.chart;
      }
      if (t.contains('artist') || t.contains('similar')) {
        return _HomeSectionLayout.artist;
      }
      if (t.contains('release')) return _HomeSectionLayout.grid;
      if (t.contains('discover') ||
          t.contains('cover') ||
          t.contains('remix') ||
          t.contains('daily') ||
          t.contains('fresh')) {
        return _HomeSectionLayout.square;
      }
      return _HomeSectionLayout.square;
  }
}

bool _isSuppressedHomeSection(String title) {
  final t = title.toLowerCase();
  return t.contains('fresh finds') ||
      t.contains('old favorites') ||
      t.contains('old favourites') ||
      t.contains('late-night drive') ||
      t.contains('late night drive') ||
      t.contains('focus flow') ||
      t.contains('foxy mix') ||
      t.contains('radio starter');
}

const String _homeParamsRelax =
    'ggM8SgQIBxADSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsSleep =
    'ggM8SgQIBxABSgQIBRADSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsEnergize =
    'ggM8SgQIBxABSgQIBRABSgQICRADSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsSad =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChADSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsRomance =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRADSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsFeelGood =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBADSgQIBBABSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsWorkout =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBADSgQIDhABSgQIAxABSgQIBhAB';
const String _homeParamsParty =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhADSgQIAxABSgQIBhAB';
const String _homeParamsCommute =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxADSgQIBhAB';
const String _homeParamsFocus =
    'ggM8SgQIBxABSgQIBRABSgQICRABSgQIChABSgQIDRABSgQICBABSgQIBBABSgQIDhABSgQIAxABSgQIBhAD';

String? _homeFeedParamsForChip(String chip) {
  switch (chip) {
    case 'Relax':
      return _homeParamsRelax;
    case 'Sleep':
      return _homeParamsSleep;
    case 'Energize':
      return _homeParamsEnergize;
    case 'Sad':
      return _homeParamsSad;
    case 'Romance':
      return _homeParamsRomance;
    case 'Feel good':
      return _homeParamsFeelGood;
    case 'Workout':
      return _homeParamsWorkout;
    case 'Party':
      return _homeParamsParty;
    case 'Drive':
      return _homeParamsCommute;
    case 'Commute':
      return _homeParamsCommute;
    case 'Focus':
      return _homeParamsFocus;
    default:
      return null;
  }
}

String _homeFeedCacheKey(String? params) => params ?? '__all__';

String? _homeMoodQueryForChip(String chip) {
  switch (chip) {
    case 'Moods':
      return 'moods';
    case 'Genres':
      return 'genres';
    case 'Charts':
      return 'charts';
    case 'Categories':
      return 'categories';
    case 'Downloads':
      return 'downloaded';
    case 'Radio':
      return 'radio';
    case 'History':
      return 'history';
    case 'Phonk':
      return 'phonk';
    default:
      return null;
  }
}

const _searchFilterChips = <String>[
  'All',
  'Songs',
  'Videos',
  'Albums',
  'Artists',
];

enum _HomeSectionLayout {
  cards,
  grid,
  video,
  chart,
  artist,
  radio,
  mixes,
  square,
}

String _formatStorageBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class _FoxyHomeShell extends StatefulWidget {
  const _FoxyHomeShell({
    this.homeBackgroundPath,
    required this.remoteConfig,
    required this.onRemoteConfigChanged,
  });

  final String? homeBackgroundPath;
  final _FoxyRemoteConfig remoteConfig;
  final ValueChanged<_FoxyRemoteConfig> onRemoteConfigChanged;

  @override
  State<_FoxyHomeShell> createState() => _FoxyHomeShellState();
}

class _FoxyHomeShellState extends State<_FoxyHomeShell>
    with WidgetsBindingObserver {
  int _tabIndex = 0;
  final GlobalKey<_HomeTabState> _homeTabKey = GlobalKey<_HomeTabState>();
  final GlobalKey<_SearchTabState> _searchTabKey = GlobalKey<_SearchTabState>();
  final GlobalKey<_LibraryTabState> _libraryTabKey =
      GlobalKey<_LibraryTabState>();
  Map<String, dynamic> _player = const {};
  final ValueNotifier<Map<String, dynamic>> _miniPlayerNotifier =
      ValueNotifier<Map<String, dynamic>>(const {});
  Map<String, dynamic> _account = const {};
  Map<String, dynamic> _shellSettings = const {};
  _Song? _homeAdaptiveAccentSong;
  StreamSubscription<dynamic>? _sub;

  /// Avoid mini player + expanded sheet stacking (and Hero flights from feed art).
  bool _nowPlayingSheetOpen = false;
  Timer? _playbackResyncTimer;
  bool _appliedDefaultOpenTab = false;

  void _schedulePlaybackResync({bool extended = false}) {
    for (final delayMs
        in extended ? const [250, 600, 1200, 2500] : const [250, 600]) {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (!mounted) return;
        unawaited(_syncPlayerFromNative());
      });
    }
  }

  void _syncPlaybackResyncTimer() {
    final song = _asMap(_player['currentSong']);
    final hasSong = (song?['videoId']?.toString().isNotEmpty ?? false);
    final needsResync =
        hasSong && !_nowPlayingSheetOpen && _effectivePlayerBuffering(_player);
    if (!needsResync) {
      _playbackResyncTimer?.cancel();
      _playbackResyncTimer = null;
      return;
    }
    _playbackResyncTimer ??= Timer.periodic(const Duration(milliseconds: 450), (
      _,
    ) {
      if (!mounted) return;
      unawaited(_syncPlayerFromNative());
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccount();
    unawaited(_loadShellSettings());
    unawaited(_syncPlayerFromNative());
    _sub = _foxyEvents.listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        if (_nowPlayingSheetOpen) return;
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          _applyPlayerState(state);
        }
      } else if (type == 'playerProgress') {
        if (_nowPlayingSheetOpen) return;
        _applyPlayerProgress(map);
      } else if (type == 'accountChanged') {
        _SongMenuContextCache.invalidate();
        unawaited(_loadAccount());
      } else if (type == 'appearanceChanged') {
        unawaited(_loadShellSettings(applyDefaultTab: false));
      }
    });
  }

  Future<void> _loadShellSettings({bool applyDefaultTab = true}) async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppearance'));
      if (!mounted || map == null) return;
      setState(() => _shellSettings = map);
      if (applyDefaultTab && !_appliedDefaultOpenTab) {
        final tab = ((map['defaultOpenTab'] ?? 0) as num).toInt();
        if (tab == 1 || tab == 3) {
          setState(() => _tabIndex = tab);
        }
        _appliedDefaultOpenTab = true;
      }
    } catch (_) {
      if (applyDefaultTab) _appliedDefaultOpenTab = true;
    }
  }

  void _updateHomeAdaptiveAccent(_Song? song) {
    final current = _homeAdaptiveAccentSong;
    if (current?.videoId == song?.videoId &&
        current?.homeArtwork == song?.homeArtwork) {
      return;
    }
    if (!mounted) return;
    setState(() => _homeAdaptiveAccentSong = song);
  }

  void _applyPlayerState(Map<String, dynamic> state) {
    final merged = <String, dynamic>{..._player, ...state};
    if (!state.containsKey('queue') && _player.containsKey('queue')) {
      merged['queue'] = _player['queue'];
    }
    final next = _detachPlayerState(merged);
    final previous = _player;
    final changed = _shellPlayerSnapshotChanged(previous, next);
    final miniChanged = _miniPlayerSnapshotChanged(previous, next);
    final nextSongMap = _asMap(next['currentSong']);
    final nextAccentSong =
        (nextSongMap != null &&
            (nextSongMap['videoId']?.toString().isNotEmpty ?? false))
        ? _Song.fromMap(nextSongMap)
        : null;
    if (!changed) {
      _player = next;
      if (miniChanged) {
        _miniPlayerNotifier.value = next;
      }
      _syncPlaybackResyncTimer();
      return;
    }
    setState(() {
      _player = next;
      _homeAdaptiveAccentSong = nextAccentSong;
    });
    if (miniChanged) {
      _miniPlayerNotifier.value = next;
    }
    _syncPlaybackResyncTimer();
  }

  void _applyPlayerProgress(Map<String, dynamic> event) {
    if (_player.isEmpty) return;
    final previous = _player;
    final position = event['positionMs'];
    final duration = event['durationMs'];
    final isPlaying = event['isPlaying'];
    final isBuffering = event['isBuffering'];
    final next = <String, dynamic>{..._player};
    if (position is num) next['positionMs'] = position.toInt();
    if (duration is num && duration.toInt() > 0) {
      next['durationMs'] = duration.toInt();
    }
    if (isPlaying is bool) next['isPlaying'] = isPlaying;
    if (isBuffering is bool) next['isBuffering'] = isBuffering;
    final detached = _detachPlayerState(next);
    _player = detached;
    if (_miniPlayerSnapshotChanged(previous, detached)) {
      _miniPlayerNotifier.value = detached;
    }
    _syncPlaybackResyncTimer();
  }

  void _setOptimisticPlayerState(Map<String, dynamic> next) {
    final detached = _detachPlayerState(next);
    final songMap = _asMap(detached['currentSong']);
    final accentSong =
        (songMap != null &&
            (songMap['videoId']?.toString().isNotEmpty ?? false))
        ? _Song.fromMap(songMap)
        : null;
    if (!mounted) return;
    setState(() {
      _player = detached;
      _homeAdaptiveAccentSong = accentSong;
    });
    _miniPlayerNotifier.value = detached;
  }

  bool _miniPlayerSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (_shellPlayerSnapshotChanged(prev, next)) return true;
    if (prev['isPlaying'] != next['isPlaying']) return true;
    if (prev['isBuffering'] != next['isBuffering']) return true;
    if (prev['songIsLiked'] != next['songIsLiked']) return true;
    if (prev['volume'] != next['volume']) return true;
    if (prev['canPlayNext'] != next['canPlayNext']) return true;
    if (prev['canPlayPrevious'] != next['canPlayPrevious']) return true;
    if (prev['shuffleEnabled'] != next['shuffleEnabled']) return true;
    if (prev['repeatMode']?.toString() != next['repeatMode']?.toString()) {
      return true;
    }
    if (prev['queueIndex'] != next['queueIndex']) return true;
    if (_playerQueueSignature(prev['queue']) !=
        _playerQueueSignature(next['queue'])) {
      return true;
    }
    if (prev['streamBitrate'] != next['streamBitrate']) return true;
    if (prev['streamCodec']?.toString() != next['streamCodec']?.toString()) {
      return true;
    }
    if (prev['streamSource']?.toString() != next['streamSource']?.toString()) {
      return true;
    }
    if (prev['durationMs'] != next['durationMs']) return true;
    return false;
  }

  bool _shellPlayerSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (prev['playerEpoch'] != next['playerEpoch']) return true;
    if (prev['paletteEpoch'] != next['paletteEpoch']) return true;
    final pVid = _asMap(prev['currentSong'])?['videoId']?.toString() ?? '';
    final nVid = _asMap(next['currentSong'])?['videoId']?.toString() ?? '';
    if (pVid != nVid) return true;
    final pSong = _asMap(prev['currentSong']) ?? const {};
    final nSong = _asMap(next['currentSong']) ?? const {};
    if (pSong['title']?.toString() != nSong['title']?.toString()) return true;
    if (pSong['artist']?.toString() != nSong['artist']?.toString()) {
      return true;
    }
    final pArt = _asMap(prev['currentSong'])?['artwork']?.toString() ?? '';
    final nArt = _asMap(next['currentSong'])?['artwork']?.toString() ?? '';
    if (pArt != nArt) return true;
    final pOff =
        _asMap(prev['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    final nOff =
        _asMap(next['currentSong'])?['offlineArtworkPath']?.toString() ?? '';
    if (pOff != nOff) return true;
    return false;
  }

  Future<void> _loadAccount() async {
    try {
      final map = _asMap(await _method.invokeMethod('accountInfo'));
      if (mounted && map != null) setState(() => _account = map);
    } catch (_) {}
  }

  Future<void> _syncPlayerFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map != null && mounted) {
        _applyPlayerState(map);
      }
    } catch (_) {}
  }

  Future<void> _startRecognitionFromHome() async {
    try {
      await _method.invokeMethod('startRecognition');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Listening for music...')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('Recognition failed: $e')));
    }
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
      builder: (sheetCtx) => Stack(
        fit: StackFit.expand,
        children: [
          _FoxyHomeBackdrop(
            customPath: widget.homeBackgroundPath,
            child: const SizedBox.expand(),
          ),
          _SettingsSheet(
            appearance: appearance,
            onSetAppearance: (patch) async {
              await _method.invokeMethod('setAppearance', patch);
            },
            onAppearancePatched: (nextAppearance) {
              if (!mounted) return;
              setState(() => _shellSettings = nextAppearance);
            },
            account: _account,
            onAccountRefresh: _loadAccount,
            onOpenAccountHub: () {
              Navigator.of(sheetCtx).pop();
              Future.microtask(() {
                if (mounted) unawaited(_openAccountHub());
              });
            },
          ),
        ],
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
                Expanded(child: _AccountHubBody(onPlay: _playSong)),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) await _loadAccount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _playbackResyncTimer?.cancel();
    _miniPlayerNotifier.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPlayerFromNative());
    }
  }

  Future<void> _playSong(
    _Song song,
    List<_Song> queue, {
    bool radioTail = false,
  }) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    final start = math.max(index, 0);
    if (mounted) {
      _setOptimisticPlayerState(<String, dynamic>{
        ..._player,
        'currentSong': song.toMap(),
        'playerEpoch': DateTime.now().microsecondsSinceEpoch,
        'isBuffering': true,
        'isPlaying': false,
        'positionMs': 0,
        'durationMs': 0,
        'queue': songs.map((item) => item.toMap()).toList(),
        'queueIndex': start,
      });
    }
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': start,
      'radioTail': radioTail,
    });
    if (mounted) {
      await _syncPlayerFromNative();
      _schedulePlaybackResync(extended: true);
    }
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
    unawaited(_syncPlayerFromNative());
    setState(() => _nowPlayingSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final top = MediaQuery.paddingOf(sheetContext).top;
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 1,
            minChildSize: 0.24,
            maxChildSize: 1,
            snap: false,
            shouldCloseOnMinExtent: true,
            builder: (context, scrollController) {
              return ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: _NowPlayingSheet(
                  player: _player,
                  initialTab: initialTab,
                  scrollController: scrollController,
                  homeBackgroundPath: widget.homeBackgroundPath,
                  onNotifyHomePlayerSync: _syncPlayerFromNative,
                  onPlay: _playSong,
                  onDiscoverSearch: _openSearchWithQuery,
                ),
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      setState(() => _nowPlayingSheetOpen = false);
      unawaited(_syncPlayerFromNative());
      _schedulePlaybackResync(extended: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSongMap = _asMap(_player['currentSong']) ?? const {};
    final currentSong = _Song.fromMap(currentSongMap);

    final hasSong =
        currentSong.videoId.isNotEmpty && currentSong.title.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final hasThreeButtonNav = bottomInset >= 28;
    final navShellHeight = hasThreeButtonNav ? 58.0 : 64.0;
    final miniBottom =
        bottomInset + navShellHeight + (hasThreeButtonNav ? 8.0 : 10.0);
    final homeBottomPadding = bottomInset + navShellHeight + 88.0;
    final liquidGlassEnabled =
        _shellSettings['enableLiquidGlassLayout'] == true;
    final miniStyle = liquidGlassEnabled ? 1 : 0;
    final navStyle = liquidGlassEnabled ? 1 : 0;
    final safeTab = _tabIndex.clamp(0, 3);
    final rawTabs = [
      _HomeTab(
        key: _homeTabKey,
        currentVideoId: currentSong.videoId,
        onPlay: _playSong,
        account: _account,
        onOpenSettings: _openHomeSettings,
        onOpenDiscover: () => setState(() => _tabIndex = 2),
        onOpenLibrary: () => setState(() => _tabIndex = 3),
        onStartRecognition: _startRecognitionFromHome,
        onDiscoverSearch: _openSearchWithQuery,
        onAdaptiveAccentChanged: _updateHomeAdaptiveAccent,
        homeBackgroundPath: widget.homeBackgroundPath,
        homeSettings: _shellSettings,
        remoteConfig: widget.remoteConfig,
        bottomContentPadding: homeBottomPadding,
      ),
      KeyedSubtree(
        key: const PageStorageKey('search-tab'),
        child: _SearchTab(
          key: _searchTabKey,
          onPlay: _playSong,
          onDiscoverSearch: _openSearchWithQuery,
        ),
      ),
      _DiscoverTab(
        onOpenSearch: () => setState(() => _tabIndex = 1),
        onDiscoverSearch: _openSearchWithQuery,
      ),
      _LibraryTab(
        key: _libraryTabKey,
        onPlay: _playSong,
        onOpenSearch: () => setState(() => _tabIndex = 1),
        onDiscoverSearch: _openSearchWithQuery,
      ),
    ];
    final tabs = [
      for (var i = 0; i < rawTabs.length; i++)
        TickerMode(
          enabled: !_nowPlayingSheetOpen && safeTab == i,
          child: rawTabs[i],
        ),
    ];
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
        if (safeTab == 3 &&
            _libraryTabKey.currentState?.consumeAndroidBack() == true) {
          return;
        }
        if (safeTab == 1 &&
            (_searchTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab == 0 &&
            (_homeTabKey.currentState?.consumeAndroidBack() == true)) {
          return;
        }
        if (safeTab != 0) {
          setState(() => _tabIndex = 0);
          return;
        }
        unawaited(_method.invokeMethod('moveTaskToBack'));
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.transparent,
        extendBody: true,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _FoxyHomeBackdrop(
              customPath: widget.homeBackgroundPath,
              adaptiveAccentSong: _homeAdaptiveAccentSong,
              showAdaptiveAccent:
                  _shellSettings['homeBackgroundEnabled'] != true,
              child: const SizedBox.expand(),
            ),
            TickerMode(
              enabled: !_nowPlayingSheetOpen,
              child: IndexedStack(index: safeTab, children: tabs),
            ),
            if (!liquidGlassEnabled)
              IgnorePointer(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: (hasSong && !_nowPlayingSheetOpen)
                        ? miniBottom + 82
                        : bottomInset + navShellHeight + 28,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0),
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.78),
                          Colors.black,
                        ],
                        stops: const [0, 0.28, 0.72, 1],
                      ),
                    ),
                  ),
                ),
              ),
            if (hasSong && !_nowPlayingSheetOpen)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: miniBottom),
                  child: ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: _miniPlayerNotifier,
                    builder: (context, player, _) {
                      return _MiniPlayer(
                        key: ValueKey<Object>(
                          player['playerEpoch'] ?? currentSong.videoId,
                        ),
                        player: player.isEmpty ? _player : player,
                        onOpen: () => _openPlayer(),
                        onResync: _syncPlayerFromNative,
                        glass: true,
                        style: miniStyle,
                        buttonStyle:
                            ((_shellSettings['playerButtonsStyle'] ?? 0) as num)
                                .toInt()
                                .clamp(0, 2),
                        bottomGap: 0,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _FoxyBottomNav(
          selectedIndex: safeTab,
          onSelected: (index) {
            if (index == 0 && safeTab == 0) {
              _homeTabKey.currentState?.resetToDefault();
            }
            if (index == 1) {
              _searchTabKey.currentState?.resetToLanding();
            }
            if (index == 3) {
              _libraryTabKey.currentState?.openAtScope(0);
            }
            setState(() => _tabIndex = index);
          },
          style: navStyle,
          compact: hasThreeButtonNav,
        ),
      ),
    );
  }
}

class _FoxyBottomNav extends StatelessWidget {
  const _FoxyBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    this.style = 0,
    this.compact = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final int style;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (0, Icons.home_rounded, 'Home'),
      (3, Icons.library_music_rounded, 'Library'),
      (1, Icons.search_rounded, 'Search'),
    ];
    final navStyle = style.clamp(0, 2);
    final transparent = navStyle == 2;
    final liquid = navStyle == 1;
    final sharedWidthFactor = liquid ? (compact ? 0.76 : 0.76) : 0.94;
    Widget navIconButton({required int itemIndex, required IconData icon}) {
      final selected = selectedIndex == itemIndex;
      final iconSize = compact ? 25.0 : 29.0;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(itemIndex),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 4 : 6),
              child: Center(
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  scale: selected ? 1.15 : 1.0,
                  child: Icon(
                    icon,
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.78),
                    size: iconSize,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final navRow = SizedBox(
      height: compact ? 48 : 54,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: transparent
                    ? _FoxyGlassButton(
                        blur: false,
                        blurSigma: 0,
                        tintOpacity: 0.02,
                        onTap: () => onSelected(items[i].$1),
                        selected: selectedIndex == items[i].$1,
                        borderRadius: BorderRadius.circular(999),
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 4 : 6,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[i].$2,
                              color: selectedIndex == items[i].$1
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.55),
                              size: 22,
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  items[i].$3,
                                  style: TextStyle(
                                    color: selectedIndex == items[i].$1
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : liquid
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: selectedIndex == items[i].$1
                              ? LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.1),
                                    Colors.white.withValues(alpha: 0.04),
                                  ],
                                )
                              : null,
                          color: selectedIndex == items[i].$1
                              ? null
                              : Colors.transparent,
                          border: Border.all(
                            color: selectedIndex == items[i].$1
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.04),
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => onSelected(items[i].$1),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: compact ? 4 : 6,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    items[i].$2,
                                    color: selectedIndex == items[i].$1
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.7),
                                    size: 22,
                                  ),
                                  if (!compact) ...[
                                    const SizedBox(height: 2),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        items[i].$3,
                                        style: TextStyle(
                                          color: selectedIndex == items[i].$1
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.62,
                                                ),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : Material(
                        color: selectedIndex == items[i].$1
                            ? _kNavPillFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onSelected(items[i].$1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                items[i].$2,
                                color: selectedIndex == items[i].$1
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.55),
                                size: 22,
                              ),
                              if (!compact) ...[
                                const SizedBox(height: 2),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    items[i].$3,
                                    style: TextStyle(
                                      color: selectedIndex == items[i].$1
                                          ? Colors.white
                                          : Colors.white.withValues(alpha: 0.5),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
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
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          liquid
              ? 0
              : compact
              ? 4
              : 8,
        ),
        child: transparent
            ? Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: compact ? 4 : 5,
                ),
                child: navRow,
              )
            : liquid
            ? Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  widthFactor: sharedWidthFactor,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final searchShellSize = compact ? 58.0 : 64.0;
                      final mainShellHeight = compact ? 50.0 : 56.0;
                      final gap = 14.0;
                      final mainShellWidth = math.max(
                        132.0,
                        (constraints.maxWidth - searchShellSize - gap) * 0.90,
                      );
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: mainShellWidth,
                            child: _FoxyLiquidChromeShell(
                              radius: 999,
                              clear: true,
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 6 : 8,
                                vertical: compact ? 4 : 5,
                              ),
                              child: SizedBox(
                                height: mainShellHeight,
                                child: Row(
                                  children: [
                                    navIconButton(
                                      itemIndex: items[0].$1,
                                      icon: items[0].$2,
                                    ),
                                    const SizedBox(width: 4),
                                    navIconButton(
                                      itemIndex: items[1].$1,
                                      icon: items[1].$2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: gap),
                          Transform.translate(
                            offset: const Offset(0, -1),
                            child: _FoxyLiquidChromeShell(
                              radius: 999,
                              clear: true,
                              padding: EdgeInsets.zero,
                              child: SizedBox(
                                width: searchShellSize,
                                height: searchShellSize,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: () => onSelected(items[2].$1),
                                    child: Center(
                                      child: AnimatedScale(
                                        duration: const Duration(
                                          milliseconds: 160,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        scale: selectedIndex == items[2].$1
                                            ? 1.15
                                            : 1.0,
                                        child: Icon(
                                          items[2].$2,
                                          color: selectedIndex == items[2].$1
                                              ? Colors.white
                                              : Colors.white.withValues(
                                                  alpha: 0.78,
                                                ),
                                          size: compact ? 28 : 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              )
            : Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      navIconButton(itemIndex: items[0].$1, icon: items[0].$2),
                      navIconButton(itemIndex: items[1].$1, icon: items[1].$2),
                      navIconButton(itemIndex: items[2].$1, icon: items[2].$2),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    super.key,
    required this.currentVideoId,
    required this.onPlay,
    required this.account,
    required this.onOpenSettings,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onStartRecognition,
    this.onDiscoverSearch,
    this.onAdaptiveAccentChanged,
    this.homeBackgroundPath,
    required this.homeSettings,
    required this.remoteConfig,
    required this.bottomContentPadding,
  });

  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onStartRecognition;
  final void Function(String query)? onDiscoverSearch;
  final ValueChanged<_Song?>? onAdaptiveAccentChanged;
  final String? homeBackgroundPath;
  final Map<String, dynamic> homeSettings;
  final _FoxyRemoteConfig remoteConfig;
  final double bottomContentPadding;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  static const int _initialHomeSections = 2;
  static const int _warmHomeSections = 4;
  static const int _homeSectionBatchSize = 2;

  List<_SongSection> _sections = _HomeCache.sections;
  List<_SongSection> _orderedSections = const [];
  _Song? _spotlightSongCache;
  bool _loading = _HomeCache.sections.isEmpty;
  String? _error = _HomeCache.error;
  String _homeChip = 'All';
  int _visibleSectionCount = _initialHomeSections;
  late final ScrollController _homeScrollController;
  Timer? _homeRevealTimer;
  int _homeLoadSerial = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _homeScrollController = ScrollController()
      ..addListener(_maybeRevealMoreHome);
    _refreshDerivedHomeSections(_sections);
    if (_HomeCache.sections.isEmpty) {
      _loadHome();
    } else {
      _scheduleStagedHomeReveal();
    }
  }

  @override
  void dispose() {
    _homeScrollController
      ..removeListener(_maybeRevealMoreHome)
      ..dispose();
    _homeRevealTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account['isSignedIn'] != widget.account['isSignedIn']) {
      unawaited(_loadHome(force: true));
    }
  }

  bool _titleHasAny(String title, List<String> patterns) {
    final t = title.toLowerCase();
    return patterns.any(t.contains);
  }

  List<_SongSection> _curatedHomeSections(List<_SongSection> sections) {
    final seenTitles = <String>{};
    final kept = sections
        .where((section) {
          final title = section.title.trim().toLowerCase();
          if (title.isEmpty || !seenTitles.add(title)) return false;
          if (_titleHasAny(title, const [
            'most replayed',
            'high quality picks',
            'downloaded but forgotten',
          ])) {
            return false;
          }
          if (_homeChip == 'All' &&
              _titleHasAny(title, const ['charting now'])) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
    if (_homeChip == 'Categories') {
      return _categoryHomeSections(kept);
    }
    return kept;
  }

  List<_SongSection> _categoryHomeSections(List<_SongSection> sections) {
    final allSongs = <_Song>[];
    final seenIds = <String>{};
    for (final section in sections) {
      for (final song in section.songs) {
        final id = song.videoId.ifBlank('${song.title}:${song.artist}');
        if (seenIds.add(id)) allSongs.add(song);
      }
    }
    if (allSongs.isEmpty) return const [];

    const specs = <({String title, List<String> terms})>[
      (
        title: 'Phonk',
        terms: ['phonk', 'funk', 'brazilian', 'slowed', 'reverb', 'drift'],
      ),
      (
        title: 'Bollywood',
        terms: ['bollywood', 'hindi', 'arijit', 'pritam', 't-series', 'yrf'],
      ),
      (
        title: 'Punjabi',
        terms: ['punjabi', 'karan aujla', 'ap dhillon', 'sidhu', 'parmish'],
      ),
      (
        title: 'Pop',
        terms: ['pop', 'weeknd', 'taylor', 'dua lipa', 'ed sheeran', 'sabrina'],
      ),
      (
        title: 'Hip-Hop',
        terms: ['hip hop', 'hip-hop', 'rap', 'drake', 'travis', 'kendrick'],
      ),
      (
        title: 'Indie',
        terms: ['indie', 'anuv jain', 'prateek', 'indie pop', 'arctic monkeys'],
      ),
      (
        title: 'Classics',
        terms: ['classic', 'old', 'retro', '90s', '80s', 'evergreen'],
      ),
      (
        title: 'Remixes & Covers',
        terms: ['remix', 'cover', 'version', 'sped up', 'acoustic'],
      ),
    ];

    bool matches(_Song song, List<String> terms) {
      final text = [
        song.title,
        song.artist,
        song.album ?? '',
        song.channelName ?? '',
        song.source ?? '',
      ].join(' ').toLowerCase();
      return terms.any(text.contains);
    }

    final output = <_SongSection>[];
    for (final spec in specs) {
      final songs = allSongs
          .where((song) => matches(song, spec.terms))
          .take(8)
          .toList(growable: false);
      if (songs.length >= 2) {
        output.add(
          _SongSection(title: spec.title, layout: 'square', songs: songs),
        );
      }
    }
    return output.isNotEmpty
        ? output
        : sections.take(6).toList(growable: false);
  }

  void _refreshDerivedHomeSections(List<_SongSection> sections) {
    _orderedSections = _curatedHomeSections(
      sections
          .where((section) => !_isSuppressedHomeSection(section.title))
          .toList(growable: false),
    );
    _spotlightSongCache = _findSpotlightSong(_orderedSections);
  }

  _Song? _findSpotlightSong(List<_SongSection> sections) {
    for (final section in sections) {
      for (final song in section.songs) {
        if (song.homeArtwork.isNotEmpty || song.artwork.isNotEmpty) {
          return song;
        }
      }
    }
    return null;
  }

  void _scheduleStagedHomeReveal() {
    _homeRevealTimer?.cancel();
    if (_loading || _homeChip != 'All') return;
    final target = math.min(_warmHomeSections, _orderedSections.length);
    if (_visibleSectionCount >= target) return;
    _homeRevealTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || _loading || _homeChip != 'All') return;
      setState(() {
        _visibleSectionCount = math.min(target, _visibleSectionCount + 1);
      });
      _scheduleStagedHomeReveal();
    });
  }

  Future<List<_SongSection>> _fetchHomeSections({
    required String? params,
    required String? mood,
    required bool fast,
  }) async {
    final requestArgs = <String, dynamic>{'fast': fast};
    if (params != null) requestArgs['params'] = params;
    if (mood != null) requestArgs['mood'] = mood;
    final response =
        _asMap(await _method.invokeMethod('homeFeed', requestArgs)) ?? const {};
    return (response['sections'] as List? ?? const [])
        .map((item) => _SongSection.fromMap(_asMap(item) ?? const {}))
        .where((section) => section.songs.isNotEmpty)
        .toList();
  }

  Future<void> _upgradeHomeFeed({
    required int serial,
    required String cacheKey,
    required String? params,
    required String? mood,
  }) async {
    try {
      final sections = await _fetchHomeSections(
        params: params,
        mood: mood,
        fast: false,
      );
      if (!mounted || serial != _homeLoadSerial || sections.isEmpty) return;
      _HomeCache.sectionsByParams[cacheKey] = sections;
      _HomeCache.errorsByParams.remove(cacheKey);
      if (cacheKey == _homeFeedCacheKey(null)) {
        _HomeCache.sections = sections;
        _HomeCache.error = null;
      }
      setState(() {
        _sections = sections;
        _refreshDerivedHomeSections(sections);
        _loading = false;
        _error = null;
        _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
      });
      _scheduleStagedHomeReveal();
    } catch (_) {
      // Fast feed is already on screen; full refresh can quietly retry later.
    }
  }

  Future<void> _loadHome({bool force = false}) async {
    final params = _homeFeedParamsForChip(_homeChip);
    final mood = _homeMoodQueryForChip(_homeChip);
    final cacheKey = mood == null ? _homeFeedCacheKey(params) : 'mood:$mood';
    final cachedSections = _HomeCache.sectionsByParams[cacheKey];
    final serial = ++_homeLoadSerial;
    if (!force && cachedSections != null) {
      setState(() {
        _sections = cachedSections;
        _refreshDerivedHomeSections(cachedSections);
        _error = _HomeCache.errorsByParams[cacheKey];
        _loading = false;
        _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
      });
      _scheduleStagedHomeReveal();
      return;
    }
    _homeRevealTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _visibleSectionCount = _initialHomeSections;
      if (_homeChip != 'All') {
        _sections = const [];
        _orderedSections = const [];
        _spotlightSongCache = null;
      }
    });
    try {
      final sections = await _fetchHomeSections(
        params: params,
        mood: mood,
        fast: true,
      );
      if (!mounted || serial != _homeLoadSerial) return;
      _HomeCache.sectionsByParams[cacheKey] = sections;
      _HomeCache.errorsByParams.remove(cacheKey);
      if (cacheKey == _homeFeedCacheKey(null)) {
        _HomeCache.sections = sections;
        _HomeCache.error = null;
      }
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _refreshDerivedHomeSections(sections);
        _loading = false;
        _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
      });
      _scheduleStagedHomeReveal();
      unawaited(
        _upgradeHomeFeed(
          serial: serial,
          cacheKey: cacheKey,
          params: params,
          mood: mood,
        ),
      );
    } catch (e) {
      if (!mounted || serial != _homeLoadSerial) return;
      _HomeCache.errorsByParams[cacheKey] = e.toString();
      if (cacheKey == _homeFeedCacheKey(null)) {
        _HomeCache.error = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _error = _HomeCache.error;
        _loading = false;
      });
    }
  }

  void _onHomeChip(String label) {
    _homeRevealTimer?.cancel();
    final params = _homeFeedParamsForChip(label);
    final mood = _homeMoodQueryForChip(label);
    final cacheKey = mood == null ? _homeFeedCacheKey(params) : 'mood:$mood';
    final cachedSections = _HomeCache.sectionsByParams[cacheKey];
    setState(() {
      _homeChip = label;
      _visibleSectionCount = _initialHomeSections;
      if (cachedSections == null) {
        _sections = const [];
        _orderedSections = const [];
        _spotlightSongCache = null;
        _loading = true;
        _error = null;
      } else {
        _sections = cachedSections;
        _refreshDerivedHomeSections(cachedSections);
        _loading = false;
        _error = _HomeCache.errorsByParams[cacheKey];
      }
    });
    unawaited(_loadHome());
  }

  void resetToDefault() {
    if (_homeScrollController.hasClients) {
      _homeScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
    if (_homeChip != 'All') {
      setState(() => _homeChip = 'All');
      unawaited(_loadHome());
      return;
    }
    setState(() {
      _visibleSectionCount = _initialVisibleCount(_orderedSections.length);
    });
  }

  bool consumeAndroidBack() {
    if (_homeChip == 'All') return false;
    resetToDefault();
    return true;
  }

  int _initialVisibleCount(int total) {
    if (_homeChip != 'All') return total;
    return math.min(_initialHomeSections, total);
  }

  void _maybeRevealMoreHome() {
    if (!_homeScrollController.hasClients || _loading || _homeChip != 'All') {
      return;
    }
    final position = _homeScrollController.position;
    if (position.extentAfter > 420) return;
    if (_visibleSectionCount >= _orderedSections.length) return;
    setState(() {
      _visibleSectionCount = math.min(
        _orderedSections.length,
        _visibleSectionCount + _homeSectionBatchSize,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    super.build(context);
    final remoteConfig = widget.remoteConfig.enabled
        ? widget.remoteConfig
        : const _FoxyRemoteConfig();
    final signedIn = widget.account['isSignedIn'] == true;
    bool isQuickPicks(_SongSection section) =>
        section.title.toLowerCase().contains('quick pick');
    bool isNewRelease(_SongSection section) {
      final title = section.title.toLowerCase();
      return title.contains('new release') || title.contains('latest drop');
    }

    bool isArtists(_SongSection section) {
      final title = section.title.toLowerCase();
      return title.contains('artist') ||
          _homeSectionLayout(section) == _HomeSectionLayout.artist;
    }

    bool isCategories(_SongSection section) {
      final title = section.title.toLowerCase();
      return title.contains('categor') ||
          title.contains('genre') ||
          title.contains('mood');
    }

    bool matchesRemoteTopKey(_SongSection section, String key) {
      final normalized = key.trim().toLowerCase().replaceAll(
        RegExp(r'[\s_-]+'),
        '',
      );
      return switch (normalized) {
        'quickpicks' || 'quickpick' || 'listenagain' => isQuickPicks(section),
        'newreleases' ||
        'newrelease' ||
        'latestdrops' ||
        'latestdrop' => isNewRelease(section),
        'artists' || 'featuredartists' => isArtists(section),
        'categories' || 'category' => isCategories(section),
        _ => section.title.toLowerCase().contains(key.trim().toLowerCase()),
      };
    }

    List<_SongSection> remoteTopSections() {
      if (!signedIn || _homeChip != 'All') return const [];
      final picked = <_SongSection>[];
      for (final key in remoteConfig.homeSectionOrder) {
        final match = _orderedSections
            .where(
              (section) =>
                  !picked.contains(section) &&
                  matchesRemoteTopKey(section, key),
            )
            .firstOrNull;
        if (match != null) picked.add(match);
      }
      return picked.take(4).toList(growable: false);
    }

    final topSections = remoteTopSections();
    final feedSections = signedIn && _homeChip == 'All'
        ? _orderedSections
              .where((section) => !topSections.contains(section))
              .toList(growable: false)
        : _orderedSections;
    final visibleSectionCount = _homeChip == 'All'
        ? math.min(_visibleSectionCount, feedSections.length)
        : feedSections.length;
    final hideSignedInSpotlight =
        signedIn &&
        remoteConfig.homeSignedInHeroMode.toLowerCase() == 'quickpicks';
    final spotlightSong = _homeChip == 'All' && !hideSignedInSpotlight
        ? _spotlightSongCache
        : null;
    final quickPicksDisplayMode =
        ((widget.homeSettings['quickPicksDisplayMode'] ?? 0) as num).toInt();
    final experimentalHeaderAccentEnabled =
        widget.homeSettings['homeBackgroundEnabled'] != true;
    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF151515),
      onRefresh: () async {
        await _loadHome(force: true);
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        controller: _homeScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 260,
        slivers: [
          SliverToBoxAdapter(
            child: _HomeTopBar(
              account: widget.account,
              onOpenSettings: widget.onOpenSettings,
              onOpenDiscover: widget.onOpenDiscover,
              onOpenLibrary: widget.onOpenLibrary,
              onStartRecognition: widget.onStartRecognition,
            ),
          ),
          if (_loading && _sections.isEmpty)
            const SliverToBoxAdapter(child: _HomeLoading())
          else if (_error != null)
            SliverToBoxAdapter(
              child: _HomeError(
                message: _error!,
                onRetry: () {
                  unawaited(_loadHome(force: true));
                },
              ),
            )
          else if (_homeChip == 'All' && feedSections.isEmpty)
            SliverToBoxAdapter(
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
            )
          else if (_homeChip == 'All') ...[
            SliverToBoxAdapter(
              child: _HomeQuickActionChips(
                onOpenRadio: () => _onHomeChip('Radio'),
                onOpenMoods: () => _onHomeChip('Moods'),
                onOpenGenres: () => _onHomeChip('Genres'),
                onOpenCharts: () => _onHomeChip('Charts'),
                onOpenCategories: () => _onHomeChip('Categories'),
                onOpenDownloads: () => _onHomeChip('Downloads'),
                onOpenHistory: () => _onHomeChip('History'),
              ),
            ),
            if (spotlightSong != null)
              SliverToBoxAdapter(
                child: _HomeShelfShell(
                  child: _HomeSpotlight(
                    song: spotlightSong,
                    sectionTitle: 'Foxy Pick',
                    onPlay: () => widget.onPlay(
                      spotlightSong,
                      feedSections.expand((s) => s.songs).take(36).toList(),
                    ),
                    onRadio: () => widget.onPlay(
                      spotlightSong,
                      feedSections.expand((s) => s.songs).take(36).toList(),
                      radioTail: true,
                    ),
                  ),
                ),
              ),
            for (final topSection in topSections)
              SliverToBoxAdapter(
                child: _HomeShelfShell(
                  child: _HomeFeedSection(
                    section: topSection,
                    layout: _homeSectionLayout(topSection),
                    currentVideoId: widget.currentVideoId,
                    onPlay: widget.onPlay,
                    onDiscoverSearch: widget.onDiscoverSearch,
                    quickPicksDisplayMode: isQuickPicks(topSection)
                        ? 0
                        : quickPicksDisplayMode,
                    experimentalHeaderAccentEnabled:
                        experimentalHeaderAccentEnabled,
                    maxGridItems: remoteConfig.homeMaxGridItems,
                  ),
                ),
              ),
            SliverList.builder(
              itemCount: visibleSectionCount,
              itemBuilder: (context, index) {
                final sec = feedSections[index];
                return _HomeShelfShell(
                  child: _HomeFeedSection(
                    section: sec,
                    layout: _homeSectionLayout(sec),
                    currentVideoId: widget.currentVideoId,
                    onPlay: widget.onPlay,
                    onDiscoverSearch: widget.onDiscoverSearch,
                    quickPicksDisplayMode: quickPicksDisplayMode,
                    experimentalHeaderAccentEnabled:
                        experimentalHeaderAccentEnabled,
                    maxGridItems: remoteConfig.homeMaxGridItems,
                  ),
                );
              },
            ),
            if (_visibleSectionCount < feedSections.length)
              const SliverToBoxAdapter(
                child: _HomeShelfShell(child: _HomeFeedLoadingMore()),
              ),
          ] else ...[
            SliverToBoxAdapter(
              child: _HomeCategoryHeader(
                title: _homeChip,
                onBack: resetToDefault,
              ),
            ),
            SliverList.builder(
              itemCount: feedSections.length,
              itemBuilder: (context, index) {
                final sec = feedSections[index];
                return _HomeShelfShell(
                  child: _HomeFeedSection(
                    section: sec,
                    layout: _homeSectionLayout(sec),
                    currentVideoId: widget.currentVideoId,
                    onPlay: widget.onPlay,
                    onDiscoverSearch: widget.onDiscoverSearch,
                    quickPicksDisplayMode: quickPicksDisplayMode,
                    experimentalHeaderAccentEnabled:
                        experimentalHeaderAccentEnabled,
                    maxGridItems: remoteConfig.homeMaxGridItems,
                  ),
                );
              },
            ),
          ],
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                _kHomeShelfGap,
                16,
                widget.bottomContentPadding,
              ),
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
  static final Map<String, List<_SongSection>> sectionsByParams = {};
  static final Map<String, String?> errorsByParams = {};
}

class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar({
    required this.account,
    required this.onOpenSettings,
    required this.onOpenDiscover,
    required this.onOpenLibrary,
    required this.onStartRecognition,
  });

  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenDiscover;
  final VoidCallback onOpenLibrary;
  final VoidCallback onStartRecognition;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _FoxyAppLogo(size: 36, borderRadius: 10, showGlow: false),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FoxyMusic',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        _kAppVersionLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                _GlassIconButton(
                  tooltip: 'Discover',
                  icon: Icons.explore_rounded,
                  onPressed: onOpenDiscover,
                  plain: true,
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Recognize song',
                  icon: Icons.mic_rounded,
                  onPressed: onStartRecognition,
                  plain: true,
                ),
                const SizedBox(width: 6),
                _GlassIconButton(
                  tooltip: 'Settings',
                  icon: Icons.settings_rounded,
                  onPressed: onOpenSettings,
                  plain: true,
                ),
              ],
            ),
            Text(
              _homeGreeting(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 15,
                fontWeight: FontWeight.w600,
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
    this.plain = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool plain;

  @override
  Widget build(BuildContext context) {
    if (plain) {
      return Tooltip(
        message: tooltip,
        child: IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onPressed,
          icon: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.9),
            size: 25,
          ),
        ),
      );
    }
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
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.88),
            size: 25,
          ),
        ),
      ),
    );
  }
}

class _HomeQuickActionChips extends StatelessWidget {
  const _HomeQuickActionChips({
    required this.onOpenRadio,
    required this.onOpenMoods,
    required this.onOpenGenres,
    required this.onOpenCharts,
    required this.onOpenCategories,
    required this.onOpenDownloads,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenRadio;
  final VoidCallback onOpenMoods;
  final VoidCallback onOpenGenres;
  final VoidCallback onOpenCharts;
  final VoidCallback onOpenCategories;
  final VoidCallback onOpenDownloads;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final chips = <({String label, IconData icon, VoidCallback onTap})>[
      (label: 'Moods', icon: Icons.auto_awesome_rounded, onTap: onOpenMoods),
      (label: 'Genres', icon: Icons.category_rounded, onTap: onOpenGenres),
      (
        label: 'Categories',
        icon: Icons.grid_view_rounded,
        onTap: onOpenCategories,
      ),
      (label: 'Charts', icon: Icons.show_chart_rounded, onTap: onOpenCharts),
      (
        label: 'Downloads',
        icon: Icons.download_rounded,
        onTap: onOpenDownloads,
      ),
      (label: 'Radio', icon: Icons.radio_rounded, onTap: onOpenRadio),
      (label: 'History', icon: Icons.history_rounded, onTap: onOpenHistory),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final chip = chips[index];
            return _FoxyGlassButton(
              onTap: chip.onTap,
              borderRadius: BorderRadius.circular(999),
              tintOpacity: 0.08,
              blur: true,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    chip.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeCategoryHeader extends StatelessWidget {
  const _HomeCategoryHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _FoxyGlassButton(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            padding: EdgeInsets.zero,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _homeGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Up late Zzz..';
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
    this.onLocalLibrary,
    this.onDownloads,
  });

  final Widget? leading;
  final String title;
  final VoidCallback? onRefresh;
  final String? subtitle;
  final VoidCallback? onSearch;
  final VoidCallback? onSparkle;
  final VoidCallback? onLocalLibrary;
  final VoidCallback? onDownloads;

  @override
  Widget build(BuildContext context) {
    final leadingWidget = leading;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ...?(leadingWidget == null ? null : [leadingWidget]),
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
                    plain: true,
                  ),
                if (onLocalLibrary != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Local library',
                    icon: Icons.library_music_rounded,
                    onPressed: onLocalLibrary!,
                    plain: true,
                  ),
                ] else if (onSparkle != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Discovery',
                    icon: Icons.auto_awesome_rounded,
                    onPressed: onSparkle!,
                    plain: true,
                  ),
                ],
                if (onSearch != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Search',
                    icon: Icons.search_rounded,
                    onPressed: onSearch!,
                    plain: true,
                  ),
                ],
                if (onRefresh != null) ...[
                  const SizedBox(width: 6),
                  _GlassIconButton(
                    tooltip: 'Refresh',
                    icon: Icons.refresh_rounded,
                    onPressed: onRefresh!,
                    plain: true,
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Padding(
        padding: margin,
        child: _FoxyGlassTint(
          borderRadius: _kCardRadius,
          tintOpacity: selected ? 0.34 : 0.22,
          borderOpacity: selected ? 0.2 : 0.1,
          child: Padding(padding: padding, child: child),
        ),
      );
    }
    return Padding(
      padding: margin,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: selected,
        borderRadius: BorderRadius.circular(_kCardRadius),
        padding: padding,
        child: child,
      ),
    );
  }
}

class _FoxySongTile extends StatelessWidget {
  const _FoxySongTile({
    required this.song,
    required this.onTap,
    this.onMore,
    this.active = false,
    this.index,
    this.thumbRadius = 6,
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final bool active;
  final int? index;
  final double thumbRadius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget trailing;
    if (onMore != null) {
      trailing = IconButton(
        tooltip: 'More',
        onPressed: onMore,
        icon: const Icon(Icons.more_vert_rounded),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: onTap,
        icon: Icon(
          Icons.play_circle_fill_rounded,
          color: active ? accent : Colors.white,
        ),
      );
    }

    return _FoxySurface(
      selected: active,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Row(
        children: [
          if (index != null) ...[
            SizedBox(
              width: 26,
              child: Text(
                '${index! + 1}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? accent : Colors.white.withValues(alpha: 0.42),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          _Artwork(
            url: song.highQualityArtwork,
            size: 52,
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
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w900 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
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

/// Foxy-style full-screen results with Songs / Videos / Albums / Artists tabs.
class _SearchResultsPage extends StatefulWidget {
  const _SearchResultsPage({required this.query, required this.onPlay});

  final String query;
  final _FoxyOnPlay onPlay;

  @override
  State<_SearchResultsPage> createState() => _SearchResultsPageState();
}

class _SearchResultsPageState extends State<_SearchResultsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<_Song> _songs = const [];
  List<_Song> _videos = const [];
  List<_Song> _albums = const [];
  List<_Song> _artists = const [];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': widget.query,
              'limit': 28,
            }),
          ) ??
          const {};
      if (!mounted) return;
      List<_Song> parseList(String key) => (response[key] as List? ?? const [])
          .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
          .where((s) => s.videoId.isNotEmpty)
          .toList();
      setState(() {
        _songs = parseList('songs');
        _videos = parseList('videos');
        _albums = parseList('albums');
        _artists = parseList('artists');
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _openMenu(_Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue.isEmpty ? [song] : queue,
      onLibraryChanged: () async {},
      searchResultsForExtras: queue.length > 1 ? queue : null,
    );
  }

  void _openArtistResult(_Song artist) {
    final artistName = artist.title.ifBlank(artist.artist);
    if (artistName.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artistName,
          artworkUrl: artist.highQualityArtwork,
          onPlay: widget.onPlay,
        ),
      ),
    );
  }

  Widget _groupedAllBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    final topAlbums = _albums.take(4).toList();
    final topArtists = _artists.take(6).toList();
    if (topAlbums.isEmpty && topArtists.isEmpty && _songs.isEmpty) {
      return const _EmptyTabBody(
        icon: Icons.search_off_rounded,
        title: 'Nothing here',
        subtitle: 'Try another spelling or category.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      children: [
        if (topAlbums.isNotEmpty) ...[
          _SearchSectionLabel('Albums'),
          const SizedBox(height: 4),
          for (final album in topAlbums)
            _FoxySearchResultRow(
              song: album,
              kind: _SearchRowKind.album,
              onTap: () => widget.onPlay(album, _albums, radioTail: false),
              onMore: () => _openMenu(album, _albums),
            ),
          const SizedBox(height: 10),
        ],
        if (topArtists.isNotEmpty) ...[
          _SearchSectionLabel('Artists'),
          const SizedBox(height: 4),
          for (final artist in topArtists)
            _FoxySearchResultRow(
              song: artist,
              kind: _SearchRowKind.artist,
              onTap: () => _openArtistResult(artist),
              onMore: () {},
            ),
          const SizedBox(height: 10),
        ],
        if (_songs.isNotEmpty) ...[
          _SearchSectionLabel('Songs'),
          const SizedBox(height: 4),
          for (final song in _songs)
            _FoxySearchResultRow(
              song: song,
              kind: _SearchRowKind.song,
              onTap: () => widget.onPlay(song, _songs, radioTail: true),
              onMore: () => _openMenu(song, _songs),
            ),
        ],
      ],
    );
  }

  Widget _tabBody(
    List<_Song> items, {
    _SearchRowKind kind = _SearchRowKind.song,
    bool radioTail = true,
  }) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 32),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final song = items[index];
        return _FoxySearchResultRow(
          song: song,
          kind: kind,
          onTap: kind == _SearchRowKind.artist
              ? () => _openArtistResult(song)
              : () => widget.onPlay(song, items, radioTail: radioTail),
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
      body: Column(
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
            color: Colors.black,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              indicatorColor: accent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white.withValues(alpha: 0.5),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: [
                Tab(text: 'All'),
                Tab(text: 'Songs (${_loading ? '...' : _songs.length})'),
                Tab(text: 'Videos (${_loading ? '...' : _videos.length})'),
                Tab(text: 'Albums (${_loading ? '...' : _albums.length})'),
                Tab(text: 'Artists (${_loading ? '...' : _artists.length})'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _groupedAllBody(),
                _tabBody(_songs, kind: _SearchRowKind.song, radioTail: true),
                _tabBody(_videos, kind: _SearchRowKind.video, radioTail: false),
                _tabBody(_albums, kind: _SearchRowKind.album, radioTail: false),
                _tabBody(
                  _artists,
                  kind: _SearchRowKind.artist,
                  radioTail: false,
                ),
              ],
            ),
          ),
        ],
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
  static const int _historyLimit = 8;
  static const int _cacheLimit = 18;
  static final List<String> _history = <String>[];
  static final Map<String, _SearchResultSnapshot> _resultCache =
      <String, _SearchResultSnapshot>{};

  final TextEditingController _controller = TextEditingController();
  String _query = '';
  String _filter = 'All';
  String? _error;
  bool _loading = false;
  Timer? _debounce;
  Timer? _loadingDelay;
  List<_Song> _songs = const [];
  List<_Song> _videos = const [];
  List<_Song> _albums = const [];
  List<_Song> _artists = const [];
  int _searchEpoch = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSearchHistory());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _loadingDelay?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    try {
      final values =
          (await _method.invokeMethod('searchHistory') as List? ?? const [])
              .map((item) => item.toString().trim())
              .where((item) => item.length >= 2)
              .toList();
      if (!mounted) return;
      setState(() {
        _history
          ..clear()
          ..addAll(values.take(_historyLimit));
      });
    } catch (_) {}
  }

  void applyExternalQuery(String raw) {
    final q = raw.trim();
    setState(() {
      _query = q;
      _controller.text = q;
      _error = null;
    });
    if (q.length >= 2) {
      _rememberQuery(q);
      unawaited(_runSearch(q));
    }
  }

  void resetToLanding() {
    _debounce?.cancel();
    _loadingDelay?.cancel();
    _searchEpoch++;
    setState(() {
      _controller.clear();
      _query = '';
      _filter = 'All';
      _error = null;
      _songs = const [];
      _videos = const [];
      _albums = const [];
      _artists = const [];
      _loading = false;
    });
  }

  bool consumeAndroidBack() {
    if (_controller.text.trim().isEmpty &&
        _query.trim().isEmpty &&
        _error == null &&
        !_hasResults) {
      return false;
    }
    resetToLanding();
    return true;
  }

  bool get _hasResults =>
      _songs.isNotEmpty ||
      _videos.isNotEmpty ||
      _albums.isNotEmpty ||
      _artists.isNotEmpty;

  List<({String header, List<({_Song song, _SearchRowKind kind})> rows})>
  get _allGroups {
    final groups =
        <({String header, List<({_Song song, _SearchRowKind kind})> rows})>[];
    final topAlbums = _albums
        .take(4)
        .map((song) => (song: song, kind: _SearchRowKind.album))
        .toList();
    if (topAlbums.isNotEmpty) {
      groups.add((header: 'Albums', rows: topAlbums));
    }
    final artists = _artists
        .take(6)
        .map((song) => (song: song, kind: _SearchRowKind.artist))
        .toList();
    if (artists.isNotEmpty) {
      groups.add((header: 'Artists', rows: artists));
    }
    final songs = _songs
        .map((song) => (song: song, kind: _SearchRowKind.song))
        .toList();
    if (songs.isNotEmpty) {
      groups.add((header: 'Songs', rows: songs));
    }
    if (groups.isEmpty && _videos.isNotEmpty) {
      groups.add((
        header: 'Videos',
        rows: _videos
            .map((song) => (song: song, kind: _SearchRowKind.video))
            .toList(),
      ));
    }
    return groups;
  }

  void _onChanged(String value) {
    if (_query != value || _error != null) {
      setState(() {
        _query = value;
        _error = null;
      });
    }
    _debounce?.cancel();
    _loadingDelay?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _searchEpoch++;
      setState(() {
        _loading = false;
        _songs = const [];
        _videos = const [];
        _albums = const [];
        _artists = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 220), () {
      unawaited(_runSearch(q));
    });
  }

  void _rememberQuery(String raw) {
    final query = raw.trim();
    if (query.length < 2) return;
    _history.removeWhere((item) => item.toLowerCase() == query.toLowerCase());
    _history.insert(0, query);
    if (_history.length > _historyLimit) {
      _history.removeRange(_historyLimit, _history.length);
    }
    unawaited(_method.invokeMethod('addSearchHistory', {'query': query}));
  }

  void _clearSearchHistory() {
    setState(_history.clear);
    unawaited(_method.invokeMethod('clearSearchHistory'));
  }

  void _cacheSearchResult(String key, _SearchResultSnapshot snapshot) {
    _resultCache.remove(key);
    _resultCache[key] = snapshot;
    while (_resultCache.length > _cacheLimit) {
      _resultCache.remove(_resultCache.keys.first);
    }
  }

  void _removeSearchHistoryItem(String item) {
    setState(() {
      _history.remove(item);
    });
    unawaited(_method.invokeMethod('removeSearchHistory', {'query': item}));
  }

  void _openArtistPage(_Song artist) {
    final artistName = artist.title.ifBlank(artist.artist);
    if (artistName.trim().isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artistName,
          artworkUrl: '',
          onPlay: widget.onPlay,
          onDiscoverSearch: widget.onDiscoverSearch,
        ),
      ),
    );
  }

  void _activateSearchQuery(String raw) {
    final query = raw.trim();
    if (query.length < 2) return;
    _debounce?.cancel();
    _rememberQuery(query);
    setState(() {
      _query = query;
      _controller.text = query;
      _controller.selection = TextSelection.collapsed(offset: query.length);
      _filter = 'All';
      _error = null;
    });
    unawaited(_runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) return;
    final cacheKey = normalizedQuery.toLowerCase();
    final cached = _resultCache[cacheKey];
    final epoch = ++_searchEpoch;
    _loadingDelay?.cancel();
    if (cached != null) {
      setState(() {
        _songs = cached.songs;
        _videos = cached.videos;
        _albums = cached.albums;
        _artists = cached.artists;
        _loading = false;
        _error = null;
      });
      return;
    }
    _loadingDelay = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || epoch != _searchEpoch) return;
      setState(() {
        _loading = true;
        _error = null;
      });
    });
    try {
      if (_looksLikeSpotifyTrackUrl(normalizedQuery)) {
        final raw = _asMap(
          await _method.invokeMethod('resolveSpotifyTrack', {
            'spotifyUrl': _normalizeSpotifyTrackUrl(normalizedQuery),
          }),
        );
        if (!mounted ||
            _query.trim() != normalizedQuery ||
            epoch != _searchEpoch) {
          return;
        }
        _loadingDelay?.cancel();
        final songMap = _asMap(raw?['song']);
        final song = songMap == null ? null : _Song.fromMap(songMap);
        final songs = song == null || song.videoId.isEmpty
            ? const <_Song>[]
            : [song];
        _cacheSearchResult(
          cacheKey,
          _SearchResultSnapshot(
            songs: songs,
            videos: const [],
            albums: const [],
            artists: const [],
          ),
        );
        setState(() {
          _songs = songs;
          _videos = const [];
          _albums = const [];
          _artists = const [];
          _loading = false;
          _error = song == null || song.videoId.isEmpty
              ? 'No playable match found for that Spotify link'
              : null;
        });
        return;
      }
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': normalizedQuery,
              'limit': 18,
            }),
          ) ??
          const {};
      if (!mounted ||
          _query.trim() != normalizedQuery ||
          epoch != _searchEpoch) {
        return;
      }
      _loadingDelay?.cancel();
      List<_Song> parseList(String key) => (response[key] as List? ?? const [])
          .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
          .where((s) => s.videoId.isNotEmpty)
          .toList();
      var songs = parseList('songs');
      final videos = parseList('videos');
      final albums = parseList('albums');
      final artists = parseList('artists');
      if (songs.isEmpty &&
          videos.isEmpty &&
          albums.isEmpty &&
          artists.isEmpty) {
        final fallback =
            _asMap(
              await _method.invokeMethod('search', {
                'query': normalizedQuery,
                'limit': 18,
              }),
            ) ??
            const {};
        songs = (fallback['songs'] as List? ?? const [])
            .map((e) => _Song.fromMap(_asMap(e) ?? const {}))
            .where((s) => s.videoId.isNotEmpty)
            .toList();
      }
      if (songs.isNotEmpty ||
          videos.isNotEmpty ||
          albums.isNotEmpty ||
          artists.isNotEmpty) {
        _cacheSearchResult(
          cacheKey,
          _SearchResultSnapshot(
            songs: songs,
            videos: videos,
            albums: albums,
            artists: artists,
          ),
        );
      }
      setState(() {
        _songs = songs;
        _videos = videos;
        _albums = albums;
        _artists = artists;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _searchEpoch) return;
      _loadingDelay?.cancel();
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  bool _looksLikeSpotifyTrackUrl(String value) {
    final q = value.trim().toLowerCase();
    return q.contains('open.spotify.com/track/') ||
        q.contains('spotify:track:');
  }

  String _normalizeSpotifyTrackUrl(String value) {
    final q = value.trim();
    if (!q.toLowerCase().startsWith('spotify:track:')) return q;
    final id = q.split(':').last.trim();
    return id.isEmpty ? q : 'https://open.spotify.com/track/$id';
  }

  void _submitSearch(String value) {
    final query = value.trim();
    if (query.length < 2) return;
    _activateSearchQuery(query);
  }

  List<({_Song song, _SearchRowKind kind})> get _visibleRows {
    switch (_filter) {
      case 'Songs':
        return _songs.map((s) => (song: s, kind: _SearchRowKind.song)).toList();
      case 'Videos':
        return _videos
            .map((s) => (song: s, kind: _SearchRowKind.video))
            .toList();
      case 'Albums':
        return _albums
            .map((s) => (song: s, kind: _SearchRowKind.album))
            .toList();
      case 'Artists':
        return _artists
            .map((s) => (song: s, kind: _SearchRowKind.artist))
            .toList();
      default:
        return _allGroups.expand((group) => group.rows).toList();
    }
  }

  Widget _buildSearchResultRow(({_Song song, _SearchRowKind kind}) row) {
    final song = row.song;
    final queue = switch (row.kind) {
      _SearchRowKind.artist => _artists,
      _SearchRowKind.album => _albums,
      _SearchRowKind.video => _videos,
      _SearchRowKind.song => _songs,
    };
    return _FoxySearchResultRow(
      song: song,
      kind: row.kind,
      onTap: row.kind == _SearchRowKind.artist
          ? () => _openArtistPage(song)
          : () => widget.onPlay(
              song,
              queue.isEmpty ? [song] : queue,
              radioTail: row.kind == _SearchRowKind.song,
            ),
      onMore: () => _openMenu(song, queue.isEmpty ? [song] : queue),
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accent = Theme.of(context).colorScheme.primary;

    final rows = _visibleRows;
    final history = List<String>.unmodifiable(_history);
    final showResults = _query.trim().length >= 2;
    return CustomScrollView(
      key: const PageStorageKey('search-scroll'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 180,
      slivers: [
        SliverToBoxAdapter(
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
                        suffixIcon: _query.isNotEmpty
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
                              selected: _filter == label,
                              onTap: () => setState(() => _filter = label),
                            ),
                        ],
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    if (history.isNotEmpty) ...[
                      Row(
                        children: [
                          const Expanded(child: _SearchSectionLabel('Recent')),
                          _FoxyGlassTextButton(
                            label: 'Clear',
                            onPressed: _clearSearchHistory,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final item in history)
                        _SearchHistoryRow(
                          query: item,
                          onTap: () => _activateSearchQuery(item),
                          onRemove: () => _removeSearchHistoryItem(item),
                        ),
                      const SizedBox(height: 12),
                    ] else
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 26, 8, 8),
                        child: Text(
                          'Search something and it will appear here.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.44),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
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
        ),
        if (showResults && _loading)
          const SliverToBoxAdapter(child: _SearchLoadingSkeleton())
        else if (showResults && rows.isEmpty && _error == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No results for "${_cleanDisplayText(_query)}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else if (showResults)
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              return _buildSearchResultRow(rows[index]);
            }, childCount: rows.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _SearchResultSnapshot {
  const _SearchResultSnapshot({
    required this.songs,
    required this.videos,
    required this.albums,
    required this.artists,
  });

  final List<_Song> songs;
  final List<_Song> videos;
  final List<_Song> albums;
  final List<_Song> artists;
}

enum _SearchRowKind { song, video, album, artist }

class _SearchLoadingSkeleton extends StatelessWidget {
  const _SearchLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: const [
          _SearchSkeletonRow(widthFactor: 0.78),
          SizedBox(height: 10),
          _SearchSkeletonRow(widthFactor: 0.62),
          SizedBox(height: 10),
          _SearchSkeletonRow(widthFactor: 0.86),
          SizedBox(height: 10),
          _SearchSkeletonRow(widthFactor: 0.7),
          SizedBox(height: 10),
          _SearchSkeletonRow(widthFactor: 0.82),
          SizedBox(height: 10),
          _SearchSkeletonRow(widthFactor: 0.58),
        ],
      ),
    );
  }
}

class _SearchSkeletonRow extends StatelessWidget {
  const _SearchSkeletonRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _HomeSkeletonBox(width: 54, height: 54, radius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                widthFactor: widthFactor.clamp(0.2, 1.0),
                alignment: Alignment.centerLeft,
                child: const _HomeSkeletonBox(
                  width: double.infinity,
                  height: 15,
                  radius: 5,
                ),
              ),
              const SizedBox(height: 8),
              FractionallySizedBox(
                widthFactor: (widthFactor * 0.72).clamp(0.2, 0.9),
                alignment: Alignment.centerLeft,
                child: const _HomeSkeletonBox(
                  width: double.infinity,
                  height: 11,
                  radius: 5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchSectionLabel extends StatelessWidget {
  const _SearchSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.46),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _SearchHistoryRow extends StatelessWidget {
  const _SearchHistoryRow({
    required this.query,
    required this.onTap,
    required this.onRemove,
  });

  final String query;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.58),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    query,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white60,
                    size: 18,
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

class _FoxySearchResultRow extends StatelessWidget {
  const _FoxySearchResultRow({
    required this.song,
    required this.kind,
    required this.onTap,
    required this.onMore,
  });

  final _Song song;
  final _SearchRowKind kind;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final isArtist = kind == _SearchRowKind.artist;
    final thumbSize = 54.0;
    final secondary = switch (kind) {
      _SearchRowKind.artist => song.artist.ifBlank('Artist'),
      _SearchRowKind.album => song.artist.ifBlank('Album'),
      _SearchRowKind.video => '${song.artist} - Video',
      _SearchRowKind.song => song.artist,
    };
    final meta = switch (kind) {
      _SearchRowKind.album => 'Album',
      _SearchRowKind.video => song.duration?.trim().ifBlank('Video') ?? 'Video',
      _SearchRowKind.song => song.duration?.trim() ?? '',
      _SearchRowKind.artist => '',
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          splashColor: Colors.white.withValues(alpha: 0.05),
          highlightColor: Colors.white.withValues(alpha: 0.03),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isArtist ? song.title.ifBlank(song.artist) : song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              secondary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.52),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: isArtist ? onTap : onMore,
                  icon: Icon(
                    isArtist
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.more_vert_rounded,
                    size: isArtist ? 18 : 24,
                    color: Colors.white.withValues(alpha: 0.82),
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

class _ArtistPage extends StatefulWidget {
  const _ArtistPage({
    required this.artist,
    required this.onPlay,
    this.artworkUrl = '',
    this.onDiscoverSearch,
  });

  final String artist;
  final String artworkUrl;
  final _FoxyOnPlay onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<_ArtistPage> {
  bool _loading = true;
  String? _error;
  String _artworkUrl = '';
  String _sourceLabel = '';
  List<_Song> _songs = const [];
  List<_Song> _albums = const [];

  @override
  void initState() {
    super.initState();
    _artworkUrl = widget.artworkUrl;
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('resolveArtistProfile', {
              'artist': widget.artist,
              'limit': 28,
            }),
          ) ??
          const {};
      List<_Song> parse(String key) => (response[key] as List? ?? const [])
          .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
          .where((song) => song.videoId.isNotEmpty)
          .toList();
      if (!mounted) return;
      final artistArt = response['artworkUrl']?.toString().trim() ?? '';
      final sourceLabel = response['sourceLabel']?.toString().trim() ?? '';
      setState(() {
        _songs = parse('songs');
        _albums = parse('albums');
        _artworkUrl = artistArt.ifBlank(_artworkUrl);
        _sourceLabel = sourceLabel;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _playArtistRadio() {
    final queue = _songs.isNotEmpty ? _songs : _albums;
    if (queue.isEmpty) {
      widget.onDiscoverSearch?.call('${widget.artist} songs');
      return;
    }
    widget.onPlay(queue.first, queue, radioTail: true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: 300,
            backgroundColor: Colors.black,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _Artwork(
                    url: _artworkUrl,
                    size: 720,
                    radius: 0,
                    highQuality: true,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.34),
                          Colors.black.withValues(alpha: 0.92),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Artist',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_sourceLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _sourceLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: _FoxyGlassButton(
                      onTap: _playArtistRadio,
                      borderRadius: BorderRadius.circular(18),
                      blurSigma: 12,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            color: accent,
                            size: 26,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Play artist radio',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _FoxyGlassButton(
                    onTap: () => widget.onDiscoverSearch?.call(widget.artist),
                    borderRadius: BorderRadius.circular(18),
                    padding: EdgeInsets.zero,
                    child: const SizedBox(
                      width: 52,
                      height: 52,
                      child: Icon(Icons.search_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 38),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
            )
          else ...[
            _ArtistSongsSliver(
              title: 'Popular',
              songs: _songs.take(10).toList(),
              kind: _SearchRowKind.song,
              onPlay: widget.onPlay,
            ),
            _ArtistSongsSliver(
              title: 'Albums',
              songs: _albums.take(8).toList(),
              kind: _SearchRowKind.album,
              onPlay: widget.onPlay,
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }
}

class _ArtistSongsSliver extends StatelessWidget {
  const _ArtistSongsSliver({
    required this.title,
    required this.songs,
    required this.kind,
    required this.onPlay,
  });

  final String title;
  final List<_Song> songs;
  final _SearchRowKind kind;
  final _FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: _SearchSectionLabel(title),
            ),
            for (final song in songs)
              _FoxySearchResultRow(
                song: song,
                kind: kind,
                onTap: () =>
                    onPlay(song, songs, radioTail: kind == _SearchRowKind.song),
                onMore: () => _showFoxySongOverflowMenu(
                  context,
                  song: song,
                  onPlay: onPlay,
                  queueForPlay: songs,
                  searchResultsForExtras: songs,
                  onLibraryChanged: () async {},
                ),
              ),
          ],
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
      borderRadius: BorderRadius.circular(20),
      blurSigma: 12,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.black87, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.15,
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
        ],
      ),
    );
  }
}

/// Metrolist-style downloads summary (storage + offline count).
class _MetrolistDownloadsHeader extends StatefulWidget {
  const _MetrolistDownloadsHeader({
    required this.songCount,
    required this.activeCount,
  });

  final int songCount;
  final int activeCount;

  @override
  State<_MetrolistDownloadsHeader> createState() =>
      _MetrolistDownloadsHeaderState();
}

class _MetrolistDownloadsHeaderState extends State<_MetrolistDownloadsHeader> {
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
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
                              ? 'Calculating storage...'
                              : '${widget.songCount} songs offline - ${_formatStorageBytes(bytes)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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

class _DownloadsPlaylistHeader extends StatefulWidget {
  const _DownloadsPlaylistHeader({
    required this.songs,
    required this.songCount,
    required this.activeCount,
    this.onPlayAll,
  });

  final List<_Song> songs;
  final int songCount;
  final int activeCount;
  final VoidCallback? onPlayAll;

  @override
  State<_DownloadsPlaylistHeader> createState() =>
      _DownloadsPlaylistHeaderState();
}

class _DownloadsPlaylistHeaderState extends State<_DownloadsPlaylistHeader> {
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
    final covers = widget.songs
        .where((song) => song.artwork.isNotEmpty)
        .take(4)
        .toList();
    final subtitle = _loading
        ? 'Calculating storage...'
        : '${widget.songCount} songs offline | ${_formatStorageBytes(bytes)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 1.9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (covers.isEmpty)
                ColoredBox(color: accent.withValues(alpha: 0.24))
              else
                _DownloadsCollage(covers: covers),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.28),
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0, 0.52, 1],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Downloads',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.activeCount > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${widget.activeCount} active download${widget.activeCount == 1 ? '' : 's'}',
                              style: TextStyle(
                                color: accent.withValues(alpha: 0.98),
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.onPlayAll != null)
                      _FoxyGlassButton(
                        onTap: widget.onPlayAll,
                        borderRadius: BorderRadius.circular(999),
                        tintOpacity: 0.34,
                        blur: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, size: 20),
                            SizedBox(width: 6),
                            Text(
                              'Play all',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ],
                        ),
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

class _DownloadsCollage extends StatelessWidget {
  const _DownloadsCollage({required this.covers});

  final List<_Song> covers;

  @override
  Widget build(BuildContext context) {
    if (covers.length == 1) {
      final song = covers.first;
      return _Artwork(
        url: song.highQualityArtwork,
        size: 800,
        radius: 0,
        highQuality: true,
        identityTag: song.videoId,
        offlineArtworkPath: song.offlineArtworkPath,
        useOfflineArtwork: song.isDownloaded,
      );
    }
    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
      ),
      itemCount: math.max(4, covers.length),
      itemBuilder: (context, index) {
        final song = covers[index % covers.length];
        return _Artwork(
          url: song.highQualityArtwork,
          size: 400,
          radius: 0,
          highQuality: true,
          identityTag: song.videoId,
          offlineArtworkPath: song.offlineArtworkPath,
          useOfflineArtwork: song.isDownloaded,
        );
      },
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    super.key,
    required this.onPlay,
    required this.onOpenSearch,
    required this.onDiscoverSearch,
  });

  final _FoxyOnPlay onPlay;
  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({
    required this.onOpenSearch,
    required this.onDiscoverSearch,
  });

  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
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

  @override
  Widget build(BuildContext context) {
    void pick(String q) => onDiscoverSearch(q);
    return CustomScrollView(
      key: const PageStorageKey('discover-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 420,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            title: 'Discover',
            subtitle: 'Quick routes into fresh music, moods, and charts',
            onSearch: onOpenSearch,
            onSparkle: () => pick('top songs charts today'),
          ),
        ),
        SliverToBoxAdapter(child: _sectionTitle('PICKS FOR YOU')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
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
                        title: 'Discover',
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
                        onTap: () =>
                            pick('latest new songs 2026 official audio'),
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
                        title: 'Energy',
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
                  subtitle: 'Hidden gems & live sessions',
                  onTap: () => pick('deep cuts live sessions'),
                ),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin {
  static const int _scopeHub = 0;
  static const int _scopeLiked = 1;
  static const int _scopeHistory = 2;
  static const int _scopeDownloads = 3;
  static const int _scopeMostPlayed = 4;
  static const int _scopePlaylists = 5;
  static const int _scopeRecognized = 6;
  static const int _scopeLocal = 7;
  static int _lastScope = _scopeHub;

  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _downloads = const [];
  List<_Song> _local = const [];
  List<_Song> _mostPlayed = const [];
  List<_Song> _recentlyAdded = const [];
  List<_UserPlaylist> _userPlaylists = const [];
  List<_RecognizedTrack> _recognized = const [];
  Map<String, dynamic> _settings = const {};
  int _scope = _lastScope;
  final Map<String, double> _downloadProgress = {};
  StreamSubscription<dynamic>? _libraryEvents;
  String _librarySignature = '';
  String _librarySettingsSignature = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _libraryEvents = _foxyEvents.listen((dynamic event) {
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
        setState(() {
          _downloadProgress
            ..clear()
            ..addAll(next);
        });
      } else if (type == 'libraryDownloadsChanged' ||
          type == 'libraryFeedChanged' ||
          type == 'accountChanged') {
        _SongMenuContextCache.invalidate();
        _load();
      }
    });
  }

  @override
  void dispose() {
    _libraryEvents?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('libraryFeed'),
      _method.invokeMethod('getAppearance'),
    ]);
    final response = _asMap(values[0]) ?? const {};
    final settings = _asMap(values[1]) ?? const {};
    if (!mounted) return;
    final liked = _songsFrom(response['liked']);
    final history = _songsFrom(response['history']);
    final downloads = _songsFrom(response['downloads']);
    final local = _songsFrom(response['local']);
    final mostPlayed = _songsFrom(response['mostPlayed']);
    final recentlyAdded = _songsFrom(
      response['recentlyAdded'],
    ).take(20).toList();
    final userPlaylists = _userPlaylistsFrom(response['userPlaylists']);
    final recognized = _recognizedTracksFrom(response['recognitionHistory']);
    final settingsSignature = (settings.keys.toList()..sort())
        .map((key) => '$key=${settings[key]}')
        .join('|');
    final signature = [
      liked.map((s) => s.videoId).join(','),
      history.take(40).map((s) => s.videoId).join(','),
      downloads.map((s) => s.videoId).join(','),
      local.map((s) => s.videoId).join(','),
      mostPlayed.take(40).map((s) => s.videoId).join(','),
      recentlyAdded.map((s) => s.videoId).join(','),
      userPlaylists.map((p) => '${p.id}:${p.songs.length}').join(','),
      recognized.map((r) => r.title).join(','),
    ].join('::');
    if (!_loading &&
        signature == _librarySignature &&
        settingsSignature == _librarySettingsSignature) {
      return;
    }
    setState(() {
      _settings = settings;
      _librarySettingsSignature = settingsSignature;
      _liked = liked;
      _history = history;
      _downloads = downloads;
      _local = local;
      _mostPlayed = mostPlayed;
      _recentlyAdded = recentlyAdded;
      _userPlaylists = userPlaylists;
      _recognized = recognized;
      _librarySignature = signature;
      _loading = false;
      if (!_libraryScopeVisible(_scope)) {
        _scope = _scopeHub;
        _lastScope = _scopeHub;
      }
    });
  }

  bool get _hub => _scope == _scopeHub;

  bool _settingBool(String key, [bool fallback = true]) =>
      _settings[key] == null ? fallback : _settings[key] == true;

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
      case _scopeRecognized:
        return const [];
      default:
        return _recentlyAdded;
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
        return 'Local library';
      case _scopeMostPlayed:
        return 'Most played';
      case _scopePlaylists:
        return 'Your playlists';
      case _scopeRecognized:
        return 'Recognized';
      default:
        return 'Recently added';
    }
  }

  void _setScope(int scope) {
    final next = scope.clamp(_scopeHub, _scopeLocal).toInt();
    if (!_libraryScopeVisible(next)) {
      _lastScope = _scopeHub;
      setState(() => _scope = _scopeHub);
      return;
    }
    _lastScope = next;
    setState(() => _scope = next);
  }

  bool _libraryScopeVisible(int scope) {
    return switch (scope) {
      _scopeLiked => _settingBool('showLikedInLibrary'),
      _scopeHistory => _settingBool('showHistoryInLibrary'),
      _scopeDownloads => _settingBool('showDownloadsInLibrary'),
      _scopeMostPlayed => _settingBool('showMostPlayedInLibrary'),
      _scopePlaylists => _settingBool('showPlaylistsInLibrary'),
      _scopeRecognized => _settingBool('showRecognizedInLibrary'),
      _scopeLocal => _settingBool('showLocalInLibrary'),
      _ => true,
    };
  }

  void _goHub() => _setScope(_scopeHub);

  /// Used from Home to jump into Library drill-ins.
  void openAtScope(int scope) {
    if (!mounted) return;
    _setScope(scope);
  }

  /// System back: leave a library drill-in (Liked, History, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦) before tabs handle back.
  bool consumeAndroidBack() {
    if (_hub) return false;
    _goHub();
    return true;
  }

  Future<void> _importLocalAudio({required bool folder}) async {
    try {
      final response = _asMap(
        await _method.invokeMethod(
          folder ? 'importLocalFolder' : 'importLocalAudio',
        ),
      );
      if (!mounted) return;
      final cancelled = response?['cancelled'] == true;
      if (cancelled) return;
      final imported = ((response?['imported'] ?? 0) as num).toInt();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            imported > 0
                ? 'Imported $imported local songs'
                : 'No new supported audio found',
          ),
        ),
      );
      await _load();
      if (mounted) setState(() => _scope = _scopeLocal);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  void _openSongOverflow(BuildContext context, _Song song, List<_Song> queue) {
    _showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: queue,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: _load,
    );
  }

  Future<void> _playUserPlaylist(
    BuildContext snackContext,
    _UserPlaylist p,
  ) async {
    await _playFetchedUserPlaylist(snackContext, p, widget.onPlay);
  }

  void _shuffleCurrent() {
    final s = _activeSongs;
    if (s.isEmpty) return;
    final list = List<_Song>.from(s)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  Future<void> _playRecognizedTrack(
    BuildContext context,
    _RecognizedTrack item,
  ) async {
    try {
      final raw = _asMap(
        await _method.invokeMethod('resolveRecognizedTrack', {
          'title': item.title,
          'artist': item.artist,
          'youtubeVideoId': item.youtubeVideoId,
          'spotifyUrl': item.spotifyUrl,
        }),
      );
      final songMap = _asMap(raw?['song']);
      if (songMap == null) throw Exception('No playable match found');
      final song = _Song.fromMap(songMap);
      widget.onPlay(song, [song]);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not resolve ${item.title} right now')),
      );
    }
  }

  Future<void> _clearRecognitionHistory(BuildContext context) async {
    await _method.invokeMethod('clearRecognitionHistory');
    if (!context.mounted) return;
    setState(() => _recognized = const []);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recognition history cleared')),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('New playlist'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (name == null || name.isEmpty || !mounted) return;
      await _method.invokeMethod('playlistCreate', {'name': name});
      await _load();
    } finally {
      controller.dispose();
    }
  }

  Widget _librarySectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
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

  Widget _hubGrid() {
    final collectionTiles = <Widget>[
      if (_libraryScopeVisible(_scopeLiked))
        _LibraryRichTile(
          color: const Color(0xFFF48FB1),
          icon: Icons.favorite_rounded,
          title: 'Liked',
          subtitle: '${_liked.length} songs',
          onTap: () => _setScope(_scopeLiked),
        ),
      if (_libraryScopeVisible(_scopeDownloads))
        _LibraryRichTile(
          color: const Color(0xFF64B5F6),
          icon: Icons.download_rounded,
          title: 'Downloads',
          subtitle: '${_downloads.length} offline',
          onTap: () => _setScope(_scopeDownloads),
        ),
      if (_libraryScopeVisible(_scopeHistory))
        _LibraryRichTile(
          color: const Color(0xFFFFB74D),
          icon: Icons.history_rounded,
          title: 'History',
          subtitle: '${_history.length} played',
          onTap: () => _setScope(_scopeHistory),
        ),
      if (_libraryScopeVisible(_scopeMostPlayed))
        _LibraryRichTile(
          color: const Color(0xFF81C784),
          icon: Icons.trending_up_rounded,
          title: 'Most played',
          subtitle: '${_mostPlayed.length} tracks',
          onTap: () => _setScope(_scopeMostPlayed),
        ),
      if (_libraryScopeVisible(_scopeLocal))
        _LibraryRichTile(
          color: const Color(0xFF90CAF9),
          icon: Icons.library_music_rounded,
          title: 'Local library',
          subtitle: _local.isEmpty
              ? 'Device songs'
              : '${_local.length} local songs',
          onTap: () => _setScope(_scopeLocal),
        ),
      if (_libraryScopeVisible(_scopePlaylists))
        _LibraryRichTile(
          color: const Color(0xFFA5D6A7),
          icon: Icons.playlist_play_rounded,
          title: 'Playlists',
          subtitle: '${_userPlaylists.length} saved mixes',
          onTap: () => _setScope(_scopePlaylists),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = ((constraints.maxWidth - 42) / 2).clamp(142.0, 260.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _librarySectionTitle('YOUR COLLECTION'),
              if (collectionTiles.isEmpty)
                Text(
                  'Enable collection shortcuts in Settings.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final tile in collectionTiles)
                      SizedBox(width: tileWidth, height: 76, child: tile),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final songs = _activeSongs;
    final chips = <(IconData, String, int)>[
      (Icons.library_music_rounded, 'Library', _scopeHub),
      (Icons.favorite_rounded, 'Liked', _scopeLiked),
      (Icons.history_rounded, 'History', _scopeHistory),
      (Icons.download_rounded, 'Downloads', _scopeDownloads),
      (Icons.trending_up_rounded, 'Most played', _scopeMostPlayed),
      (Icons.playlist_play_rounded, 'Playlists', _scopePlaylists),
      (Icons.library_music_rounded, 'Local', _scopeLocal),
      (Icons.music_note_rounded, 'Recognized', _scopeRecognized),
    ].where((item) => _libraryScopeVisible(item.$3)).toList(growable: false);

    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 400,
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            leading: !_hub
                ? _GlassIconButton(
                    tooltip: 'Back to Library',
                    icon: Icons.arrow_back_rounded,
                    onPressed: _goHub,
                    plain: true,
                  )
                : null,
            title: _hub ? 'Library' : _sectionTitle,
            subtitle: _hub
                ? '${_liked.length} liked - ${_downloads.length} offline - ${_userPlaylists.length} playlists'
                : 'Library',
            onRefresh: _load,
            onSearch: widget.onOpenSearch,
            onDownloads: _hub ? () => _setScope(_scopeDownloads) : null,
            onLocalLibrary: _hub ? () => _setScope(_scopeLocal) : null,
          ),
        ),
        if (_scope == _scopeDownloads)
          SliverToBoxAdapter(
            child: _DownloadsPlaylistHeader(
              songs: _downloads,
              songCount: _downloads.length,
              activeCount: _downloadProgress.length,
              onPlayAll: _downloads.isEmpty
                  ? null
                  : () => widget.onPlay(_downloads.first, _downloads),
            ),
          ),
        if (!_hub && _scope != _scopeDownloads)
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
                          onTap: () => _setScope(chip.$3),
                          selected: _scope == chip.$3,
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
        if (_hub) ...[SliverToBoxAdapter(child: _hubGrid())],
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, _hub ? 16 : 12, 18, 8),
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
                if (_scope == _scopeRecognized && _recognized.isNotEmpty) ...[
                  TextButton.icon(
                    onPressed: () => _clearRecognitionHistory(context),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Clear'),
                  ),
                ] else if (_scope == _scopePlaylists) ...[
                  TextButton.icon(
                    onPressed: () => _createPlaylist(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New'),
                  ),
                ] else if (_scope == _scopeLocal) ...[
                  TextButton.icon(
                    onPressed: () => _importLocalAudio(folder: false),
                    icon: const Icon(Icons.library_add_rounded, size: 18),
                    label: const Text('Songs'),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Add folder',
                    onPressed: () => _importLocalAudio(folder: true),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.create_new_folder_rounded),
                  ),
                ] else if (songs.isNotEmpty && _scope != _scopePlaylists) ...[
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
                    onPressed: () => widget.onPlay(songs.first, songs),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Play'),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_scope == _scopeDownloads && _downloadProgress.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(_kCardRadius),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
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
                      for (final e in _downloadProgress.entries)
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
                                  color: Colors.white.withValues(alpha: 0.85),
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.9),
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
          ),
        if (_scope == _scopePlaylists)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  if (_userPlaylists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Create a playlist with "New" above, add songs from the menu, or sign in on the Account tab to load your YouTube Music playlists.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    for (final p in _userPlaylists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: p.songs.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: _Artwork(
                                      url: p.songs.first.homeArtwork,
                                      size: 48,
                                      radius: 0,
                                      fit: BoxFit.cover,
                                      identityTag: p.songs.first.videoId,
                                      offlineArtworkPath:
                                          p.songs.first.offlineArtworkPath,
                                      useOfflineArtwork:
                                          p.songs.first.isDownloaded,
                                    ),
                                  )
                                : Icon(
                                    p.isYoutube
                                        ? Icons.cloud_queue_rounded
                                        : Icons.queue_music_rounded,
                                  ),
                            title: Text(p.name),
                            subtitle: Text(
                              p.isYoutube
                                  ? '${p.displayTrackCount} songs - YouTube Music'
                                  : '${p.displayTrackCount} songs - On device',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_arrow_rounded),
                              onPressed: () => _playUserPlaylist(context, p),
                            ),
                            onTap: () => _playUserPlaylist(context, p),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_scope == _scopeRecognized && _recognized.isNotEmpty)
          SliverList.builder(
            itemCount: _recognized.length,
            itemBuilder: (context, index) {
              final item = _recognized[index];
              return _RecognizedHistoryTile(
                item: item,
                onTap: () => _playRecognizedTrack(context, item),
              );
            },
          )
        else if (songs.isEmpty &&
            _scope != _scopePlaylists &&
            _scope != _scopeRecognized)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_sectionTitle),
              title: 'Nothing here yet',
              subtitle:
                  'Play music, like tracks, and download for offline - your library grows automatically.',
            ),
          )
        else if (_scope == _scopeRecognized)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: Icons.music_note_rounded,
              title: 'No recognized songs yet',
              subtitle:
                  'Use the song finder and your identified tracks will land here.',
            ),
          )
        else if (_scope != _scopePlaylists && songs.isNotEmpty)
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _FoxySearchResultRow(
                song: song,
                kind: _SearchRowKind.song,
                onTap: () => widget.onPlay(song, songs),
                onMore: () => _openSongOverflow(context, song, songs),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _RecognizedHistoryTile extends StatelessWidget {
  const _RecognizedHistoryTile({required this.item, required this.onTap});

  final _RecognizedTrack item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final when = DateTime.fromMillisecondsSinceEpoch(item.recognizedAt);
    final stamp =
        '${when.day.toString().padLeft(2, '0')}/${when.month.toString().padLeft(2, '0')} - ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    return _FoxySearchResultRow(
      song: _Song(
        videoId: item.youtubeVideoId ?? 'recognized-${item.id}',
        title: item.title,
        artist: item.artist,
        artwork: item.coverArtUrl,
        duration: stamp,
      ),
      kind: _SearchRowKind.song,
      onTap: onTap,
      onMore: onTap,
    );
  }
}

class _AccountHubBody extends StatefulWidget {
  const _AccountHubBody({required this.onPlay});

  final _FoxyOnPlay onPlay;

  @override
  State<_AccountHubBody> createState() => _AccountHubBodyState();
}

class _AccountHubBodyState extends State<_AccountHubBody>
    with AutomaticKeepAliveClientMixin {
  Map<String, dynamic> _appearance = const {};
  Map<String, dynamic> _account = const {};
  Map<String, List<_Song>> _library = const {};
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
    };
    if (mounted) {
      setState(() {
        _appearance = appearance;
        _account = account;
        _library = library;
      });
    }
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
                  onTap: signedIn
                      ? null
                      : () => _method.invokeMethod('openWebLogin', {
                          'mode': 'webview',
                        }),
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
        if (songs.isEmpty)
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
            itemBuilder: (context, index) {
              final song = songs[index];
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 10,
                onTap: () => widget.onPlay(song, songs),
              );
            },
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
    id: _cleanDisplayText(map['id']),
    name: _cleanDisplayText(map['name'], fallback: 'Playlist'),
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList(),
    source: _cleanDisplayText(map['source'], fallback: 'local'),
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

class _RecognizedTrack {
  const _RecognizedTrack({
    required this.id,
    required this.recognizedAt,
    required this.title,
    required this.artist,
    required this.coverArtUrl,
    this.youtubeVideoId,
    this.spotifyUrl,
  });

  factory _RecognizedTrack.fromMap(Map<String, dynamic> map) {
    final result = _asMap(map['result']) ?? const {};
    final hqCover = result['coverArtHqUrl']?.toString().trim() ?? '';
    final baseCover = result['coverArtUrl']?.toString().trim() ?? '';
    final youtubeVideoId = result['youtubeVideoId']?.toString().trim() ?? '';
    final spotifyUrl = result['spotifyUrl']?.toString().trim() ?? '';
    final cover = hqCover.isNotEmpty ? hqCover : baseCover;
    return _RecognizedTrack(
      id: ((map['id'] ?? 0) as num).toInt(),
      recognizedAt: ((map['recognizedAt'] ?? 0) as num).toInt(),
      title: _cleanDisplayText(result['title'], fallback: 'Unknown track'),
      artist: _cleanDisplayText(result['artist'], fallback: 'Unknown artist'),
      coverArtUrl: cover,
      youtubeVideoId: youtubeVideoId.isEmpty ? null : youtubeVideoId,
      spotifyUrl: spotifyUrl.isEmpty ? null : spotifyUrl,
    );
  }

  final int id;
  final int recognizedAt;
  final String title;
  final String artist;
  final String coverArtUrl;
  final String? youtubeVideoId;
  final String? spotifyUrl;
}

List<_UserPlaylist> _userPlaylistsFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _UserPlaylist.fromMap(_asMap(e) ?? const {}))
        .where((p) => p.id.isNotEmpty)
        .toList();

List<_RecognizedTrack> _recognizedTracksFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _RecognizedTrack.fromMap(_asMap(e) ?? const {}))
        .where((item) => item.title.isNotEmpty)
        .toList();

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

class _SongMenuContextCache {
  static Map<String, dynamic>? _feed;
  static Map<String, dynamic>? _appearance;
  static DateTime? _loadedAt;

  static bool get _fresh {
    final t = _loadedAt;
    if (t == null || _feed == null || _appearance == null) return false;
    return DateTime.now().difference(t) < const Duration(seconds: 12);
  }

  static (Map<String, dynamic>, Map<String, dynamic>)? snapshot() {
    if (!_fresh) return null;
    return (_feed!, _appearance!);
  }

  static Future<(Map<String, dynamic>, Map<String, dynamic>)> load() async {
    if (_fresh) return (_feed!, _appearance!);
    final values = await Future.wait<dynamic>([
      _method.invokeMethod('songMenuContext'),
      _method.invokeMethod('getAppearance'),
    ]);
    _feed = _asMap(values[0]) ?? const {};
    _appearance = _asMap(values[1]) ?? const {};
    _loadedAt = DateTime.now();
    return (_feed!, _appearance!);
  }

  static void invalidate() {
    _feed = null;
    _appearance = null;
    _loadedAt = null;
  }
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
  VoidCallback? onOpenLyricsTabInPlayer,
  bool showRemoveFromQueue = false,
  bool compactPlayerMenu = false,
}) async {
  final cached = _SongMenuContextCache.snapshot();
  final menuContextFuture = cached == null
      ? _SongMenuContextCache.load()
      : Future.value(cached);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => FutureBuilder<(Map<String, dynamic>, Map<String, dynamic>)>(
      future: menuContextFuture,
      builder: (ctx, snapshot) {
        if (!snapshot.hasData && !snapshot.hasError) {
          return SafeArea(
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
                      url: song.highQualityArtwork,
                      size: 52,
                      radius: 10,
                      identityTag: song.videoId,
                      highQuality: true,
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
                  const Divider(height: 1),
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 8),
                  for (final label in const [
                    'Like',
                    'Download',
                    'Add to a playlist',
                    'Add to queue',
                  ])
                    ListTile(
                      enabled: false,
                      leading: const Icon(Icons.more_horiz_rounded),
                      title: Text(label),
                    ),
                ],
              ),
            ),
          );
        }
        final (feed, appearance) = snapshot.data ?? (const {}, const {});
        final likedIds = Set<String>.from(
          _songsFrom(feed['liked']).map((s) => s.videoId),
        );
        final downloadedIds = Set<String>.from(
          _songsFrom(feed['downloads']).map((s) => s.videoId),
        );
        final userPlaylists = _userPlaylistsFrom(feed['userPlaylists']);
        final crossfadeMs = ((appearance['crossfadeMs'] ?? 0) as num).toInt();
        final crossfadeOn = crossfadeMs > 0;
        final romanize = appearance['lyricsRomanize'] == true;
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
                      url: song.highQualityArtwork,
                      size: 52,
                      radius: 10,
                      identityTag: song.videoId,
                      highQuality: true,
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
                  const Divider(height: 1),
                  if (!compactPlayerMenu &&
                      searchResultsForExtras != null &&
                      searchResultsForExtras.length > 1) ...[
                    ListTile(
                      leading: const Icon(Icons.podcasts_outlined),
                      title: const Text('Play with smart radio'),
                      subtitle: const Text('Builds a station from this track'),
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
                      _SongMenuContextCache.invalidate();
                      await onLibraryChanged?.call();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      downloadedIds.contains(song.videoId) || song.isDownloaded
                          ? Icons.offline_pin_rounded
                          : Icons.download_outlined,
                    ),
                    title: Text(
                      downloadedIds.contains(song.videoId) || song.isDownloaded
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
                      _SongMenuContextCache.invalidate();
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
                  if (!compactPlayerMenu)
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
                  if (!compactPlayerMenu)
                    ListTile(
                      leading: const Icon(Icons.radio_rounded),
                      title: const Text('Start smart radio'),
                      subtitle: const Text(
                        'Genre-aware station from this track (Metrolist-style)',
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onPlay(song, [song], radioTail: true);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.translate_rounded),
                    title: const Text('Romanize lyrics'),
                    subtitle: Text(
                      romanize
                          ? 'On - show Romanized lyrics when available'
                          : 'Off - show original lyrics text',
                    ),
                    trailing: Switch(
                      value: romanize,
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
                                  ? 'Romanized lyrics on.'
                                  : 'Romanized lyrics off.',
                            ),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('setAppearance', {
                        'lyricsRomanize': !romanize,
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
                          ? 'Crossfade is on - speed changes may sound uneven.'
                          : 'Quick presets (applies to the native player)',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      await _showPlaybackPitchSheet(context);
                    },
                  ),
                  if (onOpenLyricsTabInPlayer != null)
                    ListTile(
                      leading: const Icon(Icons.open_in_new_rounded),
                      title: const Text('Open synced lyrics tab'),
                      subtitle: const Text('Full-width lyrics in this player'),
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
                  if (!compactPlayerMenu)
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
              ),
            ),
          ),
        );
      },
    ),
  );
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
                _SongMenuContextCache.invalidate();
                await onChanged?.call();
                final libraryFeed =
                    _asMap(await _method.invokeMethod('libraryFeed')) ??
                    const {};
                if (!context.mounted) return;
                await _pickPlaylistToAddSong(
                  context,
                  song: song,
                  playlists: _userPlaylistsFrom(libraryFeed['userPlaylists']),
                  onChanged: onChanged,
                );
              }
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
                          ? '${p.displayTrackCount} songs - YouTube Music'
                          : '${p.displayTrackCount} songs - On device',
                    ),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _method.invokeMethod('playlistAddSong', {
                        'playlistId': p.id,
                        'song': song.toMap(),
                      });
                      _SongMenuContextCache.invalidate();
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

Future<void> _showPlaybackPitchSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF121212),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      Future<void> apply(double speed, double pitch) async {
        await _method.invokeMethod('setPlaybackSpeed', {
          'speed': speed,
          'pitch': pitch,
        });
      }

      Widget preset(String label, double speed, double pitch) {
        return _FoxyGlassButton(
          onTap: () async {
            await apply(speed, pitch);
            if (ctx.mounted) Navigator.pop(ctx);
          },
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${speed}x - pitch ${pitch}x',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const Text(
                'Playback speed & pitch',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                'Quick presets. Pitch stays natural unless you choose a pitch preset.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  preset('Normal', 1.0, 1.0),
                  preset('Slow', 0.85, 1.0),
                  preset('Nightcore', 1.15, 1.08),
                  preset('Podcast', 1.25, 1.0),
                  preset('Chipmunk', 1.0, 1.18),
                  preset('Deep', 1.0, 0.88),
                ],
              ),
            ],
          ),
        ),
      );
    },
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
    case 'Most played':
      return Icons.trending_up_rounded;
    case 'Recently added':
      return Icons.library_add_rounded;
    default:
      return Icons.favorite_rounded;
  }
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
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
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF181818),
            border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
          ),
          child: Column(
            children: [
              _FoxyAppLogo(size: 132, borderRadius: 30),
              const SizedBox(height: 18),
              const Text(
                'FoxyMusic',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AboutPill(
                    label: _kAppVersionLabel,
                    icon: Icons.bolt_rounded,
                  ),
                  const _AboutPill(
                    label: 'Flutter + Kotlin',
                    icon: Icons.layers_rounded,
                  ),
                  const _AboutPill(
                    label: 'Open source',
                    icon: Icons.code_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'A fast, glassy music player built around FoxyMusic vibes: clean playback, live lyrics, smart discovery, and a native audio engine.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, height: 1.42, fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: const [
            _AboutFeatureChip(
              icon: Icons.graphic_eq_rounded,
              title: 'Ultra audio',
              subtitle: 'YT + SoundCloud resolver',
            ),
            _AboutFeatureChip(
              icon: Icons.lyrics_rounded,
              title: 'Synced lyrics',
              subtitle: 'LRCLIB + romanized text',
            ),
            _AboutFeatureChip(
              icon: Icons.blur_on_rounded,
              title: 'Foxy glass',
              subtitle: 'Adaptive player visuals',
            ),
            _AboutFeatureChip(
              icon: Icons.manage_search_rounded,
              title: 'Discovery',
              subtitle: 'Moods, charts, search',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kCardRadius),
            color: const Color(0xFF181818),
            border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
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
          subtitle: 'Source, releases, and credits',
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
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => showLicensePage(context: context),
                icon: const Icon(Icons.article_outlined, size: 20),
                label: const Text('Open-source licenses'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Release $_kAppVersionName - FoxyMusic',
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

class _AboutPill extends StatelessWidget {
  const _AboutPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutFeatureChip extends StatelessWidget {
  const _AboutFeatureChip({
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
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 56) / 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.065),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
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

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.appearance,
    required this.onSetAppearance,
    this.onAppearancePatched,
    this.account = const <String, dynamic>{},
    this.onAccountRefresh,
    this.onOpenAccountHub,
  });

  final Map<String, dynamic> appearance;
  final Future<void> Function(Map<String, dynamic> patch) onSetAppearance;
  final ValueChanged<Map<String, dynamic>>? onAppearancePatched;
  final Map<String, dynamic> account;
  final Future<void> Function()? onAccountRefresh;
  final VoidCallback? onOpenAccountHub;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late Map<String, dynamic> _m;
  _FoxySettingsPage _settingsPage = _FoxySettingsPage.home;

  @override
  void initState() {
    super.initState();
    _m = Map<String, dynamic>.from(widget.appearance);
  }

  @override
  void didUpdateWidget(covariant _SettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mapEquals(oldWidget.appearance, widget.appearance)) {
      setState(() => _m = Map<String, dynamic>.from(widget.appearance));
    }
  }

  Future<void> _reloadAppearanceSnapshot() async {
    final fresh = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || fresh == null) return;
    setState(() => _m = Map<String, dynamic>.from(fresh));
  }

  Future<void> _apply(Map<String, dynamic> patch) async {
    final optimistic = Map<String, dynamic>.from(_m)..addAll(patch);
    setState(() => _m = optimistic);
    widget.onAppearancePatched?.call(Map<String, dynamic>.from(optimistic));
    await widget.onSetAppearance(patch);
    if (!mounted) return;
    await _reloadAppearanceSnapshot();
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

  Future<void> _runSettingsAction({
    required String method,
    required String success,
    required String failure,
  }) async {
    try {
      await _method.invokeMethod(method);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
      await _reloadAppearanceSnapshot();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$failure: $e')));
    }
  }

  Future<void> _showAccountHealth() async {
    try {
      final raw = _asMap(await _method.invokeMethod('accountInfo')) ?? const {};
      if (!mounted) return;
      final signedIn = raw['isSignedIn'] == true;
      final rows = <(String, String)>[
        ('YouTube', signedIn ? 'Connected' : 'Guest mode'),
        (
          'Name',
          raw['displayName']?.toString().ifBlank('Not available') ??
              'Not available',
        ),
        (
          'Email',
          raw['email']?.toString().ifBlank('Not available') ?? 'Not available',
        ),
        ('Liked songs', '${(raw['likedCount'] as num?)?.toInt() ?? 0}'),
        ('Downloads', '${(raw['downloadCount'] as num?)?.toInt() ?? 0}'),
        ('Playlists', '${(raw['playlistCount'] as num?)?.toInt() ?? 0}'),
      ];
      await _showSettingsInfoDialog(
        title: 'Account health',
        subtitle: signedIn
            ? 'Cookies and library snapshot are available.'
            : 'Sign in inside FoxyMusic to sync account shelves.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Account check failed: $e')));
    }
  }

  Future<void> _showPlaybackDiagnostics() async {
    try {
      final player =
          _asMap(await _method.invokeMethod('getPlayerState')) ?? const {};
      final settings =
          _asMap(await _method.invokeMethod('getAppearance')) ?? _m;
      if (!mounted) return;
      final bitrate = (player['streamBitrate'] as num?)?.toInt();
      final rows = <(String, String)>[
        ('State', player['isPlaying'] == true ? 'Playing' : 'Paused / idle'),
        ('Buffering', player['isBuffering'] == true ? 'Yes' : 'No'),
        (
          'Source',
          player['streamSource']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'Codec',
          player['streamCodec']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'MIME',
          player['streamMimeType']?.toString().ifBlank('Unknown') ?? 'Unknown',
        ),
        (
          'Bitrate',
          bitrate == null ? 'Unknown' : '${(bitrate / 1000).round()} kbps',
        ),
        (
          'Stream quality',
          _qualityLabel(((settings['streamQualityTier'] ?? 2) as num).toInt()),
        ),
        (
          'Crossfade',
          '${((settings['crossfadeMs'] ?? 0) as num).toInt() ~/ 1000}s',
        ),
      ];
      await _showSettingsInfoDialog(
        title: 'Playback diagnostics',
        subtitle: 'Live stream and quality state from the native player.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Diagnostics failed: $e')));
    }
  }

  Future<void> _showStorageStatus() async {
    try {
      final storage =
          _asMap(await _method.invokeMethod('storageStats')) ?? const {};
      final backup =
          _asMap(await _method.invokeMethod('backupStatus')) ?? const {};
      if (!mounted) return;
      final rows = <(String, String)>[
        (
          'Downloads',
          _formatStorageBytes((storage['downloadBytes'] as num?) ?? 0),
        ),
        (
          'Stream cache',
          _formatStorageBytes((storage['cacheBytes'] as num?) ?? 0),
        ),
        (
          'Latest backup',
          backup['fileName']?.toString().ifBlank('None yet') ?? 'None yet',
        ),
        ('Backup size', _formatStorageBytes((backup['bytes'] as num?) ?? 0)),
        (
          'Backup file',
          backup['exists'] == true ? 'Ready to restore' : 'None yet',
        ),
      ];
      await _showSettingsInfoDialog(
        title: 'Storage status',
        subtitle: 'Foxy quick quick glance for cache, downloads, and backups.',
        rows: rows,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Storage status failed: $e')));
    }
  }

  Future<void> _showSettingsInfoDialog({
    required String title,
    required String subtitle,
    required List<(String, String)> rows,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle),
              const SizedBox(height: 14),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 112,
                        child: Text(
                          row.$1,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Expanded(child: Text(row.$2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(int tier) {
    return switch (tier) {
      -1 => 'Follow default',
      0 => 'Low - 96 kbps',
      1 => 'Balanced - 160 kbps',
      2 => 'Normal - 220 kbps',
      3 => 'High - 320 kbps',
      _ => 'Ultra - best available',
    };
  }

  Future<void> _showTierPicker({
    required String title,
    required int currentValue,
    required Future<void> Function(int value) onChanged,
  }) async {
    var selected = currentValue;
    final next = await showDialog<int>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF2C2A31),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
          child: StatefulBuilder(
            builder: (context, setLocalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final item in const [
                    (0, 'Low - 96 kbps'),
                    (1, 'Balanced - 160 kbps'),
                    (2, 'Normal - 220 kbps'),
                    (3, 'High - 320 kbps'),
                    (4, 'Ultra - best available'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setLocalState(() => selected = item.$1),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected == item.$1
                                  ? Theme.of(context).colorScheme.primary
                                        .withValues(alpha: 0.72)
                                  : Colors.white.withValues(alpha: 0.12),
                              width: selected == item.$1 ? 1.35 : 1,
                            ),
                            color: selected == item.$1
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.08)
                                : Colors.white.withValues(alpha: 0.02),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected == item.$1
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                color: selected == item.$1
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white.withValues(alpha: 0.78),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  item.$2,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, selected),
                        child: const Text('Change'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (next == null || next == currentValue) return;
    await onChanged(next);
  }

  Future<void> _openWebLogin([String mode = 'webview']) async {
    final ok =
        await _method.invokeMethod('openWebLogin', {'mode': mode}) == true;
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mode == 'ytmapp' || mode == 'ytm_app' || mode == 'app'
                ? 'Could not open YouTube Music on this device'
                : 'Could not open sign-in on this device',
          ),
        ),
      );
      return;
    }
    if (mode == 'ytmapp' || mode == 'ytm_app' || mode == 'app') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'If you use the YouTube Music app first, come back and tap "Sign in inside FoxyMusic" to finish. Google does not share that login with other apps.',
          ),
          duration: Duration(seconds: 7),
        ),
      );
    }
  }

  Future<void> _signOutYoutube() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out of YouTube?'),
        content: const Text(
          'You stay in the app as a guest until you connect again using Sign in inside FoxyMusic.',
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
    if (confirm != true || !mounted) return;
    try {
      await _method.invokeMethod('accountSignOut');
    } catch (_) {}
    await widget.onAccountRefresh?.call();
    if (mounted) setState(() {});
  }

  Future<void> _pickHomeBackground() async {
    try {
      final raw = _asMap(await _method.invokeMethod('pickHomeBackground'));
      if (!mounted) return;
      if (raw?['ok'] == true) {
        await _apply({'homeBackgroundEnabled': true});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Custom background applied')),
          );
        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Default background restored')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  void _clearFlutterImageCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Image cache cleared')));
  }

  @override
  Widget build(BuildContext context) {
    final persistent = _bool('persistentQueue', true);
    final saveHistory = _bool('saveHistory', true);
    final sponsor = _bool('sponsorBlockEnabled', true);
    final lrclib = _bool('lyricsPreferLrclib', true);
    final norm = _bool('normalizeVolume');
    final skipSil = _bool('skipSilence');
    final backup = _bool('autoBackupEnabled');
    final tier = _int('streamQualityTier', 2).clamp(0, 4);
    final downloadTier = _int('downloadQualityTier', 2).clamp(0, 4);
    final cross = _int('crossfadeMs', 0);
    final continueDismiss = _bool('continuePlaybackWhenDismissed');
    final romanize = _bool('lyricsRomanize');
    final blurEffects = _bool('blurEffects', true);
    final disableAnimations = _bool('disableAnimations');
    final haptics = _bool('hapticFeedback', true);
    final enableLiquidGlassLayout = _bool('enableLiquidGlassLayout');
    final playerButtonsStyle = _int('playerButtonsStyle', 0).clamp(0, 2);
    final playerProgressStyle = _int('playerProgressStyle', 0).clamp(0, 1);
    final hidePlayerArtwork = _bool('hidePlayerArtwork');
    final artworkDisplayStyle = _int('artworkDisplayStyle', 0).clamp(0, 2);
    final thumbnailCornerRadius = _int(
      'thumbnailCornerRadius',
      16,
    ).clamp(0, 40);
    final defaultOpenTab = _int('defaultOpenTab', 0);
    final quickPicksDisplayMode = _int('quickPicksDisplayMode', 0).clamp(0, 1);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: _FoxyGlassTint(
            borderRadius: 24,
            tintOpacity: 0.22,
            borderOpacity: 0.1,
            showBottomBorder: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.035),
                    Colors.white.withValues(alpha: 0.012),
                    Colors.black.withValues(alpha: 0.04),
                  ],
                  stops: const [0.0, 0.32, 1.0],
                ),
              ),
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
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (_settingsPage != _FoxySettingsPage.home) ...[
                              IconButton(
                                tooltip: 'Back',
                                onPressed: () => setState(
                                  () => _settingsPage = _FoxySettingsPage.home,
                                ),
                                icon: const Icon(Icons.arrow_back_rounded),
                              ),
                              const SizedBox(width: 2),
                            ],
                            Expanded(
                              child: Text(
                                _settingsPage.title,
                                style: const TextStyle(
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
                        const SizedBox(height: 6),
                        Text(
                          _settingsPage.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: disableAnimations
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      child: switch (_settingsPage) {
                        _FoxySettingsPage.home => _buildSettingsHome(
                          controller,
                        ),
                        _FoxySettingsPage.account => _buildAccountSettings(
                          controller,
                        ),
                        _FoxySettingsPage.playback => _buildPlaybackSettings(
                          controller,
                          persistent: persistent,
                          continueDismiss: continueDismiss,
                          saveHistory: saveHistory,
                          sponsor: sponsor,
                          tier: tier,
                          downloadTier: downloadTier,
                          cross: cross,
                          norm: norm,
                          skipSil: skipSil,
                        ),
                        _FoxySettingsPage.appearance => _buildAppearanceTab(
                          controller,
                          enableLiquidGlassLayout: enableLiquidGlassLayout,
                          playerButtonsStyle: playerButtonsStyle,
                          playerProgressStyle: playerProgressStyle,
                          hidePlayerArtwork: hidePlayerArtwork,
                          artworkDisplayStyle: artworkDisplayStyle,
                          thumbnailCornerRadius: thumbnailCornerRadius,
                        ),
                        _FoxySettingsPage.lyrics => _buildLyricsSettings(
                          controller,
                          lrclib: lrclib,
                          romanize: romanize,
                        ),
                        _FoxySettingsPage.storage => _buildStorageSettings(
                          controller,
                          backup: backup,
                        ),
                        _FoxySettingsPage.advanced => _buildAdvancedSettings(
                          controller,
                          blurEffects: blurEffects,
                          disableAnimations: disableAnimations,
                          haptics: haptics,
                          defaultOpenTab: defaultOpenTab,
                          quickPicksDisplayMode: quickPicksDisplayMode,
                          recognitionSource: _int(
                            'recognitionSource',
                            0,
                          ).clamp(0, 1),
                          recognitionHistoryLimit: _int(
                            'recognitionHistoryLimit',
                            40,
                          ).clamp(10, 100),
                        ),
                        _FoxySettingsPage.about => ListView(
                          key: const ValueKey('settings-about'),
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                          children: [
                            _AboutUsPanel(onOpenExternal: _openExternal),
                          ],
                        ),
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountSettings(ScrollController controller) {
    return ListView(
      key: const ValueKey('settings-account'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        Builder(
          builder: (context) {
            final signedIn = widget.account['isSignedIn'] == true;
            final email = widget.account['email']?.toString() ?? '';
            return _SettingsCard(
              title: 'YouTube',
              subtitle: signedIn
                  ? (email.isNotEmpty ? email : 'Signed in')
                  : 'Sign in inside FoxyMusic, or use the YouTube Music app then finish here',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openWebLogin('webview'),
                    icon: const Icon(Icons.lock_open_rounded, size: 20),
                    label: Text(
                      signedIn ? 'Add another account' : 'Add an account',
                    ),
                  ),
                  if (signedIn) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _signOutYoutube,
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Sign out'),
                    ),
                  ],
                  if (widget.onOpenAccountHub != null) ...[
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: widget.onOpenAccountHub,
                        child: const Text('Account overview'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _showAccountHealth,
                    icon: const Icon(Icons.verified_user_rounded, size: 20),
                    label: const Text('Account health check'),
                  ),
                ],
              ),
            );
          },
        ),
        _SettingsCard(
          title: 'How this works',
          subtitle:
              'FoxyMusic stores only the YouTube Music WebView session cookie needed for personalized shelves and account playlists.',
          child: const Text(
            'The recommended WebView method clears older WebView cookies before login, saves automatically after YouTube Music opens, and then reads your account profile. Manual cookie login is available as a fallback.',
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackSettings(
    ScrollController controller, {
    required bool persistent,
    required bool continueDismiss,
    required bool saveHistory,
    required bool sponsor,
    required int tier,
    required int downloadTier,
    required int cross,
    required bool norm,
    required bool skipSil,
  }) {
    return ListView(
      key: const ValueKey('settings-playback'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Stream quality',
          subtitle:
              'Ultra compares YouTube and SoundCloud and picks the best available stream, aiming above 240 kbps and lossless-like formats when possible.',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              title: Text(_qualityLabel(tier)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showTierPicker(
                title: 'Stream quality',
                currentValue: tier,
                onChanged: (value) => _apply({'streamQualityTier': value}),
              ),
            ),
          ),
        ),
        _SettingsCard(
          title: 'Download quality',
          subtitle:
              'Separate offline target so downloads can stay lighter or go all the way up.',
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              title: Text(_qualityLabel(downloadTier)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showTierPicker(
                title: 'Download quality',
                currentValue: downloadTier,
                onChanged: (value) => _apply({'downloadQualityTier': value}),
              ),
            ),
          ),
        ),
        _SettingsCard(
          title: 'Crossfade',
          subtitle: '"beta" still in development.',
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
                  onSelected: (_) => _apply({'crossfadeMs': item.$1}),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Playback behavior',
          subtitle: 'Queue persistence, history, skips, and audio helpers.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: persistent,
                title: const Text('Restore queue after restart'),
                onChanged: (v) => _apply({'persistentQueue': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: continueDismiss,
                title: const Text('Keep playback alive'),
                subtitle: const Text(
                  'Lets audio continue when the app is swiped away from recents.',
                ),
                onChanged: (v) => _apply({'continuePlaybackWhenDismissed': v}),
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
                onChanged: (v) => _apply({'sponsorBlockEnabled': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: norm,
                title: const Text('Normalize volume'),
                subtitle: const Text(
                  'Lowers loud tracks for steadier playback.',
                ),
                onChanged: (v) => _apply({'normalizeVolume': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: skipSil,
                title: const Text('Skip silence'),
                subtitle: const Text('Reserved for deeper ExoPlayer tuning.'),
                onChanged: (v) => _apply({'skipSilence': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Shortcuts',
          subtitle: 'System integrations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _openEqualizer,
                icon: const Icon(Icons.equalizer_rounded, size: 20),
                label: const Text('System equalizer'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showPlaybackDiagnostics,
                icon: const Icon(Icons.monitor_heart_rounded, size: 20),
                label: const Text('Playback diagnostics'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsSettings(
    ScrollController controller, {
    required bool lrclib,
    required bool romanize,
  }) {
    return ListView(
      key: const ValueKey('settings-lyrics'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Lyrics sources',
          subtitle:
              'Control synced lyrics, source order, and Romanized output.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: lrclib,
                title: const Text('Prefer synced lyrics / LRCLIB first'),
                subtitle: const Text(
                  'YouTube captions are used as fallback. Turn off to try captions first.',
                ),
                onChanged: (v) => _apply({'lyricsPreferLrclib': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: romanize,
                title: const Text('Romanize lyrics'),
                subtitle: const Text(
                  'Show Latin-script lyrics when supported.',
                ),
                onChanged: (v) => _apply({'lyricsRomanize': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Lyrics tools',
          subtitle: 'Cache cleanup and lyric health checks.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'clearLyricsCache',
                  success: 'Lyrics cache cleared',
                  failure: 'Could not clear lyrics cache',
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                label: const Text('Clear lyrics cache'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Per-song lyric overrides and share-image export need a persistent lyric editor before they can be enabled safely.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSettings(
    ScrollController controller, {
    required bool backup,
  }) {
    return ListView(
      key: const ValueKey('settings-storage'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Backups',
          subtitle: 'Library and settings safety.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: backup,
                title: const Text('Auto backup'),
                subtitle: const Text(
                  'Writes local snapshots after settings changes.',
                ),
                onChanged: (v) => _apply({'autoBackupEnabled': v}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showStorageStatus,
                icon: const Icon(Icons.analytics_rounded, size: 20),
                label: const Text('Storage and backup status'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'createBackup',
                  success: 'Backup created',
                  failure: 'Backup failed',
                ),
                icon: const Icon(Icons.save_alt_rounded, size: 20),
                label: const Text('Create backup now'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'restoreLatestBackup',
                  success: 'Latest backup restored',
                  failure: 'Restore failed',
                ),
                icon: const Icon(Icons.restore_rounded, size: 20),
                label: const Text('Restore latest backup'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Cache cleanup',
          subtitle: 'Free streaming and artwork memory cache.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'clearStreamCache',
                  success: 'Stream cache cleared',
                  failure: 'Could not clear stream cache',
                ),
                icon: const Icon(Icons.cleaning_services_rounded, size: 20),
                label: const Text('Clear stream cache'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _clearFlutterImageCache,
                icon: const Icon(Icons.image_not_supported_rounded, size: 20),
                label: const Text('Clear image cache'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Playback recovery',
          subtitle: 'Move past broken streams automatically.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _bool('autoSkipNextOnError'),
            title: const Text('Auto-skip failed songs'),
            subtitle: const Text(
              'After one retry fails, Foxy jumps to the next queue item.',
            ),
            onChanged: (v) => _apply({'autoSkipNextOnError': v}),
          ),
        ),
        _SettingsCard(
          title: 'Library repair',
          subtitle: 'Rescan downloads and repair stale liked/history metadata.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'refreshDownloads',
                  success: 'Downloads refreshed',
                  failure: 'Could not refresh downloads',
                ),
                icon: const Icon(Icons.download_done_rounded, size: 20),
                label: const Text('Refresh downloads'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _runSettingsAction(
                  method: 'repairLibraryMetadata',
                  success: 'Library metadata repaired',
                  failure: 'Could not repair library metadata',
                ),
                icon: const Icon(Icons.healing_rounded, size: 20),
                label: const Text('Repair library metadata'),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'App updates',
          subtitle: 'GitHub releases',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('autoCheckUpdates', true),
                title: const Text('Check for updates automatically'),
                subtitle: const Text(
                  'Looks for new GitHub releases about once per day.',
                ),
                onChanged: (v) => _apply({'autoCheckUpdates': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _bool('updateNotifications', true),
                title: const Text('Update notifications'),
                subtitle: const Text(
                  'Shows a system notification when a newer APK is published.',
                ),
                onChanged: (v) => _apply({'updateNotifications': v}),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _checkUpdate,
                icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                label: const Text('Check for updates now'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedSettings(
    ScrollController controller, {
    required bool blurEffects,
    required bool disableAnimations,
    required bool haptics,
    required int defaultOpenTab,
    required int quickPicksDisplayMode,
    required int recognitionSource,
    required int recognitionHistoryLimit,
  }) {
    return ListView(
      key: const ValueKey('settings-advanced'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Performance & motion',
          subtitle: 'Control animation, blur, and touch feedback.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: blurEffects,
                title: const Text('Glass blur effects'),
                subtitle: const Text(
                  'Turn off on weaker phones if scrolling feels sticky.',
                ),
                onChanged: (v) => _apply({'blurEffects': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: disableAnimations,
                title: const Text('Reduce animations'),
                subtitle: const Text(
                  'Makes settings/page transitions instant.',
                ),
                onChanged: (v) => _apply({'disableAnimations': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: haptics,
                title: const Text('Haptic feedback'),
                subtitle: const Text('Light vibration on player controls.'),
                onChanged: (v) => _apply({'hapticFeedback': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Launch & home',
          subtitle: 'Choose where Foxy opens and how quick picks display.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default open tab',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: defaultOpenTab == 1 || defaultOpenTab == 3
                    ? defaultOpenTab
                    : 0,
                values: const [0, 1, 3],
                label: (v) => switch (v) {
                  1 => 'Search',
                  3 => 'Library',
                  _ => 'Home',
                },
                icon: (v) => switch (v) {
                  1 => Icons.search_rounded,
                  3 => Icons.library_music_rounded,
                  _ => Icons.home_rounded,
                },
                onChanged: (v) => _apply({'defaultOpenTab': v}),
              ),
              const SizedBox(height: 14),
              Text(
                'Quick picks layout',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _SettingsOptionGrid<int>(
                value: quickPicksDisplayMode,
                values: const [0, 1],
                label: (v) => v == 1 ? 'List' : 'Cards',
                icon: (v) => v == 1
                    ? Icons.view_list_rounded
                    : Icons.view_carousel_rounded,
                onChanged: (v) => _apply({'quickPicksDisplayMode': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Library visibility',
          subtitle: 'Hide sections you do not use.',
          child: Column(
            children: [
              for (final item in const [
                ('showLikedInLibrary', 'Liked'),
                ('showDownloadsInLibrary', 'Downloads'),
                ('showHistoryInLibrary', 'History'),
                ('showMostPlayedInLibrary', 'Most played'),
                ('showPlaylistsInLibrary', 'Playlists'),
                ('showLocalInLibrary', 'Local library'),
                ('showRecognizedInLibrary', 'Recognized songs'),
              ])
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _bool(item.$1, true),
                  title: Text(item.$2),
                  onChanged: (v) => _apply({item.$1: v}),
                ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Recognition',
          subtitle: 'Music identification source and local history retention.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsStyleChooserBox<int>(
                title: 'Fingerprint source',
                value: recognitionSource,
                values: const [0, 1],
                label: (v) => switch (v) {
                  1 => 'Fast mic',
                  _ => 'Foxy match',
                },
                icon: (v) => switch (v) {
                  1 => Icons.mic_external_on_rounded,
                  _ => Icons.graphic_eq_rounded,
                },
                onChanged: (v) => _apply({'recognitionSource': v}),
              ),
              const SizedBox(height: 14),
              _SettingsStyleChooserBox<int>(
                title: 'History limit',
                value: recognitionHistoryLimit,
                values: const [10, 25, 40, 75, 100],
                label: (v) => '$v items',
                icon: (v) => Icons.history_rounded,
                onChanged: (v) => _apply({'recognitionHistoryLimit': v}),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _runSettingsAction(
                    method: 'clearRecognitionHistory',
                    success: 'Recognition history cleared',
                    failure: 'Could not clear recognition history',
                  ),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                  label: const Text('Clear recognition history'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsHome(ScrollController controller) {
    final signedIn = widget.account['isSignedIn'] == true;
    return ListView(
      key: const ValueKey('settings-home'),
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _SettingsProfileBanner(
          signedIn: signedIn,
          email: widget.account['email']?.toString() ?? '',
          onTap: () =>
              setState(() => _settingsPage = _FoxySettingsPage.account),
        ),
        const SizedBox(height: 14),
        _FoxySettingsSection(
          children: [
            _FoxySettingsItem(
              icon: Icons.account_circle_rounded,
              title: 'Account',
              subtitle: signedIn
                  ? 'YouTube Music connected'
                  : 'Sign in, cookies, and account overview',
              accent: Theme.of(context).colorScheme.primary,
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.account),
              first: true,
            ),
            _FoxySettingsItem(
              icon: Icons.graphic_eq_rounded,
              title: 'Playback & quality',
              subtitle: 'Ultra quality, crossfade, queue, playback behavior',
              accent: _FoxyBrandPalette.foxAmber,
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.playback),
            ),
            _FoxySettingsItem(
              icon: Icons.palette_rounded,
              title: 'Appearance',
              subtitle: 'Player background, glass, wallpaper, gestures',
              accent: const Color(0xFFB388FF),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.appearance),
            ),
            _FoxySettingsItem(
              icon: Icons.lyrics_rounded,
              title: 'Lyrics',
              subtitle: 'LRCLIB, synced lyrics, Romanized text',
              accent: const Color(0xFF64B5F6),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.lyrics),
            ),
            _FoxySettingsItem(
              icon: Icons.storage_rounded,
              title: 'Storage, backup & updates',
              subtitle: 'Backups, update checks, cache plans',
              accent: const Color(0xFF81C784),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.storage),
            ),
            _FoxySettingsItem(
              icon: Icons.tune_rounded,
              title: 'Advanced',
              subtitle: 'Performance, region, and layout controls',
              accent: const Color(0xFF4DD0E1),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.advanced),
            ),
            _FoxySettingsItem(
              icon: Icons.info_rounded,
              title: 'About FoxyMusic',
              subtitle: 'Version, credits, project links',
              accent: const Color(0xFFFF8A65),
              onTap: () =>
                  setState(() => _settingsPage = _FoxySettingsPage.about),
              last: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAppearanceTab(
    ScrollController controller, {
    required bool enableLiquidGlassLayout,
    required int playerButtonsStyle,
    required int playerProgressStyle,
    required bool hidePlayerArtwork,
    required int artworkDisplayStyle,
    required int thumbnailCornerRadius,
  }) {
    final compact = _bool('compactPlayer');
    final gestures = _bool('gestureControls', true);
    final bgStyle = _normalizePlayerBackgroundStyle(
      _int('playerBackgroundStyle', 0),
    );
    final visiblePlayerButtonsStyle = playerButtonsStyle == 0
        ? 1
        : playerButtonsStyle;
    final homeBackgroundEnabled = _bool('homeBackgroundEnabled');

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        _SettingsCard(
          title: 'Layout system',
          subtitle:
              'Choose the shell language first, then tune each player surface below.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enableLiquidGlassLayout,
                title: const Text('Liquid glass layout'),
                subtitle: const Text(
                  'Turns on the iPhone-style floating glass shell for the mini-player and bottom navigation.',
                ),
                onChanged: (value) =>
                    _apply({'enableLiquidGlassLayout': value}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Style boxes',
          subtitle:
              'Each surface keeps its own boxed selector so layouts are easier to scan and switch.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsStyleChooserBox<int>(
                title: 'Player background',
                value: bgStyle,
                values: const [0, 1, 2, 3],
                label: (v) => switch (v) {
                  1 => 'Artwork',
                  2 => 'Black',
                  3 => 'Video',
                  _ => 'Blur',
                },
                icon: (v) => switch (v) {
                  1 => Icons.image_rounded,
                  2 => Icons.dark_mode_rounded,
                  3 => Icons.motion_photos_on_rounded,
                  _ => Icons.blur_on_rounded,
                },
                onChanged: (v) => _apply({'playerBackgroundStyle': v}),
              ),
              const SizedBox(height: 14),
              _SettingsStyleChooserBox<int>(
                title: 'Button style',
                value: visiblePlayerButtonsStyle,
                values: const [1, 2],
                label: (v) => switch (v) {
                  1 => 'Outline',
                  2 => 'Solid',
                  _ => 'Outline',
                },
                icon: (v) => switch (v) {
                  1 => Icons.radio_button_unchecked_rounded,
                  2 => Icons.radio_button_checked_rounded,
                  _ => Icons.radio_button_unchecked_rounded,
                },
                onChanged: (v) => _apply({'playerButtonsStyle': v}),
              ),
              const SizedBox(height: 14),
              _SettingsStyleChooserBox<int>(
                title: 'Seek bar',
                value: playerProgressStyle,
                values: const [0, 1],
                label: (v) => v == 1 ? 'Slim' : 'Standard',
                icon: (v) => v == 1
                    ? Icons.remove_rounded
                    : Icons.horizontal_rule_rounded,
                onChanged: (v) => _apply({'playerProgressStyle': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Player details',
          subtitle: 'Artwork shape, crop behavior, and control ergonomics.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: hidePlayerArtwork,
                title: const Text('Hide full-player artwork'),
                subtitle: const Text('Keeps lyrics and controls more open.'),
                onChanged: (v) => _apply({'hidePlayerArtwork': v}),
              ),
              _SettingsStyleChooserBox<int>(
                title: 'Artwork style',
                value: artworkDisplayStyle,
                values: const [0, 1, 2],
                label: (v) => switch (v) {
                  1 => 'Medium',
                  2 => 'Poster',
                  _ => 'Normal',
                },
                icon: (v) => switch (v) {
                  1 => Icons.crop_square_rounded,
                  2 => Icons.crop_portrait_rounded,
                  _ => Icons.square_rounded,
                },
                onChanged: (v) => _apply({'artworkDisplayStyle': v}),
              ),
              const SizedBox(height: 6),
              Text(
                'Artwork corner radius: $thumbnailCornerRadius',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Slider(
                value: thumbnailCornerRadius.toDouble(),
                min: 0,
                max: 40,
                divisions: 8,
                label: '$thumbnailCornerRadius',
                onChanged: (v) => _apply({'thumbnailCornerRadius': v.round()}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'Interaction',
          subtitle: 'Mini-player density and swipe behavior.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: compact,
                title: const Text('Compact mini-player'),
                onChanged: (v) => _apply({'compactPlayer': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: gestures,
                title: const Text('Swipe to change song'),
                onChanged: (v) => _apply({'gestureControls': v}),
              ),
            ],
          ),
        ),
        _SettingsCard(
          title: 'App background',
          subtitle:
              'Wallpaper and glass treatment for Home, Search, and Library.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: homeBackgroundEnabled,
                title: const Text('Enable custom wallpaper'),
                subtitle: const Text(
                  'Uses your saved wallpaper everywhere outside the player.',
                ),
                onChanged: (v) => _apply({'homeBackgroundEnabled': v}),
              ),
              FilledButton.icon(
                onPressed: _pickHomeBackground,
                icon: const Icon(Icons.image_rounded, size: 20),
                label: const Text('Choose custom background'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _resetHomeBackground,
                icon: const Icon(Icons.restart_alt_rounded, size: 20),
                label: const Text('Use default Foxy background'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _FoxySettingsPage {
  home('Settings', 'Clean categories...'),
  account('Account', 'Sign-in, provider auth, and account health.'),
  playback(
    'Playback & quality',
    'Streams, downloads, queue, and audio behavior.',
  ),
  appearance(
    'Appearance',
    'Player background, glass, wallpaper, and gestures.',
  ),
  lyrics(
    'Lyrics',
    'Synced lyrics sources, Romanized output, and future tools.',
  ),
  storage(
    'Storage & updates',
    'Backups, update checks, cache plans, and cleanup.',
  ),
  advanced('Advanced', 'Performance, region, and low-level layout controls.'),
  about('About', 'Version, credits, links, and project info.');

  const _FoxySettingsPage(this.title, this.subtitle);

  final String title;
  final String subtitle;
}

class _SettingsOptionGrid<T> extends StatelessWidget {
  const _SettingsOptionGrid({
    required this.value,
    required this.values,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final T value;
  final List<T> values;
  final String Function(T value) label;
  final IconData Function(T value) icon;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: values.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.8,
      ),
      itemBuilder: (context, index) {
        final item = values[index];
        final selected = item == value;
        return Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onChanged(item),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.92)
                      : Colors.white.withValues(alpha: 0.04),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    icon(item),
                    color: selected
                        ? accent
                        : Colors.white.withValues(alpha: 0.68),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsStyleChooserBox<T> extends StatelessWidget {
  const _SettingsStyleChooserBox({
    required this.title,
    required this.value,
    required this.values,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  final String title;
  final T value;
  final List<T> values;
  final String Function(T value) label;
  final IconData Function(T value) icon;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        _SettingsOptionGrid<T>(
          value: value,
          values: values,
          label: label,
          icon: icon,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SettingsProfileBanner extends StatelessWidget {
  const _SettingsProfileBanner({
    required this.signedIn,
    required this.email,
    required this.onTap,
  });

  final bool signedIn;
  final String email;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.92),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  signedIn ? Icons.verified_rounded : Icons.person_rounded,
                  color: Colors.black,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      signedIn ? 'Connected' : 'Guest mode',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      signedIn && email.isNotEmpty
                          ? email
                          : 'Tap to manage YouTube Music sign-in',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.62),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoxySettingsSection extends StatelessWidget {
  const _FoxySettingsSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(children: children);
  }
}

class _FoxySettingsItem extends StatelessWidget {
  const _FoxySettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    this.first = false,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 82),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: last
                  ? BorderSide.none
                  : BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.95),
                ),
                child: Icon(icon, color: Colors.black, size: 25),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.56),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ],
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 12,
            ),
          ),
          if (child is! SizedBox) ...[const SizedBox(height: 12), child],
        ],
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

class _HomeShelfShell extends StatelessWidget {
  const _HomeShelfShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: _kHomeShelfGap),
      child: RepaintBoundary(child: child),
    );
  }
}

class _HomeSpotlight extends StatelessWidget {
  const _HomeSpotlight({
    required this.song,
    required this.sectionTitle,
    required this.onPlay,
    required this.onRadio,
  });

  final _Song song;
  final String sectionTitle;
  final VoidCallback onPlay;
  final VoidCallback onRadio;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _FoxyGlassButton(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(24),
        blurSigma: 0,
        tintOpacity: 0.16,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 188,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: _Artwork(
                    url: song.homeArtwork,
                    size: 480,
                    radius: 0,
                    fit: BoxFit.cover,
                    identityTag: song.videoId,
                    offlineArtworkPath: song.offlineArtworkPath,
                    useOfflineArtwork: song.isDownloaded,
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.black.withValues(alpha: 0.2),
                          Colors.black.withValues(alpha: 0.48),
                          Colors.black.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sectionTitle.toUpperCase(),
                        style: TextStyle(
                          color: accent.withValues(alpha: 0.95),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const Spacer(),
                      _OneLineMarqueeText(
                        song.title,
                        active: true,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
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
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: onPlay,
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 22,
                            ),
                            label: const Text('Play'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed: onRadio,
                            icon: const Icon(Icons.radio_rounded, size: 20),
                            label: const Text('Radio'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
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
      ),
    );
  }
}

class _HomeQuickPicks extends StatefulWidget {
  const _HomeQuickPicks({
    required this.songs,
    required this.currentVideoId,
    required this.onPlay,
  });

  final List<_Song> songs;
  final String currentVideoId;
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
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
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
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    _FoxyGlassTextButton(
                      label: 'Play all',
                      onPressed: () => widget.onPlay(songs.first, songs),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 196,
            child: PageView.builder(
              controller: _bannerController,
              physics: _kFoxyHorizontalScrollPhysics,
              itemCount: songs.length,
              onPageChanged: (i) => setState(() => _bannerPage = i),
              itemBuilder: (context, index) {
                final song = songs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _QuickPickBannerCard(
                    song: song,
                    active: song.videoId == widget.currentVideoId,
                    onTap: () => widget.onPlay(song, songs),
                  ),
                );
              },
            ),
          ),
          if (songs.length > 1) ...[
            const SizedBox(height: 10),
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
                url: song.homeArtwork,
                size: 480,
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
                    _OneLineMarqueeText(
                      song.title,
                      active: active,
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

class _HomeFeedSection extends StatelessWidget {
  const _HomeFeedSection({
    required this.section,
    required this.layout,
    required this.currentVideoId,
    required this.onPlay,
    required this.quickPicksDisplayMode,
    required this.experimentalHeaderAccentEnabled,
    required this.maxGridItems,
    this.onDiscoverSearch,
  });

  final _SongSection section;
  final _HomeSectionLayout layout;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final int quickPicksDisplayMode;
  final bool experimentalHeaderAccentEnabled;
  final int maxGridItems;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    if (_isSuppressedHomeSection(section.title)) {
      return const SizedBox.shrink();
    }
    if (section.title.toLowerCase().contains('quick pick')) {
      return quickPicksDisplayMode == 1
          ? _HomeQuickStartSection(
              section: section,
              currentVideoId: currentVideoId,
              onPlay: onPlay,
              experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
            )
          : _HomeQuickPicks(
              songs: section.songs,
              currentVideoId: currentVideoId,
              onPlay: onPlay,
            );
    }
    return switch (layout) {
      _HomeSectionLayout.square => _HomeSquareSwipeSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
      _HomeSectionLayout.radio => _HomeRadioStarterSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
      _HomeSectionLayout.mixes => _HomeMixesSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
      _HomeSectionLayout.grid => _HomeGridShelf(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
        maxItems: maxGridItems,
      ),
      _HomeSectionLayout.video => _HomeVideoShelf(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
      _HomeSectionLayout.chart => _HomeChartShelf(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
      _HomeSectionLayout.artist => _HomeArtistShelf(
        section: section,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
        onDiscoverSearch: onDiscoverSearch,
      ),
      _HomeSectionLayout.cards => _HomeSongCardsSection(
        section: section,
        currentVideoId: currentVideoId,
        onPlay: onPlay,
        experimentalHeaderAccentEnabled: experimentalHeaderAccentEnabled,
      ),
    };
  }
}

class _HomeQuickStartSection extends StatelessWidget {
  const _HomeQuickStartSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(24).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final tileWidth = (MediaQuery.sizeOf(context).width - 30).clamp(
      280.0,
      460.0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Start a radio'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 218,
          child: GridView.builder(
            key: PageStorageKey('home-quick-picks-${section.title}'),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: tileWidth * 2,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisExtent: tileWidth,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return _HomeQuickPickRow(
                song: song,
                active: song.videoId == currentVideoId,
                onTap: () => onPlay(song, section.songs, radioTail: true),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeQuickPickRow extends StatelessWidget {
  const _HomeQuickPickRow({
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: 44,
                radius: 10,
                fit: BoxFit.cover,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OneLineMarqueeText(
                      song.title,
                      active: active,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 13,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                color: active ? accent : Colors.white.withValues(alpha: 0.56),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSquareSwipeSection extends StatelessWidget {
  const _HomeSquareSwipeSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(12).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    const cardSize = 151.0;
    const railHeight = 151.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: railHeight,
          child: ListView.separated(
            key: PageStorageKey('home-square-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: cardSize * 3,
            clipBehavior: Clip.none,
            itemCount: songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final song = songs[index];
              return _HomeSquareSongCard(
                song: song,
                active: song.videoId == currentVideoId,
                size: cardSize,
                onTap: () => onPlay(song, section.songs),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeSquareSongCard extends StatelessWidget {
  const _HomeSquareSongCard({
    required this.song,
    required this.active,
    required this.onTap,
    this.size = 152,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: _FoxyGlassButton(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        blurSigma: 8,
        tintOpacity: 0.22,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: size,
                radius: 0,
                fit: BoxFit.cover,
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
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.42, 0.68, 1],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 48,
                child: Icon(
                  active
                      ? Icons.equalizer_rounded
                      : Icons.play_circle_fill_rounded,
                  color: active ? accent : Colors.white,
                  size: 28,
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OneLineMarqueeText(
                      song.title,
                      active: active,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 10,
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
    );
  }
}

class _HomeRadioStarterSection extends StatelessWidget {
  const _HomeRadioStarterSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(12).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final columns = <List<_Song>>[];
    for (var i = 0; i < songs.length; i += 2) {
      columns.add(songs.skip(i).take(2).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Fast stations'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 134,
          child: ListView.separated(
            key: PageStorageKey('home-radio-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: 520,
            itemCount: columns.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, columnIndex) {
              final column = columns[columnIndex];
              return SizedBox(
                width: 238,
                child: Column(
                  children: [
                    for (var i = 0; i < column.length; i++) ...[
                      Expanded(
                        child: _HomeCompactSongTile(
                          song: column[i],
                          active: column[i].videoId == currentVideoId,
                          onTap: () => onPlay(column[i], section.songs),
                        ),
                      ),
                      if (i != column.length - 1) const SizedBox(height: 10),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeMixesSection extends StatelessWidget {
  const _HomeMixesSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(9).toList();
    if (songs.isEmpty) return const SizedBox.shrink();
    final groups = <List<_Song>>[];
    for (var i = 0; i < songs.length; i += 3) {
      groups.add(songs.skip(i).take(3).toList());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title, subtitle: 'Built from you'),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 164,
          child: ListView.separated(
            key: PageStorageKey('home-mixes-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: 520,
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final group = groups[index];
              final lead = group.first;
              final active = group.any((s) => s.videoId == currentVideoId);
              return _HomeMixCard(
                title: index == 0
                    ? 'Resume your vibe'
                    : index == 1
                    ? 'Offline gems'
                    : 'Replay stack',
                songs: group,
                active: active,
                onTap: () => onPlay(lead, group),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 2),
              child: Text(
                subtitle!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OneLineMarqueeText extends StatefulWidget {
  const _OneLineMarqueeText(
    this.text, {
    required this.style,
    this.active = false,
  });

  final String text;
  final TextStyle style;
  final bool active;

  @override
  State<_OneLineMarqueeText> createState() => _OneLineMarqueeTextState();
}

class _OneLineMarqueeTextState extends State<_OneLineMarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _startTimer;
  double _textWidth = 0;
  double _boxWidth = 0;
  static const double _gap = 28;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(covariant _OneLineMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.active != widget.active) {
      _startTimer?.cancel();
      _startTimer = null;
      _controller.stop();
      _textWidth = 0;
      _boxWidth = 0;
    }
  }

  @override
  void dispose() {
    _startTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _configure({required double textWidth, required double boxWidth}) {
    final overflow = textWidth - boxWidth;
    if (!widget.active || overflow <= 2) {
      _startTimer?.cancel();
      _startTimer = null;
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if ((textWidth - _textWidth).abs() < 1 &&
        (boxWidth - _boxWidth).abs() < 1 &&
        _controller.isAnimating) {
      return;
    }
    _textWidth = textWidth;
    _boxWidth = boxWidth;
    final travel = textWidth + _gap;
    _controller.duration = Duration(
      milliseconds: (travel * 28).round().clamp(4200, 12000),
    );
    _startTimer?.cancel();
    _startTimer = Timer(const Duration(milliseconds: 900), () {
      _startTimer = null;
      if (mounted && widget.active && _textWidth - _boxWidth > 2) {
        _controller.repeat();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final animationsEnabled =
        TickerMode.valuesOf(context).enabled &&
        !Scrollable.recommendDeferredLoadingForContext(context);
    if (!widget.active || !animationsEnabled) {
      _startTimer?.cancel();
      _startTimer = null;
      if (_controller.isAnimating) _controller.stop();
      return Text(
        widget.text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);
        final textWidth = painter.width;
        final boxWidth = constraints.maxWidth;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _configure(textWidth: textWidth, boxWidth: boxWidth);
          }
        });
        if (textWidth - boxWidth <= 2) {
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }
        return ClipRect(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final travel = _textWidth + _gap;
                final dx = travel <= 0 ? 0.0 : -travel * _controller.value;
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: SizedBox(
                width: textWidth * 2 + _gap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: widget.style,
                    ),
                    const SizedBox(width: _gap),
                    Text(
                      widget.text,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: widget.style,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomeAdaptiveSectionGradient extends StatefulWidget {
  const _HomeAdaptiveSectionGradient({required this.song});

  final _Song song;

  @override
  State<_HomeAdaptiveSectionGradient> createState() =>
      _HomeAdaptiveSectionGradientState();
}

class _HomeAdaptiveGradientPalette {
  const _HomeAdaptiveGradientPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  final Color primary;
  final Color secondary;
  final Color tertiary;
}

class _HomeAdaptiveSectionGradientState
    extends State<_HomeAdaptiveSectionGradient> {
  static final Map<String, _HomeAdaptiveGradientPalette> _colorCache =
      <String, _HomeAdaptiveGradientPalette>{};

  ImageStream? _stream;
  ImageStreamListener? _listener;
  _HomeAdaptiveGradientPalette? _palette;
  String? _resolvedKey;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant _HomeAdaptiveSectionGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.videoId != widget.song.videoId ||
        oldWidget.song.homeArtwork != widget.song.homeArtwork ||
        oldWidget.song.offlineArtworkPath != widget.song.offlineArtworkPath ||
        oldWidget.song.isDownloaded != widget.song.isDownloaded) {
      _unbind();
      _palette = null;
      _resolvedKey = null;
      _bind();
    }
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _unbind() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  ImageProvider<Object>? _providerForSong() {
    final offlinePath = widget.song.offlineArtworkPath?.trim() ?? '';
    if (widget.song.isDownloaded && offlinePath.isNotEmpty && !kIsWeb) {
      final file = _Artwork._existingFile(offlinePath);
      if (file != null) {
        return ResizeImage.resizeIfNeeded(36, 36, FileImage(file));
      }
    }
    final artwork = widget.song.homeArtwork.trim();
    if (artwork.isEmpty) return null;
    if (!kIsWeb &&
        !artwork.startsWith('http://') &&
        !artwork.startsWith('https://')) {
      final path = artwork.startsWith('file://')
          ? artwork.substring(7)
          : artwork;
      final file = _Artwork._existingFile(path);
      if (file != null) {
        return ResizeImage.resizeIfNeeded(36, 36, FileImage(file));
      }
    }
    return ResizeImage.resizeIfNeeded(36, 36, NetworkImage(artwork));
  }

  Future<void> _bind() async {
    final key =
        '${widget.song.videoId}|${widget.song.homeArtwork}|${widget.song.offlineArtworkPath}|${widget.song.isDownloaded}';
    _resolvedKey = key;
    final cached = _colorCache[key];
    if (cached != null) {
      if (mounted) setState(() => _palette = cached);
      return;
    }
    final provider = _providerForSong();
    if (provider == null) return;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) async {
        try {
          final palette = await _sampleArtworkPalette(info.image);
          if (!mounted || _resolvedKey != key || palette == null) return;
          _colorCache[key] = palette;
          if (_colorCache.length > 160) {
            _colorCache.remove(_colorCache.keys.first);
          }
          setState(() => _palette = palette);
        } finally {
          stream.removeListener(listener);
          if (identical(_stream, stream)) {
            _stream = null;
            _listener = null;
          }
        }
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        if (identical(_stream, stream)) {
          _stream = null;
          _listener = null;
        }
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  Future<_HomeAdaptiveGradientPalette?> _sampleArtworkPalette(
    ui.Image image,
  ) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    final bytes = data.buffer.asUint8List();
    final width = image.width;
    final height = image.height;
    if (width <= 0 || height <= 0) return null;
    Color regionColor({
      required int startX,
      required int endX,
      required int startY,
      required int endY,
      required double xBias,
      required double yBias,
    }) {
      var r = 0.0;
      var g = 0.0;
      var b = 0.0;
      var weightSum = 0.0;
      for (var y = startY; y < endY; y++) {
        for (var x = startX; x < endX; x++) {
          final idx = (y * width + x) * 4;
          if (idx + 3 >= bytes.length) continue;
          final alpha = bytes[idx + 3] / 255.0;
          if (alpha < 0.08) continue;
          final fx = width <= 1 ? 0.0 : x / (width - 1);
          final fy = height <= 1 ? 0.0 : y / (height - 1);
          final weight =
              alpha *
              (0.5 +
                  (xBias >= 0 ? fx : (1.0 - fx)) * xBias.abs() +
                  (yBias >= 0 ? fy : (1.0 - fy)) * yBias.abs());
          r += bytes[idx] * weight;
          g += bytes[idx + 1] * weight;
          b += bytes[idx + 2] * weight;
          weightSum += weight;
        }
      }
      if (weightSum <= 0.0) return const Color(0xFF1A1A1A);
      return Color.fromARGB(
        255,
        (r / weightSum).round().clamp(0, 255),
        (g / weightSum).round().clamp(0, 255),
        (b / weightSum).round().clamp(0, 255),
      );
    }

    Color rgbFactor(Color color, double factor) {
      return Color.fromARGB(
        (color.a * 255.0).round().clamp(0, 255),
        ((color.r * 255.0) * factor).round().clamp(0, 255),
        ((color.g * 255.0) * factor).round().clamp(0, 255),
        ((color.b * 255.0) * factor).round().clamp(0, 255),
      );
    }

    final primary = rgbFactor(
      regionColor(
        startX: 0,
        endX: width,
        startY: 0,
        endY: height,
        xBias: 0.15,
        yBias: -0.2,
      ),
      0.3,
    );
    final secondary = rgbFactor(
      regionColor(
        startX: (width * 0.28).floor().clamp(0, width - 1),
        endX: width,
        startY: 0,
        endY: (height * 0.72).floor().clamp(1, height),
        xBias: 0.82,
        yBias: -0.45,
      ),
      0.24,
    );
    final tertiary = rgbFactor(
      regionColor(
        startX: 0,
        endX: width,
        startY: (height * 0.18).floor().clamp(0, height - 1),
        endY: height,
        xBias: 0.32,
        yBias: 0.3,
      ),
      0.18,
    );
    return _HomeAdaptiveGradientPalette(
      primary: primary,
      secondary: secondary,
      tertiary: tertiary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        _palette ??
        const _HomeAdaptiveGradientPalette(
          primary: Color(0xFF101010),
          secondary: Color(0xFF080808),
          tertiary: Color(0xFF000000),
        );
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: const Alignment(-1.0, -0.72),
                end: const Alignment(1.0, 0.92),
                colors: [
                  palette.primary.withValues(alpha: 0.95),
                  palette.secondary.withValues(alpha: 0.684),
                  palette.tertiary.withValues(alpha: 0.323),
                  Colors.black,
                ],
                stops: const [0.0, 0.28, 0.62, 1.0],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 360,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.294),
                      Colors.black.withValues(alpha: 0.735),
                    ],
                    stops: const [0.0, 0.58, 1.0],
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

class _HomeCompactSongTile extends StatelessWidget {
  const _HomeCompactSongTile({
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
      borderRadius: BorderRadius.circular(12),
      blurSigma: 8,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _Artwork(
            url: song.homeArtwork,
            size: 52,
            radius: 8,
            fit: BoxFit.cover,
            identityTag: song.videoId,
            offlineArtworkPath: song.offlineArtworkPath,
            useOfflineArtwork: song.isDownloaded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? accent : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  song.artist.ifBlank('Radio'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
            color: active ? accent : Colors.white.withValues(alpha: 0.56),
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _HomeMixCard extends StatelessWidget {
  const _HomeMixCard({
    required this.title,
    required this.songs,
    required this.active,
    required this.onTap,
  });

  final String title;
  final List<_Song> songs;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final art = songs.take(4).toList();
    return SizedBox(
      width: 183,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(14),
        blurSigma: 10,
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 1,
                    mainAxisSpacing: 1,
                  ),
                  itemCount: math.max(1, art.length),
                  itemBuilder: (context, index) {
                    final song = art[index % art.length];
                    return _Artwork(
                      url: song.homeArtwork,
                      size: 80,
                      radius: 0,
                      fit: BoxFit.cover,
                      identityTag: song.videoId,
                      offlineArtworkPath: song.offlineArtworkPath,
                      useOfflineArtwork: song.isDownloaded,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(
                  active ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                  color: active ? accent : Colors.white.withValues(alpha: 0.58),
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeFeedLoadingMore extends StatelessWidget {
  const _HomeFeedLoadingMore();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white.withValues(alpha: 0.72),
        ),
      ),
    );
  }
}

class _HomeSongCardsSection extends StatelessWidget {
  const _HomeSongCardsSection({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    if (section.songs.isEmpty) return const SizedBox.shrink();
    final songs = section.songs.take(14).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        for (final song in songs)
          _HomeSongCard(
            song: song,
            active: song.videoId == currentVideoId,
            onTap: () => onPlay(song, section.songs),
          ),
      ],
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(18),
        blurSigma: 8,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 87,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Artwork(
                  url: song.homeArtwork,
                  size: 180,
                  radius: 0,
                  fit: BoxFit.cover,
                  identityTag: song.videoId,
                  offlineArtworkPath: song.offlineArtworkPath,
                  useOfflineArtwork: song.isDownloaded,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.88),
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0.24),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      _Artwork(
                        url: song.homeArtwork,
                        size: 60,
                        radius: 8,
                        fit: BoxFit.cover,
                        identityTag: song.videoId,
                        offlineArtworkPath: song.offlineArtworkPath,
                        useOfflineArtwork: song.isDownloaded,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _OneLineMarqueeText(
                              song.title,
                              active: active,
                              style: TextStyle(
                                color: active ? accent : Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              song.artist,
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
                      Icon(
                        active
                            ? Icons.equalizer_rounded
                            : Icons.play_arrow_rounded,
                        color: active ? accent : Colors.white54,
                        size: 28,
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
  }
}

class _HomeGridShelf extends StatelessWidget {
  const _HomeGridShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
    this.maxItems = 6,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final songs = section.songs.take(maxItems.clamp(2, 12)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileSize = ((constraints.maxWidth - 46) / 2).clamp(
              132.0,
              220.0,
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final song in songs)
                    SizedBox(
                      width: tileSize,
                      height: tileSize,
                      child: _HomeGridTile(
                        song: song,
                        active: song.videoId == currentVideoId,
                        onTap: () => onPlay(song, section.songs),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
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
      borderRadius: BorderRadius.circular(18),
      blurSigma: 12,
      tintOpacity: 0.2,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Artwork(
              url: song.homeArtwork,
              size: 240,
              radius: 0,
              fit: BoxFit.cover,
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
                    Colors.black.withValues(alpha: 0.12),
                    Colors.black.withValues(alpha: 0.9),
                  ],
                  stops: const [0.48, 0.7, 1],
                ),
              ),
            ),
            if (active)
              Positioned(
                right: 10,
                top: 10,
                child: Icon(Icons.equalizer_rounded, color: accent, size: 30),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OneLineMarqueeText(
                    song.title,
                    active: active,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                      height: 1.06,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
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

class _HomeVideoShelf extends StatelessWidget {
  const _HomeVideoShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 159,
          child: ListView.separated(
            key: PageStorageKey('home-video-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: 520,
            itemCount: section.songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 13),
            itemBuilder: (context, index) {
              final song = section.songs[index];
              return _HomeVideoCard(
                song: song,
                active: song.videoId == currentVideoId,
                onTap: () => onPlay(song, section.songs),
              );
            },
          ),
        ),
      ],
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
    const w = 234.0;
    const h = 132.0;
    return SizedBox(
      width: w,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(16),
        blurSigma: 10,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Artwork(
                  url: song.homeArtwork,
                  size: w,
                  radius: 0,
                  fit: BoxFit.cover,
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
                        Colors.black.withValues(alpha: 0.04),
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.82),
                      ],
                      stops: const [0, 0.48, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  right: 42,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OneLineMarqueeText(
                        song.title,
                        active: active,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.66),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Icon(
                    active
                        ? Icons.equalizer_rounded
                        : Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 28,
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

class _HomeChartShelf extends StatelessWidget {
  const _HomeChartShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
  });

  final _SongSection section;
  final String currentVideoId;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 190,
          child: ListView.separated(
            key: PageStorageKey('home-chart-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: 720,
            itemCount: section.songs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = section.songs[index];
              return _HomeChartBannerCard(
                song: song,
                active: song.videoId == currentVideoId,
                onTap: () => onPlay(song, section.songs),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _HomeChartBannerCard extends StatelessWidget {
  const _HomeChartBannerCard({
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
    return SizedBox(
      width: 344,
      child: _FoxyGlassButton(
        onTap: onTap,
        selected: active,
        borderRadius: BorderRadius.circular(18),
        blurSigma: 10,
        tintOpacity: 0.18,
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: song.homeArtwork,
                size: 220,
                radius: 0,
                fit: BoxFit.cover,
                identityTag: song.videoId,
                offlineArtworkPath: song.offlineArtworkPath,
                useOfflineArtwork: song.isDownloaded,
              ),
              Positioned(
                left: 12,
                right: 56,
                bottom: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OneLineMarqueeText(
                      song.title,
                      active: active,
                      style: TextStyle(
                        color: active ? accent : Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.artist.ifBlank('Chart - YouTube Music'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.66),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Icon(
                  active
                      ? Icons.equalizer_rounded
                      : Icons.play_circle_fill_rounded,
                  color: active ? accent : Colors.white,
                  size: 32,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeArtistShelf extends StatelessWidget {
  const _HomeArtistShelf({
    required this.section,
    required this.onPlay,
    required this.experimentalHeaderAccentEnabled,
    this.onDiscoverSearch,
  });

  final _SongSection section;
  final _FoxyOnPlay onPlay;
  final bool experimentalHeaderAccentEnabled;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    final artists = section.songs
        .where(
          (song) =>
              song.videoId.startsWith('UC') ||
              song.artist.toLowerCase().contains('subscriber') ||
              song.artist == 'Artist',
        )
        .toList(growable: false);
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HomeSectionHeader(title: section.title),
        const SizedBox(height: _kHomeShelfTitleGap),
        SizedBox(
          height: 142,
          child: ListView.separated(
            key: PageStorageKey('home-artist-${section.title}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            primary: false,
            physics: _kFoxyHorizontalScrollPhysics,
            cacheExtent: 360,
            itemCount: artists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final song = artists[index];
              return SizedBox(
                width: 108,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      final query = '${song.title} artist songs';
                      if (onDiscoverSearch != null) {
                        onDiscoverSearch!(query);
                      } else {
                        onPlay(song, section.songs);
                      }
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Column(
                      children: [
                        ClipOval(
                          child: _Artwork(
                            url: song.highQualityArtwork,
                            size: 96,
                            radius: 0,
                            fit: BoxFit.cover,
                            identityTag: song.videoId,
                            highQuality: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _OneLineMarqueeText(
                          song.title.ifBlank(song.artist),
                          active: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MiniPlayer extends StatefulWidget {
  const _MiniPlayer({
    super.key,
    required this.player,
    required this.onOpen,
    this.onResync,
    this.glass = false,
    this.style = 0,
    this.buttonStyle = 0,
    this.bottomGap = 0,
  });

  final Map<String, dynamic> player;
  final VoidCallback onOpen;
  final Future<void> Function()? onResync;
  final bool glass;
  final int style;
  final int buttonStyle;
  final double bottomGap;

  @override
  State<_MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<_MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  Timer? _progressTicker;
  int _lastProgressTickAtMs = 0;
  double _pullDy = 0;

  @override
  void initState() {
    super.initState();
    final p = _progressFrom(widget.player);
    _progressCtrl = AnimationController(
      vsync: this,
      value: p,
      duration: const Duration(milliseconds: 320),
      lowerBound: 0,
      upperBound: 1,
    );
    _syncProgressTicker();
  }

  double _progressFrom(Map<String, dynamic> player) {
    final duration = ((player['durationMs'] ?? 0) as num).toDouble();
    final position = ((player['positionMs'] ?? 0) as num).toDouble();
    if (duration <= 0) return 0;
    return (position / duration).clamp(0.0, 1.0);
  }

  @override
  void didUpdateWidget(covariant _MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _progressFrom(widget.player);
    if ((target - _progressCtrl.value).abs() > 0.002) {
      _progressCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
    _syncProgressTicker();
  }

  @override
  void dispose() {
    _progressTicker?.cancel();
    _progressCtrl.dispose();
    super.dispose();
  }

  void _syncProgressTicker() {
    final playing = widget.player['isPlaying'] == true;
    final buffering = _effectivePlayerBuffering(widget.player);
    final duration = ((widget.player['durationMs'] ?? 0) as num).toDouble();
    final shouldRun = playing && !buffering && duration > 0;
    if (!shouldRun) {
      _progressTicker?.cancel();
      _progressTicker = null;
      _lastProgressTickAtMs = 0;
      return;
    }
    _lastProgressTickAtMs = DateTime.now().millisecondsSinceEpoch;
    _progressTicker ??= Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final latestDuration = ((widget.player['durationMs'] ?? 0) as num)
          .toDouble();
      final latestPlaying = widget.player['isPlaying'] == true;
      if (!latestPlaying ||
          _effectivePlayerBuffering(widget.player) ||
          latestDuration <= 0) {
        _progressTicker?.cancel();
        _progressTicker = null;
        _lastProgressTickAtMs = 0;
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsed = _lastProgressTickAtMs == 0
          ? 0
          : (now - _lastProgressTickAtMs).clamp(0, 1200);
      _lastProgressTickAtMs = now;
      final delta = elapsed / latestDuration;
      _progressCtrl.value = (_progressCtrl.value + delta).clamp(0.0, 1.0);
    });
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
    final playing = widget.player['isPlaying'] == true;
    final buffering = _effectivePlayerBuffering(widget.player);
    final miniStyle = widget.style.clamp(0, 2);
    final buttonStyle = widget.buttonStyle.clamp(0, 2);
    final useLiquidButtonChrome = miniStyle == 1;
    const artworkRadius = 10.0;
    final artworkWidget = miniStyle <= 1
        ? SizedBox(
            width: 54,
            height: 54,
            child: miniStyle == 1
                ? _FoxyLiquidChromeShell(
                    radius: 14,
                    clear: true,
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _Artwork(
                        url: song.highQualityArtwork,
                        size: 50,
                        radius: artworkRadius,
                        identityTag: song.videoId,
                        offlineArtworkPath: song.offlineArtworkPath,
                        useOfflineArtwork: song.isDownloaded,
                      ),
                    ),
                  )
                : _FoxyTintedChromeShell(
                    radius: 14,
                    tintAlpha: 0.07,
                    padding: const EdgeInsets.all(2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _Artwork(
                        url: song.highQualityArtwork,
                        size: 50,
                        radius: artworkRadius,
                        identityTag: song.videoId,
                        offlineArtworkPath: song.offlineArtworkPath,
                        useOfflineArtwork: song.isDownloaded,
                      ),
                    ),
                  ),
          )
        : _Artwork(
            url: song.highQualityArtwork,
            size: 48,
            radius: artworkRadius,
            identityTag: song.videoId,
            offlineArtworkPath: song.offlineArtworkPath,
            useOfflineArtwork: song.isDownloaded,
          );

    Widget miniSideButton({
      required IconData icon,
      required String tooltip,
      required Future<void> Function() onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: () async {
          await onPressed();
          await widget.onResync?.call();
        },
        icon: Icon(
          icon,
          color: buttonStyle == 2
              ? Colors.white.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.9),
          size: 25.2,
        ),
      );
    }

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
                    artworkWidget,
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
          miniSideButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Previous',
            onPressed: () => _method.invokeMethod('previous'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _MetrolistMiniPlayRing(
              progress: _progressCtrl,
              playing: playing,
              buffering: buffering,
              accent: accent,
              buttonStyle: buttonStyle,
              useLiquidGlass: useLiquidButtonChrome,
              onPressed: () async {
                await _method.invokeMethod('togglePlayPause');
                await widget.onResync?.call();
              },
            ),
          ),
          miniSideButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Next',
            onPressed: () => _method.invokeMethod('next'),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );

    final Widget shell;
    if (miniStyle == 2) {
      shell = playerBody;
    } else if (miniStyle == 1) {
      shell = _FoxyLiquidChromeShell(
        radius: 999,
        padding: EdgeInsets.zero,
        clear: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                accent.withValues(alpha: 0.01),
                Colors.transparent,
              ],
            ),
          ),
          child: playerBody,
        ),
      );
    } else if (widget.glass) {
      shell = _FoxyTintedChromeShell(
        radius: 999,
        tintAlpha: 0.07,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                accent.withValues(alpha: 0.035),
                Colors.transparent,
              ],
            ),
          ),
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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _pullDy = 0,
      onVerticalDragUpdate: (details) {
        _pullDy += details.primaryDelta ?? details.delta.dy;
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_pullDy < -34 || velocity < -360) {
          widget.onOpen();
        }
        _pullDy = 0;
      },
      onVerticalDragCancel: () => _pullDy = 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 0, 12, widget.bottomGap),
        child: shell,
      ),
    );
  }
}

/// Metrolist / Foxy-style circular progress around the mini-player play control.
class _MetrolistMiniPlayRing extends StatelessWidget {
  const _MetrolistMiniPlayRing({
    required this.progress,
    required this.playing,
    required this.buffering,
    required this.accent,
    required this.buttonStyle,
    required this.useLiquidGlass,
    required this.onPressed,
  });

  final Animation<double> progress;
  final bool playing;
  final bool buffering;
  final Color accent;
  final int buttonStyle;
  final bool useLiquidGlass;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: progress,
      builder: (context, child) {
        return CustomPaint(
          painter: _MetrolistMiniRingPainter(
            progress: progress.value.clamp(0.0, 1.0),
            accent: accent,
          ),
          child: child,
        );
      },
      child: SizedBox(
        width: 46,
        height: 46,
        child: Center(
          child: _MiniPlayButtonCore(
            playing: playing,
            buffering: buffering,
            accent: accent,
            buttonStyle: buttonStyle,
            useLiquidGlass: useLiquidGlass,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _MiniPlayButtonCore extends StatelessWidget {
  const _MiniPlayButtonCore({
    required this.playing,
    required this.buffering,
    required this.accent,
    required this.buttonStyle,
    required this.useLiquidGlass,
    required this.onPressed,
  });

  final bool playing;
  final bool buffering;
  final Color accent;
  final int buttonStyle;
  final bool useLiquidGlass;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = buffering
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          )
        : Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 26,
          );

    final child = SizedBox(width: 36, height: 36, child: Center(child: icon));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: child,
      ),
    );
  }
}

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _HomeSkeletonBox(width: double.infinity, height: 188, radius: 24),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 190),
          SizedBox(height: 14),
          _HomeSkeletonRail(),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 160),
          SizedBox(height: 14),
          _HomeSkeletonRail(),
          SizedBox(height: 28),
          _HomeSkeletonLine(width: 175),
          SizedBox(height: 14),
          _HomeSkeletonQuickPicks(),
        ],
      ),
    );
  }
}

class _HomeSkeletonLine extends StatelessWidget {
  const _HomeSkeletonLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) =>
      _HomeSkeletonBox(width: width, height: 24, radius: 8);
}

class _HomeSkeletonRail extends StatelessWidget {
  const _HomeSkeletonRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, _) =>
            const _HomeSkeletonBox(width: 160, height: 206, radius: 18),
      ),
    );
  }
}

class _HomeSkeletonQuickPicks extends StatelessWidget {
  const _HomeSkeletonQuickPicks();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 256,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        scrollDirection: Axis.horizontal,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisExtent: 320,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: 12,
        itemBuilder: (_, _) =>
            const _HomeSkeletonBox(width: 320, height: 58, radius: 12),
      ),
    );
  }
}

class _HomeSkeletonBox extends StatelessWidget {
  const _HomeSkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: const Color(0xFF161616),
        border: Border.all(color: Colors.white.withValues(alpha: 0.045)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.042),
            Colors.white.withValues(alpha: 0.018),
            Colors.white.withValues(alpha: 0.032),
          ],
        ),
      ),
    );
  }
}

class _HomeError extends StatelessWidget {
  const _HomeError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline =
        message.toLowerCase().contains('internet') ||
        message.toLowerCase().contains('network') ||
        message.toLowerCase().contains('host lookup');
    final title = offline ? 'No internet connection' : 'Home could not load';
    final subtitle = offline
        ? 'Check your connection, then try again.'
        : message;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 54, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Icon(Icons.wifi_off_rounded, size: 34),
            ),
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
          FilledButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}

class _SongSection {
  const _SongSection({
    required this.title,
    required this.songs,
    this.layout = 'shelf',
  });

  factory _SongSection.fromMap(Map<String, dynamic> map) => _SongSection(
    title: _cleanDisplayText(map['title'], fallback: 'For you'),
    layout: _cleanDisplayText(map['layout'], fallback: 'shelf'),
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
  _Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artwork,
    this.album,
    this.duration,
    this.description,
    this.uploadDate,
    this.viewCount,
    this.likeCount,
    this.channelName,
    this.source,
    this.isDownloaded = false,
    this.localPath,
    this.offlineArtworkPath,
  }) : highQualityArtwork = videoId.startsWith('local_')
           ? artwork
           : _upgradeYouTubeArtworkUrl(artwork, videoId),
       homeArtwork = videoId.startsWith('local_')
           ? artwork
           : _homeThumbnailArtworkUrl(artwork, videoId);

  factory _Song.fromMap(Map<String, dynamic> map) {
    final artwork = [map['thumbnail'], map['artworkUrl']]
        .map((value) => value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final lp = map['localPath']?.toString();
    final oap = map['offlineArtworkPath']?.toString();
    return _Song(
      videoId: _cleanDisplayText(map['videoId']),
      title: _cleanDisplayText(map['title'], fallback: 'Untitled'),
      artist: _cleanDisplayText(map['artist'], fallback: 'Unknown artist'),
      artwork: artwork,
      album: _cleanDisplayText(map['album']).ifBlank(''),
      duration: _cleanDisplayText(map['duration']).ifBlank(''),
      description: _cleanDisplayText(
        map['description'],
      ).ifBlank(_cleanDisplayText(map['descriptionText']).ifBlank('')),
      uploadDate: _cleanDisplayText(
        map['uploadDate'],
      ).ifBlank(_cleanDisplayText(map['publishedAt']).ifBlank('')),
      viewCount: _cleanDisplayText(
        map['viewCount'],
      ).ifBlank(_cleanDisplayText(map['views']).ifBlank('')),
      likeCount: _cleanDisplayText(
        map['likeCount'],
      ).ifBlank(_cleanDisplayText(map['likes']).ifBlank('')),
      channelName: _cleanDisplayText(
        map['channelName'],
      ).ifBlank(_cleanDisplayText(map['author']).ifBlank('')),
      source: _cleanDisplayText(map['source']).ifBlank(''),
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
  final String? description;
  final String? uploadDate;
  final String? viewCount;
  final String? likeCount;
  final String? channelName;
  final String? source;
  final bool isDownloaded;
  final String? localPath;
  final String? offlineArtworkPath;
  final String highQualityArtwork;
  final String homeArtwork;

  bool get isLocalTrack => videoId.startsWith('local_');

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': artwork,
    'artworkUrl': artwork,
    if (album != null) 'album': album,
    if (description != null && description!.isNotEmpty)
      'description': description,
    if (uploadDate != null && uploadDate!.isNotEmpty) 'uploadDate': uploadDate,
    if (viewCount != null && viewCount!.isNotEmpty) 'viewCount': viewCount,
    if (likeCount != null && likeCount!.isNotEmpty) 'likeCount': likeCount,
    if (channelName != null && channelName!.isNotEmpty)
      'channelName': channelName,
    if (source != null && source!.isNotEmpty) 'source': source,
    'isDownloaded': isDownloaded,
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

String _playerQueueSignature(dynamic queue) {
  if (queue is! List) return '';
  return queue
      .map((dynamic item) => _asMap(item)?['videoId']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .join('|');
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
    RegExp(r'/(hqdefault|sddefault|mqdefault|default)\.jpg'),
    '/maxresdefault.jpg',
  );
  return u;
}

String _homeThumbnailArtworkUrl(String url, String videoId) {
  var u = url.trim();
  if (u.isEmpty && videoId.isNotEmpty) {
    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }
  if (u.isEmpty) return u;
  u = u
      .replaceAll('=s88-', '=s480-')
      .replaceAll('=s120-', '=s480-')
      .replaceAll('=s180-', '=s480-')
      .replaceAll('=s360-', '=s480-')
      .replaceAll('=w88-h88', '=w480-h360')
      .replaceAll('=w120-h120', '=w480-h360')
      .replaceAll('=w360-h360', '=w480-h360');
  u = u.replaceAll(
    RegExp(r'/(maxresdefault|sddefault|mqdefault|default)\.jpg'),
    '/hqdefault.jpg',
  );
  return u;
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

extension on String {
  bool get isBlank => trim().isEmpty;

  String ifBlank(String fallback) => trim().isEmpty ? fallback : this;
}
