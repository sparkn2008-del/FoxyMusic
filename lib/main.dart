import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, ImageFilter;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

typedef FoxyOnPlay =
    Future<void> Function(_Song song, List<_Song> queue, {bool radioTail});

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;

/// Metrolist-style now playing foreground (backdrop stays full-bleed [_BlurBackdrop]).
const Color _kMetrolistNpSurface = Color(0xFF2E2E30);
const Color _kMetrolistNpSurfaceHigh = Color(0xFF3D3D42);
const Color _kMetrolistNpTime = Color(0xFF9E9E9E);

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xCC000000),
    Color.lerp(const Color(0xFF4A4334), accent, 0.28)!,
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoxyFlutterApp());
}

class FoxyFlutterApp extends StatefulWidget {
  const FoxyFlutterApp({super.key});

  @override
  State<FoxyFlutterApp> createState() => _FoxyFlutterAppState();
}

class _FoxyFlutterAppState extends State<FoxyFlutterApp> {
  _FlutterAppearance _appearance = const _FlutterAppearance();
  bool _dynamicSongColors = true;
  int? _songAccentArgb;
  int _paletteEpoch = 0;
  String _lastPlayerVideoId = '';
  StreamSubscription<dynamic>? _rootEventSub;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
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
          setState(() {
            _dynamicSongColors = nextDynamic;
            _songAccentArgb = nextAccent;
            _paletteEpoch = nextEpoch;
            _lastPlayerVideoId = vid;
          });
          if (nextDynamic &&
              (accentChanged || epochChanged || videoChanged)) {
            unawaited(_loadAppearance());
          }
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
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
        });
      }
    } catch (_) {}
  }

  Color get _effectiveAccent {
    if (_dynamicSongColors && _songAccentArgb != null) {
      return Color(_songAccentArgb! & 0xFFFFFFFF);
    }
    return _appearance.accent;
  }

  @override
  Widget build(BuildContext context) {
    final accent = _effectiveAccent;
    return MaterialApp(
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
      home: const FoxyHomeShell(),
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

String _playerProgressStyleLabel(int raw) {
  switch (raw.clamp(0, 3)) {
    case 0:
      return 'Default';
    case 1:
      return 'Slim';
    case 2:
      return 'Wavy';
    default:
      return 'Squiggly';
  }
}

/// Metrolist-style 2×2 picker (also used from the player overflow menu).
Future<int?> pickMetrolistSeekBarStyle(
  BuildContext context, {
  required int current,
}) {
  const previewAccent = Color(0xFFFF5C8D);
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      Widget tile(int style, String label) {
        final sel = current == style;
        return Material(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.pop(ctx, style),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: sel ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _MetrolistSeekPainter(
                        progress: 0.38,
                        dimmed: false,
                        style: style,
                        accent: previewAccent,
                        motion: 0,
                        motionPhase: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return AlertDialog(
        backgroundColor: const Color(0xFF181818),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Text(
          'Seek bar style',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.94),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: tile(0, 'Default')),
                  const SizedBox(width: 10),
                  Expanded(child: tile(2, 'Wavy')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: tile(1, 'Slim')),
                  const SizedBox(width: 10),
                  Expanded(child: tile(3, 'Squiggly')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    },
  );
}

String _formatStorageBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

class FoxyHomeShell extends StatefulWidget {
  const FoxyHomeShell({super.key});

  @override
  State<FoxyHomeShell> createState() => _FoxyHomeShellState();
}

class _FoxyHomeShellState extends State<FoxyHomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;
  final GlobalKey<_SearchTabState> _searchTabKey = GlobalKey<_SearchTabState>();
  final GlobalKey<_LibraryTabState> _libraryTabKey = GlobalKey<_LibraryTabState>();
  Map<String, dynamic> _player = const {};
  Map<String, dynamic> _account = const {};
  StreamSubscription<dynamic>? _sub;
  /// Avoid mini player + expanded sheet stacking (and Hero flights from feed art).
  bool _nowPlayingSheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAccount();
    unawaited(_syncPlayerFromNative());
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
  setState(() {
    _player = _detachPlayerState(state);
  });
}
      } else if (type == 'accountChanged') {
        unawaited(_loadAccount());
      }
    });
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
        setState(() => _player = _detachPlayerState(map));
      }
    } catch (_) {}
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
        account: _account,
        onAccountRefresh: _loadAccount,
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
    _sub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncPlayerFromNative());
    }
  }

  Future<void> _playSong(_Song song, List<_Song> queue, {bool radioTail = false}) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    final start = math.max(index, 0);
    if (mounted) {
      setState(() {
        _player = _detachPlayerState(<String, dynamic>{
          ..._player,
          'currentSong': song.toMap(),
          'isBuffering': true,
          'isPlaying': false,
          'positionMs': 0,
          'durationMs': 0,
          'queue': songs.map((item) => item.toMap()).toList(),
          'queueIndex': start,
        });
      });
    }
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': start,
      'radioTail': radioTail,
    });
    if (mounted) await _syncPlayerFromNative();
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
    setState(() => _nowPlayingSheetOpen = true);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NowPlayingSheet(
        player: _player,
        initialTab: initialTab,
        onNotifyHomePlayerSync: _syncPlayerFromNative,
        onPlay: _playSong,
        onDiscoverSearch: _openSearchWithQuery,
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _nowPlayingSheetOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSongMap = _asMap(_player['currentSong']) ?? const {};
final currentSong = _Song.fromMap(currentSongMap);

final hasSong = currentSong.videoId.isNotEmpty && currentSong.title.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniBottom = bottomInset + 10;
    final tabs = [
      _HomeTab(
        key: const PageStorageKey('home-tab'),
        currentVideoId: currentSong.videoId,
        onPlay: _playSong,
        account: _account,
        onOpenSettings: _openHomeSettings,
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
      ),
    ];
    final safeTab = _tabIndex.clamp(0, tabs.length - 1);
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          IndexedStack(index: safeTab, children: tabs),
          if (hasSong && !_nowPlayingSheetOpen)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: miniBottom),
                child: _MiniPlayer(
                  key: ValueKey<String>(
                'mini-${currentSong.videoId}-${_player['queueIndex'] ?? 0}-${_player['playerEpoch'] ?? 0}',
                ),
                  player: _player,
                  onOpen: () => _openPlayer(),
                  onResync: _syncPlayerFromNative,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _FoxyBottomNav(
        selectedIndex: safeTab,
        onSelected: (index) => setState(() => _tabIndex = index),
      ),
    ),
    );
  }
}

class _FoxyBottomNav extends StatelessWidget {
  const _FoxyBottomNav({required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_rounded, 'Home'),
      (Icons.search_rounded, 'Search'),
      (Icons.library_music_rounded, 'Library'),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: _FoxySurface(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          cornerRadius: 20,
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onSelected(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: selectedIndex == i
                              ? _kNavPillFill
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(999),
                        ),
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
  });

  final String currentVideoId;
  final FoxyOnPlay onPlay;
  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> with AutomaticKeepAliveClientMixin {
  List<_SongSection> _sections = _HomeCache.sections;
  bool _loading = _HomeCache.sections.isEmpty;
  String? _error = _HomeCache.error;
  String _homeChip = 'All';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    if (_HomeCache.sections.isEmpty) {
      _loadHome();
    }
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
    setState(() => _homeChip = label);
    if (label == 'All') {
      _loadHome(force: true);
    } else {
      _loadMood(label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    super.build(context);
    return RefreshIndicator(
      color: accent,
      backgroundColor: const Color(0xFF151515),
      onRefresh: () async {
        setState(() => _homeChip = 'All');
        await _loadHome(force: true);
      },
      child: CustomScrollView(
        key: const PageStorageKey('home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _HomeTopBar(
              account: widget.account,
              onOpenSettings: widget.onOpenSettings,
              selectedChip: _homeChip,
              onChipSelected: _onHomeChip,
            ),
          ),
          if (_loading)
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
          else if (_homeChip == 'All' && _sections.isEmpty)
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
                    FilledButton(
                      onPressed: () => unawaited(_loadHome(force: true)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (_homeChip == 'All')
            for (final sec in _sections)
              SliverToBoxAdapter(
                child: _SongShelf(
                  section: sec,
                  currentVideoId: widget.currentVideoId,
                  onPlay: widget.onPlay,
                ),
              )
          else if (_sections.isNotEmpty)
            SliverToBoxAdapter(
              child: _SongShelf(
                section: _sections.first,
                currentVideoId: widget.currentVideoId,
                onPlay: widget.onPlay,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
    required this.selectedChip,
    required this.onChipSelected,
  });

  final Map<String, dynamic> account;
  final VoidCallback onOpenSettings;
  final String selectedChip;
  final ValueChanged<String> onChipSelected;

  @override
  Widget build(BuildContext context) {
    final displayName =
        account['displayName']?.toString().ifBlank('Guest') ?? 'Guest';
    final avatar = account['avatarUrl']?.toString() ?? '';
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      bottom: false,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.42),
              border: Border(
                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              ),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.alphaBlend(
                    accent.withValues(alpha: 0.14),
                    Colors.black.withValues(alpha: 0.35),
                  ),
                  Colors.black.withValues(alpha: 0.48),
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text(
                          'FoxyMusic',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      _GlassIconButton(
                        tooltip: 'Notifications',
                        icon: Icons.notifications_none_rounded,
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
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
                        onPressed: () =>
                            ScaffoldMessenger.of(context).showSnackBar(
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
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AccountAvatar(
                        name: displayName,
                        imageUrl: avatar,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _homeGreeting(),
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
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final label in const [
                          'All',
                          'Relax',
                          'Sleep',
                          'Energize',
                          'Sad',
                        ])
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
          ),
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
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white.withValues(alpha: 0.88)),
          ),
        ),
      ),
    );
  }
}

String _homeGreeting() {
  final h = DateTime.now().hour;
  if (h < 5) return 'Up late';
  if (h < 12) return 'Good morning';
  if (h < 17) return 'Good afternoon';
  if (h < 22) return 'Good evening';
  return 'Wind down';
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
  });

