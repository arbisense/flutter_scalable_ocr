library flutter_scalable_ocr;

import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import './text_recognizer_painter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';

class ScalableOCR extends StatefulWidget {
  const ScalableOCR(
      {Key? key,
      this.boxLeftOff = 4,
      this.boxRightOff = 4,
      this.boxBottomOff = 2.7,
      this.boxTopOff = 2.7,
      this.boxHeight,
      required this.getScannedText,
      this.getRawData,
      this.paintboxCustom,
      this.cameraSelection = 0,
      this.torchOn,
      this.lockCamera = true})
      : super(key: key);

  /// Offset on recalculated image left
  final double boxLeftOff;

  /// Offset on recalculated image bottom
  final double boxBottomOff;

  /// Offset on recalculated image right
  final double boxRightOff;

  /// Offset on recalculated image top
  final double boxTopOff;

  /// Height of narrowed image
  final double? boxHeight;

  /// Function to get scanned text as a string
  final Function getScannedText;

  /// Get raw data from scanned image
  final Function? getRawData;

  /// Narrower box paint
  final Paint? paintboxCustom;

  /// Function to toggle torch
  final bool? torchOn;

  /// Camera Selection
  final int cameraSelection;

  /// Lock camera orientation
  final bool lockCamera;

  @override
  ScalableOCRState createState() => ScalableOCRState();
}

class ScalableOCRState extends State<ScalableOCR> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  final cameraPrev = GlobalKey();
  final thePainter = GlobalKey();

  final bool _canProcess = true;
  bool _isBusy = false;
  bool converting = false;
  CustomPaint? customPaint;
  // String? _text;
  CameraController? _controller;
  late List<CameraDescription> _cameras;
  double zoomLevel = 3.0, minZoomLevel = 0.0, maxZoomLevel = 10.0;
  // Counting pointers (number of user fingers on screen)
  final double _minAvailableZoom = 1.0;
  final double _maxAvailableZoom = 10.0;
  double _currentScale = 3.0;
  double _baseScale = 3.0;
  double maxWidth = 0;
  double maxHeight = 0;
  String convertingAmount = "";
  get cameraController => _controller;

  Rect boundingBox = Rect.zero;

  @override
  void initState() {
    super.initState();
    startLiveFeed();
  }

  @override
  void dispose() {
    stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double sizeH = MediaQuery.of(context).size.height / 100;
    return Padding(
        padding: EdgeInsets.all(sizeH * 3),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _controller == null ||
                      _controller?.value == null ||
                      _controller?.value.isInitialized == false
                  ? Container(
                      width: MediaQuery.of(context).size.width,
                      height: widget.boxHeight ?? sizeH * 19,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(17),
                      ),
                    )
                  : _liveFeedBody(),
              SizedBox(height: sizeH * 2),
            ],
          ),
        ));
  }

  // Body of live camera stream
  Widget _liveFeedBody() {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return const Text('Tap a camera');
    } else {
      const double previewAspectRatio = 0.5;
      return SizedBox(
        height: widget.boxHeight ?? MediaQuery.of(context).size.height / 5,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: SizedBox(
                height:
                    widget.boxHeight ?? MediaQuery.of(context).size.height / 5,
                key: cameraPrev,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.all(Radius.circular(16.0)),
                    child: Center(
                      child: CameraPreview(cameraController, child:
                          LayoutBuilder(builder: (BuildContext context,
                              BoxConstraints constraints) {
                        maxWidth = constraints.maxWidth;
                        maxHeight = constraints.maxHeight;

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart: _handleScaleStart,
                          onScaleUpdate: _handleScaleUpdate,
                          onTapDown: (TapDownDetails details) =>
                              onViewFinderTap(details, constraints),
                        );
                      })),
                    ),
                  ),
                ),
              ),
            ),
            if (customPaint != null)
              LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                maxWidth = constraints.maxWidth;
                maxHeight = constraints.maxHeight;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onTapDown: (TapDownDetails details) =>
                      onViewFinderTap(details, constraints),
                  child: customPaint!,
                );
              }),
          ],
        ),
      );
    }
  }

  // Start camera stream function
  Future startLiveFeed() async {
    _cameras = await availableCameras();
    _controller = CameraController(
        _cameras[widget.cameraSelection], ResolutionPreset.max);
    final camera = _cameras[widget.cameraSelection];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      if (widget.lockCamera == true) {
        _controller?.lockCaptureOrientation();
      } else {
        _controller?.unlockCaptureOrientation();
      }

      if (_controller != null) {
        if (widget.torchOn != null) {
          if (widget.torchOn == true) {
            _controller!.setFlashMode(FlashMode.torch);
          } else {
            _controller!.setFlashMode(FlashMode.off);
          }
        }
      }

      _controller?.getMinZoomLevel().then((value) {
        zoomLevel = value;
        minZoomLevel = value;
      });
      _controller?.getMaxZoomLevel().then((value) {
        maxZoomLevel = value;
      });
      _controller?.startImageStream(_processCameraImage);
      setState(() {});
    }).catchError((Object e) {
      if (e is CameraException) {
        switch (e.code) {
          case 'CameraAccessDenied':
            log('User denied camera access.');
            break;
          default:
            log('Handle other errors.');
            break;
        }
      }
    });
  }

  // Process image from camera stream
  Future _processCameraImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final camera = _cameras[0];
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return;

    final planeData = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: Platform.isAndroid ? InputImageFormat.nv21 : inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    final inputImage =
        // InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
        InputImage.fromBytes(
            bytes: Platform.isAndroid ? image.getNv21Uint8List() : bytes,
            metadata: planeData);

    processImage(inputImage);
  }

  // Scale image
  void _handleScaleStart(ScaleStartDetails details) {
    _baseScale = _currentScale;
  }

  // Handle scale update
  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    // When there are not exactly two fingers on screen don't scale
    if (_controller == null) {
      return;
    }

    _currentScale = (_baseScale * details.scale)
        .clamp(_minAvailableZoom, _maxAvailableZoom);

    await _controller!.setZoomLevel(_currentScale);
  }

  // Focus image
  void onViewFinderTap(TapDownDetails details, BoxConstraints constraints) {
    if (_controller == null) {
      return;
    }

    final CameraController cameraController = _controller!;

    final Offset offset = Offset(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
    );
    cameraController.setExposurePoint(offset);
    cameraController.setFocusPoint(offset);
  }

  // Stop camera live stream
  Future stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  // Process image
  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    final recognizedText = await _textRecognizer.processImage(inputImage);
    if (inputImage.metadata?.size != null &&
        inputImage.metadata?.rotation != null &&
        cameraPrev.currentContext != null) {
      final RenderBox renderBox =
          cameraPrev.currentContext?.findRenderObject() as RenderBox;

      var painter = TextRecognizerPainter(
          recognizedText,
          inputImage.metadata!.size,
          inputImage.metadata!.rotation,
          renderBox, (value) {
        widget.getScannedText(value);
      }, getRawData: (value) {
        if (widget.getRawData != null) {
          widget.getRawData!(value);
        }
      },
          boxBottomOff: widget.boxBottomOff,
          boxTopOff: widget.boxTopOff,
          boxRightOff: widget.boxRightOff,
          boxLeftOff: widget.boxRightOff,
          paintboxCustom: widget.paintboxCustom,
          onPaintCompleted: (Rect boundingBox) {
            this.boundingBox = boundingBox;
            print(this.boundingBox);
          }
      );

      customPaint = CustomPaint(painter: painter);
    } else {
      customPaint = null;
    }
    Future.delayed(const Duration(milliseconds: 900)).then((value) {
      if (!converting) {
        _isBusy = false;
      }

      if (mounted) {
        setState(() {});
      }
    });
  }
}

