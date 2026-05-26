import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'src/mouth_open_estimator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  List<CameraDescription> cameras = const [];
  try {
    cameras = await availableCameras();
  } on CameraException catch (_) {
    cameras = const [];
  }

  runApp(KuchiTojiWatchApp(cameras: cameras));
}

class KuchiTojiWatchApp extends StatelessWidget {
  const KuchiTojiWatchApp({required this.cameras, super.key});

  final List<CameraDescription> cameras;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF1F8A70);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'くちとじウォッチ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        fontFamily: 'sans',
        useMaterial3: true,
      ),
      home: MouthAlertScreen(cameras: cameras),
    );
  }
}

class MouthAlertScreen extends StatefulWidget {
  const MouthAlertScreen({required this.cameras, super.key});

  final List<CameraDescription> cameras;

  @override
  State<MouthAlertScreen> createState() => _MouthAlertScreenState();
}

class _MouthAlertScreenState extends State<MouthAlertScreen>
    with WidgetsBindingObserver {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final _estimator = const MouthOpenEstimator();
  late final FaceDetector _faceDetector;

  CameraController? _controller;
  CameraDescription? _activeCamera;
  DateTime _lastProcessedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _openStartedAt;
  DateTime? _lastAlertAt;

  bool _cameraReady = false;
  bool _detectionEnabled = true;
  bool _faceFound = false;
  bool _isProcessing = false;
  bool _alerting = false;
  bool _soundEnabled = true;
  bool _initializing = true;

  double _rawScore = 0;
  double _smoothScore = 0;
  double _threshold = 0.2;
  double _alertAfterSeconds = 1.5;
  double _openDurationSeconds = 0;
  int _alertCount = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableContours: true,
        minFaceSize: 0.18,
        performanceMode: FaceDetectorMode.fast,
      ),
    );
    unawaited(_initializeCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        !_initializing) {
      unawaited(_initializeCamera(preferredCamera: _activeCamera));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disposeCamera());
    unawaited(_faceDetector.close());
    super.dispose();
  }

  Future<void> _initializeCamera({CameraDescription? preferredCamera}) async {
    if (widget.cameras.isEmpty) {
      setState(() {
        _initializing = false;
        _errorMessage = 'カメラが見つかりません';
      });
      return;
    }

    setState(() {
      _initializing = true;
      _cameraReady = false;
      _errorMessage = null;
    });

    final camera = preferredCamera ?? _defaultCamera();
    final imageFormatGroup = Platform.isAndroid
        ? ImageFormatGroup.nv21
        : ImageFormatGroup.bgra8888;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: imageFormatGroup,
    );

    try {
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      _controller = controller;
      _activeCamera = camera;
      await controller.startImageStream(_processCameraImage);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraReady = true;
        _initializing = false;
      });
    } on CameraException catch (error) {
      _controller = null;
      _activeCamera = camera;
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _errorMessage = _cameraErrorLabel(error);
      });
    }
  }

  CameraDescription _defaultCamera() {
    return widget.cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    _cameraReady = false;
    if (controller == null) return;

    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await controller.dispose();
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2 || _initializing) return;

    final currentIndex = widget.cameras.indexOf(
      _activeCamera ?? widget.cameras.first,
    );
    final nextIndex = (currentIndex + 1) % widget.cameras.length;
    final nextCamera = widget.cameras[nextIndex];

    await _disposeCamera();
    _resetDetection();
    await _initializeCamera(preferredCamera: nextCamera);
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (!_detectionEnabled || _isProcessing) return;

    final now = DateTime.now();
    if (now.difference(_lastProcessedAt).inMilliseconds < 120) return;
    _lastProcessedAt = now;
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) {
        _markNoFace();
        return;
      }

      final faces = await _faceDetector.processImage(inputImage);
      _handleFaces(faces, now);
    } catch (_) {
      _markNoFace();
    } finally {
      _isProcessing = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    final controller = _controller;
    final camera = _activeCamera;
    if (controller == null || camera == null) return null;

    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation];
      if (rotationCompensation == null) return null;

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    final unsupportedFormat =
        format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888);
    if (unsupportedFormat || image.planes.length != 1) return null;

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  void _handleFaces(List<Face> faces, DateTime now) {
    if (faces.isEmpty) {
      _markNoFace();
      return;
    }

    final face = faces.reduce((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return aArea >= bArea ? a : b;
    });

    final estimate = _estimateMouthOpen(face);
    if (estimate == null) {
      _markNoFace();
      return;
    }

    final nextSmoothScore = _smoothScore == 0
        ? estimate.score
        : (_smoothScore * 0.72) + (estimate.score * 0.28);
    final isOpen = nextSmoothScore >= _threshold;
    var nextOpenDuration = 0.0;
    var nextAlerting = false;

    if (isOpen) {
      _openStartedAt ??= now;
      nextOpenDuration =
          now.difference(_openStartedAt!).inMilliseconds / 1000.0;
      nextAlerting = nextOpenDuration >= _alertAfterSeconds;
    } else {
      _openStartedAt = null;
    }

    if (nextAlerting && !_alerting) {
      _alertCount += 1;
    }
    if (nextAlerting) {
      unawaited(_playAlert(now));
    }

    if (!mounted) return;
    setState(() {
      _faceFound = true;
      _rawScore = estimate.score;
      _smoothScore = nextSmoothScore;
      _openDurationSeconds = nextOpenDuration;
      _alerting = nextAlerting;
    });
  }

  MouthOpenEstimate? _estimateMouthOpen(Face face) {
    final upperInner = face.contours[FaceContourType.upperLipBottom]?.points;
    final lowerInner = face.contours[FaceContourType.lowerLipTop]?.points;
    if (upperInner == null || lowerInner == null) return null;

    final outline = <math.Point<int>>[
      ...?face.contours[FaceContourType.upperLipTop]?.points,
      ...upperInner,
      ...lowerInner,
      ...?face.contours[FaceContourType.lowerLipBottom]?.points,
    ];

    return _estimator.estimate(
      upperInnerLip: upperInner,
      lowerInnerLip: lowerInner,
      mouthOutline: outline,
    );
  }

  void _markNoFace() {
    _openStartedAt = null;
    if (!mounted) return;
    setState(() {
      _faceFound = false;
      _rawScore = 0;
      _smoothScore = 0;
      _openDurationSeconds = 0;
      _alerting = false;
    });
  }

  void _resetDetection() {
    _openStartedAt = null;
    _lastAlertAt = null;
    setState(() {
      _faceFound = false;
      _rawScore = 0;
      _smoothScore = 0;
      _openDurationSeconds = 0;
      _alerting = false;
    });
  }

  Future<void> _playAlert(DateTime now) async {
    if (!_soundEnabled) return;
    final lastAlertAt = _lastAlertAt;
    if (lastAlertAt != null &&
        now.difference(lastAlertAt).inMilliseconds < 1200) {
      return;
    }

    _lastAlertAt = now;
    await SystemSound.play(SystemSoundType.alert);
    await HapticFeedback.mediumImpact();
  }

  void _toggleDetection() {
    setState(() {
      _detectionEnabled = !_detectionEnabled;
    });
    if (!_detectionEnabled) {
      _resetDetection();
    }
  }

  String _cameraErrorLabel(CameraException error) {
    switch (error.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        return 'カメラ許可が必要です';
      default:
        return 'カメラを起動できません';
    }
  }

  _MouthStatus get _mouthStatus {
    if (!_detectionEnabled) {
      return const _MouthStatus('一時停止中', Color(0xFF9EA7AD), Icons.pause);
    }
    if (!_faceFound) {
      return const _MouthStatus(
        '顔未検出',
        Color(0xFF9EA7AD),
        Icons.center_focus_weak,
      );
    }
    if (_alerting) {
      return const _MouthStatus(
        'おくちが開いています',
        Color(0xFFFF6B6B),
        Icons.volume_up,
      );
    }
    if (_smoothScore >= _threshold) {
      return const _MouthStatus(
        '開き始め',
        Color(0xFFFFC857),
        Icons.warning_amber_rounded,
      );
    }
    return const _MouthStatus('OK', Color(0xFF5AD39A), Icons.check_circle);
  }

  @override
  Widget build(BuildContext context) {
    final status = _mouthStatus;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1416),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CameraLayer(
            controller: _controller,
            cameraReady: _cameraReady,
            initializing: _initializing,
            errorMessage: _errorMessage,
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: _TopBar(
                status: status,
                alertCount: _alertCount,
                soundEnabled: _soundEnabled,
                onInfoPressed: _showPrivacyNotice,
                onSoundToggle: () {
                  setState(() => _soundEnabled = !_soundEnabled);
                },
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _ControlPanel(
                status: status,
                detectionEnabled: _detectionEnabled,
                canSwitchCamera: widget.cameras.length > 1,
                rawScore: _rawScore,
                smoothScore: _smoothScore,
                threshold: _threshold,
                alertAfterSeconds: _alertAfterSeconds,
                openDurationSeconds: _openDurationSeconds,
                alertCount: _alertCount,
                onDetectionToggle: _toggleDetection,
                onCameraSwitch: _switchCamera,
                onThresholdChanged: (value) {
                  setState(() => _threshold = value);
                },
                onAlertAfterChanged: (value) {
                  setState(() => _alertAfterSeconds = value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPrivacyNotice() {
    showDialog<void>(
      context: context,
      builder: (context) => const _PrivacyNoticeDialog(),
    );
  }
}

class _CameraLayer extends StatelessWidget {
  const _CameraLayer({
    required this.controller,
    required this.cameraReady,
    required this.initializing,
    required this.errorMessage,
  });

  final CameraController? controller;
  final bool cameraReady;
  final bool initializing;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller != null && cameraReady && controller.value.isInitialized) {
      return ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 1,
            height: controller.value.previewSize?.width ?? 1,
            child: CameraPreview(controller),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF141B1E),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            errorMessage == null ? Icons.camera_alt : Icons.no_photography,
            size: 44,
            color: Colors.white70,
          ),
          const SizedBox(height: 12),
          if (initializing)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              errorMessage ?? 'カメラ準備中',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.alertCount,
    required this.soundEnabled,
    required this.onInfoPressed,
    required this.onSoundToggle,
  });

  final _MouthStatus status;
  final int alertCount;
  final bool soundEnabled;
  final VoidCallback onInfoPressed;
  final VoidCallback onSoundToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xCC101719),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(status.icon, color: status.color, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      status.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$alertCount',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _IconControlButton(
          icon: soundEnabled ? Icons.volume_up : Icons.volume_off,
          tooltip: soundEnabled ? '音あり' : '音なし',
          onPressed: onSoundToggle,
        ),
        const SizedBox(width: 8),
        _IconControlButton(
          icon: Icons.info_outline,
          tooltip: 'プライバシー',
          onPressed: onInfoPressed,
        ),
      ],
    );
  }
}

