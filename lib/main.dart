import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dahua Cloud P2P Demo',
      theme: ThemeData(primarySwatch: Colors.deepOrange),
      home: const DahuaP2PStreamScreen(),
    );
  }
}

class DahuaP2PStreamScreen extends StatefulWidget {
  const DahuaP2PStreamScreen({Key? key}) : super(key: key);

  @override
  State<DahuaP2PStreamScreen> createState() => _DahuaP2PStreamScreenState();
}

class _DahuaP2PStreamScreenState extends State<DahuaP2PStreamScreen> {
  final String _serialNumber = 'C40K4PAYRWT15WJE';
  final String _username = 'admin';
  final String _password = 'Admin@123';

  VlcPlayerController? _vlcViewController;
  bool _isLoading = false;
  bool _isStreaming = false;

  // INITIALIZE SAFELY
  void _startCloudStream() async {
    setState(() {
      _isLoading = true;
    });

    // Correct URL syntax for Dahua Cloud streaming gateways:
    // (Note: Standard RTSP syntax requires specific port/path mapping for Easy4ip)
    final String cloudRtspUrl = 'rtsp://easy4ip.com:554/$_serialNumber?channel=1&subtype=0&user=$_username&password=$_password';

    try {
      log("cloudRtspUrl $cloudRtspUrl");
      // 1. Instantiating the controller
      final controller = VlcPlayerController.network(
        cloudRtspUrl,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );

      // 2. Attach a listener to monitor if initialization fails
      controller.addListener(() {
        if (controller.value.hasError) {
          print("VLC Native Error: ${controller.value.errorDescription}");
        }
      });

      setState(() {
        _vlcViewController = controller;
        _isStreaming = true;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to link to native VLC: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dahua P2P Live Stream')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  color: Colors.black87,
                ),
                child: _isStreaming && _vlcViewController != null
                    ? VlcPlayer(
                  controller: _vlcViewController!,
                  aspectRatio: 16 / 9,
                  placeholder: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
                    : Center(
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                    'Press button to establish P2P Cloud Connection',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Text('Target SN: $_serialNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Text('Routing via: Dahua Easy4IP Cloud Gateway', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: (_isStreaming || _isLoading) ? null : _startCloudStream,
              icon: const Icon(Icons.cloud_queue),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14.0),
                child: Text('Connect via P2P Cloud ID', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Completely terminate native process to prevent leaks/channel breaks
    _vlcViewController?.stopRendererScanning();
    _vlcViewController?.dispose();
    super.dispose();
  }
}