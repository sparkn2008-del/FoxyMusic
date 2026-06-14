part of 'main.dart';

class _NowPlayingFooter extends StatelessWidget {
  const _NowPlayingFooter({
    required this.song,
    required this.streamLabel,
    required this.timeline,
    required this.effectiveDurMs,
    required this.progress,
    required this.position,
    required this.endTimeLabel,
    required this.playerProgressStyle,
    required this.playerButtonsStyle,
    required this.playerBackgroundStyle,
    required this.style2,
    required this.volume,
    required this.songIsLiked,
    required this.padBottom,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onToggleLike,
    required this.onSeek,
    required this.onVolumeChanged,
    required this.onShowTrackInfo,
    required this.onOpenLyrics,
    required this.onOpenQueue,
    required this.onShowSleepTimer,
    required this.onOpenEqualizer,
    required this.onPrevious,
    required this.onNext,
    required this.onTogglePlayPause,
  });

  final _Song song;
  final String streamLabel;
  final _PlayerTimelineState timeline;
  final int effectiveDurMs;
  final double progress;
  final double position;
  final String endTimeLabel;
  final int playerProgressStyle;
  final int playerButtonsStyle;
  final int playerBackgroundStyle;
  final bool style2;
  final double volume;
  final bool songIsLiked;
  final double padBottom;
  final VoidCallback onAddToPlaylist;
  final VoidCallback? onDownload;
  final VoidCallback onToggleLike;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onShowTrackInfo;
  final VoidCallback onOpenLyrics;
  final VoidCallback onOpenQueue;
  final VoidCallback onShowSleepTimer;
  final VoidCallback onOpenEqualizer;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTogglePlayPause;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, 0, 2, padBottom + 2.2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RepaintBoundary(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _OverflowMarqueeText(
                        text: song.title,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -0.4,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 1.8),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.62),
                        ),
                      ),
                      if (streamLabel.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          streamLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.48),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _NpIconAction(
                        tooltip: 'Playlist',
                        icon: Icons.playlist_add_rounded,
                        iconColor: Colors.white.withValues(alpha: 0.92),
                        style: playerButtonsStyle,
                        onPressed: onAddToPlaylist,
                      ),
                      const SizedBox(width: 6),
                      _NpIconAction(
                        tooltip: song.isDownloaded ? 'Downloaded' : 'Download',
                        icon: song.isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_outlined,
                        iconColor: song.isDownloaded
                            ? const Color(0xFF81C784)
                            : Colors.white.withValues(alpha: 0.92),
                        style: playerButtonsStyle,
                        onPressed: onDownload,
                      ),
                      const SizedBox(width: 6),
                      _NpIconAction(
                        tooltip: songIsLiked ? 'Unlike' : 'Like',
                        icon: songIsLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: songIsLiked
                            ? const Color(0xFFE57373)
                            : Colors.white.withValues(alpha: 0.92),
                        style: playerButtonsStyle,
                        onPressed: onToggleLike,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          if (timeline.isBuffering)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Colors.grey.shade800.withValues(alpha: 0.9),
                  color: Colors.grey.shade500,
                ),
              ),
            ),
          RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FoxySeekBar(
                  progress: progress,
                  enabled: effectiveDurMs > 750,
                  playing: timeline.isPlaying,
                  style: playerProgressStyle,
                  motion: 0,
                  onSeek: onSeek,
                ),
                const SizedBox(height: 1),
                Row(
                  children: [
                    Text(
                      _fmt(position.round()),
                      style: const TextStyle(
                        color: _kFoxyNpTime,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      endTimeLabel,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _kFoxyNpTime,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          RepaintBoundary(
            child: _SimpMusicPlayerControlLayout(
              shuffle: timeline.shuffleEnabled,
              repeatMode: timeline.repeatMode,
              playing: timeline.isPlaying,
              buffering: timeline.isBuffering,
              prevEnabled: timeline.canPlayPrevious,
              nextEnabled: timeline.canPlayNext,
              buttonStyle: playerButtonsStyle,
              onPrevious: onPrevious,
              onNext: onNext,
              onTogglePlayPause: onTogglePlayPause,
            ),
          ),
          if (style2)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: _NowPlayingVolumeStrip(
                volume: volume,
                onChanged: onVolumeChanged,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 9, bottom: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PlayerBottomToolButton(
                    tooltip: 'Track info',
                    icon: Icons.info_outline_rounded,
                    onPressed: onShowTrackInfo,
                  ),
                  const SizedBox(width: 8),
                  _PlayerBottomToolButton(
                    tooltip: 'Lyrics',
                    icon: Icons.lyrics_outlined,
                    whiteGlow: true,
                    onPressed: onOpenLyrics,
                  ),
                  const SizedBox(width: 16),
                  _PlayerBottomToolButton(
                    tooltip: 'Queue',
                    icon: Icons.queue_music_rounded,
                    onPressed: onOpenQueue,
                  ),
                  const SizedBox(width: 8),
                  _PlayerBottomToolButton(
                    tooltip: 'Sleep timer',
                    icon: Icons.bedtime_outlined,
                    onPressed: onShowSleepTimer,
                  ),
                  const SizedBox(width: 8),
                  _PlayerBottomToolButton(
                    tooltip: 'Equalizer',
                    icon: Icons.graphic_eq_rounded,
                    onPressed: onOpenEqualizer,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _NowPlayingVolumeStrip extends StatefulWidget {
  const _NowPlayingVolumeStrip({required this.volume, required this.onChanged});

  final double volume;
  final ValueChanged<double> onChanged;

  @override
  State<_NowPlayingVolumeStrip> createState() => _NowPlayingVolumeStripState();
}

class _NowPlayingVolumeStripState extends State<_NowPlayingVolumeStrip> {
  double? _preview;

  double get _shownVolume => (_preview ?? widget.volume).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant _NowPlayingVolumeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preview != null && (_shownVolume - widget.volume).abs() < 0.005) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _preview = null);
      });
    }
  }

  void _setPreview(double value) {
    setState(() => _preview = value.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final shownVolume = _shownVolume;
    return _FoxyGlassTint(
      borderRadius: 16,
      tintOpacity: 0.18,
      borderOpacity: 0.18,
      blur: true,
      blurSigma: 12,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
            minThumbSeparation: 0,
          ),
          child: Row(
            children: [
              IconButton(
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: shownVolume <= 0.0
                    ? null
                    : () {
                        final next = (shownVolume - 0.05).clamp(0.0, 1.0);
                        _setPreview(next);
                        widget.onChanged(next);
                      },
                icon: const Icon(Icons.remove_rounded, size: 18),
              ),
              Expanded(
                child: Slider(
                  value: shownVolume,
                  onChangeStart: _setPreview,
                  onChanged: (value) {
                    _setPreview(value);
                    widget.onChanged(value);
                  },
                  onChangeEnd: (_) {},
                ),
              ),
              IconButton(
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: shownVolume >= 1.0
                    ? null
                    : () {
                        final next = (shownVolume + 0.05).clamp(0.0, 1.0);
                        _setPreview(next);
                        widget.onChanged(next);
                      },
                icon: const Icon(Icons.add_rounded, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
