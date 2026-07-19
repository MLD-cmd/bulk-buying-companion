import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/deal_unit.dart';
import '../../models/receipt_extraction.dart';

/// Where the receipt photo comes from.
enum ReceiptImageSource { camera, gallery }

/// Raised when a scan cannot be completed. The message is user-facing.
class ReceiptScanFailure implements Exception {
  const ReceiptScanFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Turns a photo of a receipt into a [ReceiptExtraction]: pick the image, read
/// its text, parse the text. Backed by [MockReceiptScanner] in tests and
/// [MlKitReceiptScanner] in production; callers never depend on the concrete
/// implementation, and in particular never touch the camera or ML Kit plugins
/// from a widget test.
abstract class ReceiptScanner {
  /// Scans a receipt from [source]. Returns null when the student backs out of
  /// the image picker without choosing a photo — a cancellation, not a failure.
  /// Throws [ReceiptScanFailure] when the pick or the text recognition fails.
  Future<ReceiptExtraction?> scan(ReceiptImageSource source);
}

/// On-device scanner: [ImagePicker] for the photo, Google ML Kit for the text,
/// [ReceiptParser] for the structure. Everything runs on the phone — no
/// network, no key, nothing leaves the device.
class MlKitReceiptScanner implements ReceiptScanner {
  MlKitReceiptScanner({
    ImagePicker? imagePicker,
    ReceiptParser parser = const ReceiptParser(),
  }) : _imagePicker = imagePicker ?? ImagePicker(),
       _parser = parser;

  final ImagePicker _imagePicker;
  final ReceiptParser _parser;

  @override
  Future<ReceiptExtraction?> scan(ReceiptImageSource source) async {
    final XFile? photo;
    try {
      photo = await _imagePicker.pickImage(
        source: source == ReceiptImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
    } catch (_) {
      throw const ReceiptScanFailure(
        'Could not open the camera or photos. Check the app’s permissions.',
      );
    }
    if (photo == null) return null;

    // Built here, not in the constructor, so constructing the scanner never
    // reaches for a plugin — a widget test can wire it up without the native
    // text recognizer being present. Always closed, so the native recognizer
    // is not leaked when a scan fails.
    final inputImage = InputImage.fromFilePath(photo.path);
    final barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.all]);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final barcodeValue = await _scanBarcode(barcodeScanner, inputImage);
      final recognised = await recognizer.processImage(inputImage);
      // Rebuild the receipt's rows from where each line sits, so a label and
      // the amount beside it are read together rather than in the column-by-
      // column order OCR returns them in.
      final lines = [
        for (final block in recognised.blocks)
          for (final line in block.lines)
            ReceiptTextLine(
              text: line.text,
              top: line.boundingBox.top,
              bottom: line.boundingBox.bottom,
              left: line.boundingBox.left,
            ),
      ];
      final extraction = _parser.parse(assembleReceiptText(lines));
      return ReceiptExtraction(
        productName: extraction.productName,
        totalPrice: extraction.totalPrice,
        amount: extraction.amount,
        unit: extraction.unit,
        barcodeValue: barcodeValue,
        rawText: extraction.rawText,
      );
    } catch (_) {
      throw const ReceiptScanFailure(
        'Could not read that photo. Try a clearer, flatter shot of the receipt or barcode.',
      );
    } finally {
      await barcodeScanner.close();
      await recognizer.close();
    }
  }

  Future<String?> _scanBarcode(
    BarcodeScanner scanner,
    InputImage inputImage,
  ) async {
    final List<Barcode> barcodes;
    try {
      barcodes = await scanner.processImage(inputImage);
    } catch (_) {
      return null;
    }
    for (final barcode in barcodes) {
      final value = (barcode.rawValue ?? barcode.displayValue)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}

/// In-memory stand-in that returns a fixed extraction, so the Create Deal
/// screen's scan flow can be driven in tests without a camera or ML Kit.
class MockReceiptScanner implements ReceiptScanner {
  MockReceiptScanner({this.result, this.cancels = false, this.failure});

  /// What a successful scan yields. Defaults to a plausible bulk-buy receipt.
  final ReceiptExtraction? result;

  /// When true, [scan] returns null, standing in for the student backing out
  /// of the picker.
  final bool cancels;

  /// When set, [scan] throws it, standing in for a permission or read failure.
  final ReceiptScanFailure? failure;

  @override
  Future<ReceiptExtraction?> scan(ReceiptImageSource source) async {
    if (failure != null) throw failure!;
    if (cancels) return null;
    return result ??
        const ReceiptExtraction(
          productName: 'Rice Sack',
          totalPrice: 900,
          amount: 25,
          unit: DealUnit.kg,
          barcodeValue: '4801234567890',
          rawText: 'SUPER SAVER MART\nRice Sack 25kg 900.00\nTOTAL 900.00',
        );
  }
}
