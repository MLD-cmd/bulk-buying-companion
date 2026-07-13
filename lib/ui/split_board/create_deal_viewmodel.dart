import 'package:flutter/foundation.dart';

import '../../data/repositories/deal_repository.dart';
import '../../models/deal.dart';

/// A split with one share is not a split, and past a certain point the shares
/// get too small to be worth collecting. Bounds the slot count both ways.
const int kMinDealSlots = 2;
const int kMaxDealSlots = 50;

class CreateDealViewModel extends ChangeNotifier {
  CreateDealViewModel({required DealRepository dealRepository})
    : _dealRepository = dealRepository;

  final DealRepository _dealRepository;

  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

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
    if (parsed == null) return 'Total price must be a number.';
    if (parsed <= 0) return 'Total price must be more than 0.';
    return null;
  }

  String? validateQuantity(String? value) =>
      _validateWholeNumber(value, label: 'Quantity', min: 1);

  String? validateTotalSlots(String? value) {
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
    return null;
  }

  String? validatePickupLocation(String? value) {
    final location = (value ?? '').trim();
    if (location.isEmpty) return 'Enter where the pickup happens.';
    return null;
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

  /// What each student pays, shown live under the price field so the poster
  /// sees the split before publishing. Null while the inputs are unusable.
  double? previewPricePerShare({
    required String? totalPrice,
    required String? totalSlots,
  }) {
    final price = double.tryParse((totalPrice ?? '').trim());
    final slots = int.tryParse((totalSlots ?? '').trim());
    if (price == null || slots == null || price <= 0 || slots <= 0) return null;
    return price / slots;
  }

  /// Returns the published deal, or null when it was rejected. The reason is
  /// exposed on [errorMessage].
  Future<Deal?> submit(DealDraft draft) async {
    if (_isSubmitting) return null;

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      return await _dealRepository.createDeal(draft);
    } on DealFailure catch (error) {
      _errorMessage = error.message;
      return null;
    } catch (_) {
      _errorMessage = 'Could not publish the deal. Please try again.';
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
