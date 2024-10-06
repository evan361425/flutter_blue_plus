import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_example/widgets/child_to_image.dart';

import "../utils/snackbar.dart";
import "descriptor_tile.dart";

class CharacteristicTile extends StatefulWidget {
  final BluetoothDevice device;
  final BluetoothCharacteristic characteristic;
  final List<DescriptorTile> descriptorTiles;

  const CharacteristicTile({
    Key? key,
    required this.characteristic,
    required this.descriptorTiles,
    required this.device,
  }) : super(key: key);

  @override
  State<CharacteristicTile> createState() => _CharacteristicTileState();
}

class _CharacteristicTileState extends State<CharacteristicTile> {
  Uint8List _value = Uint8List(0);

  late _printerHelper printer;

  late StreamSubscription<Uint8List> _lastValueSubscription;

  @override
  void initState() {
    super.initState();
    _lastValueSubscription = widget.characteristic.lastValueStream.listen((value) {
      _value = value;
      if (mounted) {
        setState(() {});
      }
    });
    c.onValueReceived.forEach((ev) {
      print(
          '===== 0x${widget.characteristic.uuid.str.toUpperCase()} onValueReceived: ${ev.map((e) => e.toRadixString(16).padLeft(2, '0')).join(',')}');
    });
  }

  @override
  void dispose() {
    _lastValueSubscription.cancel();
    super.dispose();
  }

  BluetoothCharacteristic get c => widget.characteristic;

  Future onReadPressed() async {
    try {
      await c.read();
      Snackbar.show(ABC.c, "Read: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Read Error:", e), success: false);
    }
  }

  Future onWritePressed() async {
    try {
      final image = await getImage(context);
      if (image == null) {
        return;
      }

      for (final chunk in printer.chunks(Uint8List.fromList([
        ...printer._wrapCommand(_printerHelper.cmdControlLattice, _printerHelper._prefixLattice),
        ...printer._wrapCommand(_printerHelper.cmdMode, [0x00]),
        ...printer._wrapCommand(_printerHelper.cmdConfigFeedSpeed, [0x0a]),
        ...printer._wrapImage(image),
        ...printer._wrapCommand(_printerHelper.cmdFeedPaper, [0x2a, 0x00]),
        ...printer._wrapCommand(_printerHelper.cmdControlLattice, _printerHelper._postfixLattice),
      ]))) {
        // print('write chunk: ${chunk.map((e) => e.toRadixString(16).padLeft(2, '0')).join(',')}');
        await c.write(chunk, withoutResponse: c.properties.writeWithoutResponse);
      }

      Snackbar.show(ABC.c, "Write: Success", success: true);
      if (c.properties.read) {
        await c.read();
      }
    } catch (e, stack) {
      Snackbar.show(ABC.c, prettyException("Write Error:", e), success: false);
      print(stack);
    }
  }

  Future onSubscribePressed() async {
    try {
      String op = c.isNotifying == false ? "Subscribe" : "UnSubscribe";
      await c.setNotifyValue(c.isNotifying == false);
      Snackbar.show(ABC.c, "$op : Success", success: true);
      if (c.properties.read) {
        await c.read();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Subscribe Error:", e), success: false);
    }
  }

  Widget buildUuid(BuildContext context) {
    String uuid = '0x${widget.characteristic.uuid.str.toUpperCase()}';
    return Text(uuid, style: TextStyle(fontSize: 13));
  }

  Widget buildValue(BuildContext context) {
    String data = _value.toString();
    return Text(data, style: TextStyle(fontSize: 13, color: Colors.grey));
  }

  Widget buildReadButton(BuildContext context) {
    return TextButton(
        child: Text("Read"),
        onPressed: () async {
          await onReadPressed();
          if (mounted) {
            setState(() {});
          }
        });
  }

  Widget buildWriteButton(BuildContext context) {
    bool withoutResp = widget.characteristic.properties.writeWithoutResponse;
    return TextButton(
        child: Text(withoutResp ? "WriteNoResp" : "Write"),
        onPressed: () async {
          await onWritePressed();
          if (mounted) {
            setState(() {});
          }
        });
  }

  Widget buildSubscribeButton(BuildContext context) {
    bool isNotifying = widget.characteristic.isNotifying;
    return TextButton(
        child: Text(isNotifying ? "Unsubscribe" : "Subscribe"),
        onPressed: () async {
          await onSubscribePressed();
          if (mounted) {
            setState(() {});
          }
        });
  }

  Widget buildButtonRow(BuildContext context) {
    bool read = widget.characteristic.properties.read;
    bool write = widget.characteristic.properties.write || widget.characteristic.properties.writeWithoutResponse;
    bool notify = widget.characteristic.properties.notify;
    bool indicate = widget.characteristic.properties.indicate;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (read) buildReadButton(context),
        if (write) buildWriteButton(context),
        if (notify || indicate) buildSubscribeButton(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: ListTile(
        title: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Characteristic'),
            buildUuid(context),
            buildValue(context),
          ],
        ),
        subtitle: buildButtonRow(context),
        contentPadding: const EdgeInsets.all(0.0),
      ),
      children: widget.descriptorTiles,
    );
  }

  @override
  void didChangeDependencies() {
    printer = _printerHelper(widget.device);
    super.didChangeDependencies();
  }
}

