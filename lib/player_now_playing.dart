part of 'main.dart';

class _MetrolistMiniRingPainter extends CustomPainter {
  _MetrolistMiniRingPainter({required this.progress, required this.accent});

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
  bool shouldRepaint(covariant _MetrolistMiniRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.accent != accent;
}

class _MetrolistPlayerSectionLabel extends StatelessWidget {
  const _MetrolistPlayerSectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;
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
            ...?(trailingWidget == null ? null : [trailingWidget]),
          ],
        ),
        const SizedBox(height: 8),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PlayerControlSnapshot {
  const _PlayerControlSnapshot({
    required this.playing,
    required this.buffering,
    required this.shuffle,
    required this.repeatMode,
  });

  final bool playing;
  final bool buffering;
  final bool shuffle;
  final String repeatMode;

  factory _PlayerControlSnapshot.fromPlayer(Map<String, dynamic> player) {
    return _PlayerControlSnapshot(
      playing: player['isPlaying'] == true,
      buffering: _effectivePlayerBuffering(player),
      shuffle: player['shuffleEnabled'] == true,
      repeatMode: (player['repeatMode'] ?? 'Off').toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _PlayerControlSnapshot &&
        other.playing == playing &&
        other.buffering == buffering &&
        other.shuffle == shuffle &&
        other.repeatMode == repeatMode;
  }

  @override
  int get hashCode => Object.hash(playing, buffering, shuffle, repeatMode);
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.player,
    required this.scrollController,
    this.initialTab = 0,
    this.homeBackgroundPath,
    this.onNotifyHomePlayerSync,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final Map<String, dynamic> player;
  final ScrollController scrollController;
  final int initialTab;
  final String? homeBackgroundPath;
  final Future<void> Function()? onNotifyHomePlayerSync;
  final _FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  static final Map<String, List<_LyricLine>> _lyricsCache =
      <String, List<_LyricLine>>{};
  static final Map<String, String> _artistArtworkCache = <String, String>{};

  late Map<String, dynamic> _player = _detachPlayerState(
    _asMap(widget.player) ?? <String, dynamic>{},
  );
  StreamSubscription<dynamic>? _sub;
  late int _tab = widget.initialTab;
  int _progressStyle = 0;
  int _seekMotion = 0;
  int _playerButtonsStyle = 0;
  bool _enableLiquidGlassLayout = false;
  bool _hapticFeedback = true;
  bool _hidePlayerArtwork = false;
  int _artworkDisplayStyle = 0;
  double _thumbnailCornerRadius = 16;
  List<_LyricLine> _lyrics = const [];
  String? _lyricsFor;
  String? _lyricsCacheKeyFor;
  int _lyricsRequestSerial = 0;
  bool _lyricsLoading = false;
  String? _artistArtFor;
  String? _artistArtworkUrl;
  final ValueNotifier<double> _artworkSwipeDx = ValueNotifier<double>(0);
  final ValueNotifier<int> _positionMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> _durationMsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _sheetScrollingNotifier = ValueNotifier<bool>(
    false,
  );
  late final ValueNotifier<_PlayerControlSnapshot> _controlsNotifier =
      ValueNotifier<_PlayerControlSnapshot>(
        _PlayerControlSnapshot.fromPlayer(_player),
      );
  Timer? _sheetScrollIdleTimer;
  bool _swipeCompleting = false;
  int _playerBackgroundStyle = 0;
  final ScrollController _lyricsPanelScroll = ScrollController();
  final ScrollController _queuePanelScroll = ScrollController();
  final GlobalKey _compactLyricsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _positionMsNotifier.value = ((_player['positionMs'] ?? 0) as num).toInt();
    _durationMsNotifier.value = ((_player['durationMs'] ?? 0) as num).toInt();
    _loadAppearance();
    _sub = _foxyEvents.listen((dynamic event) {
      final map = _asMap(event);
      if (map == null) return;
      final type = map['type']?.toString();
      if (type == 'playerState') {
        final state = _asMap(map['state']);
        if (state != null && mounted) {
          final previousId = _asMap(
            _player['currentSong'],
          )?['videoId']?.toString();
          final detached = _mergePlayerState(state);
          final nextId = _asMap(
            detached['currentSong'],
          )?['videoId']?.toString();
          final previousSong = _asMap(_player['currentSong']) ?? const {};
          final nextSong = _asMap(detached['currentSong']) ?? const {};
          final trackMetadataChanged =
              previousId != nextId ||
              previousSong['title']?.toString() !=
                  nextSong['title']?.toString() ||
              previousSong['artist']?.toString() !=
                  nextSong['artist']?.toString() ||
              previousSong['artwork']?.toString() !=
                  nextSong['artwork']?.toString() ||
              previousSong['thumbnail']?.toString() !=
                  nextSong['thumbnail']?.toString() ||
              previousSong['offlineArtworkPath']?.toString() !=
                  nextSong['offlineArtworkPath']?.toString();
          final structuralChanged = _nowPlayingSnapshotChanged(
            _player,
            detached,
          );
          final nextPosition = ((detached['positionMs'] ?? 0) as num).toInt();
          final nextDuration = ((detached['durationMs'] ?? 0) as num).toInt();
          if (_positionMsNotifier.value != nextPosition) {
            _positionMsNotifier.value = nextPosition;
          }
          if (_durationMsNotifier.value != nextDuration) {
            _durationMsNotifier.value = nextDuration;
          }
          _updateControls(detached);
          if (structuralChanged) {
            setState(() {
              _player = detached;
              if (previousId != nextId) {
                _artworkSwipeDx.value = 0;
                _swipeCompleting = false;
              }
            });
          } else {
            _player = detached;
          }
          if (trackMetadataChanged) {
            _loadLyricsIfNeeded(detached);
            _loadArtistArtworkIfNeeded(detached);
          }
        }
      } else if (type == 'playerProgress') {
        final nextPosition = ((map['positionMs'] ?? 0) as num).toInt();
        final nextDuration = ((map['durationMs'] ?? 0) as num).toInt();
        if (_positionMsNotifier.value != nextPosition) {
          _positionMsNotifier.value = nextPosition;
        }
        if (nextDuration > 0 && _durationMsNotifier.value != nextDuration) {
          _durationMsNotifier.value = nextDuration;
        }
        final next = <String, dynamic>{..._player};
        next['positionMs'] = nextPosition;
        if (nextDuration > 0) next['durationMs'] = nextDuration;
        final playing = map['isPlaying'];
        final buffering = map['isBuffering'];
        if (playing is bool) next['isPlaying'] = playing;
        if (buffering is bool) next['isBuffering'] = buffering;
        final detached = _detachPlayerState(next);
        _player = detached;
        _updateControls(detached);
      } else if (type == 'appearanceChanged') {
        _loadAppearance();
        unawaited(_refreshPlayerSettings());
        _lyricsFor = '';
        _lyricsCacheKeyFor = null;
        unawaited(_loadLyricsIfNeeded(_player));
      }
    });
    _loadLyricsIfNeeded(_player);
    _loadArtistArtworkIfNeeded(_player);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _artworkSwipeDx.dispose();
    _positionMsNotifier.dispose();
    _durationMsNotifier.dispose();
    _sheetScrollIdleTimer?.cancel();
    _sheetScrollingNotifier.dispose();
    _controlsNotifier.dispose();
    _lyricsPanelScroll.dispose();
    _queuePanelScroll.dispose();
    super.dispose();
  }

  Future<void> _loadAppearance() async {
    final map = _asMap(await _method.invokeMethod('getAppearance'));
    if (!mounted || map == null) return;
    final nextBackgroundStyle = _normalizePlayerBackgroundStyle(
      ((map['playerBackgroundStyle'] ?? 0) as num).toInt(),
    );
    setState(() {
      _progressStyle = _normalizePlayerProgressStyle(
        ((map['playerProgressStyle'] ?? 0) as num).toInt(),
      );
      _seekMotion = 0;
      _playerButtonsStyle = ((map['playerButtonsStyle'] ?? 0) as num)
          .toInt()
          .clamp(0, 2);
      _enableLiquidGlassLayout = map['enableLiquidGlassLayout'] == true;
      _hapticFeedback = map['hapticFeedback'] != false;
      _hidePlayerArtwork = map['hidePlayerArtwork'] == true;
      _artworkDisplayStyle = ((map['artworkDisplayStyle'] ?? 0) as num)
          .toInt()
          .clamp(0, 2);
      _thumbnailCornerRadius = ((map['thumbnailCornerRadius'] ?? 16) as num)
          .toDouble()
          .clamp(0, 40);
      _playerBackgroundStyle = nextBackgroundStyle;
    });
  }

  Future<void> _refreshPlayerSettings() async {
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap == null || !mounted) return;
    _positionMsNotifier.value = ((snap['positionMs'] ?? 0) as num).toInt();
    _durationMsNotifier.value = ((snap['durationMs'] ?? 0) as num).toInt();
    setState(() => _player = _mergePlayerState(snap));
    _updateControls(_player);
  }

  void _updateControls(Map<String, dynamic> player) {
    final next = _PlayerControlSnapshot.fromPlayer(player);
    if (_controlsNotifier.value != next) {
      _controlsNotifier.value = next;
    }
  }

  void _markSheetScrolling() {
    if (!_sheetScrollingNotifier.value) {
      _sheetScrollingNotifier.value = true;
    }
    _sheetScrollIdleTimer?.cancel();
    _sheetScrollIdleTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted) _sheetScrollingNotifier.value = false;
    });
  }

  Map<String, dynamic> _mergePlayerState(Map<String, dynamic> state) {
    final merged = <String, dynamic>{..._player, ...state};
    if (!state.containsKey('queue') && _player.containsKey('queue')) {
      merged['queue'] = _player['queue'];
    }
    return _detachPlayerState(merged);
  }

  bool _nowPlayingSnapshotChanged(
    Map<String, dynamic> prev,
    Map<String, dynamic> next,
  ) {
    if (prev['playerEpoch'] != next['playerEpoch']) return true;
    if (prev['songIsLiked'] != next['songIsLiked']) return true;
    if (prev['shuffleEnabled'] != next['shuffleEnabled']) return true;
    if (prev['repeatMode']?.toString() != next['repeatMode']?.toString()) {
      return true;
    }
    if (prev['queueIndex'] != next['queueIndex']) return true;
    if (_playerQueueSignature(prev['queue']) !=
        _playerQueueSignature(next['queue'])) {
      return true;
    }
    final pSong = _asMap(prev['currentSong']) ?? const {};
    final nSong = _asMap(next['currentSong']) ?? const {};
    for (final key in const [
      'videoId',
      'title',
      'artist',
      'artwork',
      'thumbnail',
      'offlineArtworkPath',
      'isDownloaded',
    ]) {
      if (pSong[key]?.toString() != nSong[key]?.toString()) return true;
    }
    return false;
  }

  Future<void> _loadLyricsIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final preferLrclib = player['lyricsPreferLrclib'] != false;
    final romanize = player['lyricsRomanize'] == true;
    final cacheKey = '${song.videoId}|$preferLrclib|$romanize';
    if (song.videoId.isEmpty) {
      if (_lyrics.isNotEmpty || _lyricsLoading || _lyricsFor != null) {
        setState(() {
          _lyrics = const [];
          _lyricsFor = null;
          _lyricsCacheKeyFor = null;
          _lyricsLoading = false;
        });
      }
      return;
    }
    if (_lyricsCacheKeyFor == cacheKey &&
        (_lyricsLoading || _lyrics.isNotEmpty)) {
      return;
    }
    final requestSerial = ++_lyricsRequestSerial;
    _lyricsFor = song.videoId;
    _lyricsCacheKeyFor = cacheKey;
    final cached = _lyricsCache[cacheKey];
    if (cached != null) {
      setState(() {
        _lyrics = cached;
        _lyricsLoading = false;
      });
      return;
    }
    setState(() {
      _lyricsLoading = true;
      _lyrics = const [];
    });
    try {
      final response = await _method.invokeMethod('lyrics', {
        'song': song.toMap(),
      });
      if (!mounted ||
          requestSerial != _lyricsRequestSerial ||
          _lyricsCacheKeyFor != cacheKey) {
        return;
      }
      final lines = (response as List? ?? const [])
          .map((item) => _LyricLine.fromMap(_asMap(item) ?? const {}))
          .where((line) => line.text.isNotEmpty)
          .toList();
      _lyricsCache[cacheKey] = lines;
      if (_lyricsCache.length > 32) {
        _lyricsCache.remove(_lyricsCache.keys.first);
      }
      setState(() {
        _lyrics = lines;
        _lyricsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (requestSerial != _lyricsRequestSerial ||
          _lyricsCacheKeyFor != cacheKey) {
        return;
      }
      setState(() => _lyricsLoading = false);
    }
  }

  Future<void> _loadArtistArtworkIfNeeded(Map<String, dynamic> player) async {
    final song = _Song.fromMap(_asMap(player['currentSong']) ?? const {});
    final artist = _primaryArtistNameForLookup(song.artist).trim();
    final artistKey = _normalizeArtistLookupKey(artist);
    if (artist.isEmpty || artistKey.isEmpty || _artistArtFor == artistKey) {
      return;
    }
    _artistArtFor = artistKey;
    final cached = _artistArtworkCache[artistKey];
    if (cached != null) {
      setState(() => _artistArtworkUrl = cached.isEmpty ? null : cached);
      return;
    }
    setState(() => _artistArtworkUrl = null);
    try {
      final response =
          _asMap(
            await _method.invokeMethod('resolveArtistProfile', {
              'artist': artist,
              'limit': 18,
            }),
          ) ??
          const {};
      if (!mounted || _artistArtFor != artistKey) return;
      final resolvedArtist = response['artist']?.toString().trim() ?? '';
      final resolvedKey = _normalizeArtistLookupKey(resolvedArtist);
      final artwork = resolvedKey == artistKey
          ? (response['artworkUrl']?.toString().trim() ?? '')
          : '';
      _artistArtworkCache[artistKey] = artwork;
      if (_artistArtworkCache.length > 48) {
        _artistArtworkCache.remove(_artistArtworkCache.keys.first);
      }
      setState(() {
        _artistArtworkUrl = artwork.isEmpty ? null : artwork;
      });
    } catch (_) {
      if (!mounted || _artistArtFor != artistKey) return;
      setState(() => _artistArtworkUrl = null);
    }
  }

  void _openDefaultPlayerPage() {
    setState(() => _tab = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _openFullLyrics() {
    setState(() => _tab = 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.animateTo(
        widget.scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _toggleLike(_Song song) async {
    final method = _player['songIsLiked'] == true ? 'unlike' : 'like';
    await _method.invokeMethod(method, {'song': song.toMap()});
    if (!mounted) return;
    final snap = _asMap(await _method.invokeMethod('getPlayerState'));
    if (snap != null) {
      setState(() => _player = _mergePlayerState(snap));
    }
    await widget.onNotifyHomePlayerSync?.call();
  }

  Future<void> _openPlaylistPicker(_Song song) async {
    final feed = _asMap(await _method.invokeMethod('libraryFeed')) ?? const {};
    if (!mounted) return;
    await _pickPlaylistToAddSong(
      context,
      song: song,
      playlists: _userPlaylistsFrom(feed['userPlaylists']),
      onChanged: widget.onNotifyHomePlayerSync,
    );
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
      compactPlayerMenu: true,
      onOpenLyricsTabInPlayer: () {
        if (mounted) _openFullLyrics();
      },
    );
  }

  void _openArtistPage(_Song song) {
    final artist = song.artist.trim();
    if (artist.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ArtistPage(
          artist: artist,
          artworkUrl:
              (_artistArtworkUrl?.ifBlank(song.highQualityArtwork) ??
              song.highQualityArtwork),
          onPlay: widget.onPlay ?? _fallbackPlayFromArtistPage,
          onDiscoverSearch: widget.onDiscoverSearch,
        ),
      ),
    );
  }

  Future<void> _fallbackPlayFromArtistPage(
    _Song song,
    List<_Song> queue, {
    bool radioTail = false,
  }) async {
    await _method.invokeMethod('playQueue', {
      'songs': (queue.isEmpty ? <_Song>[song] : queue)
          .map((item) => item.toMap())
          .toList(),
      'startIndex': math.max(
        0,
        queue.indexWhere((s) => s.videoId == song.videoId),
      ),
      'radioTail': radioTail,
    });
  }

  void _shareSongLink(_Song song) {
    if (song.videoId.isEmpty) return;
    Clipboard.setData(
      ClipboardData(text: 'https://music.youtube.com/watch?v=${song.videoId}'),
    );
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    final posterArtworkUrl = song.highQualityArtwork;
    final backgroundArtworkUrl = posterArtworkUrl;
    final hintMs = _durationHintMsFromCatalog(song.duration);
    final rawQueue = (_player['queue'] as List?) ?? const [];
    final queueIndex = ((_player['queueIndex'] ?? -1) as num).toInt();
    final hasQueue = rawQueue.isNotEmpty;
    _Song? queueSongAt(int index) {
      if (index < 0 || index >= rawQueue.length) return null;
      return _Song.fromMap(_asMap(rawQueue[index]) ?? const {});
    }

    final effectiveQueueIndex = hasQueue
        ? queueIndex.clamp(0, rawQueue.length - 1)
        : (song.videoId.isNotEmpty ? 0 : -1);
    final queueForTab = _tab == 2
        ? rawQueue
              .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
              .where((item) => item.videoId.isNotEmpty || item.title.isNotEmpty)
              .toList(growable: false)
        : null;
    final effectiveQueueForTab = queueForTab == null
        ? const <_Song>[]
        : (queueForTab.isNotEmpty
              ? queueForTab
              : (song.videoId.isNotEmpty ? <_Song>[song] : const <_Song>[]));
    final effectiveQueueTabIndex = effectiveQueueForTab.isEmpty
        ? -1
        : effectiveQueueIndex.clamp(0, effectiveQueueForTab.length - 1);
    final padL = 14.0 + MediaQuery.paddingOf(context).left;
    final padR = 14.0 + MediaQuery.paddingOf(context).right;
    final padBottom = MediaQuery.paddingOf(context).bottom;
    return PopScope(
      canPop: _tab != 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted && _tab == 1) {
          setState(() => _tab = 0);
        }
      },
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: ValueListenableBuilder<_PlayerControlSnapshot>(
                  valueListenable: _controlsNotifier,
                  builder: (context, controls, _) =>
                      ValueListenableBuilder<bool>(
                        valueListenable: _sheetScrollingNotifier,
                        builder: (context, scrolling, _) => _NowPlayingBackdrop(
                          song: song,
                          artworkUrl: backgroundArtworkUrl,
                          backgroundStyle: _playerBackgroundStyle,
                          playing: controls.playing && !scrolling,
                          lightweight: scrolling,
                        ),
                      ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(padL, 4, padR, 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 2, bottom: 6),
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
                            icon: const Icon(Icons.keyboard_arrow_down_rounded),
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
                                  onPlayer: _openDefaultPlayerPage,
                                  onLyrics: _openFullLyrics,
                                  onQueue: () => setState(() => _tab = 2),
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
                Expanded(
                  child: ValueListenableBuilder<_PlayerControlSnapshot>(
                    valueListenable: _controlsNotifier,
                    builder: (context, controls, _) => LayoutBuilder(
                      builder: (context, c) {
                        final playing = controls.playing;
                        final buffering = controls.buffering;
                        final shuffle = controls.shuffle;
                        final repeat = controls.repeatMode;
                        final prevEnabled =
                            _player['canPlayPrevious'] == true ||
                            effectiveQueueIndex > 0;
                        final nextEnabled =
                            _player['canPlayNext'] == true ||
                            (hasQueue &&
                                effectiveQueueIndex >= 0 &&
                                effectiveQueueIndex < rawQueue.length - 1);
                        final previousSong = hasQueue && effectiveQueueIndex > 0
                            ? queueSongAt(effectiveQueueIndex - 1)
                            : null;
                        final nextSong = nextEnabled
                            ? queueSongAt(effectiveQueueIndex + 1)
                            : null;
                        final maxW = c.maxWidth;
                        final viewH = MediaQuery.sizeOf(context).height;
                        final titleSeekGap = viewH * 0.022;
                        final controlsLyricsGap = viewH * 0.0048;
                        final artSide = math
                            .min(maxW - 18, viewH * 0.45)
                            .clamp(300.0, 760.0);
                        final swipePageWidth = math.max(1.0, maxW - 36);
                        return NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification ||
                                notification is ScrollUpdateNotification ||
                                notification is OverscrollNotification) {
                              _markSheetScrolling();
                            }
                            return false;
                          },
                          child: SingleChildScrollView(
                            controller: widget.scrollController,
                            physics: _kFoxyPlayerSheetPhysics,
                            dragStartBehavior: DragStartBehavior.down,
                            clipBehavior: Clip.none,
                            padding: EdgeInsets.fromLTRB(
                              18,
                              0,
                              18,
                              padBottom + 10,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(height: 14),
                                Text(
                                  'NOW PLAYING',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.95),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                if (_tab == 1) ...[
                                  _LyricsFullscreenTrackHeader(
                                    song: song,
                                    liked: _player['songIsLiked'] == true,
                                    onLike: () => unawaited(_toggleLike(song)),
                                    onMenu: () => _openMenu(song),
                                  ),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    height: (viewH * 0.62).clamp(500.0, 760.0),
                                    child: AnimatedBuilder(
                                      animation: _positionMsNotifier,
                                      builder: (context, _) => _LyricsTab(
                                        lines: _lyrics,
                                        loading: _lyricsLoading,
                                        positionMs: _positionMsNotifier.value,
                                        accent: accent,
                                        scrollController: _lyricsPanelScroll,
                                        preferLrclib:
                                            _player['lyricsPreferLrclib'] !=
                                            false,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                ] else ...[
                                  GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    dragStartBehavior: DragStartBehavior.down,
                                    onHorizontalDragUpdate: (details) {
                                      if (_swipeCompleting) return;
                                      _artworkSwipeDx.value =
                                          (_artworkSwipeDx.value +
                                                  details.delta.dx)
                                              .clamp(
                                                -swipePageWidth,
                                                swipePageWidth,
                                              );
                                    },
                                    onHorizontalDragEnd: (_) {
                                      if (_swipeCompleting) return;
                                      if (_artworkSwipeDx.value > 72) {
                                        setState(() {
                                          _swipeCompleting = true;
                                          _artworkSwipeDx.value =
                                              swipePageWidth;
                                        });
                                        _method.invokeMethod('previous');
                                      } else if (_artworkSwipeDx.value < -72) {
                                        setState(() {
                                          _swipeCompleting = true;
                                          _artworkSwipeDx.value =
                                              -swipePageWidth;
                                        });
                                        _method.invokeMethod('next');
                                      } else {
                                        _artworkSwipeDx.value = 0;
                                      }
                                    },
                                    onHorizontalDragCancel: () {
                                      if (!_swipeCompleting) {
                                        _artworkSwipeDx.value = 0;
                                      }
                                    },
                                    child: ValueListenableBuilder<double>(
                                      valueListenable: _artworkSwipeDx,
                                      builder: (context, dragDx, _) =>
                                          RepaintBoundary(
                                            child: _SwipePlayerPageDeck(
                                              current: song,
                                              previous: previousSong,
                                              next: nextSong,
                                              currentArtworkUrl:
                                                  posterArtworkUrl,
                                              playing: playing && !buffering,
                                              dragDx: dragDx,
                                              pageWidth: swipePageWidth,
                                              maxSide: artSide,
                                              liked:
                                                  _player['songIsLiked'] ==
                                                  true,
                                              hideArtwork: _hidePlayerArtwork,
                                              artworkDisplayStyle:
                                                  _artworkDisplayStyle,
                                              thumbnailCornerRadius:
                                                  _thumbnailCornerRadius,
                                              onLike: () =>
                                                  unawaited(_toggleLike(song)),
                                              onShare: () =>
                                                  _shareSongLink(song),
                                              onDownload: song.isDownloaded
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
                                                              _mergePlayerState(
                                                                snap,
                                                              ),
                                                        );
                                                      }
                                                    },
                                              onPlaylist: () => unawaited(
                                                _openPlaylistPicker(song),
                                              ),
                                            ),
                                          ),
                                    ),
                                  ),
                                  SizedBox(height: titleSeekGap),
                                ],
                                if (buffering)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        minHeight: 4,
                                        backgroundColor: Colors.grey.shade800
                                            .withValues(alpha: 0.9),
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                AnimatedBuilder(
                                  animation: Listenable.merge([
                                    _positionMsNotifier,
                                    _durationMsNotifier,
                                  ]),
                                  builder: (context, _) {
                                    final duration = _durationMsNotifier.value
                                        .toDouble();
                                    final position = _positionMsNotifier.value
                                        .toDouble();
                                    final effectiveDurMs = duration > 750
                                        ? duration
                                        : (hintMs?.toDouble() ?? 0.0);
                                    final progress = effectiveDurMs <= 0
                                        ? 0.0
                                        : (position / effectiveDurMs).clamp(
                                            0.0,
                                            1.0,
                                          );
                                    final endTimeLabel = effectiveDurMs > 750
                                        ? _fmt(effectiveDurMs.round())
                                        : '--:--';
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        RepaintBoundary(
                                          child: _MetrolistSeekBar(
                                            value: progress,
                                            enabled: effectiveDurMs > 750,
                                            style: _progressStyle,
                                            motion: _seekMotion,
                                            accent: accent,
                                            onSeek: (value) =>
                                                _method.invokeMethod('seekTo', {
                                                  'positionMs':
                                                      (effectiveDurMs * value)
                                                          .round(),
                                                }),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            6,
                                            2,
                                            6,
                                            0,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _fmt(position.round()),
                                                style: const TextStyle(
                                                  color: _kMetrolistNpTime,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                endTimeLabel,
                                                style: const TextStyle(
                                                  color: _kMetrolistNpTime,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  fontFeatures: [
                                                    FontFeature.tabularFigures(),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 4),
                                _FoxyPlayerControlLayout(
                                  shuffle: shuffle,
                                  repeatMode: repeat,
                                  playing: playing,
                                  buffering: buffering,
                                  prevEnabled: prevEnabled,
                                  nextEnabled: nextEnabled,
                                  buttonStyle: _playerButtonsStyle,
                                  useLiquidGlass: _enableLiquidGlassLayout,
                                  hapticFeedback: _hapticFeedback,
                                ),
                                SizedBox(height: controlsLyricsGap * 0.72),
                                if (_tab != 1)
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeOutCubic,
                                    child: switch (_tab) {
                                      2 => SizedBox(
                                        key: const ValueKey('queue-section'),
                                        height: viewH * 0.48,
                                        child: _QueueTab(
                                          queue: effectiveQueueForTab,
                                          currentIndex: effectiveQueueTabIndex,
                                          scrollController: _queuePanelScroll,
                                          onPlay: widget.onPlay,
                                          onDiscoverSearch:
                                              widget.onDiscoverSearch,
                                        ),
                                      ),
                                      _ => Column(
                                        key: const ValueKey('details-section'),
                                        children: [
                                          AnimatedBuilder(
                                            animation: _positionMsNotifier,
                                            builder: (context, _) =>
                                                _CompactLyricsPreviewCard(
                                                  key: _compactLyricsKey,
                                                  lines: _lyrics,
                                                  loading: _lyricsLoading,
                                                  positionMs:
                                                      _positionMsNotifier.value,
                                                  accent: accent,
                                                  onTap: _openFullLyrics,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          _ScrollRevealOnApproach(
                                            scrollController:
                                                widget.scrollController,
                                            child: _PlayerArtistMiniCard(
                                              artist: song.artist,
                                              artworkUrl:
                                                  _artistArtworkUrl?.ifBlank(
                                                    song.highQualityArtwork,
                                                  ) ??
                                                  song.highQualityArtwork,
                                              accent: accent,
                                              onTap: () =>
                                                  _openArtistPage(song),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          _ScrollRevealOnApproach(
                                            scrollController:
                                                widget.scrollController,
                                            child: _SongDetailsCard(
                                              song: song,
                                              player: _player,
                                            ),
                                          ),
                                        ],
                                      ),
                                    },
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
          ],
        ),
      ),
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({
    required this.accent,
    required this.selected,
    required this.onPlayer,
    required this.onLyrics,
    required this.onQueue,
  });

  final Color accent;
  final int selected;
  final VoidCallback onPlayer;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    final tabs = <(IconData, String, VoidCallback, bool)>[
      (Icons.album_rounded, 'Player', onPlayer, selected == 0),
      (Icons.lyrics_outlined, 'Lyrics', onLyrics, selected == 1),
      (Icons.queue_music_outlined, 'Queue', onQueue, selected == 2),
    ];
    return _FoxyGlassButton(
      borderRadius: BorderRadius.circular(999),
      tintOpacity: 0.26,
      blurSigma: 14,
      blur: true,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Tooltip(
                message: tabs[i].$2,
                child: _FoxyGlassButton(
                  onTap: tabs[i].$3,
                  borderRadius: BorderRadius.circular(999),
                  blur: true,
                  blurSigma: 10,
                  tintOpacity: tabs[i].$4 ? 0.2 : 0.08,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 9,
                  ),
                  child: Icon(
                    tabs[i].$1,
                    size: 21,
                    color: tabs[i].$4
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ),
            ),
        ],
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
    with TickerProviderStateMixin {
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    final initial = widget.value.clamp(0.0, 1.0);
    _progressCtrl = AnimationController(
      vsync: this,
      value: initial,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void didUpdateWidget(covariant _MetrolistSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.value.clamp(0.0, 1.0);
    if ((target - _progressCtrl.value).abs() > 0.001) {
      if ((target - _progressCtrl.value).abs() < 0.012) {
        _progressCtrl.value = target;
      } else {
        _progressCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  double get _paintHeight {
    final s = _normalizePlayerProgressStyle(widget.style);
    if (s == 0) return 34.0;
    return 28.0;
  }

  void _seek(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    widget.onSeek((dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final st = _normalizePlayerProgressStyle(widget.style);
    Widget buildBar(double phase, double progress) {
      return CustomPaint(
        painter: _MetrolistSeekPainter(
          progress: progress,
          dimmed: !widget.enabled,
          style: st,
          accent: widget.accent,
          motion: 0,
          motionPhase: phase,
        ),
        child: SizedBox(height: _paintHeight, width: double.infinity),
      );
    }

    final content = AnimatedBuilder(
      animation: _progressCtrl,
      builder: (context, _) => buildBar(0, _progressCtrl.value.clamp(0.0, 1.0)),
    );
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
    final inactiveColor = dimmed
        ? _inactive.withValues(alpha: 0.45)
        : _inactive;
    final activeColor = dimmed ? Colors.white38 : _active;
    final trackH = 8.5;
    final radius = const Radius.circular(999);
    final full = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, y - trackH / 2, size.width, trackH),
      radius,
    );
    canvas.drawRRect(full, Paint()..color = inactiveColor);
    if (p > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, y - trackH / 2, size.width * p, trackH),
          radius,
        ),
        Paint()..color = activeColor,
      );
    }
    const tw = 4.0;
    const th = 17.0;
    final half = tw / 2 + 1.0;
    final cx = (size.width * p).clamp(half, size.width - half);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, y), width: tw, height: th),
      Radius.circular(tw / 2),
    );
    canvas.drawRRect(thumb, Paint()..color = dimmed ? Colors.white54 : _active);
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

/// Bottom tool row on the now-playing sheet (info, lyrics, queue, ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦).
/// Foxy-style transport row: shuffle ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· previous ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· large play/pause ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· next ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· repeat
/// .
class _FoxyPlayerControlLayout extends StatelessWidget {
  const _FoxyPlayerControlLayout({
    required this.shuffle,
    required this.repeatMode,
    required this.playing,
    required this.buffering,
    required this.prevEnabled,
    required this.nextEnabled,
    required this.buttonStyle,
    required this.useLiquidGlass,
    required this.hapticFeedback,
  });

  final bool shuffle;
  final String repeatMode;
  final bool playing;
  final bool buffering;
  final bool prevEnabled;
  final bool nextEnabled;
  final int buttonStyle;
  final bool useLiquidGlass;
  final bool hapticFeedback;

  void _tap(String method) {
    if (hapticFeedback) HapticFeedback.lightImpact();
    _method.invokeMethod(method);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final repeatOn = repeatMode != 'Off';

    Widget slot(Widget child) => Expanded(child: Center(child: child));

    Widget iconOnlyBtn({required VoidCallback? onTap, required Widget icon}) {
      return IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        splashRadius: 26,
        constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
        icon: icon,
      );
    }

    Widget mainPlay() {
      const playSize = 140.0;
      final solid = buttonStyle == 2;
      final outline = buttonStyle == 1;
      final coreContent = buffering
          ? Center(
              child: SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: outline ? Colors.white70 : Colors.black38,
                ),
              ),
            )
          : Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: playing ? 64 : 68,
              color: outline ? Colors.white : Colors.black87,
            );
      Widget inner = Container(
        width: playSize,
        height: playSize,
        decoration: outline
            ? BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 2),
              )
            : null,
        child: coreContent,
      );

      Widget body;
      if (solid || outline) {
        body = Material(
          color: solid ? accent.withValues(alpha: 0.95) : Colors.transparent,
          elevation: outline ? 0 : 8,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: inner,
        );
      } else {
        body = Material(
          color: Colors.white.withValues(alpha: 0.96),
          elevation: 8,
          shadowColor: Colors.black45,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: playSize,
            height: playSize,
            child: Center(child: coreContent),
          ),
        );
      }
      return slot(
        InkWell(
          customBorder: const CircleBorder(),
          onTap: () => _tap('togglePlayPause'),
          child: body,
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            slot(
              iconOnlyBtn(
                onTap: () => _tap('toggleShuffle'),
                icon: Icon(
                  Icons.shuffle_rounded,
                  size: 30,
                  color: shuffle ? accent : Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: prevEnabled ? () => _tap('previous') : null,
                icon: Icon(
                  Icons.skip_previous_rounded,
                  size: 40,
                  color: prevEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            mainPlay(),
            slot(
              iconOnlyBtn(
                onTap: nextEnabled ? () => _tap('next') : null,
                icon: Icon(
                  Icons.skip_next_rounded,
                  size: 40,
                  color: nextEnabled
                      ? Colors.white.withValues(alpha: 0.95)
                      : Colors.white30,
                ),
              ),
            ),
            slot(
              iconOnlyBtn(
                onTap: () => _tap('cycleRepeatMode'),
                icon: Icon(
                  repeatMode == 'One'
                      ? Icons.repeat_one_rounded
                      : Icons.repeat_rounded,
                  size: 30,
                  color: repeatOn
                      ? accent
                      : Colors.white.withValues(alpha: 0.9),
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
    required this.scrollController,
    this.preferLrclib = true,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final ScrollController scrollController;
  final bool preferLrclib;
  bool get _showProviderHeading => false;

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
                'Loading lyrics...',
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
          subtitle: preferLrclib
              ? 'LRCLIB had no match - try turning off "Prefer LRCLIB" in Settings or the menu.'
              : 'YouTube captions had no match - try "Prefer LRCLIB" in Settings.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_showProviderHeading)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              preferLrclib ? 'Synced - LRCLIB' : 'Synced - YouTube captions',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        _AnimatedLyricsList(
          lines: lines,
          positionMs: positionMs,
          accent: accent,
          scrollController: scrollController,
        ),
      ],
    );
  }
}

const int _kFullscreenLyricsExtraLines = 4;
const double _kLyricLineExtent = 74.0;

class _AnimatedLyricsList extends StatefulWidget {
  const _AnimatedLyricsList({
    required this.lines,
    required this.positionMs,
    required this.accent,
    required this.scrollController,
  });

  final List<_LyricLine> lines;
  final int positionMs;
  final Color accent;
  final ScrollController scrollController;

  @override
  State<_AnimatedLyricsList> createState() => _AnimatedLyricsListState();
}

class _AnimatedLyricsListState extends State<_AnimatedLyricsList> {
  int _lastActive = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerActiveLine(animated: false);
    });
  }

  @override
  void didUpdateWidget(covariant _AnimatedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = _activeIndex;
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _centerActiveLine(animated: true);
      });
    }
  }

  void _centerActiveLine({required bool animated}) {
    if (!widget.scrollController.hasClients) return;
    final viewport = widget.scrollController.position.viewportDimension.isFinite
        ? widget.scrollController.position.viewportDimension
        : 520.0;
    final target =
        (_activeIndex * _kLyricLineExtent -
                viewport * 0.5 +
                _kLyricLineExtent * 0.5)
            .clamp(0.0, widget.scrollController.position.maxScrollExtent);
    if (animated) {
      widget.scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.scrollController.jumpTo(target);
    }
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackHeight = MediaQuery.sizeOf(context).height * 0.58;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : fallbackHeight;
        final topPad = math.max(92.0, h * 0.42);
        final bottomPad = math.max(120.0, h * 0.48);
        return SizedBox(
          height: h,
          child: ListView.builder(
            controller: widget.scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(4, topPad, 4, bottomPad),
            itemCount: widget.lines.length,
            cacheExtent: _kLyricLineExtent * _kFullscreenLyricsExtraLines,
            itemBuilder: (context, index) {
              final line = widget.lines[index];
              final isActive = index == active;
              final passed = index < active;
              final distance = (index - active).abs();
              final inactiveAlpha = (0.62 - distance * 0.06).clamp(0.18, 0.56);
              return TweenAnimationBuilder<double>(
                key: ValueKey('${line.timeMs}-$isActive'),
                tween: Tween(begin: 0, end: isActive ? 1 : 0),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) {
                  final scale = 1.0 + (0.045 * t);
                  return AnimatedOpacity(
                    duration: const Duration(milliseconds: 260),
                    opacity: isActive ? 1 : inactiveAlpha.toDouble(),
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: isActive ? 12 : 9,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: Text(
                            line.text,
                            textAlign: TextAlign.center,
                            maxLines: isActive ? 3 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isActive
                                  ? Colors.white
                                  : passed
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.86),
                              fontSize: isActive ? 27 : 22,
                              height: 1.14,
                              fontWeight: isActive
                                  ? FontWeight.w900
                                  : FontWeight.w700,
                              shadows: isActive
                                  ? [
                                      Shadow(
                                        color: widget.accent.withValues(
                                          alpha: 0.26,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.queue,
    required this.currentIndex,
    required this.scrollController,
    this.onPlay,
    this.onDiscoverSearch,
  });

  final List<_Song> queue;
  final int currentIndex;
  final ScrollController scrollController;
  final _FoxyOnPlay? onPlay;
  final void Function(String query)? onDiscoverSearch;

  @override
  Widget build(BuildContext context) {
    if (queue.isEmpty) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(bottom: 120),
        children: const [
          SizedBox(height: 14),
          Padding(
            padding: EdgeInsets.only(top: 48),
            child: _EmptyTabBody(
              icon: Icons.queue_music_rounded,
              title: 'Queue is empty',
              subtitle: 'Play a song to build your queue, then open this tab.',
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: queue.length + 1,
      itemBuilder: (context, rawIndex) {
        if (rawIndex == 0) {
          final current =
              queue[currentIndex.clamp(0, queue.length - 1).toInt()];
          return Column(
            children: [
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    leading: _Artwork(
                      url: current.artwork,
                      size: 54,
                      radius: 12,
                      identityTag: current.videoId,
                    ),
                    title: const Text(
                      'Now playing',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
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
            ],
          );
        }
        final index = rawIndex - 1;
        final item = queue[index];
        final active = index == currentIndex;
        return _FoxySongTile(
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
          onTap: () =>
              _method.invokeMethod('skipToQueueIndex', {'index': index}),
        );
      },
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

class _PlayerArtistMiniCard extends StatelessWidget {
  const _PlayerArtistMiniCard({
    required this.artist,
    required this.artworkUrl,
    required this.accent,
    this.onTap,
  });

  final String artist;
  final String artworkUrl;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (artist.trim().isEmpty) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 1.58,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(
                url: artworkUrl,
                size: 600,
                radius: 0,
                highQuality: true,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.12),
                      Colors.black.withValues(alpha: 0.68),
                    ],
                    stops: const [0, 0.46, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 14,
                child: Text(
                  'Artists',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.95),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Tap to explore artist radio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 13,
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
                  Icons.chevron_right_rounded,
                  color: accent.withValues(alpha: 0.95),
                  size: 28,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactLyricsPreviewCard extends StatelessWidget {
  const _CompactLyricsPreviewCard({
    super.key,
    required this.lines,
    required this.loading,
    required this.positionMs,
    required this.accent,
    required this.onTap,
  });

  final List<_LyricLine> lines;
  final bool loading;
  final int positionMs;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = lines.isEmpty
        ? null
        : lines.lastWhere(
            (line) => line.timeMs <= positionMs,
            orElse: () => lines.first,
          );
    final preview = loading
        ? 'Loading lyrics...'
        : active?.text.trim().ifBlank('Open synced lyrics') ??
              'Open synced lyrics';

    const radius = 24.0;
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70.5),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          child: Row(
            children: [
              if (loading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.3,
                    color: accent.withValues(alpha: 0.9),
                  ),
                )
              else
                Icon(Icons.lyrics_rounded, color: accent, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: loading
                        ? Colors.white.withValues(alpha: 0.72)
                        : Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollRevealOnApproach extends StatefulWidget {
  const _ScrollRevealOnApproach({
    required this.scrollController,
    required this.child,
  });

  final ScrollController scrollController;
  final Widget child;

  @override
  State<_ScrollRevealOnApproach> createState() =>
      _ScrollRevealOnApproachState();
}

class _ScrollRevealOnApproachState extends State<_ScrollRevealOnApproach> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_checkVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void didUpdateWidget(covariant _ScrollRevealOnApproach oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_checkVisibility);
      widget.scrollController.addListener(_checkVisibility);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
    }
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (_visible || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || !widget.scrollController.hasClients) return;
    final position = widget.scrollController.position;
    final revealOffset = viewport.getOffsetToReveal(box, 0.15).offset;
    if (position.pixels + position.viewportDimension * 0.92 >= revealOffset) {
      setState(() => _visible = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.08),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class _SongDetailsCard extends StatelessWidget {
  const _SongDetailsCard({required this.song, required this.player});

  final _Song song;
  final Map<String, dynamic> player;

  @override
  Widget build(BuildContext context) {
    final title = song.title.trim();
    final artist = song.artist.trim();
    final album = song.album?.trim() ?? '';
    final descriptionText = (song.description?.trim().isNotEmpty ?? false)
        ? song.description!.trim()
        : player['description']?.toString().trim() ?? '';
    final uploadDate = (song.uploadDate?.trim().isNotEmpty ?? false)
        ? song.uploadDate!.trim()
        : (player['uploadDate'] ?? player['publishedAt'])?.toString().trim() ??
              '';
    final viewCount = (song.viewCount?.trim().isNotEmpty ?? false)
        ? song.viewCount!.trim()
        : (player['viewCount'] ?? player['views'])?.toString().trim() ?? '';
    final likeCount = (song.likeCount?.trim().isNotEmpty ?? false)
        ? song.likeCount!.trim()
        : (player['likeCount'] ?? player['likes'])?.toString().trim() ?? '';
    final channelName = (song.channelName?.trim().isNotEmpty ?? false)
        ? song.channelName!.trim()
        : (player['channelName'] ?? player['author'])?.toString().trim() ?? '';
    final liked = player['songIsLiked'] == true;
    final source = player['streamSource']?.toString().trim() ?? '';
    final rawCodec = player['streamCodec']?.toString().trim() ?? '';
    final mime = player['streamMimeType']?.toString().trim() ?? '';
    final codec = _friendlyCodecLabel(rawCodec, mime);
    final quality = player['streamQualityLabel']?.toString().trim() ?? '';
    final bitrate = (player['streamBitrate'] as num?)?.toInt();
    final bitrateLabel = _formatBitrateLabel(bitrate);
    final details = <String>[
      if (album.isNotEmpty) album,
      if (quality.isNotEmpty) quality,
      if (bitrateLabel.isNotEmpty) bitrateLabel,
      if (codec.isNotEmpty) codec,
      if (source.isNotEmpty) source,
      if ((song.duration?.trim().isNotEmpty ?? false)) song.duration!.trim(),
      if (uploadDate.isNotEmpty) uploadDate,
      if (viewCount.isNotEmpty) viewCount,
      if (liked) 'Liked',
      if (song.isDownloaded) 'Downloaded',
    ];

    final description = <String>[
      if (title.isNotEmpty && artist.isNotEmpty) '$title - $artist',
      if (channelName.isNotEmpty) 'Channel: $channelName',
      if (album.isNotEmpty) 'Album: $album',
      if (uploadDate.isNotEmpty) 'Published: $uploadDate',
      if (viewCount.isNotEmpty || likeCount.isNotEmpty)
        [
          if (viewCount.isNotEmpty) 'Views: $viewCount',
          if (likeCount.isNotEmpty) 'Likes: $likeCount',
        ].join(' | '),
      if (quality.isNotEmpty ||
          bitrateLabel.isNotEmpty ||
          codec.isNotEmpty ||
          source.isNotEmpty)
        [
          if (quality.isNotEmpty) quality,
          if (bitrateLabel.isNotEmpty) bitrateLabel,
          if (codec.isNotEmpty) codec,
          if (source.isNotEmpty) source,
        ].join(' | '),
      if (descriptionText.isNotEmpty) descriptionText,
      if (liked || song.isDownloaded)
        [
          if (liked) 'Saved in likes',
          if (song.isDownloaded) 'Available offline',
        ].join(' | '),
      if (details.isNotEmpty) details.join(' | '),
    ].join('\n\n');

    return _ExpandableSongDescriptionCard(
      publishedLabel: uploadDate.isNotEmpty
          ? uploadDate
          : album.isNotEmpty
          ? 'Album $album'
          : song.duration == null
          ? 'Track details'
          : 'Duration ${song.duration}',
      headline: title.ifBlank(artist.ifBlank('FoxyMusic')),
      description: description,
      details: details,
    );
  }
}

String _friendlyCodecLabel(String codec, String mime) {
  final raw = [
    codec,
    mime,
  ].where((v) => v.trim().isNotEmpty).join(' ').toLowerCase();
  if (raw.contains('flac')) return 'FLAC';
  if (raw.contains('opus')) return 'OPUS';
  if (raw.contains('aac') ||
      raw.contains('mp4a') ||
      raw.contains('audio/mp4')) {
    return 'AAC';
  }
  if (raw.contains('vorbis')) return 'Vorbis';
  if (raw.contains('mp3') || raw.contains('mpeg')) return 'MP3';
  if (codec.trim().isNotEmpty) return codec.trim().toUpperCase();
  if (mime.trim().isNotEmpty) return mime.trim();
  return '';
}

String _formatBitrateLabel(int? bitrate) {
  if (bitrate == null || bitrate <= 0) return '';
  final kbps = bitrate >= 1000 ? (bitrate / 1000).round() : bitrate;
  return '$kbps kbps';
}

class _ExpandableSongDescriptionCard extends StatelessWidget {
  const _ExpandableSongDescriptionCard({
    required this.publishedLabel,
    required this.headline,
    required this.description,
    required this.details,
  });

  final String publishedLabel;
  final String headline;
  final String description;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: _FoxyGlassTint(
        borderRadius: 16,
        tintOpacity: 0.34,
        borderOpacity: 0.08,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                publishedLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                headline,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.96),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in details.take(4))
                      Text(
                        item,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text(
                description,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 14,
                  height: 1.46,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerTitleActionRow extends StatelessWidget {
  const _PlayerTitleActionRow({
    required this.song,
    required this.onShare,
    required this.onPlaylist,
    this.onDownload,
  });

  final _Song song;
  final VoidCallback onShare;
  final VoidCallback onPlaylist;
  final Future<void> Function()? onDownload;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OneLineMarqueeText(
                song.title,
                active: true,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              _OneLineMarqueeText(
                song.artist,
                active: true,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy link',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            Icons.share_outlined,
            color: Colors.white.withValues(alpha: 0.92),
            size: 22,
          ),
          onPressed: onShare,
        ),
        IconButton(
          tooltip: song.isDownloaded ? 'Downloaded' : 'Download',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            song.isDownloaded
                ? Icons.download_done_rounded
                : Icons.download_outlined,
            color: song.isDownloaded
                ? const Color(0xFF81C784)
                : Colors.white.withValues(alpha: 0.92),
            size: 22,
          ),
          onPressed: song.isDownloaded || onDownload == null
              ? null
              : () => unawaited(onDownload!()),
        ),
        IconButton(
          tooltip: 'Add to playlist',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          icon: Icon(
            Icons.playlist_add_rounded,
            color: Colors.white.withValues(alpha: 0.92),
            size: 24,
          ),
          onPressed: onPlaylist,
        ),
      ],
    );
  }
}

class _LyricsFullscreenTrackHeader extends StatelessWidget {
  const _LyricsFullscreenTrackHeader({
    required this.song,
    required this.liked,
    required this.onLike,
    required this.onMenu,
  });

  final _Song song;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _Artwork(
            url: song.highQualityArtwork,
            size: 48,
            radius: 9,
            highQuality: true,
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: liked ? 'Unlike' : 'Like',
            onPressed: onLike,
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: 28,
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: onMenu,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PlayerArtwork extends StatelessWidget {
  const _PlayerArtwork({
    required this.url,
    required this.playing,
    required this.tag,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.maxSide,
    this.liked = false,
    this.hideArtwork = false,
    this.artworkDisplayStyle = 0,
    this.thumbnailCornerRadius = 16,
    this.onLike,
  });

  final String url;
  final bool playing;
  final String tag;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;
  final bool liked;
  final bool hideArtwork;
  final int artworkDisplayStyle;
  final double thumbnailCornerRadius;
  final VoidCallback? onLike;

  /// Caps artwork so transport rows never collide on narrow devices.
  final double? maxSide;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final base = math.min(w - 18, h * 0.45).clamp(300.0, 760.0);
    final side = maxSide ?? base;
    final style = artworkDisplayStyle.clamp(0, 2);
    final artWidth = style == 2
        ? side * 0.72
        : (style == 1 ? side * 0.9 : side);
    final artHeight = style == 2 ? side : artWidth;
    final radiusFactor = (thumbnailCornerRadius.clamp(0.0, 40.0) / 40.0);
    final maxRadiusBase = math.min(artWidth, artHeight) / 2;
    final radius = maxRadiusBase * radiusFactor;
    final identity = tag.startsWith('art-') ? tag.substring(4) : tag;

    if (hideArtwork) {
      return SizedBox(
        width: side,
        height: 72,
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            size: 44,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    return SizedBox(
      width: side,
      height: math.max(artHeight, 72),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: SizedBox(
              width: artWidth,
              height: artHeight,
              child: _Artwork(
                url: url,
                size: math.max(artWidth, artHeight),
                radius: 0,
                highQuality: true,
                identityTag: identity,
                offlineArtworkPath: offlineArtworkPath,
                useOfflineArtwork: useOfflineArtwork,
                fit: BoxFit.cover,
              ),
            ),
          ),
          if (onLike != null)
            Positioned(
              right: 10,
              bottom: 10,
              child: _FoxyGlassButton(
                onTap: onLike,
                borderRadius: BorderRadius.circular(999),
                tintOpacity: 0.28,
                blurSigma: 12,
                blur: true,
                padding: const EdgeInsets.all(10),
                child: Icon(
                  liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: liked
                      ? const Color(0xFFFF8A80)
                      : Colors.white.withValues(alpha: 0.92),
                  size: 22,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwipePlayerPageDeck extends StatelessWidget {
  const _SwipePlayerPageDeck({
    required this.current,
    required this.currentArtworkUrl,
    required this.playing,
    required this.dragDx,
    required this.pageWidth,
    required this.maxSide,
    required this.liked,
    required this.hideArtwork,
    required this.artworkDisplayStyle,
    required this.thumbnailCornerRadius,
    required this.onLike,
    required this.onShare,
    required this.onPlaylist,
    this.onDownload,
    this.previous,
    this.next,
  });

  final _Song current;
  final String currentArtworkUrl;
  final _Song? previous;
  final _Song? next;
  final bool playing;
  final double dragDx;
  final double pageWidth;
  final double maxSide;
  final bool liked;
  final bool hideArtwork;
  final int artworkDisplayStyle;
  final double thumbnailCornerRadius;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onPlaylist;
  final Future<void> Function()? onDownload;

  Widget _previewTitle(_Song song, double opacity) {
    return Opacity(
      opacity: opacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _OneLineMarqueeText(
              song.title,
              active: opacity > 0.98,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                height: 1.04,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            _OneLineMarqueeText(
              song.artist,
              active: opacity > 0.98,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _page({
    required _Song song,
    required bool primary,
    required double opacity,
  }) {
    final artworkUrl = primary ? currentArtworkUrl : song.highQualityArtwork;
    return SizedBox(
      width: pageWidth,
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: primary ? 1.0 : 0.965,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: _PlayerArtwork(
                  url: artworkUrl,
                  playing: primary && playing,
                  tag: 'art-${song.videoId}',
                  offlineArtworkPath: song.offlineArtworkPath,
                  useOfflineArtwork:
                      song.isDownloaded &&
                      artworkUrl == song.highQualityArtwork,
                  maxSide: maxSide,
                  liked: primary ? liked : false,
                  hideArtwork: primary && hideArtwork,
                  artworkDisplayStyle: artworkDisplayStyle,
                  thumbnailCornerRadius: thumbnailCornerRadius,
                  onLike: primary ? onLike : null,
                ),
              ),
              const SizedBox(height: 14),
              if (primary)
                _PlayerTitleActionRow(
                  song: song,
                  onShare: onShare,
                  onDownload: onDownload,
                  onPlaylist: onPlaylist,
                )
              else
                _previewTitle(song, opacity),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = pageWidth <= 0 ? MediaQuery.sizeOf(context).width : pageWidth;
    final progress = (dragDx.abs() / width).clamp(0.0, 1.0);
    final previewOpacity = (0.38 + progress * 0.62).clamp(0.0, 1.0);
    return SizedBox(
      width: width,
      child: ClipRect(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            if (previous != null)
              Transform.translate(
                offset: Offset(dragDx - width, 0),
                child: _page(
                  song: previous!,
                  primary: false,
                  opacity: previewOpacity,
                ),
              ),
            if (next != null)
              Transform.translate(
                offset: Offset(dragDx + width, 0),
                child: _page(
                  song: next!,
                  primary: false,
                  opacity: previewOpacity,
                ),
              ),
            Transform.translate(
              offset: Offset(dragDx, 0),
              child: _page(song: current, primary: true, opacity: 1),
            ),
          ],
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
    this.useOfflineArtwork = false,
    this.highQuality = false,
    this.fit = BoxFit.cover,
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
  final BoxFit fit;

  static final Map<String, File> _existingFileCache = <String, File>{};

  static File? _existingFile(String path) {
    final cached = _existingFileCache[path];
    if (cached != null) return cached;
    final f = File(path);
    if (!f.existsSync()) return null;
    _existingFileCache[path] = f;
    return f;
  }

  @override
  Widget build(BuildContext context) {
    File? offlineFile() {
      if (!useOfflineArtwork || kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      return _existingFile(p);
    }

    File? localPathFile() {
      if (kIsWeb) return null;
      final u = url.trim();
      if (u.isEmpty) return null;
      if (u.startsWith('http://') || u.startsWith('https://')) return null;
      final path = u.startsWith('file://') ? u.substring(7) : u;
      return _existingFile(path);
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

    final cacheMax = highQuality ? 1200 : 320;
    if (of != null) {
      final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(64, cacheMax);
      return RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.file(
            of,
            key: ValueKey<String>(cacheKey),
            width: size,
            height: size,
            fit: fit,
            gaplessPlayback: false,
            filterQuality: highQuality ? FilterQuality.high : FilterQuality.low,
            cacheWidth: cachePx,
            errorBuilder: (context, error, stackTrace) => placeholder,
          ),
        ),
      );
    }

    if (url.isBlank) {
      return placeholder;
    }

    final cachePx = (size * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(64, cacheMax);

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          key: ValueKey<String>(cacheKey),
          width: size,
          height: size,
          fit: fit,
          gaplessPlayback: false,
          filterQuality: highQuality ? FilterQuality.high : FilterQuality.low,
          cacheWidth: cachePx,
          loadingBuilder: (context, child, loadingProgress) =>
              loadingProgress == null ? child : placeholder,
          errorBuilder: (context, error, stackTrace) => placeholder,
        ),
      ),
    );
  }
}

class _NowPlayingBackdrop extends StatelessWidget {
  const _NowPlayingBackdrop({
    required this.song,
    required this.artworkUrl,
    required this.backgroundStyle,
    required this.playing,
    required this.lightweight,
  });

  final _Song song;
  final String artworkUrl;
  final int backgroundStyle;
  final bool playing;
  final bool lightweight;

  @override
  Widget build(BuildContext context) {
    final style = _normalizePlayerBackgroundStyle(backgroundStyle);
    if (style == 2) {
      return const ColoredBox(color: Colors.black);
    }
    if (lightweight) {
      return _NonBlurredArtworkBackdrop(
        url: artworkUrl,
        offlineArtworkPath: song.offlineArtworkPath,
        useOfflineArtwork:
            song.isDownloaded && artworkUrl == song.highQualityArtwork,
      );
    }
    if (style == 3) {
      return _VideoClipBackdrop(song: song, playing: playing);
    }
    if (style == 1) {
      return _NonBlurredArtworkBackdrop(
        url: artworkUrl,
        offlineArtworkPath: song.offlineArtworkPath,
        useOfflineArtwork:
            song.isDownloaded && artworkUrl == song.highQualityArtwork,
      );
    }
    return _BlurBackdrop(
      url: artworkUrl,
      blurEnabled: true,
      offlineArtworkPath: song.offlineArtworkPath,
      useOfflineArtwork:
          song.isDownloaded && artworkUrl == song.highQualityArtwork,
      fullBleed: true,
    );
  }
}

class _VideoClipBackdrop extends StatefulWidget {
  const _VideoClipBackdrop({required this.song, required this.playing});

  final _Song song;
  final bool playing;

  @override
  State<_VideoClipBackdrop> createState() => _VideoClipBackdropState();
}

class _VideoClipBackdropState extends State<_VideoClipBackdrop> {
  VideoPlayerController? _controller;
  bool _failed = false;
  int _serial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant _VideoClipBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.videoId != widget.song.videoId ||
        oldWidget.song.title != widget.song.title ||
        oldWidget.song.artist != widget.song.artist) {
      unawaited(_load());
      return;
    }
    _syncPlayback();
  }

  @override
  void dispose() {
    _serial++;
    final old = _controller;
    _controller = null;
    unawaited(old?.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    final song = widget.song;
    final videoId = song.videoId.trim();
    final serial = ++_serial;
    final old = _controller;
    _controller = null;
    _failed = false;
    if (mounted) setState(() {});
    unawaited(old?.dispose());
    if (videoId.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final raw = await _method.invokeMethod('getVideoClipStream', {
        'videoId': videoId,
        'title': song.title,
        'artist': song.artist,
      });
      if (!mounted || serial != _serial) return;
      final map = _asMap(raw) ?? const {};
      final url = map['url']?.toString().trim() ?? '';
      if (url.isEmpty) {
        setState(() => _failed = true);
        return;
      }
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.initialize();
      if (!mounted || serial != _serial) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _failed = false;
      _syncPlayback();
      setState(() {});
    } catch (_) {
      if (mounted && serial == _serial) {
        setState(() => _failed = true);
      }
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.playing) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed || controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.18),
                Colors.black.withValues(alpha: 0.34),
                Colors.black.withValues(alpha: 0.82),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NonBlurredArtworkBackdrop extends StatelessWidget {
  const _NonBlurredArtworkBackdrop({
    required this.url,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
  });

  final String url;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  File? _offlineFile() {
    if (!useOfflineArtwork || kIsWeb) return null;
    final p = offlineArtworkPath?.trim();
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  @override
  Widget build(BuildContext context) {
    final of = _offlineFile();
    final deviceWidth =
        MediaQuery.sizeOf(context).width *
        MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = deviceWidth.isFinite
        ? deviceWidth.round().clamp(960, 2200)
        : 1600;
    final image = of != null
        ? Image.file(
            of,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF050505)),
          )
        : url.isBlank
        ? const ColoredBox(color: Color(0xFF050505))
        : Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF050505)),
          );
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: image),
        ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
      ],
    );
  }
}

class _BlurBackdrop extends StatelessWidget {
  const _BlurBackdrop({
    required this.url,
    required this.blurEnabled,
    this.offlineArtworkPath,
    this.useOfflineArtwork = false,
    this.fullBleed = false,
  });

  final String url;
  final bool blurEnabled;
  final String? offlineArtworkPath;
  final bool useOfflineArtwork;

  /// Full-screen blurred artwork only (now playing card).
  final bool fullBleed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    File? offlineFile() {
      if (!useOfflineArtwork || kIsWeb) return null;
      final p = offlineArtworkPath?.trim();
      if (p == null || p.isEmpty) return null;
      final f = File(p);
      if (f.existsSync()) return f;
      return null;
    }

    final of = offlineFile();
    final brandUnderlay = fullBleed
        ? const ColoredBox(color: Color(0xFF050505))
        : _FoxyBrandGradientBackdrop(
            variant: _FoxyGradientVariant.player,
            child: const SizedBox.expand(),
          );
    if (!blurEnabled || (url.isBlank && of == null)) {
      return Stack(
        fit: StackFit.expand,
        children: [
          brandUnderlay,
          if (!fullBleed)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.1, -0.35),
                  radius: 1.45,
                  colors: [
                    accent.withValues(alpha: 0.22),
                    _FoxyBrandPalette.foxDeep.withValues(alpha: 0.14),
                    const Color(0xFF080808).withValues(alpha: 0.96),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    final imageChild = of != null
        ? Image.file(
            of,
            key: ValueKey<String>('bd|${of.path}'),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => url.isBlank
                ? const ColoredBox(color: Color(0xFF080808))
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    alignment: Alignment.center,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: Color(0xFF080808)),
                  ),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            alignment: Alignment.center,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF080808)),
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: Transform.scale(
            scale: fullBleed ? 1.35 : 1.18,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: fullBleed ? 42 : 36,
                sigmaY: fullBleed ? 42 : 36,
              ),
              child: SizedBox.expand(child: imageChild),
            ),
          ),
        ),
      ],
    );
  }
}
