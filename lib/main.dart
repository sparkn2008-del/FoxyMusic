import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

/// Dark UI shell defaults: OLED black canvas, bottom-nav selection fill.
const Color _kTrueBlack = Color(0xFF000000);
const Color _kNavPillFill = Color(0xFF30363C);
const Color _kMiniPlayerFallbackTint = Color(0xFF3D3528);
const double _kCardRadius = 12;

Color _miniPlayerTint(Color accent) {
  return Color.alphaBlend(
    const Color(0xCC000000),
    Color.lerp(const Color(0xFF4A4334), accent, 0.28)!,
  );
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

  @override
  void initState() {
    super.initState();
    _loadAppearance();
  }

  Future<void> _loadAppearance() async {
    try {
      final map = _asMap(await _method.invokeMethod('getAppearance'));
      if (map != null && mounted) {
        setState(() => _appearance = _FlutterAppearance.fromMap(map));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _appearance.background,
        colorScheme: ColorScheme.dark(
          primary: _appearance.accent,
          secondary: const Color(0xFFFFC857),
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
              return _appearance.accent.withValues(alpha: 0.55);
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

class _FoxyHomeShellState extends State<FoxyHomeShell> {
  int _tabIndex = 0;
  Map<String, dynamic> _player = const {};
  Map<String, dynamic> _account = const {};
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _loadAccount();
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) setState(() => _player = state);
      }
    });
  }

  Future<void> _loadAccount() async {
    try {
      final map = _asMap(await _method.invokeMethod('accountInfo'));
      if (mounted && map != null) setState(() => _account = map);
    } catch (_) {}
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
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _playSong(_Song song, List<_Song> queue) async {
    final songs = queue.isEmpty ? [song] : queue;
    final index = songs.indexWhere((item) => item.videoId == song.videoId);
    await _method.invokeMethod('playQueue', {
      'songs': songs.map((item) => item.toMap()).toList(),
      'startIndex': math.max(index, 0),
    });
  }

  void _openPlayer({int initialTab = 0}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NowPlayingSheet(player: _player, initialTab: initialTab),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = _Song.fromMap(
      _asMap(_player['currentSong']) ?? const {},
    );
    final hasSong = currentSong.videoId.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final miniBottom = bottomInset + 10;
    final baseTheme = Theme.of(context);
    final baseScheme = baseTheme.colorScheme;
    final dynamicOn = _player['dynamicSongColors'] != false;
    final accentArgb = _player['songAccentArgb'];
    final Color shellPrimary = (dynamicOn && accentArgb is num)
        ? Color(accentArgb.toInt() & 0xFFFFFFFF)
        : baseScheme.primary;
    final shellTheme = baseTheme.copyWith(
      colorScheme: baseScheme.copyWith(
        primary: shellPrimary,
        secondary: shellPrimary,
      ),
    );
    final tabs = [
      _HomeTab(
        key: const PageStorageKey('home-tab'),
        currentVideoId: currentSong.videoId,
        onPlay: _playSong,
        onSearch: () => setState(() => _tabIndex = 1),
        account: _account,
        onOpenProfile: _openAccountHub,
      ),
      _SearchTab(key: const PageStorageKey('search-tab'), onPlay: _playSong),
      _LibraryTab(
        key: const PageStorageKey('library-tab'),
        onPlay: _playSong,
        onOpenSearch: () => setState(() => _tabIndex = 1),
        onGoHome: () => setState(() => _tabIndex = 0),
      ),
    ];
    final safeTab = _tabIndex.clamp(0, tabs.length - 1);
    if (safeTab != _tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tabIndex = safeTab);
      });
    }

    return Theme(
      data: shellTheme,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            IndexedStack(index: safeTab, children: tabs),
            if (hasSong)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: EdgeInsets.only(bottom: miniBottom),
                  child: _MiniPlayer(
                    key: ValueKey<String>(currentSong.videoId),
                    player: _player,
                    onOpen: () => _openPlayer(),
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
    required this.onSearch,
    required this.account,
    required this.onOpenProfile,
  });

  final String currentVideoId;
  final Future<void> Function(_Song song, List<_Song> queue) onPlay;
  final VoidCallback onSearch;
  final Map<String, dynamic> account;
  final VoidCallback onOpenProfile;

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
              onSearch: widget.onSearch,
              account: widget.account,
              onOpenProfile: widget.onOpenProfile,
              selectedChip: _homeChip,
              onChipSelected: _onHomeChip,
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeFeatureRail(
              onMood: _loadMood,
              onSearch: widget.onSearch,
              onOpenProfile: widget.onOpenProfile,
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(child: _HomeLoading())
          else if (_error != null)
            SliverToBoxAdapter(
              child: _HomeError(
                message: _error!,
                onRetry: () => _loadHome(force: true),
              ),
            )
          else
            ..._sections.map(
              (section) => SliverToBoxAdapter(
                child: _SongShelf(
                  section: section,
                  currentVideoId: widget.currentVideoId,
                  onPlay: widget.onPlay,
                ),
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
    required this.onSearch,
    required this.account,
    required this.onOpenProfile,
    required this.selectedChip,
    required this.onChipSelected,
  });

  final VoidCallback onSearch;
  final Map<String, dynamic> account;
  final VoidCallback onOpenProfile;
  final String selectedChip;
  final ValueChanged<String> onChipSelected;

  @override
  Widget build(BuildContext context) {
    final displayName =
        account['displayName']?.toString().ifBlank('Guest') ?? 'Guest';
    final avatar = account['avatarUrl']?.toString() ?? '';
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: _kTrueBlack),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                        const SizedBox(height: 2),
                        Text(
                          _homeGreeting(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    onPressed: onOpenProfile,
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Account',
                    onPressed: onOpenProfile,
                    icon: _AccountAvatar(
                      name: displayName,
                      imageUrl: avatar,
                      size: 34,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Material(
                color: Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onSearch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search songs, artists, moods',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
  const _ScreenTopBar({required this.title, this.onRefresh, this.subtitle});

  final String title;
  final VoidCallback? onRefresh;
  final String? subtitle;

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
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
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

/// Compact library header for the liked list: Home, play, shuffle, search.
class _FavoriteListAppBar extends StatelessWidget {
  const _FavoriteListAppBar({
    required this.onBack,
    required this.onPlayAll,
    required this.onShufflePlay,
    required this.onSearch,
    required this.hasTracks,
  });

  final VoidCallback onBack;
  final VoidCallback onPlayAll;
  final VoidCallback onShufflePlay;
  final VoidCallback onSearch;
  final bool hasTracks;

  @override
  Widget build(BuildContext context) {
    final dim = !hasTracks;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Home',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const Expanded(
              child: Text(
                'Favorite',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Opacity(
              opacity: dim ? 0.35 : 1,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: dim ? null : onPlayAll,
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Opacity(
              opacity: dim ? 0.35 : 1,
              child: IconButton(
                tooltip: 'Shuffle',
                onPressed: dim ? null : onShufflePlay,
                icon: const Icon(Icons.shuffle_rounded),
              ),
            ),
            IconButton(
              tooltip: 'Search',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded),
            ),
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
  });

  final _Song song;
  final VoidCallback onTap;
  final VoidCallback? onMore;
  final IconData trailingIcon;
  final bool active;
  final int? index;
  final double thumbRadius;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
          _Artwork(url: song.artwork, size: 52, radius: thumbRadius),
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
          if (onMore != null)
            IconButton(
              tooltip: 'More',
              onPressed: onMore,
              icon: const Icon(Icons.more_vert_rounded),
            )
          else
            IconButton(
              tooltip: 'Play',
              onPressed: onTap,
              icon: Icon(trailingIcon, color: active ? accent : Colors.white),
            ),
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
  const _SearchTab({super.key, required this.onPlay});

  final Future<void> Function(_Song song, List<_Song> queue) onPlay;

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
                thumbRadius: 10,
                onTap: () => widget.onPlay(song, _results),
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    super.key,
    required this.onPlay,
    required this.onOpenSearch,
    required this.onGoHome,
  });

  final Future<void> Function(_Song song, List<_Song> queue) onPlay;
  final VoidCallback onOpenSearch;
  final VoidCallback onGoHome;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  List<_Song> _liked = const [];
  List<_Song> _history = const [];
  List<_Song> _playlists = const [];
  List<_Song> _downloads = const [];
  int _section = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response =
        _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;
    setState(() {
      _liked = _songsFrom(response['liked']);
      _history = _songsFrom(response['history']);
      _playlists = _songsFrom(response['playlists'] ?? response['saved']);
      _downloads = _songsFrom(response['downloads']);
      _loading = false;
    });
  }

  List<_Song> get _activeList {
    switch (_section.clamp(0, 3)) {
      case 1:
        return _history;
      case 2:
        return _playlists;
      case 3:
        return _downloads;
      default:
        return _liked;
    }
  }

  String get _activeLabel {
    switch (_section.clamp(0, 3)) {
      case 1:
        return 'History';
      case 2:
        return 'Playlists';
      case 3:
        return 'Downloads';
      default:
        return 'Liked';
    }
  }

  void _shuffleLikedAndPlay() {
    if (_liked.isEmpty) return;
    final list = List<_Song>.from(_liked)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  void _shuffleActiveAndPlay() {
    final songs = _activeList;
    if (songs.isEmpty) return;
    final list = List<_Song>.from(songs)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  void _openLikedSongMenu(BuildContext context, _Song song, List<_Song> queue) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Play'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onPlay(song, queue);
              },
            ),
            ListTile(
              leading: const Icon(Icons.heart_broken_rounded),
              title: const Text('Remove from liked'),
              onTap: () async {
                Navigator.pop(ctx);
                await _method.invokeMethod('unlike', {'song': song.toMap()});
                if (mounted) await _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final songs = _activeList;
    final chips = [
      (Icons.favorite_rounded, 'Liked', _liked.length),
      (Icons.history_rounded, 'History', _history.length),
      (Icons.playlist_play_rounded, 'Playlists', _playlists.length),
      (Icons.download_rounded, 'Downloads', _downloads.length),
    ];
    return CustomScrollView(
      key: const PageStorageKey('library-scroll'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_section == 0)
          SliverToBoxAdapter(
            child: _FavoriteListAppBar(
              onBack: widget.onGoHome,
              onPlayAll: () {
                if (songs.isEmpty) return;
                widget.onPlay(songs.first, songs);
              },
              onShufflePlay: _shuffleLikedAndPlay,
              onSearch: widget.onOpenSearch,
              hasTracks: songs.isNotEmpty,
            ),
          )
        else
          SliverToBoxAdapter(
            child: _ScreenTopBar(
              title: 'Library',
              subtitle:
                  '${_liked.length + _history.length + _playlists.length + _downloads.length} items',
              onRefresh: _load,
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < chips.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(chips[i].$1, size: 18),
                        label: Text('${chips[i].$2}  ${chips[i].$3}'),
                        selected: _section == i,
                        onSelected: (_) => setState(() => _section = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_section != 0)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  Text(
                    _activeLabel,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  if (songs.isNotEmpty) ...[
                    IconButton.filledTonal(
                      tooltip: 'Shuffle',
                      onPressed: _shuffleActiveAndPlay,
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
        if (_loading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyTabBody(
              icon: _sectionIcon(_activeLabel),
              title: 'Nothing in $_activeLabel yet',
              subtitle: _section == 0
                  ? 'Like songs from the player to fill this shelf.'
                  : _section == 1
                  ? 'History fills as you listen with saving enabled in Settings.'
                  : _section == 2
                  ? 'Save playlists from YouTube Music when that flow is connected.'
                  : 'Use the player menu to download songs for offline playback.',
            ),
          )
        else
          SliverList.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              if (_section == 0) {
                return _FoxySongTile(
                  song: song,
                  thumbRadius: 10,
                  onTap: () => widget.onPlay(song, songs),
                  onMore: () =>
                      _openLikedSongMenu(context, song, songs),
                );
              }
              return _FoxySongTile(
                song: song,
                index: index,
                thumbRadius: 10,
                trailingIcon: _section == 3
                    ? Icons.offline_pin_rounded
                    : Icons.play_circle_fill_rounded,
                onTap: () => widget.onPlay(song, songs),
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

  final Future<void> Function(_Song song, List<_Song> queue) onPlay;

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
                      : () => _method.invokeMethod('openWebLogin'),
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

IconData _sectionIcon(String label) {
  switch (label) {
    case 'Playlists':
      return Icons.playlist_play_rounded;
    case 'History':
      return Icons.history_rounded;
    case 'Downloads':
      return Icons.download_rounded;
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
  });

  final Map<String, dynamic> appearance;
  final Future<void> Function(Map<String, dynamic> patch) onSetAppearance;

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

  Future<void> _openWebLogin() async {
    final ok = await _method.invokeMethod('openWebLogin') == true;
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No browser available for sign-in')),
      );
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
                title: 'Player progress style',
                subtitle:
                    'Used on the Flutter full player (Line / Pill / Wave / Squiggle)',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        selected: prog == i,
                        label: Text(['Line', 'Pill', 'Wave', 'Squiggle'][i]),
                        onSelected: (_) => _apply({'playerProgressStyle': i}),
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
                      onPressed: _openWebLogin,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                        ),
                      ),
                      child: const Text('Sign in (browser)'),
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
      (Icons.album_rounded, 'Player', 'Mini player, gestures'),
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

class _HomeFeatureRail extends StatelessWidget {
  const _HomeFeatureRail({
    required this.onMood,
    required this.onSearch,
    required this.onOpenProfile,
  });

  final ValueChanged<String> onMood;
  final VoidCallback onSearch;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final items = <_HomeFeature>[
      _HomeFeature(
        Icons.auto_awesome_rounded,
        'Quick picks',
        'Fresh radio',
        () => onMood('Quick picks'),
      ),
      _HomeFeature(
        Icons.stacked_line_chart_rounded,
        'Charts',
        'Top songs',
        () => onMood('Top songs today'),
      ),
      _HomeFeature(
        Icons.new_releases_rounded,
        'New',
        'Releases',
        () => onMood('New release music'),
      ),
      _HomeFeature(
        Icons.nightlight_round,
        'Sleep',
        'Soft mix',
        () => onMood('Sleep'),
      ),
      _HomeFeature(Icons.lyrics_rounded, 'Lyrics', 'Synced view', onSearch),
      _HomeFeature(
        Icons.tune_rounded,
        'Settings',
        'Theme/audio',
        onOpenProfile,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        height: 94,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          scrollDirection: Axis.horizontal,
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: 118,
              child: _FoxySurface(
                padding: const EdgeInsets.all(12),
                onTap: item.onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeFeature {
  const _HomeFeature(this.icon, this.title, this.subtitle, this.onTap);

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _SongShelf extends StatelessWidget {
  const _SongShelf({
    required this.section,
    required this.currentVideoId,
    required this.onPlay,
  });

  final _SongSection section;
  final String currentVideoId;
  final Future<void> Function(_Song song, List<_Song> queue) onPlay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => onPlay(section.songs.first, section.songs),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Play all'),
                ),
                IconButton(
                  tooltip: 'Shuffle',
                  onPressed: () {
                    final list = List<_Song>.from(section.songs)
                      ..shuffle(math.Random());
                    if (list.isEmpty) return;
                    onPlay(list.first, list);
                  },
                  icon: const Icon(Icons.shuffle_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 218,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              scrollDirection: Axis.horizontal,
              itemCount: section.songs.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
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

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 142,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Hero(
                  tag: 'art-${song.videoId}',
                  child: _Artwork(url: song.artwork, size: 142, radius: 14),
                ),
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: active ? 1 : 0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.black.withValues(alpha: 0.32),
                      ),
                      child: Icon(
                        Icons.equalizer_rounded,
                        color: accent,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.58),
                fontSize: 12,
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
  });

  final Map<String, dynamic> player;
  final VoidCallback onOpen;

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
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onOpen,
            child: SizedBox(
              height: 58,
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const SizedBox(width: 10),
                        _Artwork(url: song.artwork, size: 42, radius: 10),
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
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: liked ? 'Unlike' : 'Like',
                          onPressed: () => _method.invokeMethod(
                            liked ? 'unlike' : 'like',
                            {'song': song.toMap()},
                          ),
                          icon: Icon(
                            liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: liked
                                ? const Color(0xFFE53935)
                                : Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              _method.invokeMethod('togglePlayPause'),
                          icon: buffering
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(
                                  playing
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  size: 36,
                                  color: Colors.white,
                                ),
                        ),
                        IconButton(
                          onPressed: () => _method.invokeMethod('next'),
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(width: 2),
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
      ),
    );
  }
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({required this.player, this.initialTab = 0});

  final Map<String, dynamic> player;
  final int initialTab;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  late Map<String, dynamic> _player = widget.player;
  StreamSubscription<dynamic>? _sub;
  late int _tab = widget.initialTab;
  int _progressStyle = 2;
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
          setState(() => _player = state);
          _loadLyricsIfNeeded(state);
        }
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _PlayerActionMenu(
        song: song,
        progressStyle: _progressStyle,
        onStyle: _setProgressStyle,
        onLyrics: () => setState(() => _tab = 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    final playing = _player['isPlaying'] == true;
    final buffering = _player['isBuffering'] == true;
    final shuffle = _player['shuffleEnabled'] == true;
    final repeat = (_player['repeatMode'] ?? 'Off').toString();
    final duration = ((_player['durationMs'] ?? 0) as num).toDouble();
    final position = ((_player['positionMs'] ?? 0) as num).toDouble();
    final progress = duration <= 0
        ? 0.0
        : (position / duration).clamp(0.0, 1.0);
    final queue = (_player['queue'] as List? ?? const [])
        .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
        .toList();
    final queueIndex = ((_player['queueIndex'] ?? -1) as num).toInt();

    return DraggableScrollableSheet(
      initialChildSize: 0.985,
      minChildSize: 0.78,
      maxChildSize: 1.0,
      builder: (context, scrollController) {
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: _BlurBackdrop(
                  url: song.artwork,
                  blurEnabled: _blurPlayerBackdrop,
                ),
              ),
              ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              _tab == 0
                                  ? 'NOW PLAYING'
                                  : _tab == 1
                                  ? 'LYRICS'
                                  : 'QUEUE',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.56),
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _PlayerTabs(
                              selected: _tab,
                              onPick: (tab) => setState(() => _tab = tab),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _openMenu(song),
                        icon: const Icon(Icons.more_vert_rounded),
                      ),
                    ],
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: switch (_tab) {
                      1 => _LyricsTab(
                        key: const ValueKey('lyrics'),
                        lines: _lyrics,
                        loading: _lyricsLoading,
                        positionMs: position.round(),
                        accent: Theme.of(context).colorScheme.primary,
                      ),
                      2 => _QueueTab(
                        key: const ValueKey('queue'),
                        queue: queue,
                        currentIndex: queueIndex,
                      ),
                      _ => Column(
                        key: const ValueKey('player'),
                        children: [
                          const SizedBox(height: 16),
                          GestureDetector(
                            onHorizontalDragUpdate: (details) {
                              _artworkSwipeDx += details.delta.dx;
                            },
                            onHorizontalDragEnd: (_) {
                              if (_artworkSwipeDx > 64) {
                                _method.invokeMethod('previous');
                              } else if (_artworkSwipeDx < -64) {
                                _method.invokeMethod('next');
                              }
                              _artworkSwipeDx = 0;
                            },
                            child: Center(
                              child: _PlayerArtwork(
                                url: song.artwork,
                                playing: playing && !buffering,
                                tag: 'art-${song.videoId}',
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            song.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            song.artist,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.62),
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 26),
                          _PlayerProgressBar(
                            value: progress,
                            style: duration <= 750 ? 0 : _progressStyle,
                            onSeek: duration <= 750
                                ? null
                                : (value) => _method.invokeMethod('seekTo', {
                                    'positionMs': (duration * value).round(),
                                  }),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _fmt(position.round()),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                _fmt(duration.round()),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _RoundControl(
                                icon: Icons.shuffle_rounded,
                                active: shuffle,
                                onTap: () =>
                                    _method.invokeMethod('toggleShuffle'),
                              ),
                              _RoundControl(
                                icon: Icons.skip_previous_rounded,
                                large: true,
                                onTap: () => _method.invokeMethod('previous'),
                              ),
                              _MainPlayButton(
                                playing: playing,
                                buffering: buffering,
                              ),
                              _RoundControl(
                                icon: Icons.skip_next_rounded,
                                large: true,
                                onTap: () => _method.invokeMethod('next'),
                              ),
                              _RoundControl(
                                icon: repeat == 'One'
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                active: repeat != 'Off',
                                onTap: () =>
                                    _method.invokeMethod('cycleRepeatMode'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          Row(
                            children: [
                              Expanded(
                                child: _UtilityButton(
                                  icon: Icons.lyrics_rounded,
                                  label: 'Lyrics',
                                  onTap: () => setState(() => _tab = 1),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _UtilityButton(
                                  icon: Icons.queue_music_rounded,
                                  label: 'Queue',
                                  onTap: () => setState(() => _tab = 2),
                                ),
                              ),
                            ],
                          ),
                          if (_lyrics.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            _LyricsPeek(
                              lines: _lyrics,
                              positionMs: position.round(),
                              onTap: () => setState(() => _tab = 1),
                            ),
                          ],
                        ],
                      ),
                    },
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
  const _PlayerTabs({required this.selected, required this.onPick});

  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.album_rounded, 'Player'),
      (Icons.lyrics_rounded, 'Lyrics'),
      (Icons.queue_music_rounded, 'Queue'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < tabs.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Tooltip(
              message: tabs[i].$2,
              child: IconButton(
                onPressed: () => onPick(i),
                style: IconButton.styleFrom(
                  backgroundColor: selected == i
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.06),
                  foregroundColor: selected == i
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white.withValues(alpha: 0.78),
                  fixedSize: const Size(40, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: Icon(tabs[i].$1, size: 20),
              ),
            ),
          ),
      ],
    );
  }
}

class _PlayerProgressBar extends StatelessWidget {
  const _PlayerProgressBar({
    required this.value,
    required this.style,
    required this.onSeek,
  });

  final double value;
  final int style;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onSeek == null
          ? null
          : (details) => _seek(context, details.localPosition.dx),
      onHorizontalDragUpdate: onSeek == null
          ? null
          : (details) => _seek(context, details.localPosition.dx),
      child: SizedBox(
        height: 44,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              painter: _ProgressPainter(
                progress: value.clamp(0.0, 1.0),
                style: style,
                accent: accent,
                inactive: Colors.white.withValues(alpha: 0.16),
              ),
            );
          },
        ),
      ),
    );
  }

  void _seek(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    onSeek?.call((dx / width).clamp(0.0, 1.0));
  }
}

class _ProgressPainter extends CustomPainter {
  const _ProgressPainter({
    required this.progress,
    required this.style,
    required this.accent,
    required this.inactive,
  });

  final double progress;
  final int style;
  final Color accent;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final inactivePaint = Paint()
      ..color = inactive
      ..strokeCap = StrokeCap.round
      ..strokeWidth = style == 1 ? 14 : 4;
    final activePaint = Paint()
      ..color = accent
      ..strokeCap = StrokeCap.round
      ..strokeWidth = style == 1 ? 14 : 4;
    if (style == 1) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y - 7, size.width, 14),
        const Radius.circular(999),
      );
      canvas.drawRRect(r, inactivePaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - 7, size.width * progress, 14),
          const Radius.circular(999),
        ),
        activePaint,
      );
    } else if (style == 2 || style == 3) {
      final path = Path()..moveTo(0, y);
      final amp = style == 3 ? 7.0 : 4.0;
      final freq = style == 3 ? 18.0 : 12.0;
      for (double x = 0; x <= size.width; x += 3) {
        path.lineTo(x, y + math.sin(x / freq * math.pi * 2) * amp);
      }
      canvas.drawPath(path, inactivePaint);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, size.width * progress, size.height));
      canvas.drawPath(path, activePaint);
      canvas.restore();
    } else {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), inactivePaint);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * progress, y),
        activePaint,
      );
    }
    canvas.drawCircle(
      Offset(size.width * progress, y),
      7,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.style != style ||
      oldDelegate.accent != accent;
}

