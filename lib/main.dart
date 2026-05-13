import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _method = MethodChannel('foxy_music/methods');
const _events = EventChannel('foxy_music/events');

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
  Map<String, dynamic> _player = const {};
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = _events.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final type = event['type']?.toString();
        if (type == 'playerState' && event['state'] is Map) {
          setState(() => _player = Map<String, dynamic>.from(event['state'] as Map));
        }
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _toggle() => _method.invokeMethod('togglePlayPause');
  Future<void> _next() => _method.invokeMethod('next');

  @override
  Widget build(BuildContext context) {
    final title = (_player['currentSong']?['title'] ?? 'FoxyMusic') as String;
    final artist = (_player['currentSong']?['artist'] ?? 'Flutter bridge ready') as String;
    final isPlaying = (_player['isPlaying'] ?? false) == true;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        appBar: AppBar(title: const Text('FoxyMusic (Flutter)')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(artist, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(onPressed: _toggle, icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow)),
                    IconButton(onPressed: _next, icon: const Icon(Icons.skip_next)),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Channel contract wired: foxy_music/methods + foxy_music/events', style: TextStyle(color: Colors.white54), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

