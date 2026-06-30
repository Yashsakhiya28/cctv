import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCTV Control Center',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF0EA5E9),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          elevation: 4,
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF0EA5E9),
          secondary: Color(0xFFF97316),
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
      ),
      home: const MainCameraControlScreen(),
    );
  }
}

// Camera connection service using MethodChannel
class CameraService {
  static const MethodChannel _channel = MethodChannel('camera_sdk');

  static Future<bool> connectCamera({
    required String uid,
    required String username,
    required String password,
  }) async {
    try {
      final bool result = await _channel.invokeMethod<bool>("connectCamera", {
        "uid": uid,
        "username": username,
        "password": password,
      }) ?? false;
      return result;
    } on PlatformException catch (e) {
      throw e.message ?? "Unknown Native Error";
    }
  }
}

enum ConnectionMode { easy4ipRTSP, p2pUID }

enum P2PStatus { disconnected, connecting, connected, streaming, error }

class MainCameraControlScreen extends StatefulWidget {
  const MainCameraControlScreen({super.key});

  @override
  State<MainCameraControlScreen> createState() => _MainCameraControlScreenState();
}

class _MainCameraControlScreenState extends State<MainCameraControlScreen>
    with SingleTickerProviderStateMixin {
  ConnectionMode _connectionMode = ConnectionMode.p2pUID;

  // RTSP fields
  final String _rtspSerialNumber = 'C40K4PAYRWT15WJE';
  final String _rtspUsername = 'admin';
  final String _rtspPassword = 'Admin@123';
  VlcPlayerController? _vlcViewController;
  bool _isRtspLoading = false;
  bool _isRtspStreaming = false;

  // P2P UID fields
  final TextEditingController _uidController = TextEditingController(text: 'A1B2C3D4E5');
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController(text: '123456');
  
  P2PStatus _p2pStatus = P2PStatus.disconnected;
  String _p2pError = '';
  final List<String> _consoleLogs = [];
  final ScrollController _consoleScrollController = ScrollController();
  
  // Animation for scanner line in P2P stream simulation
  late AnimationController _scanController;
  late Timer _clockTimer;
  String _currentTimeString = '';
  bool _recBlink = true;
  bool _isRecording = false;
  double _zoomLevel = 1.0;
  String _ptzStatus = 'Idle';

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _clockTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final now = DateTime.now();
      final timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
      setState(() {
        _currentTimeString = timeStr;
        _recBlink = !_recBlink;
      });
    });

    _log("System initialized. Ready for connections.");
  }

  @override
  void dispose() {
    _scanController.dispose();
    _clockTimer.cancel();
    _vlcViewController?.stopRendererScanning();
    _vlcViewController?.dispose();
    _uidController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _consoleScrollController.dispose();
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().split('T')[1].substring(0, 8);
    setState(() {
      _consoleLogs.add("[$timestamp] $message");
    });
    // Auto scroll console to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_consoleScrollController.hasClients) {
        _consoleScrollController.animateTo(
          _consoleScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Clear console log
  void _clearLogs() {
    setState(() {
      _consoleLogs.clear();
    });
  }

  // Easy4IP RTSP connect handler
  void _startRtspStream() async {
    setState(() {
      _isRtspLoading = true;
    });

    final String cloudRtspUrl = 'rtsp://easy4ip.com:554/$_rtspSerialNumber?channel=1&subtype=0&user=$_rtspUsername&password=$_rtspPassword';
    _log("RTSP: Connecting to $cloudRtspUrl");

    try {
      final controller = VlcPlayerController.network(
        cloudRtspUrl,
        hwAcc: HwAcc.full,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );

      controller.addListener(() {
        if (controller.value.hasError) {
          _log("RTSP Error: ${controller.value.errorDescription}");
        }
      });

      setState(() {
        _vlcViewController = controller;
        _isRtspStreaming = true;
        _isRtspLoading = false;
      });
      _log("RTSP: Connected successfully.");
    } catch (e) {
      setState(() {
        _isRtspLoading = false;
      });
      _log("RTSP Error: Failed to link to native VLC: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to link to native VLC: $e")),
      );
    }
  }

  void _stopRtspStream() async {
    _log("RTSP: Closing connection...");
    await _vlcViewController?.stopRendererScanning();
    await _vlcViewController?.dispose();
    setState(() {
      _vlcViewController = null;
      _isRtspStreaming = false;
      _isRtspLoading = false;
    });
    _log("RTSP: Connection closed.");
  }

  // P2P UID connect handler
  void _connectP2PUID() async {
    final uid = _uidController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (uid.isEmpty || username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all P2P credentials.")),
      );
      return;
    }

    setState(() {
      _p2pStatus = P2PStatus.connecting;
      _p2pError = '';
    });

    _log("P2P: Initiating handshake process...");
    _log("P2P: Resolving UID '$uid' via Vendor Cloud gateway...");

    try {
      // Small simulated delay to feel realistic and allow logs to show
      await Future.delayed(const Duration(milliseconds: 800));

      _log("P2P: Invoking MethodChannel 'camera_sdk' -> connectCamera");
      final success = await CameraService.connectCamera(
        uid: uid,
        username: username,
        password: password,
      );

      if (success) {
        _log("P2P [Native]: Cloud Authentication Success.");
        setState(() {
          _p2pStatus = P2PStatus.connected;
        });

        // Simulate establishing video stream
        _log("P2P: Fetching camera configurations...");
        await Future.delayed(const Duration(milliseconds: 600));

        _log("P2P: Initializing remote video stream...");
        setState(() {
          _p2pStatus = P2PStatus.streaming;
        });
        _log("P2P: Live Stream Active (Bitrate: 2.4 Mbps, 1080p @ 30fps)");
      } else {
        throw "Authentication failed";
      }
    } catch (e) {
      _log("P2P Error: Connection failed. $e");
      setState(() {
        _p2pStatus = P2PStatus.error;
        _p2pError = e.toString();
      });
    }
  }

  void _disconnectP2P() {
    _log("P2P: Disconnecting from camera...");
    setState(() {
      _p2pStatus = P2PStatus.disconnected;
      _isRecording = false;
      _zoomLevel = 1.0;
      _ptzStatus = 'Idle';
    });
    _log("P2P: Disconnected successfully.");
  }

  // Interactive controls for simulated camera
  void _triggerPTZ(String direction) {
    setState(() {
      _ptzStatus = "Pan/Tilt: $direction";
    });
    _log("PTZ: Sent remote PTZ command '$direction' to P2P Camera");
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _ptzStatus.contains(direction)) {
        setState(() {
          _ptzStatus = 'Idle';
        });
      }
    });
  }

  void _captureImage() {
    _log("SDK: Capturing live snapshot...");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.photo_camera, color: Colors.white),
            SizedBox(width: 8),
            Text("Snapshot saved to gallery"),
          ],
        ),
        backgroundColor: Colors.teal,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleRecord() {
    setState(() {
      _isRecording = !_isRecording;
    });
    if (_isRecording) {
      _log("SDK: Started recording live stream to local storage");
    } else {
      _log("SDK: Recording saved successfully.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.videocam, color: Color(0xFF0EA5E9)),
            const SizedBox(width: 10),
            const Text(
              'CCTV Control Center',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear Console Logs',
            onPressed: _clearLogs,
          )
        ],
        elevation: 0,
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar configuration panel (Left)
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Connection mode switcher
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(4.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                if (_p2pStatus == P2PStatus.streaming || _p2pStatus == P2PStatus.connected) {
                                  _disconnectP2P();
                                }
                                setState(() => _connectionMode = ConnectionMode.p2pUID);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _connectionMode == ConnectionMode.p2pUID
                                      ? const Color(0xFF0EA5E9)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                child: Text(
                                  'P2P UID',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _connectionMode == ConnectionMode.p2pUID ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                if (_isRtspStreaming) {
                                  _stopRtspStream();
                                }
                                setState(() => _connectionMode = ConnectionMode.easy4ipRTSP);
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _connectionMode == ConnectionMode.easy4ipRTSP
                                      ? const Color(0xFF0EA5E9)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                alignment: Alignment.center,
                                child: Text(
                                  'Easy4ip RTSP',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _connectionMode == ConnectionMode.easy4ipRTSP ? Colors.white : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Render Active Configuration Panel
                    _connectionMode == ConnectionMode.p2pUID
                        ? _buildP2PConfigPanel()
                        : _buildRtspConfigPanel(),
                  ],
                ),
              ),
            ),
          ),
          
          // Live Video + Terminal Log Panel (Right)
          Expanded(
            flex: 3,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Color(0xFF334155), width: 1),
                ),
                color: Color(0xFF090D16),
              ),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Video Screen
                  Expanded(
                    flex: 6,
                    child: _buildVideoFrame(),
                  ),
                  const SizedBox(height: 16),
                  
                  // Console Output Log
                  Expanded(
                    flex: 4,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF020617),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'NATIVE VENDOR SDK LOGS',
                                style: TextStyle(
                                  color: Colors.greenAccent,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                child: const Text(
                                  'ACTIVE',
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            ],
                          ),
                          const Divider(color: Color(0xFF1E293B)),
                          Expanded(
                            child: ListView.builder(
                              controller: _consoleScrollController,
                              itemCount: _consoleLogs.length,
                              itemBuilder: (context, index) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Text(
                                    _consoleLogs[index],
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                              },
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
        ],
      ),
    );
  }

  // UI Component: P2P Config Panel
  Widget _buildP2PConfigPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_sync, color: Color(0xFF0EA5E9)),
                const SizedBox(width: 8),
                Text(
                  'P2P UID Credentials',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFF334155)),
            
            // UID Input
            TextField(
              controller: _uidController,
              decoration: const InputDecoration(
                labelText: 'Camera UID (Unique ID)',
                prefixIcon: Icon(Icons.qr_code),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF0F172A),
              ),
              enabled: _p2pStatus == P2PStatus.disconnected || _p2pStatus == P2PStatus.error,
            ),
            const SizedBox(height: 16),

            // Username Input
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF0F172A),
              ),
              enabled: _p2pStatus == P2PStatus.disconnected || _p2pStatus == P2PStatus.error,
            ),
            const SizedBox(height: 16),

            // Password Input
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock),
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF0F172A),
              ),
              obscureText: true,
              enabled: _p2pStatus == P2PStatus.disconnected || _p2pStatus == P2PStatus.error,
            ),
            const SizedBox(height: 24),

            // Submit Button
            if (_p2pStatus == P2PStatus.disconnected || _p2pStatus == P2PStatus.error)
              ElevatedButton(
                onPressed: _connectP2PUID,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0EA5E9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Connect via Cloud SDK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            else if (_p2pStatus == P2PStatus.connecting)
              ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Handshaking...'),
                  ],
                ),
              )
            else
              ElevatedButton(
                onPressed: _disconnectP2P,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Disconnect Stream', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            
            if (_p2pStatus == P2PStatus.error) ...[
              const SizedBox(height: 12),
              Text(
                'Connection Error: $_p2pError',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              )
            ]
          ],
        ),
      ),
    );
  }

  // UI Component: RTSP Config Panel
  Widget _buildRtspConfigPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Color(0xFFF97316)),
                const SizedBox(width: 8),
                Text(
                  'Easy4ip Cloud RTSP',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, color: Color(0xFF334155)),
            
            Text('Target SN: $_rtspSerialNumber', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Gateway: Dahua Easy4IP Cloud Gateway (Direct RTSP tunneling port 554)',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 20),

            if (!_isRtspStreaming && !_isRtspLoading)
              ElevatedButton(
                onPressed: _startRtspStream,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Connect RTSP Link', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            else if (_isRtspLoading)
              ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Connecting...'),
                  ],
                ),
              )
            else
              ElevatedButton(
                onPressed: _stopRtspStream,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Stop RTSP Stream', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
          ],
        ),
      ),
    );
  }

  // UI Component: Live Video Screen (Actual VLC player OR premium animated P2P mockup)
  Widget _buildVideoFrame() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // 1. Connection Mode routing
          if (_connectionMode == ConnectionMode.easy4ipRTSP)
            // RTSP Stream View (VLC)
            _isRtspStreaming && _vlcViewController != null
                ? VlcPlayer(
                    controller: _vlcViewController!,
                    aspectRatio: 16 / 9,
                    placeholder: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  )
                : Center(
                    child: _isRtspLoading
                        ? const CircularProgressIndicator(color: Color(0xFFF97316))
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.link_off, size: 48, color: Colors.white30),
                              SizedBox(height: 12),
                              Text(
                                'Easy4ip RTSP Connection Offline',
                                style: TextStyle(color: Colors.white30, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                  )
          else
            // P2P UID View (Simulated/Mock PlatformView SDK Output)
            _p2pStatus == P2PStatus.streaming
                ? _buildP2PStreamSimulator()
                : Center(
                    child: _p2pStatus == P2PStatus.connecting
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Color(0xFF0EA5E9)),
                              SizedBox(height: 16),
                              Text(
                                'Establishing P2P Cloud Channel...',
                                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cloud_off, size: 48, color: Colors.white30),
                              const SizedBox(height: 12),
                              Text(
                                _p2pStatus == P2PStatus.error
                                    ? 'Authentication Error'
                                    : 'P2P SDK Stream Offline',
                                style: const TextStyle(color: Colors.white30, fontWeight: FontWeight.bold),
                              ),
                              if (_p2pStatus == P2PStatus.error) ...[
                                const SizedBox(height: 8),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(
                                    _p2pError,
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              ]
                            ],
                          ),
                  ),

          // 2. Overlay: Video controls & indicators if streaming active
          if ((_connectionMode == ConnectionMode.p2pUID && _p2pStatus == P2PStatus.streaming) ||
              (_connectionMode == ConnectionMode.easy4ipRTSP && _isRtspStreaming))
            _buildStreamControlsOverlay(),
        ],
      ),
    );
  }

  // Interactive UI: P2P live camera simulator frame
  Widget _buildP2PStreamSimulator() {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // CCTV Background Pattern
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF02233C),
                    Color(0xFF081827),
                    Color(0xFF010A14),
                  ],
                ),
              ),
            ),
            
            // Grid Lines Overlay
            CustomPaint(
              painter: GridPainter(),
            ),

            // Mock moving objects or static shapes to feel alive
            Center(
              child: Opacity(
                opacity: 0.1,
                child: Icon(
                  Icons.center_focus_strong,
                  size: 200 * _zoomLevel,
                  color: Colors.cyanAccent,
                ),
              ),
            ),

            // Scan line animation
            Positioned(
              top: _scanController.value * MediaQuery.of(context).size.height * 0.45,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.cyanAccent.withOpacity(0.3),
                      blurRadius: 8,
                      spreadRadius: 2,
                    )
                  ],
                ),
              ),
            ),

            // Watermarks (Standard CCTV styling)
            Positioned(
              top: 16,
              left: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_recBlink)
                        const Icon(Icons.circle, color: Colors.red, size: 12)
                      else
                        const SizedBox(width: 12, height: 12),
                      const SizedBox(width: 6),
                      Text(
                        _isRecording ? 'REC ●' : 'LIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          fontSize: 14,
                          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'CAM 01 - UID: ${_uidController.text}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  Text(
                    'PTZ Status: $_ptzStatus',
                    style: TextStyle(
                      color: _ptzStatus == 'Idle' ? Colors.white70 : Colors.greenAccent,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),

            Positioned(
              top: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currentTimeString,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                  Text(
                    'FPS: 30 | Zoom: ${_zoomLevel.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // UI Component: Overlaid stream control action keys
  Widget _buildStreamControlsOverlay() {
    return Positioned(
      bottom: 16,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: SDK functions (record, snap)
          Row(
            children: [
              // Photo capture
              ClipOval(
                child: Material(
                  color: Colors.black45,
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    tooltip: 'Capture Image',
                    onPressed: _connectionMode == ConnectionMode.p2pUID ? _captureImage : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Video record
              ClipOval(
                child: Material(
                  color: _isRecording ? Colors.red.withOpacity(0.6) : Colors.black45,
                  child: IconButton(
                    icon: Icon(
                      _isRecording ? Icons.fiber_manual_record : Icons.videocam,
                      color: _isRecording ? Colors.white : Colors.white,
                    ),
                    tooltip: 'Record Stream',
                    onPressed: _connectionMode == ConnectionMode.p2pUID ? _toggleRecord : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Zoom In/Out
              if (_connectionMode == ConnectionMode.p2pUID) ...[
                ClipOval(
                  child: Material(
                    color: Colors.black45,
                    child: IconButton(
                      icon: const Icon(Icons.zoom_in, color: Colors.white),
                      tooltip: 'Zoom In',
                      onPressed: () {
                        setState(() {
                          if (_zoomLevel < 3.0) {
                            _zoomLevel += 0.5;
                            _log("SDK: Set digital zoom to ${_zoomLevel}x");
                          }
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ClipOval(
                  child: Material(
                    color: Colors.black45,
                    child: IconButton(
                      icon: const Icon(Icons.zoom_out, color: Colors.white),
                      tooltip: 'Zoom Out',
                      onPressed: () {
                        setState(() {
                          if (_zoomLevel > 1.0) {
                            _zoomLevel -= 0.5;
                            _log("SDK: Set digital zoom to ${_zoomLevel}x");
                          }
                        });
                      },
                    ),
                  ),
                ),
              ]
            ],
          ),
          
          // Right: PTZ directional keys (P2P exclusive)
          if (_connectionMode == ConnectionMode.p2pUID)
            Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_left, color: Colors.cyanAccent),
                    onPressed: () => _triggerPTZ('LEFT'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_drop_up, color: Colors.cyanAccent),
                        onPressed: () => _triggerPTZ('UP'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                        onPressed: () => _triggerPTZ('DOWN'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_right, color: Colors.cyanAccent),
                    onPressed: () => _triggerPTZ('RIGHT'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Custom Painter to draw technical grid on simulated screen
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.04)
      ..strokeWidth = 1.0;

    // Draw vertical lines
    const cols = 8;
    final colWidth = size.width / cols;
    for (var i = 1; i < cols; i++) {
      canvas.drawLine(Offset(i * colWidth, 0), Offset(i * colWidth, size.height), paint);
    }

    // Draw horizontal lines
    const rows = 6;
    final rowHeight = size.height / rows;
    for (var i = 1; i < rows; i++) {
      canvas.drawLine(Offset(0, i * rowHeight), Offset(size.width, i * rowHeight), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}