  final Widget? leading;
  final String title;
  final VoidCallback? onRefresh;
  final String? subtitle;
  final VoidCallback? onSearch;
  final VoidCallback? onSparkle;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (leading != null) leading!,
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (onSparkle != null)
                  IconButton(
                    tooltip: 'Discovery',
                    onPressed: onSparkle,
                    icon: const Icon(Icons.auto_awesome_rounded),
                  ),
                if (onSearch != null)
                  IconButton(
                    tooltip: 'Search',
                    onPressed: onSearch,
                    icon: const Icon(Icons.search_rounded),
                  ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
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
      child: ActionChip(
        onPressed: onTap,
        backgroundColor: selected
            ? const Color(0xFF2C2C2C)
            : Colors.white.withValues(alpha: 0.04),
        side: BorderSide(
          color: Colors.white.withValues(alpha: selected ? 0 : 0.22),
        ),
        label: Row(
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool selected;
  final VoidCallback? onTap;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: margin,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(cornerRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(cornerRadius),
          onTap: onTap,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(cornerRadius),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.46)
                    : Colors.white.withValues(alpha: 0.065),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _FoxySectionHeader extends StatelessWidget {
  const _FoxySectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

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
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
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
    this.songDownloadProgress,
    this.showPlayAndMore = false,
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final IconData trailingIcon;
  final bool active;
  final int? index;
  final double thumbRadius;
  /// When set (e.g. active Media3 / progressive download), a thin bar is shown under the row.
  final double? songDownloadProgress;
  /// When true with [onMore], shows both play and overflow actions (e.g. Downloads tab).
  final bool showPlayAndMore;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Widget trailing;
    if (onMore != null && showPlayAndMore) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play',
            onPressed: onTap,
            icon: Icon(trailingIcon, color: active ? accent : Colors.white),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      );
    } else if (onMore != null) {
      trailing = IconButton(
        tooltip: 'More',
        onPressed: onMore,
        icon: const Icon(Icons.more_vert_rounded),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: onTap,
        icon: Icon(trailingIcon, color: active ? accent : Colors.white),
      );
    }

    return _FoxySurface(
      selected: active,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                url: song.artwork,
                size: 52,
                radius: thumbRadius,
                identityTag: song.videoId,
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
          if (songDownloadProgress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: songDownloadProgress!.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.black.withValues(alpha: 0.22),
                color: accent.withValues(alpha: 0.85),
              ),
            ),
          ],
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

class _SearchTab extends StatefulWidget {
  const _SearchTab({
    super.key,
    required this.onPlay,
    required this.onDiscoverSearch,
  });

  final FoxyOnPlay onPlay;
  final void Function(String query) onDiscoverSearch;

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<_Song> _results = const [];
  bool _loading = false;
  String _query = '';
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void applyExternalQuery(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    setState(() {
      _query = q;
      _controller.text = q;
      _error = null;
      if (q.length < 2) {
        _results = const [];
        _loading = false;
      } else {
        _loading = true;
      }
    });
    if (q.length >= 2) {
      _debounce = Timer(
        const Duration(milliseconds: 120),
        () => _search(q),
      );
    }
  }

  /// System back: clear the search field / results before leaving the tab.
  bool consumeAndroidBack() {
    if (_controller.text.trim().isEmpty &&
        _query.trim().isEmpty &&
        _results.isEmpty &&
        _error == null) {
      return false;
    }
    _debounce?.cancel();
    setState(() {
      _controller.clear();
      _query = '';
      _results = const [];
      _error = null;
      _loading = false;
    });
    return true;
  }

  void _openSearchSongMenu(_Song song) {
    showFoxySongOverflowMenu(
      context,
      song: song,
      onPlay: widget.onPlay,
      queueForPlay: _results.isEmpty ? [song] : _results,
      onDiscoverSearch: widget.onDiscoverSearch,
      onLibraryChanged: () async {},
      searchResultsForExtras: _results.length > 1 ? _results : null,
    );
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value;
      _error = null;
      if (value.trim().length < 2) _results = const [];
    });
    if (value.trim().length < 2) return;
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(value));
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response =
          _asMap(
            await _method.invokeMethod('search', {'query': query, 'limit': 45}),
          ) ??
          const {};
      final songs = (response['songs'] as List? ?? const [])
          .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
          .where((song) => song.videoId.isNotEmpty)
          .toList();
      if (!mounted || query != _controller.text.trim()) return;
      setState(() {
        _results = songs;
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final accent = Theme.of(context).colorScheme.primary;
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
      slivers: [
        SliverToBoxAdapter(
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Search',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Clear',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    autofocus: false,
                    textInputAction: TextInputAction.search,
                    onChanged: _onChanged,
                    onSubmitted: _search,
                    decoration: InputDecoration(
                      hintText: 'Search songs, artists, albums',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _loading
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: accent.withValues(alpha: 0.65),
                          width: 1.5,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_query.trim().length < 2) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in suggestions)
                          ActionChip(
                            label: Text(item),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.06),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                            onPressed: () {
                              _controller.text = item;
                              _controller.selection = TextSelection.collapsed(
                                offset: item.length,
                              );
                              _onChanged(item);
                            },
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
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
        if (_query.trim().length >= 2 &&
            !_loading &&
            _results.isEmpty &&
            _error == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: Icons.search_off_rounded,
              title: 'No results yet',
              subtitle: 'Try another song, artist, or album name.',
            ),
          )
        else ...[
          if (_results.isNotEmpty)
            SliverToBoxAdapter(
              child: _FoxySectionHeader(
                title: 'Songs',
                subtitle: '${_results.length} results',
              ),
            ),
          SliverList.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final song = _results[index];
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 12,
                showPlayAndMore: true,
                onTap: () => widget.onPlay(song, [song], radioTail: true),
                onMore: () => _openSearchSongMenu(song),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
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
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: Colors.black87, size: 28),
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
                        color: Colors.black87,
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
                          color: Colors.black.withValues(alpha: 0.55),
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
  });

