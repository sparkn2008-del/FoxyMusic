part of 'main.dart';

@immutable
class _PlayerTimelineState {
  const _PlayerTimelineState({
    required this.positionMs,
    required this.durationMs,
    required this.isPlaying,
    required this.isBuffering,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.canPlayPrevious,
    required this.canPlayNext,
    required this.volume,
  });

  final int positionMs;
  final int durationMs;
  final bool isPlaying;
  final bool isBuffering;
  final bool shuffleEnabled;
  final String repeatMode;
  final bool canPlayPrevious;
  final bool canPlayNext;
  final double volume;

  factory _PlayerTimelineState.fromPlayer(Map<String, dynamic> player) =>
      _PlayerTimelineState(
        positionMs: ((player['positionMs'] ?? 0) as num).toInt(),
        durationMs: ((player['durationMs'] ?? 0) as num).toInt(),
        isPlaying: player['isPlaying'] == true,
        isBuffering:
            player['isBuffering'] == true && player['isPlaying'] != true,
        shuffleEnabled: player['shuffleEnabled'] == true,
        repeatMode: (player['repeatMode'] ?? 'Off').toString(),
        canPlayPrevious: player['canPlayPrevious'] == true,
        canPlayNext: player['canPlayNext'] == true,
        volume: (((player['volume'] ?? 1.0) as num).toDouble()).clamp(0.0, 1.0),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PlayerTimelineState &&
          runtimeType == other.runtimeType &&
          positionMs == other.positionMs &&
          durationMs == other.durationMs &&
          isPlaying == other.isPlaying &&
          isBuffering == other.isBuffering &&
          shuffleEnabled == other.shuffleEnabled &&
          repeatMode == other.repeatMode &&
          canPlayPrevious == other.canPlayPrevious &&
          canPlayNext == other.canPlayNext &&
          volume == other.volume;

  @override
  int get hashCode => Object.hash(
    positionMs,
    durationMs,
    isPlaying,
    isBuffering,
    shuffleEnabled,
    repeatMode,
    canPlayPrevious,
    canPlayNext,
    volume,
  );
}

@immutable
class _PlayerQueueState {
  const _PlayerQueueState({required this.queue, required this.queueIndex});

  final List<_Song> queue;
  final int queueIndex;

  factory _PlayerQueueState.fromPlayer(Map<String, dynamic> player) =>
      _PlayerQueueState(
        queue: (player['queue'] as List? ?? const [])
            .map((item) => _Song.fromMap(_asMap(item) ?? const {}))
            .where((song) => song.videoId.isNotEmpty)
            .toList(growable: false),
        queueIndex: ((player['queueIndex'] ?? -1) as num).toInt(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _PlayerQueueState &&
          runtimeType == other.runtimeType &&
          queueIndex == other.queueIndex &&
          _queueIds(queue) == _queueIds(other.queue);

  @override
  int get hashCode => Object.hash(queueIndex, _queueIds(queue));

  static String _queueIds(List<_Song> queue) =>
      queue.map((song) => song.videoId).join('|');
}

class _PlayerStateController extends ChangeNotifier {
  Map<String, dynamic> _player = const {};
  final ValueNotifier<String> currentVideoIdListenable = ValueNotifier<String>(
    '',
  );
  final ValueNotifier<Map<String, dynamic>> visualListenable =
      ValueNotifier<Map<String, dynamic>>(const {});
  final ValueNotifier<_PlayerTimelineState> timelineListenable =
      ValueNotifier<_PlayerTimelineState>(
        const _PlayerTimelineState(
          positionMs: 0,
          durationMs: 0,
          isPlaying: false,
          isBuffering: false,
          shuffleEnabled: false,
          repeatMode: 'Off',
          canPlayPrevious: false,
          canPlayNext: false,
          volume: 1.0,
        ),
      );
  final ValueNotifier<_PlayerQueueState> queueListenable =
      ValueNotifier<_PlayerQueueState>(
        const _PlayerQueueState(queue: <_Song>[], queueIndex: -1),
      );
  Timer? _timelineTicker;
  int _lastTimelineTickAtMs = 0;

  Map<String, dynamic> get value => _player;

  String get currentVideoId =>
      _asMap(_player['currentSong'])?['videoId']?.toString() ?? '';

  bool get hasSong {
    final song = _Song.fromMap(_asMap(_player['currentSong']) ?? const {});
    return song.videoId.isNotEmpty && song.title.isNotEmpty;
  }

  Future<void> loadFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('getPlayerState'));
      if (map != null) applyExternal(map);
    } catch (_) {}
  }

  Future<void> resync() => loadFromNative();

