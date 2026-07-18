import 'package:flutter/foundation.dart';

import '../../data/repositories/deal_repository.dart';
import '../../data/services/receipt_scanner.dart';
import '../../models/cost_split.dart';
import '../../models/deal.dart';
import '../../models/deal_unit.dart';
import '../../models/physical_share.dart';
import '../../models/receipt_extraction.dart';

/// A split with one share is not a split, and past a certain point the shares
/// get too small to be worth collecting. Bounds the slot count both ways.
const int kMinDealSlots = 2;
const int kMaxDealSlots = 50;

class CreateDealViewModel extends ChangeNotifier {
  CreateDealViewModel({
    required DealRepository dealRepository,
    ReceiptScanner? receiptScanner,
  }) : _dealRepository = dealRepository,
       _receiptScanner = receiptScanner;

  final DealRepository _dealRepository;

  /// Optional: without it the "Scan receipt" affordance is simply absent, and
  /// the form works exactly as it did before. Kept nullable so tests and any
  /// build without the scanner wired in still construct the view model.
  final ReceiptScanner? _receiptScanner;

  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isScanning = false;
  String? _scanErrorMessage;
  bool _disposed = false;

  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  /// Whether to offer receipt scanning at all — true only when a scanner was
  /// wired in.
  bool get scanningEnabled => _receiptScanner != null;
  bool get isScanning => _isScanning;
  String? get scanErrorMessage => _scanErrorMessage;

  /// Scans a receipt and returns what it could read, for the screen to pre-fill
  /// the form with. Returns null when the student backs out of the picker or
  /// when the scan fails — a failure sets [scanErrorMessage] rather than
  /// throwing, so the screen never has to catch anything.
  Future<ReceiptExtraction?> scanReceipt(ReceiptImageSource source) async {
    final scanner = _receiptScanner;
    if (_disposed || scanner == null || _isScanning) return null;

    _isScanning = true;
    _scanErrorMessage = null;
    notifyListeners();

    try {
      return await scanner.scan(source);
    } on ReceiptScanFailure catch (failure) {
      if (!_disposed) _scanErrorMessage = failure.message;
      return null;
    } catch (_) {
      if (!_disposed) {
        _scanErrorMessage = 'Could not scan the receipt. Please try again.';
      }
      return null;
    } finally {
      if (!_disposed) {
        _isScanning = false;
        notifyListeners();
      }
    }
  }

  String? validateTitle(String? value) {
    final title = (value ?? '').trim();
    if (title.isEmpty) return 'Enter the product name.';
    if (title.length < 3) return 'Product name is too short.';
    return null;
  }

  /// Optional — a deal without a description is still a valid deal.
  String? validateDescription(String? value) {
    final description = (value ?? '').trim();
    if (description.length > 280) {
      return 'Keep the description under 280 characters.';
    }
    return null;
  }

  String? validateTotalPrice(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the total price.';
    final parsed = double.tryParse(text);
    // 'Infinity', 'NaN' and '1e400' all parse to a double happily, and the
    // centavo arithmetic cannot do anything with them.
    if (parsed == null || !parsed.isFinite) {
      return 'Total price must be a number.';
    }
    if (parsed <= 0) return 'Total price must be more than 0.';
    // Below a centavo the split rounds away to nothing and every student pays
    // zero, which is not a deal. Compared in pesos, not via the rounded
    // centavo: P0.005 would round *up* to a centavo and slip through, leaving
    // the stored total and the split disagreeing about what the deal costs.
    if (parsed < 0.01) return 'Total price must be at least P0.01.';
    if (parsed > CostSplit.maxTotalPrice) {
      return 'That is more than a bulk buy can total.';
    }
    return null;
  }

  String? validateAmount(String? value, DealUnit unit) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the amount.';

    final parsed = double.tryParse(text);
    if (parsed == null || !parsed.isFinite) return 'Amount must be a number.';
    if (parsed <= 0) return 'Amount must be more than 0.';