  final FoxyOnPlay onPlay;
  final VoidCallback onOpenSearch;
  final void Function(String query) onDiscoverSearch;

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

  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _downloads = const [];
  List<_Song> _mostPlayed = const [];
  List<_Song> _recentlyAdded = const [];
  List<_UserPlaylist> _userPlaylists = const [];
  int _scope = _scopeHub;
  final Map<String, double> _downloadProgress = {};
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
        setState(() {
          _downloadProgress
            ..clear()
            ..addAll(next);
        });
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
    super.dispose();
  }

  Future<void> _load() async {
    final response =
        _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;
    setState(() {
      _liked = _songsFrom(response['liked']);
      _history = _songsFrom(response['history']);
      _downloads = _songsFrom(response['downloads']);
      _mostPlayed = _songsFrom(response['mostPlayed']);
      _recentlyAdded = _songsFrom(response['recentlyAdded']);
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
      case _scopeMostPlayed:
        return _mostPlayed;
      case _scopePlaylists:
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
      case _scopeMostPlayed:
        return 'Most played';
      case _scopePlaylists:
        return 'Your playlists';
      default:
        return 'Recently added';
    }
  }

  void _goHub() => setState(() => _scope = _scopeHub);

  /// Used from Home to jump into Library drill-ins.
  void openAtScope(int scope) {
    if (!mounted) return;
    setState(() {
      _scope = scope.clamp(_scopeHub, _scopePlaylists);
    });
  }

  /// System back: leave a library drill-in (Liked, History, …) before tabs handle back.
  bool consumeAndroidBack() {
    if (_hub) return false;
    _goHub();
    return true;
  }

  void _openSongOverflow(BuildContext context, _Song song, List<_Song> queue) {
    showFoxySongOverflowMenu(
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
    await playFetchedUserPlaylist(snackContext, p, widget.onPlay);
  }

  void _shuffleCurrent() {
    final s = _activeSongs;
    if (s.isEmpty) return;
    final list = List<_Song>.from(s)..shuffle(math.Random());
    widget.onPlay(list.first, list);
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

  Widget _hubGrid() {
    void pick(String q) => widget.onDiscoverSearch(q);
    return Padding(
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
      (Icons.trending_up_rounded, 'Most played', _scopeMostPlayed),
      (Icons.playlist_play_rounded, 'Playlists', _scopePlaylists),
    ];

    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _ScreenTopBar(
            leading: !_hub
                ? IconButton(
                    tooltip: 'Discover',
                    onPressed: _goHub,
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : null,
            title: 'Library',
            subtitle: _hub
                ? '${_liked.length} liked · ${_downloads.length} offline · ${_userPlaylists.length} playlists'
                : _sectionTitle,
            onRefresh: _load,
            onSearch: widget.onOpenSearch,
            onSparkle: () => widget.onDiscoverSearch('top songs charts today'),
          ),
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
                      child: ChoiceChip(
                        showCheckmark: _scope == chip.$3,
                        avatar: Icon(chip.$1, size: 18),
                        label: Text(chip.$2),
                        selected: _scope == chip.$3,
                        onSelected: (_) => setState(() => _scope = chip.$3),
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
                      onPressed: () async {
                        final c = TextEditingController();
                        final name = await showDialog<String>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            title: const Text('New playlist'),
                            content: TextField(
                              controller: c,
                              decoration:
                                  const InputDecoration(hintText: 'Name'),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dCtx),
                                child: const Text('Cancel'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                  dCtx,
                                  c.text.trim(),
                                ),
                                child: const Text('Create'),
                              ),
                            ],
                          ),
                        );
                        if (name != null && name.isNotEmpty && mounted) {
                          await _method.invokeMethod('playlistCreate', {
                            'name': name,
                          });
                          await _load();
                        }
                      },
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
                height: 88,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _userPlaylists.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final p = _userPlaylists[i];
                    final art =
                        p.songs.isEmpty ? '' : p.songs.first.artwork;
                    return Material(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          if (p.songs.isEmpty) return;
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: const Color(0xFF111111),
                            builder: (ctx) => DraggableScrollableSheet(
                              expand: false,
                              initialChildSize: 0.65,
                              maxChildSize: 0.92,
                              builder: (_, scroll) => ListView(
                                controller: scroll,
                                padding: const EdgeInsets.all(12),
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  for (var j = 0; j < p.songs.length; j++)
                                    _FoxySongTile(
                                      song: p.songs[j],
                                      index: j,
                                      thumbRadius: 10,
                                      showPlayAndMore: true,
                                      onTap: () =>
                                          widget.onPlay(p.songs[j], p.songs),
                                      onMore: () => _openSongOverflow(
                                        context,
                                        p.songs[j],
                                        p.songs,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: SizedBox(
                          width: 200,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: art.isEmpty
                                      ? Container(
                                          width: 48,
                                          height: 48,
                                          color: Colors.grey.shade800,
                                          child: const Icon(
                                            Icons.queue_music_rounded,
                                          ),
                                        )
                                      : Image.network(
                                          art,
                                          width: 48,
                                          height: 48,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
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
                                  backgroundColor:
                                      Colors.black.withValues(alpha: 0.25),
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
                        'Create a playlist with “New” above, add songs from the ··· menu, or sign in on the Account tab to load your YouTube Music playlists.',
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
                            leading: Icon(
                              p.isYoutube
                                  ? Icons.cloud_queue_rounded
                                  : Icons.queue_music_rounded,
                            ),
                            title: Text(p.name),
                            subtitle: Text(
                              p.isYoutube
                                  ? '${p.displayTrackCount} songs · YouTube Music'
                                  : '${p.displayTrackCount} songs · On device',
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
        else if (songs.isEmpty && _scope != _scopePlaylists)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_sectionTitle),
              title: 'Nothing here yet',
              subtitle:
                  'Play music, like tracks, and download for offline — your library grows automatically.',
            ),
          )
        else if (_scope != _scopePlaylists && songs.isNotEmpty)
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              final dl = _scope == _scopeDownloads;
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 12,
                trailingIcon: dl
                    ? Icons.offline_pin_rounded
                    : Icons.play_circle_fill_rounded,
                showPlayAndMore: true,
                songDownloadProgress:
                    dl ? _downloadProgress[song.videoId] : null,
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

class _AccountHubBody extends StatefulWidget {
  const _AccountHubBody({required this.onPlay});

  final FoxyOnPlay onPlay;

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

List<_UserPlaylist> _userPlaylistsFrom(dynamic raw) =>
    (raw as List? ?? const [])
        .map((e) => _UserPlaylist.fromMap(_asMap(e) ?? const {}))
        .where((p) => p.id.isNotEmpty)
        .toList();

Future<void> playFetchedUserPlaylist(
  BuildContext context,
  _UserPlaylist p,
  FoxyOnPlay onPlay,
) async {
  if (p.songs.isNotEmpty) {
    onPlay(p.songs.first, p.songs);
    return;
  }
  if (!p.isYoutube) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This playlist is empty')),
    );
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

Future<void> showFoxySongOverflowMenu(
  BuildContext context, {
  required _Song song,
  required FoxyOnPlay onPlay,
  required List<_Song> queueForPlay,
  void Function(String query)? onDiscoverSearch,
  Future<void> Function()? onLibraryChanged,
  List<_Song>? searchResultsForExtras,
  String bulkQueuePlayTitle = 'Play all search results',
  String bulkQueuePlaySubtitle = 'Keeps the current result order',
  VoidCallback? onOpenLyricsTabInPlayer,
  int? playerProgressStyleForPicker,
  Future<void> Function(int style)? onPickPlayerProgressStyle,
  bool showRemoveFromQueue = false,
}) async {
  final feed = _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
  final likedIds =
      Set<String>.from(_songsFrom(feed['liked']).map((s) => s.videoId));
  final downloadedIds =
      Set<String>.from(_songsFrom(feed['downloads']).map((s) => s.videoId));
  final userPlaylists = _userPlaylistsFrom(feed['userPlaylists']);
  final appearance = _asMap(await _method.invokeMethod('getAppearance')) ?? const {};
  final crossfadeOn = ((appearance['crossfadeMs'] ?? 0) as num).toInt() > 0;
  final lrclib = appearance['lyricsPreferLrclib'] != false;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
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
              const Divider(height: 1),
              if (searchResultsForExtras != null &&
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
                    await _method.invokeMethod(
                      'removeDownload',
                      {'song': song.toMap()},
                    );
                  } else {
                    await _method.invokeMethod(
                      'download',
                      {'song': song.toMap()},
                    );
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
                  _method.invokeMethod('addToQueue', {'song': song.toMap()});
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
                title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Play this track'),
                onTap: () {
                  Navigator.pop(ctx);
                  onPlay(song, [song]);
                },
              ),
              ListTile(
                leading: const Icon(Icons.radio_rounded),
                title: const Text('Start radio'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final mix = _asMap(
                        await _method.invokeMethod('moodMix', {
                          'mood': '${song.title} ${song.artist}',
                        }),
                      ) ??
                      const {};
                  final songs = (mix['songs'] as List? ?? const [])
                      .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
                      .where((s) => s.videoId.isNotEmpty)
                      .toList();
                  if (songs.isEmpty) return;
                  await _method.invokeMethod('playQueue', {
                    'songs': songs.map((e) => e.toMap()).toList(),
                    'startIndex': 0,
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.lyrics_rounded),
                title: const Text('Main lyrics provider'),
                subtitle: Text(
                  lrclib ? 'LRCLIB (when available)' : 'YouTube captions',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Change lyrics source in Settings → Playback & data.',
                      ),
                    ),
                  );
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
                      ? 'Crossfade is on — speed changes may sound uneven.'
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
                  subtitle: const Text('Full-width lyrics in this player'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpenLyricsTabInPlayer!();
                  },
                ),
              if (onPickPlayerProgressStyle != null &&
                  playerProgressStyleForPicker != null)
                ListTile(
                  leading: const Icon(Icons.linear_scale_rounded),
                  title: const Text('Seek bar appearance'),
                  subtitle: Text(
                    'Current: ${_playerProgressStyleLabel(playerProgressStyleForPicker!)}',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (!context.mounted) return;
                    final next = await pickMetrolistSeekBarStyle(
                      context,
                      current: playerProgressStyleForPicker!,
                    );
                    if (next != null && context.mounted) {
                      await onPickPlayerProgressStyle!(next);
                    }
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
                      const SnackBar(content: Text('Link copied to clipboard')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
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
                      onPressed: () => Navigator.pop(
                        dCtx,
                        nameCtrl.text.trim(),
                      ),
                      child: const Text('Create'),
                    ),
                  ],
                ),
              );
              if (name != null && name.isNotEmpty && context.mounted) {
                await _method.invokeMethod('playlistCreate', {'name': name});
                await onChanged?.call();
                if (!context.mounted) return;
                await _pickPlaylistToAddSong(
                  context,
                  song: song,
                  playlists: _userPlaylistsFrom(
                    (_asMap(await _method.invokeMethod('libraryFeed')) ??
                            const {})['userPlaylists'],
                  ),
                  onChanged: onChanged,
                );
              }
            },
          ),
          if (playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Text(
                'No playlists yet. Tap “New playlist” above.',
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
                      p.isYoutube ? Icons.cloud_queue_rounded : Icons.queue_music_rounded,
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      p.isYoutube
                          ? '${p.displayTrackCount} songs · YouTube Music'
                          : '${p.displayTrackCount} songs · On device',
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

class _SettingsSheetState extends State<_SettingsSheet> {
  late Map<String, dynamic> _m;
  late TextEditingController _contentLang;
  late TextEditingController _appLang;
  late TextEditingController _proxyEp;

  @override
  void initState() {
    super.initState();
    _m = Map<String, dynamic>.from(widget.appearance);
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
    _contentLang.dispose();
    _appLang.dispose();
    _proxyEp.dispose();
    super.dispose();
  }

  Future<void> _apply(Map<String, dynamic> patch) async {
    await widget.onSetAppearance(patch);
    if (!mounted) return;
    setState(() => _m.addAll(patch));
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
    final ok = map['ok'] == true;
    final tag = map['tagName']?.toString() ?? '';
    final html = map['htmlUrl']?.toString() ?? '';
    final apk = map['downloadUrl']?.toString() ?? '';
    final err = map['error']?.toString() ?? '';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ok ? 'Latest release' : 'Update check'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!ok) Text(err.isEmpty ? 'Unknown error' : err),
              if (ok && tag.isNotEmpty) Text('Tag: $tag'),
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
                _openExternal(html);
              },
              child: const Text('Release page'),
            ),
          if (apk.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _openExternal(apk);
              },
              child: const Text('Download APK'),
            ),
        ],
      ),
    );
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

  Future<void> _openWebLogin([String mode = 'webview']) async {
    final ok = await _method.invokeMethod('openWebLogin', {'mode': mode}) == true;
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
            'If you use the YouTube Music app first, come back and tap “Sign in inside FoxyMusic” to finish. Google does not share that login with other apps.',
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

  @override
  Widget build(BuildContext context) {
    final theme = _int('themePalette', 0).clamp(0, 3);
    final mode = _int('themeMode', 0).clamp(0, 2);
    final thumbAccent = _bool('dynamicSongColors');
    final blur = _bool('blurEffects', true);
    final compact = _bool('compactPlayer');
    final gestures = _bool('gestureControls', true);
    final persistent = _bool('persistentQueue', true);
    final saveHistory = _bool('saveHistory', true);
    final sponsor = _bool('sponsorBlockEnabled', true);
    final lrclib = _bool('lyricsPreferLrclib', true);
    final proxyOn = _bool('proxyEnabled');
    final norm = _bool('normalizeVolume');
    final skipSil = _bool('skipSilence');
    final backup = _bool('autoBackupEnabled');
    final tier = _int('streamQualityTier', 2).clamp(0, 2);
    final cross = _int('crossfadeMs', 0);
    final prog = _int('playerProgressStyle', 2).clamp(0, 3);
    final progMotion = _int('playerSeekMotion', 0).clamp(0, 2);

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (context, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF101010),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
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
              const Text(
                'Settings',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
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
                          label: const Text('Sign in inside FoxyMusic'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () => _openWebLogin('ytmapp'),
                          icon: const Icon(Icons.play_circle_outline_rounded, size: 20),
                          label: const Text('Open YouTube Music app'),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openWebLogin('browser'),
                          icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                          label: const Text('Open system browser instead'),
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
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _SettingsDrawerHeader(
                theme: theme,
                mode: mode,
                onTheme: (i) => _apply({
                  'themePalette': i.clamp(0, 3),
                  'accentArgb': 0xFFFF1744,
                }),
                onMode: (i) => _apply({'themeMode': i}),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                title: 'Themes',
                subtitle:
                    'Pick a base palette. With “Song thumbnail accent”, Flutter reads the same artwork accent computed in Kotlin (no extra packages).',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        selected: theme == i,
                        label: Text(['Foxy', 'Aurora', 'Gold', 'Rose'][i]),
                        onSelected: (_) => _apply({
                          'themePalette': i,
                          'accentArgb': 0xFFFF1744,
                        }),
                      ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'Theme mode',
                subtitle: 'System, always dark, or always light',
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'System'),
                      (1, 'Dark'),
                      (2, 'Light'),
                    ])
                      ChoiceChip(
                        selected: mode == item.$1,
                        label: Text(item.$2),
                        onSelected: (_) => _apply({'themeMode': item.$1}),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: thumbAccent,
                title: const Text(
                  'Song thumbnail accent',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text(
                  'Follow artwork colors on the full player when enabled',
                ),
                onChanged: (value) => _apply({
                  'dynamicSongColors': value,
                  'accentArgb': 0xFFFF1744,
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: blur,
                title: const Text(
                  'Blur on player',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: const Text('Blurred artwork vs solid theme surfaces'),
                onChanged: (v) => _apply({'blurEffects': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: compact,
                title: const Text(
                  'Compact mini-player',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onChanged: (v) => _apply({'compactPlayer': v}),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: gestures,
                title: const Text(
                  'Swipe to change song',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onChanged: (v) => _apply({'gestureControls': v}),
              ),
              _SettingsCard(
                title: 'Stream quality',
                subtitle:
                    'Caps preferred adaptive bitrate on the Kotlin extractor (low / medium / best).',
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final item in const [
                      (0, 'Low ~64'),
                      (1, 'Medium ~128'),
                      (2, 'High'),
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
                title: 'Crossfade',
                subtitle: 'Volume ramp between tracks (native player)',
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
                title: 'Now playing · seek bar',
                subtitle:
                    'Metrolist-style fullscreen player: choose the bar shape in a 2×2 picker, '
                    'then add motion. Wavy and squiggly use your accent on the played side.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bar style',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          final v = await pickMetrolistSeekBarStyle(
                            context,
                            current: prog,
                          );
                          if (v != null && mounted) {
                            await _apply({'playerProgressStyle': v});
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _playerProgressStyleLabel(prog),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap to open style gallery',
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.5,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.white.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Motion & animation',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pulse animates the thumb; shimmer adds a soft sweep on the played segment; '
                      'with Wave or Squiggle, motion also scrolls the waveform.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.52),
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < 3; i++)
                          ChoiceChip(
                            showCheckmark: false,
                            selected: progMotion == i,
                            label: Text(
                              ['Off', 'Thumb pulse', 'Played shimmer'][i],
                            ),
                            onSelected: (_) =>
                                _apply({'playerSeekMotion': i}),
                          ),
                      ],
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
                      title: const Text('Restore queue after restart'),
                      onChanged: (v) => _apply({'persistentQueue': v}),
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
                      value: lrclib,
                      title: const Text('Prefer LRCLIB for lyrics'),
                      onChanged: (v) => _apply({'lyricsPreferLrclib': v}),
                    ),
                  ],
                ),
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
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
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
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
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
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
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
                  'Persisted for a future DSP pass (reserved)',
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
                  'Persisted for future ExoPlayer wiring (reserved)',
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
                subtitle: const Text('UI + persistence only for now'),
                onChanged: (v) => _apply({'autoBackupEnabled': v}),
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
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                      ),
                      child: const Text('System equalizer'),
                    ),
                    OutlinedButton(
                      onPressed: _checkUpdate,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                      ),
                      child: const Text('Check GitHub release'),
                    ),
                  ],
                ),
              ),
              _SettingsCard(
                title: 'About',
                subtitle: 'FoxyMusic',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'v1.1 beta',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Playback and YouTube Music data run on-device in Kotlin; '
                      'this Flutter layer is the main UI.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () {
                            showLicensePage(context: context);
                          },
                          child: const Text('Open-source licenses'),
                        ),
                        TextButton(
                          onPressed: () => _openExternal(
                            'https://github.com/sparkn2008-del/FoxyMusic',
                          ),
                          child: const Text('GitHub project'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: open the ⋮ menu on the full player for sleep timer and queue tools.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
        );
      },
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181818),
        borderRadius: BorderRadius.circular(_kCardRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
      ),
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

class _SettingsDrawerHeader extends StatelessWidget {
  const _SettingsDrawerHeader({
    required this.theme,
    required this.mode,
    required this.onTheme,
    required this.onMode,
  });

  final int theme;
  final int mode;
  final ValueChanged<int> onTheme;
  final ValueChanged<int> onMode;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final groups = [
      (Icons.palette_rounded, 'Appearance', 'Colors, blur, nav'),
      (Icons.album_rounded, 'Player', 'Seek bar style, motion, mini player'),
      (Icons.graphic_eq_rounded, 'Audio', 'Quality, crossfade'),
      (Icons.lyrics_rounded, 'Lyrics', 'Provider and animation'),
    ];
    return Material(
      color: Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_kCardRadius),
          border: Border.all(color: Colors.white.withValues(alpha: 0.065)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.settings_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Look, playback shell, and audio',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in groups)
                  Chip(
                    avatar: Icon(item.$1, size: 18),
                    label: Text(item.$2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CompactSegment(
                    label: [
                      'Foxy',
                      'Aurora',
                      'Gold',
                      'Rose',
                    ][theme.clamp(0, 3)],
                    icon: Icons.color_lens_rounded,
                    onTap: () => onTheme((theme + 1) % 4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CompactSegment(
                    label: ['System', 'Dark', 'Light'][mode.clamp(0, 2)],
                    icon: Icons.dark_mode_rounded,
                    onTap: () => onMode((mode + 1) % 3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactSegment extends StatelessWidget {
  const _CompactSegment({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
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

class _SongShelf extends StatelessWidget {
  const _SongShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final FoxyOnPlay onPlay;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MUSIC FOR YOU',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: section.songs.isEmpty
                          ? null
                          : () => onPlay(section.songs.first, section.songs),
                      child: const Text('Play'),
                    ),
                    IconButton(
                      tooltip: 'Shuffle',
                      onPressed: section.songs.isEmpty
                          ? null
                          : () {
                              final list = List<_Song>.from(section.songs)
                                ..shuffle(math.Random());
                              onPlay(list.first, list);
                            },
                      icon: Icon(Icons.shuffle_rounded, color: accent),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 192,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final song = section.songs[index];
                return _SongCard(
                  song: song,
                  active: song.videoId == currentVideoId,
                  onTap: () => onPlay(song, section.songs),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.song,
    required this.active,
    required this.onTap,
  });

  final _Song song;
  final bool active;
  final VoidCallback onTap;

  static const double _thumb = 126;
  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: _thumb,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _Artwork(
                  url: song.artwork,
                  size: _thumb,
                  radius: _radius,
                  identityTag: song.videoId,
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: active ? 1 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_radius),
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: accent,
                        size: 30,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _kMetrolistNpTime,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    super.key,
    required this.player,
    required this.onOpen,
    this.onResync,
  });

  final Map<String, dynamic> player;
  final VoidCallback onOpen;
  final Future<void> Function()? onResync;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dynamicOn = player['dynamicSongColors'] != false;
    final barColor =
        dynamicOn ? _miniPlayerTint(accent) : _kMiniPlayerFallbackTint;
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final liked = player['songIsLiked'] == true;
    final playing = player['isPlaying'] == true;
    final buffering = player['isBuffering'] == true;
    final duration = ((player['durationMs'] ?? 0) as num).toDouble();
    final position = ((player['positionMs'] ?? 0) as num).toDouble();
    final progress = duration <= 0
        ? 0.0
        : (position / duration).clamp(0.0, 1.0);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 2),
        child: Material(
          color: barColor,
          elevation: 6,
          shadowColor: Colors.black54,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 58,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: onOpen,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Row(
                              children: [
                                _Artwork(
                                  url: song.artwork,
                                  size: 42,
                                  radius: 12,
                                  identityTag: song.videoId,
                                  offlineArtworkPath: song.offlineArtworkPath,
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
                                        ),
                                      ),
                                      Text(
                                        song.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.7,
                                          ),
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
                        tooltip: 'Previous',
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 26,
                        onPressed: () async {
                          await _method.invokeMethod('previous');
                          await onResync?.call();
                        },
                        icon: Icon(
                          Icons.skip_previous_outlined,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      IconButton(
                        tooltip: playing ? 'Pause' : 'Play',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          await _method.invokeMethod('togglePlayPause');
                          await onResync?.call();
                        },
                        icon: buffering
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Container(
                                width: 40,
                                height: 40,
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
                                  size: 28,
                                ),
                              ),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 26,
                        onPressed: () async {
                          await _method.invokeMethod('next');
                          await onResync?.call();
                        },
                        icon: Icon(
                          Icons.skip_next_outlined,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      IconButton(
                        tooltip: liked ? 'Unlike' : 'Like',
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        padding: EdgeInsets.zero,
                        iconSize: 24,
                        onPressed: () async {
                          try {
                            await _method.invokeMethod(
                              liked ? 'unlike' : 'like',
                              {'song': song.toMap()},
                            );
                          } finally {
                            await onResync?.call();
                          }
                        },
                        icon: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: liked
                              ? const Color(0xFFE53935)
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 2,
                  color: Colors.white.withValues(alpha: 0.85),
                  backgroundColor: Colors.black.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetrolistPlayerRoundIconButton extends StatelessWidget {
  const _MetrolistPlayerRoundIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 44,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: _kMetrolistNpSurface,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: size * 0.46,
            color: iconColor ?? Colors.white.withValues(alpha: 0.88),
          ),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

class _MetrolistPlayerSectionLabel extends StatelessWidget {
  const _MetrolistPlayerSectionLabel(this.text, {this.trailing});

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
            Expanded(
              child: Text(text.toUpperCase(), style: upper),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          color: Colors.white.withValues(alpha: 0.08),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.player,
    this.initialTab = 0,
    this.onNotifyHomePlayerSync,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final Map<String, dynamic> player;
  final int initialTab;
  final Future<void> Function()? onNotifyHomePlayerSync;
  final FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  late Map<String, dynamic> _player =
      _detachPlayerState(_asMap(widget.player) ?? <String, dynamic>{});
  StreamSubscription<dynamic>? _sub;
  late int _tab = widget.initialTab;
  int _progressStyle = 2;
  int _seekMotion = 0;
  List<_LyricLine> _lyrics = const [];
  String? _lyricsFor;
  bool _lyricsLoading = false;
  double _artworkSwipeDx = 0;
  bool _blurPlayerBackdrop = true;

  @override
  void initState() {
    super.initState();
    _loadAppearance();
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          final detached = _detachPlayerState(state);
          setState(() => _player = detached);
          _loadLyricsIfNeeded(detached);
        }
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
      }
    });
    _loadLyricsIfNeeded(_player);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    setState(
      () {
        _progressStyle = ((map['playerProgressStyle'] ?? 2) as num)
            .toInt()
            .clamp(0, 3);
        _seekMotion = ((map['playerSeekMotion'] ?? 0) as num).toInt().clamp(0, 2);
        _blurPlayerBackdrop = map['blurEffects'] != false;
      },
    );
  }

  Future<void> _loadLyricsIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    if (song.videoId.isEmpty || _lyricsFor == song.videoId || _lyricsLoading) {
      return;
    }
    _lyricsFor = song.videoId;
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

  Future<void> _setProgressStyle(int style) async {
    setState(() => _progressStyle = style);
    await _method.invokeMethod('setPlayerProgressStyle', {'style': style});
  }

  void _openMenu(_Song song) {
    final parent = context;
    final onPlay = widget.onPlay;
    if (onPlay == null) return;
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((s) => s.videoId.isNotEmpty)
        .toList();
    showFoxySongOverflowMenu(
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
        if (mounted) setState(() => _tab = 1);
      },
      playerProgressStyleForPicker: _progressStyle,
      onPickPlayerProgressStyle: _setProgressStyle,
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

  void _shareSongLink(_Song song) {
    if (song.videoId.isEmpty) return;
    Clipboard.setData(
      ClipboardData(
        text: 'https://music.youtube.com/watch?v=${song.videoId}',
      ),
    );
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(content: Text('Link copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    final playing = _player['isPlaying'] == true;
    final buffering = _player['isBuffering'] == true;
    final shuffle = _player['shuffleEnabled'] == true;
    final repeat = (_player['repeatMode'] ?? 'Off').toString();
    final duration = ((_player['durationMs'] ?? 0) as num).toDouble();
    final position = ((_player['positionMs'] ?? 0) as num).toDouble();
    final hintMs = _durationHintMsFromCatalog(song.duration);
    final effectiveDurMs = duration > 750 ? duration : (hintMs?.toDouble() ?? 0.0);
    final progress = effectiveDurMs <= 0
        ? 0.0
        : (position / effectiveDurMs).clamp(0.0, 1.0);
    final endTimeLabel =
        effectiveDurMs > 750 ? _fmt(effectiveDurMs.round()) : '—:—';
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .toList();
    final queueIndex = ((_player['queueIndex'] ?? -1) as num).toInt();
    final npSubtitle = song.isDownloaded
        ? 'Playlist downloaded'
        : (queue.length > 1
            ? 'Queue · ${queue.length} tracks'
            : 'Playing');

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.78,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        final padL = 14.0 + MediaQuery.paddingOf(context).left;
        final padR = 14.0 + MediaQuery.paddingOf(context).right;
        final padBottom = MediaQuery.paddingOf(context).bottom;
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _BlurBackdrop(
                  url: song.artwork,
                  blurEnabled: _blurPlayerBackdrop,
                  offlineArtworkPath: song.offlineArtworkPath,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.42),
                          Colors.black.withValues(alpha: 0.62),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padL, 8, padR, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(top: 4, bottom: 8),
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
                              onPressed: () => Navigator.pop(context),
                            ),
                            Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _PlayerTabs(
                                    accent: accent,
                                    selected: _tab,
                                    onPick: (tab) =>
                                        setState(() => _tab = tab),
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
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(padL, 0, padR, 0),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: switch (_tab) {
                          1 => SingleChildScrollView(
                            key: const ValueKey('lyrics'),
                            controller: scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: padBottom + 8),
                            child: _LyricsTab(
                              lines: _lyrics,
                              loading: _lyricsLoading,
                              positionMs: position.round(),
                              accent: accent,
                            ),
                          ),
                          2 => SingleChildScrollView(
                            key: const ValueKey('queue'),
                            controller: scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.only(bottom: padBottom + 8),
                            child: _QueueTab(
                              queue: queue,
                              currentIndex: queueIndex,
                              onPlay: widget.onPlay,
                              onDiscoverSearch: widget.onDiscoverSearch,
                            ),
                          ),
                          _ => KeyedSubtree(
                            key: const ValueKey('player'),
                            child: LayoutBuilder(
                              builder: (context, c) {
                                final prevEnabled = queueIndex > 0;
                                final nextEnabled = queue.isNotEmpty &&
                                    queueIndex >= 0 &&
                                    queueIndex < queue.length - 1;
                                final maxW = c.maxWidth;
                                final maxH = c.maxHeight;
                                final artSide = math.min(
                                  maxW * 0.90,
                                  math.max(300.0, maxH * 0.48),
                                );
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: scrollController,
                                        physics:
                                            const AlwaysScrollableScrollPhysics(),
                                        padding:
                                            const EdgeInsets.only(bottom: 24),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                             const SizedBox(height: 24),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Text(
                                                    'NOW PLAYING',
                                                    textAlign:
                                                        TextAlign.center,
                                                    style: TextStyle(
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.95,
                                                      ),
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 1.2,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                    ),
                                                    child: Text(
                                                      npSubtitle,
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                          alpha: 0.55,
                                                        ),
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 40),
                                              Center(
                                                child: GestureDetector(
                                                  onHorizontalDragUpdate:
                                                      (details) {
                                                    _artworkSwipeDx +=
                                                        details.delta.dx;
                                                  },
                                                  onHorizontalDragEnd: (_) {
                                                    if (_artworkSwipeDx > 64) {
                                                      _method.invokeMethod(
                                                        'previous',
                                                      );
                                                    } else if (_artworkSwipeDx <
                                                        -64) {
                                                      _method.invokeMethod(
                                                        'next',
                                                      );
                                                    }
                                                    _artworkSwipeDx = 0;
                                                  },
                                                  child: _PlayerArtwork(
                                                    url: song.artwork,
                                                    playing: playing &&
                                                        !buffering,
                                                    tag:
                                                        'art-${song.videoId}',
                                                    offlineArtworkPath: song
                                                        .offlineArtworkPath,
                                                    maxSide: artSide
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          song.title,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 22,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800,
                                                            height: 1.12,
                                                            color: Colors.white,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Text(
                                                          song.artist,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 15,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            height: 1.2,
                                                            color: Colors.white
                                                                .withValues(
                                                              alpha: 0.68,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Copy link',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      Icons.share_outlined,
                                                      color: Colors.white
                                                          .withValues(
                                                        alpha: 0.92,
                                                      ),
                                                      size: 22,
                                                    ),
                                                    onPressed: () =>
                                                        _shareSongLink(song),
                                                  ),
                                                  IconButton(
                                                    tooltip: song.isDownloaded
                                                        ? 'Downloaded'
                                                        : 'Download',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      song.isDownloaded
                                                          ? Icons
                                                              .download_done_rounded
                                                          : Icons
                                                              .download_outlined,
                                                      color: song.isDownloaded
                                                          ? const Color(
                                                              0xFF81C784,
                                                            )
                                                          : Colors.white
                                                              .withValues(
                                                              alpha: 0.92,
                                                            ),
                                                      size: 22,
                                                    ),
                                                    onPressed:
                                                        song.isDownloaded
                                                            ? null
                                                            : () async {
                                                                await _method
                                                                    .invokeMethod(
                                                                  'download',
                                                                  {
                                                                    'song': song
                                                                        .toMap(),
                                                                  },
                                                                );
                                                                if (!mounted) {
                                                                  return;
                                                                }
                                                                final snap =
                                                                    _asMap(
                                                                  await _method
                                                                      .invokeMethod(
                                                                    'getPlayerState',
                                                                  ),
                                                                );
                                                                if (snap !=
                                                                    null) {
                                                                  setState(
                                                                    () => _player =
                                                                        _detachPlayerState(
                                                                      snap,
                                                                    ),
                                                                  );
                                                                }
                                                              },
                                                  ),
                                                  IconButton(
                                                    tooltip: _player['songIsLiked'] ==
                                                            true
                                                        ? 'Unlike'
                                                        : 'Like',
                                                    padding: EdgeInsets.zero,
                                                    constraints:
                                                        const BoxConstraints(
                                                      minWidth: 40,
                                                      minHeight: 40,
                                                    ),
                                                    icon: Icon(
                                                      _player['songIsLiked'] ==
                                                              true
                                                          ? Icons
                                                              .favorite_rounded
                                                          : Icons
                                                              .favorite_border_rounded,
                                                      color: _player['songIsLiked'] ==
                                                              true
                                                          ? const Color(
                                                              0xFFE57373,
                                                            )
                                                          : Colors.white
                                                              .withValues(
                                                              alpha: 0.92,
                                                            ),
                                                      size: 24,
                                                    ),
                                                    onPressed: () async {
                                                      final m = _player['songIsLiked'] ==
                                                              true
                                                          ? 'unlike'
                                                          : 'like';
                                                      await _method
                                                          .invokeMethod(
                                                        m,
                                                        {
                                                          'song':
                                                              song.toMap(),
                                                        },
                                                      );
                                                      if (!mounted) return;
                                                      final snap = _asMap(
                                                        await _method
                                                            .invokeMethod(
                                                          'getPlayerState',
                                                        ),
                                                      );
                                                      if (snap != null) {
                                                        setState(
                                                          () => _player =
                                                              _detachPlayerState(
                                                            snap,
                                                          ),
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              if (buffering)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      8,
                                                    ),
                                                    child:
                                                        LinearProgressIndicator(
                                                      minHeight: 4,
                                                      backgroundColor: Colors
                                                          .grey.shade800
                                                          .withValues(
                                                        alpha: 0.9,
                                                      ),
                                                      color: Colors
                                                          .grey.shade500,
                                                    ),
                                                  ),
                                                ),
                                              _MetrolistSeekBar(
                                               value: progress,
                                                enabled: effectiveDurMs > 750,
                                                style: 0,
                                                motion: _seekMotion,
                                                accent: accent,
                                                onSeek: (value) => _method.invokeMethod('seekTo', {
                                                'positionMs': (effectiveDurMs * value).round(),
                                               }),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                  6,
                                                  6,
                                                  6,
                                                  0,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      _fmt(position.round()),
                                                      style: const TextStyle(
                                                        color: _kMetrolistNpTime,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures(),
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      endTimeLabel,
                                                      style: const TextStyle(
                                                        color: _kMetrolistNpTime,
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontFeatures: [
                                                          FontFeature
                                                              .tabularFigures(),
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
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.black.withValues(
                                              alpha: 0.0,
                                            ),
                                            Colors.black.withValues(
                                              alpha: 0.55,
                                            ),
                                          ],
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          top: 4,
                                          bottom: 8,
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _SimpMusicPlayerControlLayout(
                                              shuffle: shuffle,
                                              repeatMode: repeat,
                                              playing: playing,
                                              buffering: buffering,
                                              prevEnabled: prevEnabled,
                                              nextEnabled: nextEnabled,
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.spaceEvenly,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Track info',
                                                  icon: Icon(
                                                    Icons
                                                        .info_outline_rounded,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    size: 24,
                                                  ),
                                                  onPressed: () =>
                                                      _showTrackInfo(song),
                                                ),
                                                IconButton(
                                                  tooltip: 'Lyrics',
                                                  icon: Icon(
                                                    Icons.lyrics_outlined,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    size: 24,
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _tab = 1,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Queue',
                                                  icon: Icon(
                                                    Icons.queue_music_rounded,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    size: 24,
                                                  ),
                                                  onPressed: () => setState(
                                                    () => _tab = 2,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Sleep timer',
                                                  icon: Icon(
                                                    Icons.bedtime_outlined,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    size: 24,
                                                  ),
                                                  onPressed: () =>
                                                      _showSleepTimerSheet(
                                                    context,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Equalizer',
                                                  icon: Icon(
                                                    Icons.graphic_eq_rounded,
                                                    color: Colors.white
                                                        .withValues(
                                                      alpha: 0.92,
                                                    ),
                                                    size: 24,
                                                  ),
                                                  onPressed: () =>
                                                      _openSystemEqualizer(),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({
    required this.accent,
    required this.selected,
    required this.onPick,
  });

  final Color accent;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String)>[
      (Icons.play_circle_outline_rounded, 'Player'),
      (Icons.lyrics_outlined, 'Lyrics'),
      (Icons.queue_music_outlined, 'Queue'),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kMetrolistNpSurface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _kMetrolistNpSurfaceHigh.withValues(alpha: 0.85),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Tooltip(
                  message: tabs[i].$2,
                  child: Material(
                    color: selected == i
                        ? accent
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onPick(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        child: Icon(
                          tabs[i].$1,
                          size: 21,
                          color: selected == i
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetrolistSeekBar extends StatefulWidget {
  const _MetrolistSeekBar({
    required this.value,
    required this.enabled,
    required this.style,
    required this.motion,
    required this.accent,
    required this.onSeek,
  });

  final double value;
  final bool enabled;
  final int style;
  final int motion;
  final Color accent;
  final ValueChanged<double> onSeek;

  @override
  State<_MetrolistSeekBar> createState() => _MetrolistSeekBarState();
}

class _MetrolistSeekBarState extends State<_MetrolistSeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motionCtrl;

  @override
  void initState() {
    super.initState();
    _motionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.motion > 0) {
      _motionCtrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _MetrolistSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.motion > 0) {
      if (!_motionCtrl.isAnimating) {
        _motionCtrl.repeat();
      }
    } else {
      _motionCtrl.stop();
      _motionCtrl.value = 0;
    }
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
    super.dispose();
  }

  double get _paintHeight {
    final s = widget.style.clamp(0, 3);
    if (s == 0) return 24.0;
    if (s == 1) return 40.0;
    return 48.0;
  }

  void _seek(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    widget.onSeek((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value.clamp(0.0, 1.0);
    final st = widget.style.clamp(0, 3);
    final mo = widget.motion.clamp(0, 2);
    Widget buildBar(double phase) {
      return CustomPaint(
        painter: _MetrolistSeekPainter(
          progress: v,
          dimmed: !widget.enabled,
          style: st,
          accent: widget.accent,
          motion: mo,
          motionPhase: phase,
        ),
        child: SizedBox(height: _paintHeight, width: double.infinity),
      );
    }

    final content = mo > 0
        ? AnimatedBuilder(
            animation: _motionCtrl,
            builder: (context, _) => buildBar(_motionCtrl.value),
          )
        : buildBar(0);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      onHorizontalDragUpdate: widget.enabled
          ? (d) => _seek(context, d.localPosition.dx)
          : null,
      child: content,
    );
  }
}

class _MetrolistSeekPainter extends CustomPainter {
  _MetrolistSeekPainter({
    required this.progress,
    required this.dimmed,
    required this.style,
    required this.accent,
    required this.motion,
    required this.motionPhase,
  });

  final double progress;
  final bool dimmed;
  final int style;
  final Color accent;
  final int motion;
  final double motionPhase;

  static const _inactive = Color(0xFF5C5C5C);
  static const _active = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final p = progress.clamp(0.0, 1.0);
    final inactiveColor = dimmed ? _inactive.withValues(alpha: 0.45) : _inactive;
    final shimmer = motion == 2 ? (0.72 + 0.28 * math.sin(motionPhase * math.pi * 2)) : 1.0;
    final useAccent = style >= 2;
    var activeColor = dimmed
        ? Colors.white38
        : (useAccent ? accent : _active);
    if (motion == 2) {
      activeColor = activeColor.withValues(alpha: (activeColor.a * shimmer).clamp(0.15, 1.0));
    }

    if (style == 1) {
      final trackH = 14.0;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
        const Radius.circular(999),
      );
      canvas.drawRRect(r, Paint()..color = inactiveColor);
      if (p > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
            const Radius.circular(999),
          ),
          Paint()..color = activeColor,
        );
      }
    } else if (style == 2 || style == 3) {
      final inactivePaint = Paint()
        ..color = inactiveColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final activePaint = Paint()
        ..color = activeColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(0, y);
      final amp = style == 3 ? 7.0 : 4.0;
      final freq = style == 3 ? 18.0 : 12.0;
      // When motion is on, scroll the phase so Wave / Squiggle feel alive (Metrolist-like).
      final scroll =
          motion > 0 ? motionPhase * math.pi * 2 * 2.2 : 0.0;
      for (double x = 0; x <= size.width; x += 1.2) {
        path.lineTo(
          x,
          y +
              math.sin(x / freq * math.pi * 2 + scroll) * amp,
        );
      }
      canvas.drawPath(path, inactivePaint);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * p, size.height));
      canvas.drawPath(path, activePaint);
      canvas.restore();
    } else {
      final trackH = 4.0;
      final full = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
        const Radius.circular(2),
      );
      canvas.drawRRect(full, Paint()..color = inactiveColor);
      if (p > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
            const Radius.circular(2),
          ),
          Paint()..color = activeColor,
        );
      }
    }

    final pulse = motion == 1
        ? (1.0 + 0.35 * math.sin(motionPhase * math.pi * 2))
        : 1.0;
    final tw = (3.0 * pulse).clamp(2.5, 5.5);
    final th = (14.0 * (0.92 + 0.08 * pulse)).clamp(12.0, 17.0);
    final half = tw / 2 + 1.0;
    final cx = (size.width * p).clamp(half, size.width - half);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: tw, height: th),
      Radius.circular(tw / 2),
    );
    canvas.drawRRect(
      thumb,
      Paint()..color = dimmed ? Colors.white54 : _active,
    );
  }

  @override
  bool shouldRepaint(covariant _MetrolistSeekPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.dimmed != dimmed ||
      oldDelegate.style != style ||
      oldDelegate.accent != accent ||
      oldDelegate.motion != motion ||
      oldDelegate.motionPhase != motionPhase;
}

/// SimpMusic-style transport row: shuffle · previous · large play/pause · next · repeat
/// (see `PlayerControlLayout.kt` in SimpMusic).
class _SimpMusicPlayerControlLayout extends StatelessWidget {
  const _SimpMusicPlayerControlLayout({
    required this.shuffle,
    required this.repeatMode,
    required this.playing,
    required this.buffering,
    required this.prevEnabled,
    required this.nextEnabled,
  });

  final bool shuffle;
  final String repeatMode;
  final bool playing;
  final bool buffering;
  final bool prevEnabled;
  final bool nextEnabled;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final repeatOn = repeatMode != 'Off';

    Widget slot(Widget child) => Expanded(child: Center(child: child));

    Widget mainPlay() {
      return slot(
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _method.invokeMethod('togglePlayPause'),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.35),
                    blurRadius: 18,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: SizedBox(
                width: 68,
                height: 68,
                child: buffering
                    ? const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black38,
                          ),
                        ),
                      )
                    : Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: playing ? 36 : 40,
                        color: Colors.black87,
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 88,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            slot(
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _method.invokeMethod('toggleShuffle'),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.shuffle_rounded,
                      size: 28,
                      color: shuffle ? accent : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            slot(
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: prevEnabled
                      ? () => _method.invokeMethod('previous')
                      : null,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      Icons.skip_previous_rounded,
                      size: 36,
                      color: prevEnabled ? Colors.white : Colors.white30,
                    ),
                  ),
                ),
              ),
            ),
            mainPlay(),
            slot(
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: nextEnabled
                      ? () => _method.invokeMethod('next')
                      : null,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Icon(
                      Icons.skip_next_rounded,
                      size: 36,
                      color: nextEnabled ? Colors.white : Colors.white30,
                    ),
                  ),
                ),
              ),
            ),
            slot(
              Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _method.invokeMethod('cycleRepeatMode'),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      repeatMode == 'One'
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      size: 28,
                      color: repeatOn ? accent : Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LyricsTab extends StatelessWidget {
  const _LyricsTab({
    required this.lines,
    required this.loading,
    required this.positionMs,
    required this.accent,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: accent.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Loading lyrics…',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 48),
        child: _EmptyTabBody(
          icon: Icons.subtitles_off_rounded,
          title: 'No synced lyrics',
          subtitle:
              'Try another source in Settings, or play a track with community lyrics.',
        ),
      );
    }
    return _AnimatedLyricsList(
      lines: lines,
      positionMs: positionMs,
      accent: accent,
    );
  }
}

class _AnimatedLyricsList extends StatefulWidget {
  const _AnimatedLyricsList({
    required this.lines,
    required this.positionMs,
    required this.accent,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final Color accent;

  @override
  State<_AnimatedLyricsList> createState() => _AnimatedLyricsListState();
}

class _AnimatedLyricsListState extends State<_AnimatedLyricsList> {
  late final ScrollController _controller;
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = _activeIndex;
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final target = (active * 58.0 - 150).clamp(
          0.0,
          _controller.position.maxScrollExtent,
        );
        _controller.animateTo(
          target,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _activeIndex {
    var active = widget.lines.lastIndexWhere(
      (line) => line.timeMs <= widget.positionMs,
    );
    if (active < 0) active = 0;
    return active;
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeIndex;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        _MetrolistPlayerSectionLabel('Lyrics'),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: ListView.builder(
            controller: _controller,
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: widget.lines.length,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              final isActive = index == active;
              final passed = index < active;
              return TweenAnimationBuilder<double>(
                key: ValueKey('${line.timeMs}-$isActive'),
                tween: Tween(begin: 0, end: isActive ? 1 : 0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  final scale = 1.0 + (0.055 * t);
                  return Transform.scale(
                    scale: scale,
                    alignment: Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: EdgeInsets.symmetric(
                        horizontal: isActive ? 14 : 0,
                        vertical: isActive ? 12 : 7,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? widget.accent.withValues(alpha: 0.13)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        line.text,
                        style: TextStyle(
                          color: isActive
                              ? Colors.white
                              : passed
                              ? Colors.white.withValues(alpha: 0.34)
                              : Colors.white.withValues(alpha: 0.58),
                          fontSize: isActive ? 25 : 19,
                          height: 1.32,
                          fontWeight: isActive
                              ? FontWeight.w900
                              : FontWeight.w700,
                          shadows: isActive
                              ? [
                                  Shadow(
                                    color: widget.accent.withValues(
                                      alpha: 0.65,
                                    ),
                                    blurRadius: 18,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.currentIndex,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_Song> queue;
  final int currentIndex;
  final FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _MetrolistPlayerSectionLabel(
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
          ...queue.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final active = index == currentIndex;
            return _FoxySongTile(
              song: item,
              index: index,
              thumbRadius: 10,
              active: active,
              onMore: () {
                final play = onPlay;
                if (play != null) {
                  showFoxySongOverflowMenu(
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
              onTap: () =>
                  _method.invokeMethod('skipToQueueIndex', {'index': index}),
            );
          }),
      ],
    );
  }
}

class _MenuQuickAction extends StatelessWidget {
  const _MenuQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kCardRadius),
        onTap: () async {
          await onTap();
          if (context.mounted) Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
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
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Future<dynamic> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
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

class _PlayerArtwork extends StatefulWidget {
  const _PlayerArtwork({
    required this.url,
    required this.playing,
    required this.tag,
    this.offlineArtworkPath,
    this.maxSide,
  });

  final String url;
  final bool playing;
  final String tag;
  final String? offlineArtworkPath;
  /// Caps artwork so transport rows never collide on narrow devices.
  final double? maxSide;

  @override
  State<_PlayerArtwork> createState() => _PlayerArtworkState();
}

class _PlayerArtworkState extends State<_PlayerArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.playing) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
    final w = MediaQuery.sizeOf(context).width;
    final base = (w * 0.84).clamp(256.0, 320.0);
    final cap = widget.maxSide;
    final side = cap != null ? math.min(base, cap) : base;
    final radius = (side * 0.11).clamp(18.0, 32.0);
    final accent = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.playing
            ? 1.0 + math.sin(_controller.value * math.pi * 2) * 0.006
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: SizedBox(
        width: side,
        height: side,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius + 1),
            border: Border.all(
              color: _kMetrolistNpSurfaceHigh.withValues(alpha: 0.9),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
              BoxShadow(
                color: accent.withValues(alpha: 0.18),
                blurRadius: 42,
                spreadRadius: -10,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: _Artwork(
              url: widget.url,
              size: side,
              radius: 0,
              identityTag: widget.tag.startsWith('art-')
                  ? widget.tag.substring(4)
                  : widget.tag,
              offlineArtworkPath: widget.offlineArtworkPath,
            ),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.url,
    required this.size,
    required this.radius,
    this.identityTag,
    this.offlineArtworkPath,
  });

  final String url;
  final double size;
  final double radius;
  /// When set, combined with [url] for [Image.network] keys so artwork swaps on track change.
  final String? identityTag;
  /// Native-resolved JPEG path (embedded / cached) for offline artwork.
  final String? offlineArtworkPath;

  @override
  Widget build(BuildContext context) {
    File? offlineFile() {
      if (kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      final f = File(p);
      if (f.existsSync()) return f;
      return null;
    }

    final of = offlineFile();
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

    if (of != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.file(
          of,
          key: ValueKey<String>(cacheKey),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: false,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      );
    }

    if (url.isBlank) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        key: ValueKey<String>(cacheKey),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.blurEnabled,
    this.sigma = 52,
    this.offlineArtworkPath,
  });

  final String url;
  final bool blurEnabled;
  final double sigma;
  final String? offlineArtworkPath;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    File? offlineFile() {
      if (kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      final f = File(p);
      if (f.existsSync()) return f;
      return null;
    }

    final of = offlineFile();
    if (!blurEnabled || (url.isBlank && of == null)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.15,
            colors: [
              accent.withValues(alpha: url.isBlank ? 0.22 : 0.34),
              const Color(0xFF261018).withValues(alpha: 0.72),
              const Color(0xFF080808),
            ],
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Transform.scale(
          scale: 1.18,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
            child: SizedBox.expand(
              child: of != null
                  ? Image.file(
                      of,
                      key: ValueKey<String>('bd|${of.path}'),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: const Color(0xFF080808),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white.withValues(alpha: 0.2),
                          size: 120,
                        ),
                      ),
                    )
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => ColoredBox(
                        color: const Color(0xFF080808),
                        child: Icon(
                          Icons.music_note_rounded,
                          color: Colors.white.withValues(alpha: 0.2),
                          size: 120,
                        ),
                      ),
                    ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.55),
                Color.lerp(const Color(0xFF000000), accent, 0.08)!
                    .withValues(alpha: 0.94),
              ],
            ),
          ),
        ),
      ],
    );
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

class _SongSection {
  const _SongSection({required this.title, required this.songs});

  factory _SongSection.fromMap(Map<String, dynamic> map) => _SongSection(
    title: map['title']?.toString() ?? 'For you',
    songs: (map['songs'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .where((song) => song.videoId.isNotEmpty)
        .toList(),
  );

  final String title;
  final List<_Song> songs;
}

class _Song {
  const _Song({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.artwork,
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
  final String? duration;
  final bool isDownloaded;
  final String? localPath;
  final String? offlineArtworkPath;

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': artwork,
    'artworkUrl': artwork,
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
    out['queue'] = q
        .map((dynamic e) {
          final m = _asMap(e);
          return m != null ? Map<String, dynamic>.from(m) : e;
        })
        .toList();
  }
  return out;
}

dynamic _normalize(dynamic value) {
  if (value is Map) return _asMap(value);
  if (value is List) return value.map(_normalize).toList();
  return value;
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