  void patchTimeline({
    int? positionMs,
    int? durationMs,
    bool? isPlaying,
    bool? isBuffering,
    double? volume,
  }) {
    if (_player.isEmpty) return;
    final next = Map<String, dynamic>.from(_player);
    if (positionMs != null) next['positionMs'] = positionMs;
    if (durationMs != null) next['durationMs'] = durationMs;
    if (isPlaying != null) next['isPlaying'] = isPlaying;
    if (isBuffering != null) next['isBuffering'] = isBuffering;
    if (volume != null) next['volume'] = volume.clamp(0.0, 1.0);
    setOptimistic(next);
  }

  void applyExternal(Map<String, dynamic> state) {
    final next = _mergePlayerState(_player, state);
    if (!_playerSnapshotChanged(_player, next)) return;
    _player = _detachPlayerState(next);
    _syncSlices();
    final nextVideoId = currentVideoId;
    if (currentVideoIdListenable.value != nextVideoId) {
      currentVideoIdListenable.value = nextVideoId;
    }
    notifyListeners();
  }

  void setOptimistic(Map<String, dynamic> player) {
    final next = _detachPlayerState(player);
    if (!_playerSnapshotChanged(_player, next)) return;
    _player = next;
    _syncSlices();
    final nextVideoId = currentVideoId;
    if (currentVideoIdListenable.value != nextVideoId) {
      currentVideoIdListenable.value = nextVideoId;
    }
    notifyListeners();
  }

  void _syncSlices() {
    final currentVisual = visualListenable.value;
    if (_playerVisualSignature(currentVisual) !=
        _playerVisualSignature(_player)) {
      visualListenable.value = _detachPlayerState(_player);
    }
    final nextTimeline = _PlayerTimelineState.fromPlayer(_player);
    _lastTimelineTickAtMs = DateTime.now().millisecondsSinceEpoch;
    if (timelineListenable.value != nextTimeline) {
      timelineListenable.value = nextTimeline;
    }
    _syncTimelineTicker(nextTimeline);
    final nextQueue = _PlayerQueueState.fromPlayer(_player);
    if (queueListenable.value != nextQueue) {
      queueListenable.value = nextQueue;
    }
  }

  void _syncTimelineTicker(_PlayerTimelineState timeline) {
    final shouldRun =
        timeline.isPlaying && !timeline.isBuffering && timeline.durationMs > 0;
    if (!shouldRun) {
      _timelineTicker?.cancel();
      _timelineTicker = null;
      return;
    }
    _timelineTicker ??= Timer.periodic(const Duration(milliseconds: 220), (_) {
      final current = timelineListenable.value;
      if (!current.isPlaying ||
          current.isBuffering ||
          current.durationMs <= 0) {
        _timelineTicker?.cancel();
        _timelineTicker = null;
        return;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final elapsedMs = (nowMs - _lastTimelineTickAtMs).clamp(0, 1200);
      _lastTimelineTickAtMs = nowMs;
      final nextPosition = math.min(
        current.durationMs,
        current.positionMs + elapsedMs,
      );
      final next = _PlayerTimelineState(
        positionMs: nextPosition,
        durationMs: current.durationMs,
        isPlaying: current.isPlaying,
        isBuffering: false,
        shuffleEnabled: current.shuffleEnabled,
        repeatMode: current.repeatMode,
        canPlayPrevious: current.canPlayPrevious,
        canPlayNext: current.canPlayNext,
        volume: current.volume,
      );
      if (timelineListenable.value != next) {
        timelineListenable.value = next;
      }
    });
  }

  @override
  void dispose() {
    _timelineTicker?.cancel();
    currentVideoIdListenable.dispose();
    visualListenable.dispose();
    timelineListenable.dispose();
    queueListenable.dispose();
    super.dispose();
  }
}

class _AccountStateController extends ValueNotifier<Map<String, dynamic>> {
  _AccountStateController() : super(const {});

  Future<void> loadFromNative() async {
    try {
      final map = _asMap(await _method.invokeMethod('accountInfo'));
      if (map == null || mapEquals(value, map)) return;
      value = map;
    } catch (_) {}
  }
}

class _SearchController extends ChangeNotifier {
  _SearchUiState _state = const _SearchUiState();
  final ValueNotifier<_SearchUiState> stateListenable =
      ValueNotifier<_SearchUiState>(const _SearchUiState());
  Timer? _debounce;

  _SearchUiState get state => _state;

  void disposeController() {
    _debounce?.cancel();
  }

  void _emit(_SearchUiState next) {
    if (_state == next) return;
    _state = next;
    if (stateListenable.value != next) {
      stateListenable.value = next;
    }
    notifyListeners();
  }

  void applyExternalQuery(String raw, {required VoidCallback syncText}) {
    final q = raw.trim();
    _emit(_state.copyWith(query: q, error: null));
    syncText();
    if (q.length >= 2) {
      unawaited(runSearch(q));
    }
  }

  bool consumeBack() {
    if (_state.query.trim().isEmpty &&
        _state.error == null &&
        !_state.hasResults) {
      return false;
    }
    _emit(const _SearchUiState());
    return true;
  }

