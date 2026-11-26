// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'AutoHub';

  @override
  String get loginTitle => 'अपने फ़ोन नंबर से लॉग इन करें';

  @override
  String get loginSubtitle => 'हम SMS से 6 अंकों का कोड भेजेंगे';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get sendOtp => 'कोड भेजें';

  @override
  String get otpLabel => '6 अंकों का कोड डालें';

  @override
  String otpSentTo(String phone) {
    return '$phone पर कोड भेजा गया';
  }

  @override
  String get verify => 'सत्यापित करें और आगे बढ़ें';

  @override
  String resendIn(int seconds) {
    return '$seconds सेकंड में दोबारा भेजें';
  }

  @override
  String get resend => 'कोड दोबारा भेजें';

  @override
  String devCodeHint(String code) {
    return 'टेस्ट मोड कोड: $code';
  }

  @override
  String get serverAddress => 'सर्वर पता';

  @override
  String get save => 'सेव करें';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get retry => 'फिर से कोशिश करें';

  @override
  String get logout => 'लॉग आउट';

  @override
  String get offlineBanner =>
      'आप ऑफ़लाइन हैं — सेव किए गए नतीजे दिख रहे हैं। कीमतें बदल सकती हैं।';

  @override
  String get somethingWrong => 'कुछ गड़बड़ हो गई';

  @override
  String get tabParts => 'पार्ट्स';

  @override
  String get tabServices => 'सर्विस';

  @override
  String get tabBookings => 'बुकिंग';

  @override
  String get tabAccount => 'खाता';

  @override
  String get searchParts => 'पार्ट, ब्रांड या पार्ट नंबर खोजें';

  @override
  String get fitsYourCar => 'आपकी कार में फिट';

  @override
  String get universalFit => 'सभी कारों में फिट';

  @override
  String get doesNotFit => 'फिट नहीं होगा';

  @override
  String get outOfStock => 'स्टॉक में नहीं';

  @override
  String get deliveryToday => 'आज डिलीवरी';

  @override
  String get deliveryTomorrow => 'कल डिलीवरी';

  @override
  String kmAway(String km) {
    return '$km किमी दूर';
  }

  @override
  String get noResults => 'कोई पार्ट नहीं मिला। कुछ और खोजें।';

  @override
  String get sortRelevance => 'सबसे उपयुक्त';

  @override
  String get sortPriceLow => 'कीमत: कम से ज़्यादा';

  @override
  String get sortPriceHigh => 'कीमत: ज़्यादा से कम';

  @override
  String get sortRating => 'सबसे अच्छी रेटिंग';

  @override
  String forVehicle(String vehicle) {
    return '$vehicle के लिए';
  }

  @override
  String get allVehicles => 'सभी कारें';

  @override
  String get nearbyShops => 'आपके पास के सर्विस सेंटर';

  @override
  String get openNow => 'अभी खुला';

  @override
  String get closed => 'बंद';

  @override
  String get bookService => 'सर्विस बुक करें';

  @override
  String get selectServices => 'सर्विस चुनें';

  @override
  String get pickSlot => 'समय चुनें';

  @override
  String get noSlots => 'इस दिन कोई स्लॉट खाली नहीं';

  @override
  String get notes => 'समस्या बताएं (वैकल्पिक)';

  @override
  String get priceOnInspection => 'जांच के बाद कीमत';

  @override
  String startsFrom(String price) {
    return '$price से शुरू';
  }

  @override
  String get advanceToPay => 'अभी एडवांस देना है';

  @override
  String get confirmBooking => 'बुकिंग पक्की करें';

  @override
  String payNow(String amount) {
    return '$amount भुगतान करें';
  }

  @override
  String get testPaymentTitle => 'टेस्ट भुगतान';

  @override
  String get testPaymentBody =>
      'सर्वर टेस्ट मोड में है, असली पैसे नहीं कटेंगे। सफल UPI भुगतान का नमूना चलाने के लिए टैप करें।';

  @override
  String get paymentSuccess => 'भुगतान सफल';

  @override
  String get paymentFailed =>
      'भुगतान सत्यापित नहीं हो सका। पैसे कटे हैं तो वापस आ जाएंगे।';

  @override
  String get bookingTimeline => 'प्रगति';

  @override
  String get estimate => 'अनुमान';

  @override
  String get optionalItem => 'सुझाया गया (वैकल्पिक)';

  @override
  String get approveEstimate => 'अनुमान मंज़ूर करें';

  @override
  String get rejectEstimate => 'मना करें';

  @override
  String get total => 'कुल';

  @override
  String get subtotal => 'उप-योग';

  @override
  String get gst => 'GST';

  @override
  String get balanceDue => 'बाकी रकम';

  @override
  String get cancelBooking => 'बुकिंग रद्द करें';

  @override
  String get myBookings => 'मेरी बुकिंग';

  @override
  String get noBookings => 'अभी कोई बुकिंग नहीं';

  @override
  String get status_requested => 'दुकान के जवाब का इंतज़ार';

  @override
  String get status_confirmed => 'पक्की';

  @override
  String get status_vehicle_received => 'कार पहुंच गई';

  @override
  String get status_estimate_shared => 'अनुमान तैयार';

  @override
  String get status_in_progress => 'काम चल रहा है';

  @override
  String get status_ready => 'कार तैयार';

  @override
  String get status_completed => 'पूरा हुआ';

  @override
  String get status_rejected => 'दुकान ने मना किया';

  @override
  String get status_cancelled => 'रद्द';

  @override
  String get status_no_show => 'नहीं पहुंचे';

  @override
  String get language => 'भाषा';

  @override
  String get dashboard => 'डैशबोर्ड';

  @override
  String get todayBookings => 'आज की बुकिंग';

  @override
  String get newOrders => 'नए ऑर्डर';

  @override
  String get toDispatch => 'भेजने हैं';

  @override
  String get revenueToday => 'आज की कमाई';

  @override
  String get availableBalance => 'उपलब्ध';

  @override
  String get onHold => 'होल्ड पर';

  @override
  String get needsAttention => 'आपका ध्यान चाहिए';

  @override
  String get last7Days => 'पिछले 7 दिन';

  @override
  String get todaySchedule => 'आज का शेड्यूल';

  @override
  String get nothingScheduled => 'आज कुछ शेड्यूल नहीं';

  @override
  String get confirm => 'पक्का करें';

  @override
  String get reject => 'मना करें';

  @override
  String get checkIn => 'कार चेक-इन करें';

  @override
  String get startWork => 'काम शुरू करें';

  @override
  String get markReady => 'तैयार चिह्नित करें';

  @override
  String get sendEstimate => 'अनुमान भेजें';

  @override
  String get addLine => 'लाइन जोड़ें';

  @override
  String get description => 'विवरण';

  @override
  String get amountRupees => 'रकम (₹, GST के बिना)';

  @override
  String get notVendor => 'यह नंबर किसी दुकान से जुड़ा नहीं है।';
}