class _LyricsTab extends StatelessWidget {
  const _LyricsTab({
    super.key,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Lyrics',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 16),
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

class _LyricsPeek extends StatelessWidget {
  const _LyricsPeek({
    required this.lines,
    required this.positionMs,
    required this.onTap,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    var active = lines.lastIndexWhere((line) => line.timeMs <= positionMs);
    if (active < 0) active = 0;
    final text = lines[active].text;
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(_kCardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(_kCardRadius),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                Icons.lyrics_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.open_in_full_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({super.key, required this.queue, required this.currentIndex});

  final List<_Song> queue;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 14),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Queue',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
            Text(
              '${queue.length} songs',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
            ),
          ],
        ),
        const SizedBox(height: 12),
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
              onMore: () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: const Color(0xFF111111),
                builder: (_) => _QueueSongMenu(song: item),
              ),
              onTap: () =>
                  _method.invokeMethod('skipToQueueIndex', {'index': index}),
            );
          }),
      ],
    );
  }
}

class _PlayerActionMenu extends StatelessWidget {
  const _PlayerActionMenu({
    required this.song,
    required this.progressStyle,
    required this.onStyle,
    required this.onLyrics,
  });

  final _Song song;
  final int progressStyle;
  final ValueChanged<int> onStyle;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _Artwork(url: song.artwork, size: 58, radius: 10),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _MenuQuickAction(
                    icon: Icons.favorite_rounded,
                    label: 'Like',
                    onTap: () =>
                        _method.invokeMethod('like', {'song': song.toMap()}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MenuQuickAction(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    onTap: () => _method.invokeMethod('download', {
                      'song': song.toMap(),
                    }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MenuQuickAction(
                    icon: Icons.queue_music_rounded,
                    label: 'Queue',
                    onTap: () => _method.invokeMethod('addToQueue', {
                      'song': song.toMap(),
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _MenuAction(
              icon: Icons.queue_play_next_rounded,
              label: 'Play next',
              subtitle: 'Insert this track after the current one',
              onTap: () => _method.invokeMethod('enqueuePlayNext', {
                'song': song.toMap(),
              }),
            ),
            _MenuAction(
              icon: Icons.lyrics_rounded,
              label: 'Open lyrics',
              subtitle: 'Show synced lyrics in the full player',
              onTap: () async => onLyrics(),
            ),
            _MenuAction(
              icon: Icons.equalizer_rounded,
              label: 'System equalizer',
              subtitle: 'Open Android audio effects if available',
              onTap: () => _method.invokeMethod('openSystemEqualizer'),
            ),
            _MenuAction(
              icon: Icons.bedtime_rounded,
              label: 'Sleep after current song',
              subtitle: 'Stop playback when this track ends',
              onTap: () async =>
                  _method.invokeMethod('sleepTimer', {'minutes': 0}),
            ),
            _MenuAction(
              icon: Icons.timer_rounded,
              label: 'Sleep in 30 minutes',
              subtitle: 'Schedule a timed stop',
              onTap: () async =>
                  _method.invokeMethod('sleepTimer', {'minutes': 30}),
            ),
            _MenuAction(
              icon: Icons.timer_off_rounded,
              label: 'Cancel sleep timer',
              subtitle: 'Clear any pending sleep timer',
              onTap: () async => _method.invokeMethod('cancelSleepTimer'),
            ),
            _MenuAction(
              icon: Icons.radio_rounded,
              label: 'Start radio',
              subtitle: 'Build a station from this song.',
              onTap: () async {
                final mix =
                    _asMap(
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
            _MenuAction(
              icon: Icons.share_rounded,
              label: 'Share',
              subtitle: 'Copy link to this track',
              onTap: () async {
                final link =
                    'https://music.youtube.com/watch?v=${song.videoId}';
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Link copied to clipboard')),
                  );
                }
              },
            ),
            _MenuAction(
              icon: Icons.open_in_new_rounded,
              label: 'Open in YouTube Music',
              subtitle: 'In your browser',
              onTap: () async => _method.invokeMethod('openExternalUrl', {
                'url': 'https://music.youtube.com/watch?v=${song.videoId}',
              }),
            ),
            if (song.isDownloaded)
              _MenuAction(
                icon: Icons.delete_outline_rounded,
                label: 'Remove download',
                subtitle: 'Delete offline file for this track',
                onTap: () async => _method.invokeMethod('removeDownload', {
                  'song': song.toMap(),
                }),
              ),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Progress style',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.62),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final item in const [
                  (0, 'Line', Icons.horizontal_rule_rounded),
                  (1, 'Pill', Icons.drag_handle_rounded),
                  (2, 'Wave', Icons.graphic_eq_rounded),
                  (3, 'Squiggle', Icons.show_chart_rounded),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Tooltip(
                        message: item.$2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(_kCardRadius),
                          onTap: () => onStyle(item.$1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: progressStyle == item.$1
                                  ? accent.withValues(alpha: 0.2)
                                  : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(_kCardRadius),
                              border: Border.all(
                                color: progressStyle == item.$1
                                    ? accent
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Icon(item.$3, size: 20),
                          ),
                        ),
                      ),
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
            leading: _Artwork(url: song.artwork, size: 52, radius: 6),
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
  });

  final String url;
  final bool playing;
  final String tag;

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
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = widget.playing
            ? 1.0 + math.sin(_controller.value * math.pi * 2) * 0.012
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
      child: Hero(
        tag: widget.tag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: _Artwork(url: widget.url, size: 304, radius: 0),
        ),
      ),
    );
  }
}

class _MainPlayButton extends StatelessWidget {
  const _MainPlayButton({required this.playing, required this.buffering});

  final bool playing;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: () => _method.invokeMethod('togglePlayPause'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.38),
              blurRadius: playing ? 28 : 12,
            ),
          ],
        ),
        child: buffering
            ? const Padding(
                padding: EdgeInsets.all(25),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Colors.black,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
                size: 44,
              ),
      ),
    );
  }
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.onTap,
    this.active = false,
    this.large = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return IconButton(
      onPressed: onTap,
      iconSize: large ? 40 : 27,
      color: active ? accent : Colors.white,
      icon: Icon(icon),
    );
  }
}