  void updateQuery(String value) {
    _emit(_state.copyWith(query: value, error: null));
    _debounce?.cancel();
    final q = value.trim();
    if (q.length < 2) {
      _emit(
        _state.copyWith(
          loading: false,
          error: null,
          payload: const _SearchPayload(
            songs: [],
            videos: [],
            albums: [],
            artists: [],
          ),
        ),
      );
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 280), () {
      unawaited(runSearch(q));
    });
  }

  void setFilter(String label) {
    if (_state.filter == label) return;
    _emit(_state.copyWith(filter: label));
  }

  Future<void> submitSearch(String value) async {
    final query = value.trim();
    if (query.length < 2) return;
    _debounce?.cancel();
    await runSearch(query);
  }

  Future<void> runSearch(String query) async {
    final cached = _SearchCache.get(query, _SearchTabState._searchLimit);
    if (cached != null) {
      if (_state.query.trim() != query) return;
      _emit(_state.copyWith(loading: false, error: null, payload: cached));
      return;
    }
    _emit(_state.copyWith(loading: true, error: null));
    try {
      final response =
          _asMap(
            await _method.invokeMethod('searchAll', {
              'query': query,
              'limit': _SearchTabState._searchLimit,
            }),
          ) ??
          const {};
      if (_state.query.trim() != query) return;
      final payload = _SearchPayload.fromResponse(response);
      _SearchCache.put(query, _SearchTabState._searchLimit, payload);
      _emit(_state.copyWith(loading: false, payload: payload));
    } catch (e) {
      _emit(_state.copyWith(loading: false, error: e.toString()));
    }
  }

  @override
  void dispose() {
    stateListenable.dispose();
    super.dispose();
  }
}

bool _playerSnapshotChanged(
  Map<String, dynamic> prev,
  Map<String, dynamic> next,
) {
  if (prev['playerEpoch'] != next['playerEpoch']) return true;
  if (prev['positionMs'] != next['positionMs']) return true;
  if (prev['durationMs'] != next['durationMs']) return true;
  if (prev['isPlaying'] != next['isPlaying']) return true;
  if (prev['isBuffering'] != next['isBuffering']) return true;
  if (prev['songIsLiked'] != next['songIsLiked']) return true;
  if (prev['paletteEpoch'] != next['paletteEpoch']) return true;
  if (prev['volume'] != next['volume']) return true;
  if (prev['canPlayNext'] != next['canPlayNext']) return true;
  if (prev['canPlayPrevious'] != next['canPlayPrevious']) return true;
  if (prev['shuffleEnabled'] != next['shuffleEnabled']) return true;
  if (prev['repeatMode']?.toString() != next['repeatMode']?.toString()) {
    return true;
  }
  if (prev['queueIndex'] != next['queueIndex']) return true;
  final pQ = prev['queue'];
  final nQ = next['queue'];
  if (_queueSignature(pQ) != _queueSignature(nQ)) return true;
  final pVid = _asMap(prev['currentSong'])?['videoId']?.toString() ?? '';
  final nVid = _asMap(next['currentSong'])?['videoId']?.toString() ?? '';
  if (pVid != nVid) return true;
  final pSong = _asMap(prev['currentSong']) ?? const {};
  final nSong = _asMap(next['currentSong']) ?? const {};
  final pTitle = pSong['title']?.toString() ?? '';
  final nTitle = nSong['title']?.toString() ?? '';
  if (pTitle != nTitle) return true;
  final pArtist = pSong['artist']?.toString() ?? '';
  final nArtist = nSong['artist']?.toString() ?? '';
  if (pArtist != nArtist) return true;
  final pArt = _songArtworkKey(pSong);
  final nArt = _songArtworkKey(nSong);
  if (pArt != nArt) return true;
  if (prev['streamBitrate'] != next['streamBitrate']) return true;
  if (prev['streamCodec']?.toString() != next['streamCodec']?.toString()) {
    return true;
  }
  if (prev['streamMimeType']?.toString() !=
      next['streamMimeType']?.toString()) {
    return true;
  }
  if (prev['streamSampleRate'] != next['streamSampleRate']) return true;
  if (prev['streamItag'] != next['streamItag']) return true;
  if (prev['streamSource']?.toString() != next['streamSource']?.toString()) {
    return true;
  }
  if (prev['streamQualityLabel']?.toString() !=
      next['streamQualityLabel']?.toString()) {
    return true;
  }
  if (prev['playerBackgroundStyle'] != next['playerBackgroundStyle']) {
    return true;
  }
  if (prev['playerStyle'] != next['playerStyle']) return true;
  if (prev['playerButtonsStyle'] != next['playerButtonsStyle']) return true;
  if (prev['playerArtworkShape'] != next['playerArtworkShape']) return true;
  if (prev['lyricsPreferLrclib'] != next['lyricsPreferLrclib']) return true;
  if (prev['lyricsRomanize'] != next['lyricsRomanize']) return true;
  return false;
}
