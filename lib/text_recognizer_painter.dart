import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'coordinates_translator.dart';

class TextRecognizerPainter extends CustomPainter {
  TextRecognizerPainter(this.recognizedText, this.absoluteImageSize,
      this.rotation, this.renderBox, this.getScannedText,
      {this.boxLeftOff = 4,
      this.boxBottomOff = 2,
      this.boxRightOff = 4,
      this.boxTopOff = 2,
      this.getRawData,
      this.paintboxCustom,
      this.onPaintCompleted
      });

  /// ML kit recognizer
  final RecognizedText recognizedText;

  /// Image scanned size
  final Size absoluteImageSize;

  /// Image scanned rotation
  final InputImageRotation rotation;

  /// Render box for narrow camera
  final RenderBox renderBox;

  /// Function to get scanned text as a string
  final Function getScannedText;

  /// Scanned text string
  String scannedText = "";

  /// Offset on recalculated image left
  final double boxLeftOff;

  /// Offset on recalculated image bottom
  final double boxBottomOff;

  /// Offset on recalculated image right
  final double boxRightOff;

  /// Offset on recalculated image top
  final double boxTopOff;

  /// Get raw data from scanned image
  final Function? getRawData;

  /// Narrower box paint
  final Paint? paintboxCustom;

  /// onPaintCompleted callback
  final Function? onPaintCompleted;

  @override
  void paint(Canvas canvas, Size size) {
    scannedText = "";

    final Paint background = Paint()
      ..color = const Color.fromARGB(153, 98, 152, 227);

    final Size boxSize = renderBox.size;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    var siz = getRatioHeight(rotation, size, absoluteImageSize);
    var siz1 = getRatioWidth(rotation, size, absoluteImageSize);

    var currentScannerBoxWidth = boxSize.width / siz1;
    var currentScannerBoxHeight = boxSize.height / siz;
    var currentXOffset = offset.dx * siz1;
    var currentYOffset = offset.dy * siz;

    var rawLeft = (currentScannerBoxWidth / boxLeftOff) + currentXOffset;
    var rawTop = (currentScannerBoxHeight / boxTopOff) + currentYOffset;
    var rawRight = (currentScannerBoxWidth + currentXOffset) -
        (currentScannerBoxWidth / boxRightOff);
    var rawBottom = (currentScannerBoxHeight + currentYOffset) -
        (currentScannerBoxHeight / boxBottomOff);

    if (onPaintCompleted != null) {
      final boundingBox = Rect.fromLTRB(rawLeft, rawTop, rawRight, rawBottom);
      onPaintCompleted!(boundingBox);
    }

    final boxLeft = translateX(
        rawLeft,
        rotation,
        size,
        absoluteImageSize);
    final boxTop = translateY(
        rawTop,
        rotation,
        size,
        absoluteImageSize);
    final boxRight = translateX(
        rawRight,
        rotation,
        size,
        absoluteImageSize);
    final boxBottom = translateY(
        rawBottom,
        rotation,
        size,
        absoluteImageSize);

    final Paint paintbox = paintboxCustom ??
        (Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = const Color.fromARGB(153, 102, 160, 241));

    canvas.drawRect(
      Rect.fromLTRB(boxLeft, boxTop, boxRight, boxBottom),
      paintbox,
    );
    List textBlocks = [];
    for (final textBunk in recognizedText.blocks) {
      for (final element in textBunk.lines) {
        for (final textBlock in element.elements) {
          final left = translateX(
              (textBlock.boundingBox.left), rotation, size, absoluteImageSize);
          final top = translateY(
              (textBlock.boundingBox.top), rotation, size, absoluteImageSize);
          final right = translateX(
              (textBlock.boundingBox.right), rotation, size, absoluteImageSize);
          final bottom = translateY(
              (textBlock.boundingBox.bottom), rotation, size, absoluteImageSize);

          if (left >= boxLeft &&
              right <= boxRight &&
              (top >= (boxTop + 15) && top <= (boxBottom - 20))) {
            // (top >= (boxTop + 15) && bottom <= (boxBottom - 20))) {
            textBlocks.add(textBlock);

            var parsedText = textBlock.text;
            scannedText += " ${textBlock.text}";

            final ParagraphBuilder builder = ParagraphBuilder(
              ParagraphStyle(
                  textAlign: TextAlign.left,
                  fontSize: 14,
                  textDirection: TextDirection.ltr),
            );
            builder.pushStyle(
                ui.TextStyle(color: Colors.white, background: background));
            builder.addText(parsedText);
            builder.pop();

            canvas.drawParagraph(
              builder.build()
                ..layout(ParagraphConstraints(
                  width: right - left,
                )),
              Offset(left, top),
            );
          }
        }
      }
    }
    if (getRawData != null) {
      getRawData!(textBlocks);
    }
    getScannedText(scannedText);
  }

  @override
  bool shouldRepaint(TextRecognizerPainter oldDelegate) {
    return oldDelegate.recognizedText != recognizedText;
  }
}
