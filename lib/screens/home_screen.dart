import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/audio_stream_service.dart';
import '../services/connectivity_service.dart';
import '../services/tracking_manager.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _running = false;
  bool _loading = true;
  bool? _gpsOn;
  bool? _netOn;
  bool _micStreaming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Make sure we don't leave the mic hot when the screen is gone.
    AudioStreamService.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _boot() async {
    await _refresh();

    final perm = await Geolocator.checkPermission();
    final canTrack = perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
final notifPermission = await FlutterForegroundTask.checkNotificationPermission();
if (notifPermission != NotificationPermission.granted) {
  final result = await FlutterForegroundTask.requestNotificationPermission();
  if (result != NotificationPermission.granted) {
    // Optionally show a message, but don't block tracking entirely
    debugPrint('Notification permission denied — foreground service may not show properly');
  }
}
    if (!canTrack) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission missing — open Settings to grant.'),
          ),
        );
      }
      return;
    }

    if (!_running) {
      await TrackingManager.start(); // no withMicrophone — safe at launch
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final running = await TrackingManager.isRunning();
    final status = await ConnectivityService.check();
    if (!mounted) return;
    setState(() {
      _running = running;
      _gpsOn = status.gpsEnabled;
      _netOn = status.internetConnected;
      _loading = false;
    });
  }

  Future<void> _toggleMic(bool value) async {
    if (value) {
      // Stop the current service (if running) and restart with mic type.
      await TrackingManager.stop();
      final started = await TrackingManager.start(withMicrophone: true);
      if (!started) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not start microphone service. Check RECORD_AUDIO permission.'),
            ),
          );
        }
        return;
      }
      final ok = await AudioStreamService.start();
      if (!mounted) return;
      setState(() => _micStreaming = ok);
      if (!ok) {
        // Roll back the service to non-mic mode
        await TrackingManager.stop();
        await TrackingManager.start();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start mic — permission denied.')),
        );
      }
    } else {
      await AudioStreamService.stop();
      await TrackingManager.stop();
      await TrackingManager.start(); // restart without mic
      if (!mounted) return;
      setState(() => _micStreaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Locator'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _running ? Icons.gps_fixed : Icons.gps_off,
                    size: 72,
                    color: _running ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _running ? 'Tracking is ON' : 'Tracking is OFF',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A persistent notification is shown whenever tracking is active.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  _StatusChip(label: 'GPS', ok: _gpsOn),
                  const SizedBox(height: 8),
                  _StatusChip(label: 'Internet', ok: _netOn),
                  const SizedBox(height: 32),

                  // ---- Live microphone toggle ----
                  Card(
                    child: SwitchListTile(
                      title: const Text('Live Microphone'),
                      subtitle: const Text(
                        'Stream this phone\'s microphone to your dashboard '
                        'while tracking is active.',
                      ),
                      secondary: Icon(
                        _micStreaming ? Icons.mic : Icons.mic_off,
                        color: _micStreaming ? Colors.red : Colors.grey,
                      ),
                      value: _micStreaming,
                      onChanged: _toggleMic,
                    ),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _running ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (_running) {
                          await TrackingManager.stop();
                        } else {
                          await TrackingManager.start();
                        }
                        await _refresh();
                      },
                      child: Text(
                        _running ? 'Pause tracking' : 'Start tracking',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool? ok;
  const _StatusChip({required this.label, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok == null ? Colors.grey : (ok! ? Colors.green : Colors.red);
    final text = ok == null ? '$label: unknown' : '$label: ${ok! ? "ON" : "OFF"}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}