class _UtilityButton extends StatelessWidget {
  const _UtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCardRadius),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.url, required this.size, required this.radius});

  final String url;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (url.isBlank) {
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        key: ValueKey<String>(url),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          width: size,
          height: size,
          color: const Color(0xFF242424),
          alignment: Alignment.center,
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.white.withValues(alpha: 0.42),
          ),
        ),
      ),
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.blurEnabled,
    this.sigma = 52,
  });

  final String url;
  final bool blurEnabled;
  final double sigma;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (!blurEnabled || url.isBlank) {
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
              child: Image.network(
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
                const Color(0xFF000000).withValues(alpha: 0.92),
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
  });

  factory _Song.fromMap(Map<String, dynamic> map) {
    final artwork = [map['artworkUrl'], map['thumbnail']]
        .map((value) => value?.toString() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return _Song(
      videoId: map['videoId']?.toString() ?? '',
      title: map['title']?.toString().ifBlank('Untitled') ?? 'Untitled',
      artist:
          map['artist']?.toString().ifBlank('Unknown artist') ??
          'Unknown artist',
      artwork: artwork,
      duration: map['duration']?.toString(),
      isDownloaded: map['isDownloaded'] == true,
    );
  }

  final String videoId;
  final String title;
  final String artist;
  final String artwork;
  final String? duration;
  final bool isDownloaded;

  Map<String, dynamic> toMap() => {
    'videoId': videoId,
    'title': title,
    'artist': artist,
    'thumbnail': artwork,
    'artworkUrl': artwork,
    'isDownloaded': isDownloaded,
    if (duration != null) 'duration': duration,
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