class _PrivacyNoticeDialog extends StatelessWidget {
  const _PrivacyNoticeDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('プライバシーと注意'),
      content: const SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NoticeLine('カメラ映像は端末内で処理します。'),
            _NoticeLine('録画、保存、クラウド送信はしません。'),
            _NoticeLine('顔認証や個人識別はしません。'),
            _NoticeLine('このアプリは診断や治療を目的としません。'),
            _NoticeLine('いびき、鼻づまり、睡眠中の呼吸停止などが気になる場合は、小児科、耳鼻科、小児歯科などに相談してください。'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

class _NoticeLine extends StatelessWidget {
  const _NoticeLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 6),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({
    required this.status,
    required this.detectionEnabled,
    required this.canSwitchCamera,
    required this.rawScore,
    required this.smoothScore,
    required this.threshold,
    required this.alertAfterSeconds,
    required this.openDurationSeconds,
    required this.alertCount,
    required this.onDetectionToggle,
    required this.onCameraSwitch,
    required this.onThresholdChanged,
    required this.onAlertAfterChanged,
  });

  final _MouthStatus status;
  final bool detectionEnabled;
  final bool canSwitchCamera;
  final double rawScore;
  final double smoothScore;
  final double threshold;
  final double alertAfterSeconds;
  final double openDurationSeconds;
  final int alertCount;
  final VoidCallback onDetectionToggle;
  final VoidCallback onCameraSwitch;
  final ValueChanged<double> onThresholdChanged;
  final ValueChanged<double> onAlertAfterChanged;

  @override
  Widget build(BuildContext context) {
    final scoreProgress = (smoothScore / 0.5).clamp(0.0, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE101719),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: status.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(status.icon, color: status.color, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: scoreProgress,
                          backgroundColor: Colors.white12,
                          color: status.color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _Metric(value: smoothScore.toStringAsFixed(2), label: 'score'),
                const SizedBox(width: 8),
                _Metric(
                  value: openDurationSeconds.toStringAsFixed(1),
                  label: 'sec',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SliderSetting(
                    icon: Icons.tune,
                    label: 'しきい値 ${threshold.toStringAsFixed(2)}',
                    value: threshold,
                    min: 0.08,
                    max: 0.4,
                    divisions: 32,
                    onChanged: onThresholdChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SliderSetting(
                    icon: Icons.timer,
                    label: '${alertAfterSeconds.toStringAsFixed(1)}秒',
                    value: alertAfterSeconds,
                    min: 0.5,
                    max: 5,
                    divisions: 45,
                    onChanged: onAlertAfterChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDetectionToggle,
                    icon: Icon(
                      detectionEnabled ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(detectionEnabled ? '停止' : '開始'),
                  ),
                ),
                const SizedBox(width: 8),
                _IconControlButton(
                  icon: Icons.cameraswitch,
                  tooltip: 'カメラ切替',
                  onPressed: canSwitchCamera ? onCameraSwitch : null,
                ),
                const SizedBox(width: 8),
                _Metric(value: '$alertCount', label: 'alert'),
                const SizedBox(width: 8),
                _Metric(value: rawScore.toStringAsFixed(2), label: 'raw'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _IconControlButton extends StatelessWidget {
  const _IconControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon),
        style: IconButton.styleFrom(
          fixedSize: const Size(46, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _MouthStatus {
  const _MouthStatus(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;
}
