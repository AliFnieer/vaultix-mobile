import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/data/totp_repository.dart';
import '../../../core/di/providers.dart';
import '../../../core/crypto/totp.dart';

class ScanQrScreen extends ConsumerStatefulWidget {
  const ScanQrScreen({super.key});

  @override
  ConsumerState<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends ConsumerState<ScanQrScreen> {
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handling = false;
  bool _saved = false;
  String? _message;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handling) return;
    final value = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .firstWhere(
          (value) => value != null && value.isNotEmpty,
          orElse: () => null,
        );
    if (value == null) return;

    _handling = true;
    unawaited(_saveCode(value));
  }

  Future<void> _saveCode(String value) async {
    final config = parseOtpauthUri(value);
    if (config == null) {
      if (mounted) {
        setState(() {
          _message = 'This QR code is not a supported TOTP setup code.';
        });
      }
      return;
    }

    final db = ref.read(appDbProvider);
    final key = ref.read(vaultKeyProvider);
    if (db == null || key == null) {
      if (mounted) {
        setState(() => _message = 'Unlock your vault before adding a code.');
      }
      return;
    }

    try {
      await TotpRepository(db, key).add(config);
      if (!mounted) return;
      setState(() {
        _saved = true;
        _message = 'Authenticator code added securely on this device.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) context.go('/totp');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Vaultix authenticator',
          context: ErrorDescription('while saving a scanned TOTP code'),
        ),
      );
      if (mounted) {
        setState(
          () => _message = 'Could not save this code. Please try again.',
        );
      }
    }
  }

  void _scanAgain() {
    setState(() {
      _handling = false;
      _message = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan authenticator QR')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.no_photography_outlined,
                            size: 48,
                            color: colors.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Camera unavailable. Check camera permission in '
                            'your device settings.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.error),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _message ??
                        'Point your camera at the authenticator setup QR code.',
                    textAlign: TextAlign.center,
                  ),
                  if (_saved) ...[
                    const SizedBox(height: 12),
                    const CircularProgressIndicator(),
                  ] else if (_message != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _scanAgain,
                      child: const Text('Scan another code'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
