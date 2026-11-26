// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'AutoHub';

  @override
  String get loginTitle => 'Log in with your phone';

  @override
  String get loginSubtitle => 'We\'ll send you a 6-digit code by SMS';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get sendOtp => 'Send code';

  @override
  String get otpLabel => 'Enter the 6-digit code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get verify => 'Verify & continue';

  @override
  String resendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get resend => 'Resend code';

  @override
  String devCodeHint(String code) {
    return 'Test mode code: $code';
  }

  @override
  String get serverAddress => 'Server address';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get retry => 'Retry';

  @override
  String get logout => 'Log out';

  @override
  String get offlineBanner =>
      'You\'re offline — showing saved results. Prices may have changed.';

  @override
  String get somethingWrong => 'Something went wrong';

  @override
  String get tabParts => 'Parts';

  @override
  String get tabServices => 'Services';

  @override
  String get tabBookings => 'Bookings';

  @override
  String get tabAccount => 'Account';

  @override
  String get searchParts => 'Search parts, brands or part numbers';

  @override
  String get fitsYourCar => 'Fits your car';

  @override
  String get universalFit => 'Fits all cars';

  @override
  String get doesNotFit => 'Does not fit';

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get deliveryToday => 'Delivery today';

  @override
  String get deliveryTomorrow => 'Delivery tomorrow';

  @override
  String kmAway(String km) {
    return '$km km away';
  }

  @override
  String get noResults => 'No parts found. Try another search.';

  @override
  String get sortRelevance => 'Relevance';

  @override
  String get sortPriceLow => 'Price: low to high';

  @override
  String get sortPriceHigh => 'Price: high to low';

  @override
  String get sortRating => 'Top rated';

  @override
  String forVehicle(String vehicle) {
    return 'For $vehicle';
  }

  @override
  String get allVehicles => 'All cars';

  @override
  String get nearbyShops => 'Service centres near you';

  @override
  String get openNow => 'Open now';

  @override
  String get closed => 'Closed';

  @override
  String get bookService => 'Book a service';

  @override
  String get selectServices => 'Choose services';

  @override
  String get pickSlot => 'Pick a time';

  @override
  String get noSlots => 'No free slots on this day';

  @override
  String get notes => 'Describe the problem (optional)';

  @override
  String get priceOnInspection => 'Price after inspection';

  @override
  String startsFrom(String price) {
    return 'From $price';
  }

  @override
  String get advanceToPay => 'Advance to pay now';

  @override
  String get confirmBooking => 'Confirm booking';

  @override
  String payNow(String amount) {
    return 'Pay $amount';
  }

  @override
  String get testPaymentTitle => 'Test payment';

  @override
  String get testPaymentBody =>
      'The server is in test mode, so no real money moves. Tap to simulate a successful UPI payment.';

  @override
  String get paymentSuccess => 'Payment successful';

  @override
  String get paymentFailed =>
      'Payment could not be verified. If money was debited it will be refunded.';

  @override
  String get bookingTimeline => 'Progress';

  @override
  String get estimate => 'Estimate';

  @override
  String get optionalItem => 'Recommended (optional)';

  @override
  String get approveEstimate => 'Approve estimate';

  @override
  String get rejectEstimate => 'Decline';

  @override
  String get total => 'Total';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get gst => 'GST';

  @override
  String get balanceDue => 'Balance due';

  @override
  String get cancelBooking => 'Cancel booking';

  @override
  String get myBookings => 'My bookings';

  @override
  String get noBookings => 'No bookings yet';

  @override
  String get status_requested => 'Waiting for shop';

  @override
  String get status_confirmed => 'Confirmed';

  @override
  String get status_vehicle_received => 'Car received';

  @override
  String get status_estimate_shared => 'Estimate ready';

  @override
  String get status_in_progress => 'Work in progress';

  @override
  String get status_ready => 'Ready for pickup';

  @override
  String get status_completed => 'Completed';

  @override
  String get status_rejected => 'Declined by shop';

  @override
  String get status_cancelled => 'Cancelled';

  @override
  String get status_no_show => 'Missed';

  @override
  String get language => 'Language';

  @override
  String get dashboard => 'Dashboard';

  @override
  String get todayBookings => 'Today\'s bookings';

  @override
  String get newOrders => 'New orders';

  @override
  String get toDispatch => 'To dispatch';

  @override
  String get revenueToday => 'Revenue today';

  @override
  String get availableBalance => 'Available';

  @override
  String get onHold => 'On hold';

  @override
  String get needsAttention => 'Needs your attention';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get todaySchedule => 'Today\'s schedule';

  @override
  String get nothingScheduled => 'Nothing scheduled today';

  @override
  String get confirm => 'Confirm';

  @override
  String get reject => 'Reject';

  @override
  String get checkIn => 'Check in car';

  @override
  String get startWork => 'Start work';

  @override
  String get markReady => 'Mark ready';

  @override
  String get sendEstimate => 'Send estimate';

  @override
  String get addLine => 'Add line';

  @override
  String get description => 'Description';

  @override
  String get amountRupees => 'Amount (₹, excl. GST)';

  @override
  String get notVendor => 'This number is not linked to any shop.';
}