    // You cannot buy half a bottle. Weights and volumes are happy to be
    // fractional; countable things are not.
    if (unit.discrete && parsed != parsed.roundToDouble()) {
      final noun = unit.label[0].toUpperCase() + unit.label.substring(1);
      return '$noun come in whole numbers.';
    }
    return null;
  }

  /// The slot count is only meaningful against the goods being split, so this
  /// takes them too. Flutter validators are closures, so the screen can hand
  /// over the other fields and the error still lands on the slots field.
  String? validateTotalSlots(
    String? value, {
    required String? amount,
    required DealUnit unit,
  }) {
    final error = _validateWholeNumber(
      value,
      label: 'Slots',
      min: kMinDealSlots,
    );
    if (error != null) return error;

    final slots = int.parse(value!.trim());
    if (slots < kMinDealSlots) {
      return 'A split needs at least $kMinDealSlots slots.';
    }
    if (slots > kMaxDealSlots) {
      return 'Keep it to $kMaxDealSlots slots or fewer.';
    }

    // Without a usable amount there is nothing to divide yet; the amount field
    // is already complaining, and two errors for one mistake helps nobody.
    final parsedAmount = double.tryParse((amount ?? '').trim());
    if (parsedAmount == null || !parsedAmount.isFinite || parsedAmount <= 0) {
      return null;
    }

    final share = PhysicalShare.from(
      amount: parsedAmount,
      unit: unit,
      slots: slots,
    );
    if (share.dividesEvenly) return null;

    if (!share.canBeSplit) {
      return 'A single ${unit.singularLabel} cannot be split.';
    }

    return '${share.totalLabel} across $slots slots leaves '
        '${_trimmed(share.amountPerShare)} each. '
        'Try ${_suggest(share.workableSlotCounts, slots)}.';
  }

  /// The nearest workable counts either side of what the poster typed. Naming
  /// every divisor of 60 would be a wall of numbers, not a suggestion.
  String _suggest(List<int> workable, int wanted) {
    int? below;
    int? above;
    for (final count in workable) {
      if (count < wanted) below = count;
      if (count > wanted && above == null) above = count;
    }

    final options = [?below, ?above];
    if (options.isEmpty) return '${workable.first} slots';
    if (options.length == 1) return '${options.first} slots';
    return '${options.first} or ${options.last} slots';
  }

  /// 7.5, not 7.50; 6, not 6.0.
  String _trimmed(double value) {
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toString();
  }

  String? validatePickupLocation(String? value) {
    final location = (value ?? '').trim();
    if (location.isEmpty) return 'Enter where the pickup happens.';
    return null;
  }

  String? validatePaymentMethod(String? value) {
    return _validateOptionalLength(
      value,
      max: 40,
      message: 'Keep the payment method under 40 characters.',
    );
  }

  String? validatePaymentAccountName(String? value) {
    return _validateOptionalLength(
      value,
      max: 80,
      message: 'Keep the account name under 80 characters.',
    );
  }

  String? validatePaymentAccountHandle(String? value) {
    return _validateOptionalLength(
      value,
      max: 80,
      message: 'Keep the account number or handle under 80 characters.',
    );
  }

  String? validatePaymentInstructions(String? value) {
    return _validateOptionalLength(
      value,
      max: 180,
      message: 'Keep the payment instructions under 180 characters.',
    );
  }

  /// Optional, but a deadline that has already passed would close the deal the
  /// moment it is published.
  String? validateDeadline(DateTime? value) {
    if (value == null) return null;
    if (!value.isAfter(DateTime.now())) return 'Pick a deadline in the future.';
    return null;
  }

  String? _validateWholeNumber(
    String? value, {
    required String label,
    required int min,
  }) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Enter the ${label.toLowerCase()}.';
    final parsed = int.tryParse(text);
    if (parsed == null) return '$label must be a whole number.';
    if (parsed < min) return '$label must be at least $min.';
    return null;
  }

  String? _validateOptionalLength(
    String? value, {
    required int max,
    required String message,
  }) {
    if ((value ?? '').trim().length > max) return message;
    return null;
  }

  /// The split shown live under the price field, so the poster sees exactly
  /// what students will be asked to pay before publishing.
  ///
  /// Null — never an exception — while the inputs are unusable: this runs on
  /// every keystroke from inside build, and a half-typed price must not take
  /// the form down. Only the split bounds are enforced here; the rest of the
  /// validation has its say on submit.
  CostSplit? previewSplit({
    required String? totalPrice,
    required String? totalSlots,
  }) {
    final price = double.tryParse((totalPrice ?? '').trim());
    final slots = int.tryParse((totalSlots ?? '').trim());
    if (price == null || slots == null) return null;
    if (!price.isFinite || price < 0.01 || price > CostSplit.maxTotalPrice) {
      return null;
    }
    // Previewing a one-way "split" would quote a confident price that
    // validateTotalSlots then rejects on submit.
    if (slots < kMinDealSlots || slots > kMaxDealSlots) return null;
    return CostSplit.from(totalPrice: price, slots: slots);
  }

  /// What each student physically receives, shown live beside what they pay.
  /// Null — never an exception — while the inputs are unusable: this runs on
  /// every keystroke from inside build.
  PhysicalShare? previewShare({
    required String? amount,
    required DealUnit unit,
    required String? totalSlots,
  }) {
    final parsedAmount = double.tryParse((amount ?? '').trim());
    final slots = int.tryParse((totalSlots ?? '').trim());
    if (parsedAmount == null || slots == null) return null;
    if (!parsedAmount.isFinite || parsedAmount <= 0) return null;
    if (slots < kMinDealSlots || slots > kMaxDealSlots) return null;

    return PhysicalShare.from(amount: parsedAmount, unit: unit, slots: slots);
  }

  /// Returns the published deal, or null when it was rejected. The reason is
  /// exposed on [errorMessage].
  Future<Deal?> submit(DealDraft draft) async {
    if (_disposed || _isSubmitting) return null;

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _dealRepository.createDeal(draft);
    } on DealFailure catch (error) {
      if (_disposed) return null;
      _errorMessage = error.message;
      return null;
    } catch (_) {
      if (_disposed) return null;
      _errorMessage = 'Could not publish the deal. Please try again.';
      return null;
    } finally {
      if (!_disposed) {
        _isSubmitting = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
