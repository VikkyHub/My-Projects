import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_mr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('mr'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'AutoHub'**
  String get appName;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in with your phone'**
  String get loginTitle;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll send you a 6-digit code by SMS'**
  String get loginSubtitle;

  /// No description provided for @phoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get phoneLabel;

  /// No description provided for @sendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendOtp;

  /// No description provided for @otpLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-digit code'**
  String get otpLabel;

  /// No description provided for @otpSentTo.
  ///
  /// In en, this message translates to:
  /// **'Code sent to {phone}'**
  String otpSentTo(String phone);

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get verify;

  /// No description provided for @resendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendIn(int seconds);

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Resend code'**
  String get resend;

  /// No description provided for @devCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Test mode code: {code}'**
  String devCodeHint(String code);

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddress;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — showing saved results. Prices may have changed.'**
  String get offlineBanner;

  /// No description provided for @somethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWrong;

  /// No description provided for @tabParts.
  ///
  /// In en, this message translates to:
  /// **'Parts'**
  String get tabParts;

  /// No description provided for @tabServices.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get tabServices;

  /// No description provided for @tabBookings.
  ///
  /// In en, this message translates to:
  /// **'Bookings'**
  String get tabBookings;

  /// No description provided for @tabAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get tabAccount;

  /// No description provided for @searchParts.
  ///
  /// In en, this message translates to:
  /// **'Search parts, brands or part numbers'**
  String get searchParts;

  /// No description provided for @fitsYourCar.
  ///
  /// In en, this message translates to:
  /// **'Fits your car'**
  String get fitsYourCar;

  /// No description provided for @universalFit.
  ///
  /// In en, this message translates to:
  /// **'Fits all cars'**
  String get universalFit;

  /// No description provided for @doesNotFit.
  ///
  /// In en, this message translates to:
  /// **'Does not fit'**
  String get doesNotFit;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @deliveryToday.
  ///
  /// In en, this message translates to:
  /// **'Delivery today'**
  String get deliveryToday;

  /// No description provided for @deliveryTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Delivery tomorrow'**
  String get deliveryTomorrow;

  /// No description provided for @kmAway.
  ///
  /// In en, this message translates to:
  /// **'{km} km away'**
  String kmAway(String km);

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No parts found. Try another search.'**
  String get noResults;

  /// No description provided for @sortRelevance.
  ///
  /// In en, this message translates to:
  /// **'Relevance'**
  String get sortRelevance;

  /// No description provided for @sortPriceLow.
  ///
  /// In en, this message translates to:
  /// **'Price: low to high'**
  String get sortPriceLow;

  /// No description provided for @sortPriceHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: high to low'**
  String get sortPriceHigh;

  /// No description provided for @sortRating.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get sortRating;

  /// No description provided for @forVehicle.
  ///
  /// In en, this message translates to:
  /// **'For {vehicle}'**
  String forVehicle(String vehicle);

  /// No description provided for @allVehicles.
  ///
  /// In en, this message translates to:
  /// **'All cars'**
  String get allVehicles;

  /// No description provided for @nearbyShops.
  ///
  /// In en, this message translates to:
  /// **'Service centres near you'**
  String get nearbyShops;

  /// No description provided for @openNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get openNow;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @bookService.
  ///
  /// In en, this message translates to:
  /// **'Book a service'**
  String get bookService;

  /// No description provided for @selectServices.
  ///
  /// In en, this message translates to:
  /// **'Choose services'**
  String get selectServices;

  /// No description provided for @pickSlot.
  ///
  /// In en, this message translates to:
  /// **'Pick a time'**
  String get pickSlot;

  /// No description provided for @noSlots.
  ///
  /// In en, this message translates to:
  /// **'No free slots on this day'**
  String get noSlots;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem (optional)'**
  String get notes;

  /// No description provided for @priceOnInspection.
  ///
  /// In en, this message translates to:
  /// **'Price after inspection'**
  String get priceOnInspection;

  /// No description provided for @startsFrom.
  ///
  /// In en, this message translates to:
  /// **'From {price}'**
  String startsFrom(String price);

  /// No description provided for @advanceToPay.
  ///
  /// In en, this message translates to:
  /// **'Advance to pay now'**
  String get advanceToPay;

  /// No description provided for @confirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get confirmBooking;

  /// No description provided for @payNow.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String payNow(String amount);

  /// No description provided for @testPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Test payment'**
  String get testPaymentTitle;

  /// No description provided for @testPaymentBody.
  ///
  /// In en, this message translates to:
  /// **'The server is in test mode, so no real money moves. Tap to simulate a successful UPI payment.'**
  String get testPaymentBody;

  /// No description provided for @paymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment successful'**
  String get paymentSuccess;

  /// No description provided for @paymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment could not be verified. If money was debited it will be refunded.'**
  String get paymentFailed;

  /// No description provided for @bookingTimeline.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get bookingTimeline;

  /// No description provided for @estimate.
  ///
  /// In en, this message translates to:
  /// **'Estimate'**
  String get estimate;

  /// No description provided for @optionalItem.
  ///
  /// In en, this message translates to:
  /// **'Recommended (optional)'**
  String get optionalItem;

  /// No description provided for @approveEstimate.
  ///
  /// In en, this message translates to:
  /// **'Approve estimate'**
  String get approveEstimate;

  /// No description provided for @rejectEstimate.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get rejectEstimate;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @gst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get gst;

  /// No description provided for @balanceDue.
  ///
  /// In en, this message translates to:
  /// **'Balance due'**
  String get balanceDue;

  /// No description provided for @cancelBooking.
  ///
  /// In en, this message translates to:
  /// **'Cancel booking'**
  String get cancelBooking;

  /// No description provided for @myBookings.
  ///
  /// In en, this message translates to:
  /// **'My bookings'**
  String get myBookings;

  /// No description provided for @noBookings.
  ///
  /// In en, this message translates to:
  /// **'No bookings yet'**
  String get noBookings;

  /// No description provided for @status_requested.
  ///
  /// In en, this message translates to:
  /// **'Waiting for shop'**
  String get status_requested;

  /// No description provided for @status_confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get status_confirmed;

  /// No description provided for @status_vehicle_received.
  ///
  /// In en, this message translates to:
  /// **'Car received'**
  String get status_vehicle_received;

  /// No description provided for @status_estimate_shared.
  ///
  /// In en, this message translates to:
  /// **'Estimate ready'**
  String get status_estimate_shared;

  /// No description provided for @status_in_progress.
  ///
  /// In en, this message translates to:
  /// **'Work in progress'**
  String get status_in_progress;

  /// No description provided for @status_ready.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get status_ready;

  /// No description provided for @status_completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get status_completed;

  /// No description provided for @status_rejected.
  ///
  /// In en, this message translates to:
  /// **'Declined by shop'**
  String get status_rejected;

  /// No description provided for @status_cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get status_cancelled;

  /// No description provided for @status_no_show.
  ///
  /// In en, this message translates to:
  /// **'Missed'**
  String get status_no_show;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @todayBookings.
  ///
  /// In en, this message translates to:
  /// **'Today\'s bookings'**
  String get todayBookings;

  /// No description provided for @newOrders.
  ///
  /// In en, this message translates to:
  /// **'New orders'**
  String get newOrders;

  /// No description provided for @toDispatch.
  ///
  /// In en, this message translates to:
  /// **'To dispatch'**
  String get toDispatch;

  /// No description provided for @revenueToday.
  ///
  /// In en, this message translates to:
  /// **'Revenue today'**
  String get revenueToday;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get availableBalance;

  /// No description provided for @onHold.
  ///
  /// In en, this message translates to:
  /// **'On hold'**
  String get onHold;

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs your attention'**
  String get needsAttention;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @todaySchedule.
  ///
  /// In en, this message translates to:
  /// **'Today\'s schedule'**
  String get todaySchedule;

  /// No description provided for @nothingScheduled.
  ///
  /// In en, this message translates to:
  /// **'Nothing scheduled today'**
  String get nothingScheduled;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @checkIn.
  ///
  /// In en, this message translates to:
  /// **'Check in car'**
  String get checkIn;

  /// No description provided for @startWork.
  ///
  /// In en, this message translates to:
  /// **'Start work'**
  String get startWork;

  /// No description provided for @markReady.
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get markReady;

  /// No description provided for @sendEstimate.
  ///
  /// In en, this message translates to:
  /// **'Send estimate'**
  String get sendEstimate;

  /// No description provided for @addLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get addLine;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @amountRupees.
  ///
  /// In en, this message translates to:
  /// **'Amount (₹, excl. GST)'**
  String get amountRupees;

  /// No description provided for @notVendor.
  ///
  /// In en, this message translates to:
  /// **'This number is not linked to any shop.'**
  String get notVendor;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'mr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'mr':
      return AppLocalizationsMr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
