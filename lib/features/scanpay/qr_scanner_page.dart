import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera and returns the text of the first QR code it sees,
/// or null when the person backs out.
Future<String?> scanQrCode(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerPage()),
    );

/// Full-screen camera with a square guide. Works on its own, without
/// Google Play services' scanner module.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final side = MediaQuery.sizeOf(context).width * 0.68;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan a UPI QR'),
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Turn off light' : 'Turn on light',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              try {
                await _controller.toggleTorch();
                if (mounted) setState(() => _torchOn = !_torchOn);
              } catch (_) {
                // Phones without a flash: nothing to do.
              }
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) => _CameraError(error: error),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text(
              'Point the camera at the QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            denied
                ? 'Dripless needs the camera to scan QR codes. Allow Camera for Dripless in '
                    'your phone\'s Settings → Apps → Dripless → Permissions, then come back.'
                : 'The camera could not start. Close other apps using the camera and try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }
}
