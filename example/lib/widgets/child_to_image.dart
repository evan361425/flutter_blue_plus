import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ChildToImage extends StatelessWidget {
  final ChildToImageController controller;

  final Color color;

  const ChildToImage({
    Key? key,
    required this.controller,
    this.color = const Color(0xFFFFFFFF),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: DefaultTextStyle(
          style: const TextStyle(color: Color(0xFF424242)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            constraints: const BoxConstraints(maxWidth: 600),
            child: RepaintBoundary(
              key: controller.key,
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/pizza_hut.webp',
                      fit: BoxFit.fitHeight,
                      height: 200,
                    ),
                    const Text(
                      'PURCHASE RECEIPT',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(thickness: 2),
                    Table(
                      columnWidths: const {1: IntrinsicColumnWidth()},
                      children: const [
                        TableRow(
                          children: [
                            Text('ORANGE JUICE'),
                            Text(r'$2'),
                          ],
                        ),
                        TableRow(
                          children: [
                            Text('這是一張測試列印'),
                            Text(r'$2.9'),
                          ],
                        ),
                      ],
                    ),
                    const Divider(thickness: 2),
                    const FittedBox(
                      fit: BoxFit.cover,
                      child: Row(
                        children: [
                          Text(
                            'TOTAL',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(width: 16),
                          Text(
                            r'$200',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                    const Divider(thickness: 2),
                    const Text('Thank you for your purchase!'),
                    const SizedBox(height: 24),
                    Center(
                      child: Image.asset(
                        'assets/qrcode.png',
                        width: 150,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChildToImageController {
  final GlobalKey key;

  /// How many pixels in a row
  final int width;

  ChildToImageController({
    required this.key,
    this.width = 384,
  });

  Future<ConvertibleImage?> toImage() async {
    // Delay is required. See Issue https://github.com/flutter/flutter/issues/22308
    await Future.delayed(const Duration(milliseconds: 20));

    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      return null;
    }

    final image = await boundary.toImage(pixelRatio: width / boundary.size.width);
    final byteData = await image.toByteData();
    final result = ConvertibleImage(byteData!.buffer.asUint8List());
    print('Get image size: ${result.bytes.length}');

    image.dispose();
    return result;
  }
}

class ConvertibleImage {
  final Uint8List bytes;

  const ConvertibleImage(this.bytes);

  /// see: https://en.wikipedia.org/wiki/Luma_%28video%29#Rec._601_luma_versus_Rec._709_luma_coefficients
  ConvertibleImage toGrayScale() {
    // 4 bytes to 1 byte
    final result = Uint8List(bytes.length ~/ 4);
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i];
      final g = bytes[i + 1];
      final b = bytes[i + 2];
      result[i ~/ 4] = (r * 0.299 + g * 0.587 + b * 0.114).round();
    }
    print('Get gray size: ${result.length}');

    return ConvertibleImage(result);
  }

  /// see: https://en.wikipedia.org/wiki/Floyd%E2%80%93Steinberg_dithering
  ConvertibleImage toBitMap({required int width, bool invertBits = false, bool blackIsOne = false}) {
    // 8 bits to 1 bit
    final result = Uint8List(bytes.length ~/ 8);
    final lastRow = bytes.length - width;
    for (var i = 0; i < bytes.length; i++) {
      // convert to binary image
      var err = bytes[i];
      if (bytes[i] > 127) {
        err = bytes[i] - 255;
        if (invertBits) {
          result[i ~/ 8] |= 1 << (i % 8);
        } else {
          result[i ~/ 8] |= 1 << (7 - i % 8);
        }
      }
      continue;

      // floyd-steinberg dithering
      if (i % width < width - 1) {
        bytes[i + 1] += err * 7 ~/ 16;
        if (i < lastRow) {
          bytes[i + width + 1] += err ~/ 16;
        }
      }

      if (i < lastRow) {
        bytes[i + width - 1] += err * 3 ~/ 16;
        bytes[i + width] += err * 5 ~/ 16;
      }
    }

    print('Get bitmap size: ${result.length}');
    if (blackIsOne) {
      return ConvertibleImage(Uint8List.fromList(result.map((e) => ~e).toList()));
    }

    return ConvertibleImage(result);
  }
}
