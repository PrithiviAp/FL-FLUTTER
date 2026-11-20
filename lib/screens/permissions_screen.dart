import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'home_screen.dart';

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});
  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _requesting = false;

  Future<void> _requestAll() async {
    setState(() => _requesting = true);

    // 1) Foreground + background location
    await Geolocator.requestPermission();
    await Permission.locationAlways.request();

    // 2) Notifications (Android 13+)
    await Permission.notification.request();

    // 3) Call logs + SMS (restricted group on Android 10+)
    await Permission.sms.request();
    await Permission.phone.request();
    await Permission.microphone.request();
    await Permission.phone.request(); // READ_PHONE_STATE already covered, but explicit is fine

    // 4) All files access for the file manager
    // 4) All files access for the file manager
    await Permission.manageExternalStorage.request();

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Permissions needed')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Family Locator needs the following to work. A persistent '
              'notification will always be visible while tracking is on.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 20),
            const _PermRow(
              icon: Icons.location_on,
              text: 'Location (incl. background)',
            ),
            const _PermRow(
              icon: Icons.notifications,
              text: 'Notifications',
            ),
            const _PermRow(
              icon: Icons.call,
              text: 'Call logs',
            ),
            const _PermRow(
              icon: Icons.sms,
              text: 'SMS',
            ),
            const _PermRow(
              icon: Icons.mic,
              text: 'Microphone (call recording & live audio)',
            ),
            const _PermRow(
              icon: Icons.folder,
              text: 'All files access (file manager)',
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _requesting ? null : _requestAll,
                child: _requesting
                    ? const CircularProgressIndicator()
                    : const Text('Grant permissions'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _PermRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}