class _printerHelper {
  final BluetoothDevice device;

  _printerHelper(this.device);

  int checksum(List<int> data) {
    int result = 0;
    for (final byte in data) {
      result = _checksumTable[result ^ byte];
    }

    return result;
  }

  Iterable<Uint8List> chunks(Uint8List data) sync* {
    // 8 byte: l2cap protocol (4), opcode (1), handle (2), padding (1)
    final size = device.mtuNow - 8;
    for (var i = 0; i < data.length; i += size) {
      yield data.sublist(i, min(i + size, data.length));
    }
  }

  Uint8List _wrapCommand(int cmd, List<int> data) {
    return Uint8List.fromList([
      prefix1,
      prefix2,
      cmd,
      0, //send to printer
      data.length & 0xFF,
      0, // actual value is `data.length >> 8`, but should always be 0
      ...data,
      checksum(data),
      postfix,
    ]);
  }

  Uint8List _wrapImage(List<int> data) {
    final result = Uint8List((data.length / 48).ceil() * 8 + data.length);
    print('start draw, total:${data.length} result:${result.length}');
    var start = 0;
    for (var i = 0; i < data.length; i += 48) {
      final sub = data.sublist(i, min(i + 48, data.length));
      result[start + 0] = prefix1;
      result[start + 1] = prefix2;
      result[start + 2] = cmdDraw;
      result[start + 3] = 0;
      result[start + 4] = sub.length & 0xFF;
      result[start + 5] = 0;
      result.setAll(start + 6, sub);
      result[start + 6 + sub.length] = checksum(sub);
      result[start + 7 + sub.length] = postfix;
      start = start + 8 + sub.length;
    }
    return result;
  }

