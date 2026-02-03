import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_localizations.dart';

class BarcodeScannerDialog extends StatefulWidget {
  const BarcodeScannerDialog({super.key});

  @override
  State<BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<BarcodeScannerDialog> {
  MobileScannerController? controller;
  bool _hasPermission = false;
  bool _checkingPermission = true;
  bool _isControllerInitialized = false;
  double _zoomFactor = 0.0;
  int _availableCamerasCount = 0;
  int _currentCameraIndex = 0;
  int _selectedCameraIndex = 0;
  bool _useDesktopCamera = false;
  
  final TextEditingController _desktopController = TextEditingController();
  final FocusNode _desktopFocus = FocusNode();

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _checkingPermission = false;
      _hasPermission = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _desktopFocus.requestFocus();
      });
    } else {
      controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        returnImage: false,
      );
      _checkPermission();
    }
  }

  void _ensureController() {
    controller ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      returnImage: false,
    );
  }

  Future<void> _checkPermission() async {
    if (kIsWeb || Platform.isMacOS) {
      if (mounted) {
        setState(() {
          _hasPermission = true;
          _checkingPermission = false;
        });
      }
      return;
    }

    try {
      final status = await Permission.camera.request();
      if (mounted) {
        setState(() {
          _hasPermission = status.isGranted;
          _checkingPermission = false;
        });
      }
    } catch (e) {
      debugPrint('Permission error: $e');
      if (mounted) {
        setState(() {
          _hasPermission = true; 
          _checkingPermission = false;
        });
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    _desktopController.dispose();
    _desktopFocus.dispose();
    super.dispose();
  }

  void _handleZoom(double value) {
    if (!_isControllerInitialized || controller == null) return;
    setState(() => _zoomFactor = value);
    try {
      controller!.setZoomScale(value);
    } catch (e) {
      debugPrint('Error setting zoom: $e');
    }
  }

  void _toggleTorch() {
    if (!_isControllerInitialized || controller == null) return;
    try {
      controller!.toggleTorch();
    } catch (e) {
      debugPrint('Error toggling torch: $e');
    }
  }

  void _switchCamera() {
    if (!_isControllerInitialized || controller == null) return;
    try {
      controller!.switchCamera();
      if (_availableCamerasCount > 0) {
        setState(() {
          _currentCameraIndex = (_currentCameraIndex + 1) % _availableCamerasCount;
          _selectedCameraIndex = _currentCameraIndex;
        });
      }
    } catch (e) {
      debugPrint('Error switching camera: $e');
    }
  }

  void _setCameraIndex(int index) {
    if (!_isControllerInitialized || controller == null) return;
    if (_availableCamerasCount <= 1) return;
    if (index == _currentCameraIndex) {
      setState(() => _selectedCameraIndex = index);
      return;
    }

    var steps = index - _currentCameraIndex;
    if (steps < 0) steps += _availableCamerasCount;
    for (var i = 0; i < steps; i++) {
      try {
        controller!.switchCamera();
      } catch (e) {
        debugPrint('Error switching camera: $e');
        break;
      }
    }

    setState(() {
      _currentCameraIndex = index;
      _selectedCameraIndex = index;
    });
  }

  String _cameraLabel(AppLocalizations l10n, int index) {
    if (_availableCamerasCount <= 1) return l10n.cameraUnknown;
    if (index == 0) return l10n.cameraBack;
    if (index == 1) return l10n.cameraExternal;
    return '${l10n.cameraUnknown} ${index + 1}';
  }

  void _onDesktopSubmit(String value) {
    final cleaned = value.trim();
    if (cleaned.isNotEmpty && mounted) {
      Navigator.pop(context, cleaned);
    }
  }

  void _onDesktopChanged(String value) {
    if (value.contains('\n') || value.contains('\r') || value.contains('\t')) {
      _onDesktopSubmit(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    if (_isDesktop) {
      if (_useDesktopCamera) {
        _ensureController();
        return AlertDialog(
          title: Text(l10n.scanBarcode),
          contentPadding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Stack(
                children: [
                  MobileScanner(
                    controller: controller!,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        final String? code = barcodes.first.rawValue;
                        if (code != null && mounted) {
                          Navigator.pop(context, code);
                        }
                      }
                    },
                    errorBuilder: (context, error, child) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error, color: Colors.red, size: 32),
                            const SizedBox(height: 8),
                            Text('Scanner Error: ${error.errorCode}'),
                          ],
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: controller!,
                            builder: (context, state, child) {
                              final isInitialized = state.isInitialized;
                              final count = state.availableCameras ?? 0;
                              if (isInitialized && (!_isControllerInitialized || count != _availableCamerasCount)) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  setState(() {
                                    _availableCamerasCount = count;
                                    _isControllerInitialized = true;
                                    if (_selectedCameraIndex >= count && count > 0) {
                                      _selectedCameraIndex = 0;
                                      _currentCameraIndex = 0;
                                    }
                                  });
                                });
                              }

                              if (!isInitialized || count <= 1) return const SizedBox.shrink();

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _selectedCameraIndex,
                                      dropdownColor: Colors.black87,
                                      iconEnabledColor: Colors.white,
                                      style: const TextStyle(color: Colors.white),
                                      items: List.generate(count, (i) {
                                        return DropdownMenuItem(
                                          value: i,
                                          child: Text(_cameraLabel(l10n, i)),
                                        );
                                      }),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        _setCameraIndex(value);
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () {
                            setState(() => _useDesktopCamera = false);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _desktopFocus.requestFocus();
                            });
                          },
                          icon: const Icon(Icons.keyboard, color: Colors.white),
                          style: IconButton.styleFrom(backgroundColor: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        ValueListenableBuilder(
                          valueListenable: controller!,
                          builder: (context, state, child) {
                            final isInitialized = state.isInitialized;
                            return Slider(
                              value: _zoomFactor,
                              onChanged: isInitialized ? _handleZoom : null,
                              activeColor: Colors.orange,
                              inactiveColor: Colors.white24,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _ControlButton(
                              icon: Icons.flash_on,
                              onPressed: _toggleTorch,
                              label: l10n.flash,
                              enabled: _isControllerInitialized,
                            ),
                            _ControlButton(
                              icon: Icons.switch_camera,
                              onPressed: _switchCamera,
                              label: l10n.switchCamera,
                              enabled: _isControllerInitialized && _availableCamerasCount > 1,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
          ],
        );
      }

      return AlertDialog(
        title: Text(l10n.scanBarcode),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.usb, size: 48, color: Colors.orange),
                    const SizedBox(height: 8),
                    Text(
                      l10n.scanWithUsbOrType, 
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "USB Scanners act as keyboards. Just scan!",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _desktopController,
                focusNode: _desktopFocus,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.barcode,
                  hintText: l10n.scanOrTypeHint,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.qr_code),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: () => _onDesktopSubmit(_desktopController.text),
                  ),
                ),
                onChanged: _onDesktopChanged,
                onSubmitted: _onDesktopSubmit,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _useDesktopCamera = true;
                _zoomFactor = 0.0;
              });
            },
            child: Text(l10n.switchCamera),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(l10n.scanBarcode),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _checkingPermission
            ? const Center(child: CircularProgressIndicator())
            : !_hasPermission
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt, color: Colors.grey, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            l10n.cameraPermissionRequired,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _checkPermission,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : ClipRRect(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Stack(
                      children: [
                        MobileScanner(
                          controller: controller!,
                          onDetect: (capture) {
                            final List<Barcode> barcodes = capture.barcodes;
                            if (barcodes.isNotEmpty) {
                              final String? code = barcodes.first.rawValue;
                              if (code != null && mounted) {
                                Navigator.pop(context, code);
                              }
                            }
                          },
                          errorBuilder: (context, error, child) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error, color: Colors.red, size: 32),
                                  const SizedBox(height: 8),
                                  Text('Scanner Error: ${error.errorCode}'),
                                ],
                              ),
                            );
                          },
                        ),
                        Positioned(
                          top: 12,
                          right: 12,
                          child: ValueListenableBuilder(
                            valueListenable: controller!,
                            builder: (context, state, child) {
                              final isInitialized = state.isInitialized;
                              final count = state.availableCameras ?? 0;

                              if (isInitialized && (!_isControllerInitialized || count != _availableCamerasCount)) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  if (!mounted) return;
                                  setState(() {
                                    _availableCamerasCount = count;
                                    _isControllerInitialized = true;
                                    if (_selectedCameraIndex >= count && count > 0) {
                                      _selectedCameraIndex = 0;
                                      _currentCameraIndex = 0;
                                    }
                                  });
                                });
                              }

                              if (!isInitialized || count <= 1) return const SizedBox.shrink();

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<int>(
                                      value: _selectedCameraIndex,
                                      dropdownColor: Colors.black87,
                                      iconEnabledColor: Colors.white,
                                      style: const TextStyle(color: Colors.white),
                                      items: List.generate(count, (i) {
                                        return DropdownMenuItem(
                                          value: i,
                                          child: Text(_cameraLabel(l10n, i)),
                                        );
                                      }),
                                      onChanged: (value) {
                                        if (value == null) return;
                                        _setCameraIndex(value);
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Scanner Overlay
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                            ),
                            child: Center(
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 250,
                                    height: 250,
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.white, width: 2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  Container(
                                    width: 250,
                                    height: 2,
                                    color: Colors.red.withValues(alpha: 0.8),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Controls
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Column(
                            children: [
                              ValueListenableBuilder(
                                valueListenable: controller!,
                                builder: (context, state, child) {
                                  final isInitialized = state.isInitialized;

                                  return Slider(
                                    value: _zoomFactor,
                                    onChanged: isInitialized ? _handleZoom : null,
                                    activeColor: Colors.orange,
                                    inactiveColor: Colors.white24,
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _ControlButton(
                                    icon: Icons.flash_on,
                                    onPressed: _toggleTorch,
                                    label: l10n.flash,
                                    enabled: _isControllerInitialized,
                                  ),
                                  _ControlButton(
                                    icon: Icons.switch_camera,
                                    onPressed: _switchCamera,
                                    label: l10n.switchCamera,
                                    enabled: _isControllerInitialized && _availableCamerasCount > 1,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String label;
  final bool enabled;

  const _ControlButton({
    required this.icon,
    required this.onPressed,
    required this.label,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: enabled ? onPressed : null,
          icon: Icon(icon),
          color: Colors.white,
          disabledColor: Colors.white24,
          style: IconButton.styleFrom(
            backgroundColor: Colors.black45,
            padding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: enabled ? Colors.white : Colors.white24,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

Future<String?> showBarcodeScanner(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const BarcodeScannerDialog(),
  );
}
