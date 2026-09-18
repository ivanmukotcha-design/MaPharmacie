import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  bool _completed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scanner un code-barres')),
    body: MobileScanner(
      controller: _controller,
      errorBuilder: (_, error, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Caméra indisponible. Autorisez son accès dans les réglages ou saisissez le code manuellement.\n${error.errorCode.name}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      onDetect: (capture) {
        if (_completed) return;
        for (final barcode in capture.barcodes) {
          final code = barcode.rawValue;
          if (code == null || code.isEmpty) continue;
          _completed = true;
          Navigator.pop(context, code);
          break;
        }
      },
    ),
  );
}