  static const _checksumTable = [
    // 16 bytes each line
    0x00, 0x07, 0x0e, 0x09, 0x1c, 0x1b, 0x12, 0x15, 0x38, 0x3f, 0x36, 0x31, 0x24, 0x23, 0x2a, 0x2d, // #1
    0x70, 0x77, 0x7e, 0x79, 0x6c, 0x6b, 0x62, 0x65, 0x48, 0x4f, 0x46, 0x41, 0x54, 0x53, 0x5a, 0x5d, // #2
    0xe0, 0xe7, 0xee, 0xe9, 0xfc, 0xfb, 0xf2, 0xf5, 0xd8, 0xdf, 0xd6, 0xd1, 0xc4, 0xc3, 0xca, 0xcd, // #3
    0x90, 0x97, 0x9e, 0x99, 0x8c, 0x8b, 0x82, 0x85, 0xa8, 0xaf, 0xa6, 0xa1, 0xb4, 0xb3, 0xba, 0xbd, // #4
    0xc7, 0xc0, 0xc9, 0xce, 0xdb, 0xdc, 0xd5, 0xd2, 0xff, 0xf8, 0xf1, 0xf6, 0xe3, 0xe4, 0xed, 0xea, // #5
    0xb7, 0xb0, 0xb9, 0xbe, 0xab, 0xac, 0xa5, 0xa2, 0x8f, 0x88, 0x81, 0x86, 0x93, 0x94, 0x9d, 0x9a, // #6
    0x27, 0x20, 0x29, 0x2e, 0x3b, 0x3c, 0x35, 0x32, 0x1f, 0x18, 0x11, 0x16, 0x03, 0x04, 0x0d, 0x0a, // #7
    0x57, 0x50, 0x59, 0x5e, 0x4b, 0x4c, 0x45, 0x42, 0x6f, 0x68, 0x61, 0x66, 0x73, 0x74, 0x7d, 0x7a, // #8
    0x89, 0x8e, 0x87, 0x80, 0x95, 0x92, 0x9b, 0x9c, 0xb1, 0xb6, 0xbf, 0xb8, 0xad, 0xaa, 0xa3, 0xa4, // #9
    0xf9, 0xfe, 0xf7, 0xf0, 0xe5, 0xe2, 0xeb, 0xec, 0xc1, 0xc6, 0xcf, 0xc8, 0xdd, 0xda, 0xd3, 0xd4, // #10
    0x69, 0x6e, 0x67, 0x60, 0x75, 0x72, 0x7b, 0x7c, 0x51, 0x56, 0x5f, 0x58, 0x4d, 0x4a, 0x43, 0x44, // #11
    0x19, 0x1e, 0x17, 0x10, 0x05, 0x02, 0x0b, 0x0c, 0x21, 0x26, 0x2f, 0x28, 0x3d, 0x3a, 0x33, 0x34, // #12
    0x4e, 0x49, 0x40, 0x47, 0x52, 0x55, 0x5c, 0x5b, 0x76, 0x71, 0x78, 0x7f, 0x6a, 0x6d, 0x64, 0x63, // #13
    0x3e, 0x39, 0x30, 0x37, 0x22, 0x25, 0x2c, 0x2b, 0x06, 0x01, 0x08, 0x0f, 0x1a, 0x1d, 0x14, 0x13, // #14
    0xae, 0xa9, 0xa0, 0xa7, 0xb2, 0xb5, 0xbc, 0xbb, 0x96, 0x91, 0x98, 0x9f, 0x8a, 0x8d, 0x84, 0x83, // #15
    0xde, 0xd9, 0xd0, 0xd7, 0xc2, 0xc5, 0xcc, 0xcb, 0xe6, 0xe1, 0xe8, 0xef, 0xfa, 0xfd, 0xf4, 0xf3 // #16
  ];

  static const _prefixLattice = [
    0xAA, 0x55, 0x17, 0x38, 0x44, 0x5F, 0x5F, 0x5F, 0x44, 0x38, 0x2C //
  ];
  static const _postfixLattice = [
    0xAA, 0x55, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x17 //
  ];

  static const prefix1 = 0x51;
  static const prefix2 = 0x78;
  static const postfix = 0xFF;
  static const cmdFeedPaper = 0xA1;
  static const cmdDraw = 0xA2;
  static const cmdGetState = 0xA3;
  static const cmdSetQuality = 0xA4;
  static const cmdControlLattice = 0xA6;
  static const cmdConfigFeedSpeed = 0xBD;
  static const cmdMode = 0xBE;
}

Future<Uint8List?> getImage(BuildContext context) async {
  final controller = ChildToImageController(key: GlobalKey());
  Uint8List? image;
  await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Image'),
          content: ChildToImage(controller: controller),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final img = await controller.toImage();
                image = img?.toGrayScale().toBitMap(width: controller.width, blackIsOne: true, invertBits: true).bytes;
                Navigator.of(context).pop(true);
              },
              child: Text('OK'),
            ),
          ],
        );
      });

  return image;
}