extension Nv21Converter on CameraImage {
  Uint8List getNv21Uint8List() {
    var width = this.width;
    var height = this.height;

    var yPlane = planes[0];
    var uPlane = planes[1];
    var vPlane = planes[2];

    var yBuffer = yPlane.bytes;
    var uBuffer = uPlane.bytes;
    var vBuffer = vPlane.bytes;

    var numPixels = (width * height * 1.5).toInt();
    var nv21 = List<int>.filled(numPixels, 0);

    // Full size Y channel and quarter size U+V channels.
    int idY = 0;
    int idUV = width * height;
    var uvWidth = width ~/ 2;
    var uvHeight = height ~/ 2;
    // Copy Y & UV channel.
    // NV21 format is expected to have YYYYVU packaging.
    // The U/V planes are guaranteed to have the same row stride and pixel stride.
    // getRowStride analogue??
    var uvRowStride = uPlane.bytesPerRow;
    // getPixelStride analogue
    var uvPixelStride = uPlane.bytesPerPixel ?? 0;
    var yRowStride = yPlane.bytesPerRow;
    var yPixelStride = yPlane.bytesPerPixel ?? 0;

    for (int y = 0; y < height; ++y) {
      var uvOffset = y * uvRowStride;
      var yOffset = y * yRowStride;

      for (int x = 0; x < width; ++x) {
        nv21[idY++] = yBuffer[yOffset + x * yPixelStride];

        if (y < uvHeight && x < uvWidth) {
          var bufferIndex = uvOffset + (x * uvPixelStride);
          //V channel
          nv21[idUV++] = vBuffer[bufferIndex];
          //V channel
          nv21[idUV++] = uBuffer[bufferIndex];
        }
      }
    }
    return Uint8List.fromList(nv21);
  }
}

