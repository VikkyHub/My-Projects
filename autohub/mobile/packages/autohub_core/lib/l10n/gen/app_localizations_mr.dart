// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class AppLocalizationsMr extends AppLocalizations {
  AppLocalizationsMr([String locale = 'mr']) : super(locale);

  @override
  String get appName => 'AutoHub';

  @override
  String get loginTitle => 'तुमच्या फोन नंबरने लॉग इन करा';

  @override
  String get loginSubtitle => 'आम्ही SMS ने 6 अंकी कोड पाठवू';

  @override
  String get phoneLabel => 'मोबाइल नंबर';

  @override
  String get sendOtp => 'कोड पाठवा';

  @override
  String get otpLabel => '6 अंकी कोड टाका';

  @override
  String otpSentTo(String phone) {
    return '$phone वर कोड पाठवला';
  }

  @override
  String get verify => 'पडताळा आणि पुढे जा';

  @override
  String resendIn(int seconds) {
    return '$seconds सेकंदात पुन्हा पाठवा';
  }

  @override
  String get resend => 'कोड पुन्हा पाठवा';

  @override
  String devCodeHint(String code) {
    return 'टेस्ट मोड कोड: $code';
  }

  @override
  String get serverAddress => 'सर्व्हर पत्ता';

  @override
  String get save => 'सेव्ह करा';

  @override
  String get cancel => 'रद्द करा';

  @override
  String get retry => 'पुन्हा प्रयत्न करा';

  @override
  String get logout => 'लॉग आउट';

  @override
  String get offlineBanner =>
      'तुम्ही ऑफलाइन आहात — सेव्ह केलेले निकाल दिसत आहेत. किमती बदललेल्या असू शकतात.';

  @override
  String get somethingWrong => 'काहीतरी चुकले';

  @override
  String get tabParts => 'पार्ट्स';

  @override
  String get tabServices => 'सर्व्हिस';

  @override
  String get tabBookings => 'बुकिंग';

  @override
  String get tabAccount => 'खाते';

  @override
  String get searchParts => 'पार्ट, ब्रँड किंवा पार्ट नंबर शोधा';

  @override
  String get fitsYourCar => 'तुमच्या कारला बसतो';

  @override
  String get universalFit => 'सर्व कारना बसतो';

  @override
  String get doesNotFit => 'बसणार नाही';

  @override
  String get outOfStock => 'स्टॉकमध्ये नाही';

  @override
  String get deliveryToday => 'आज डिलिव्हरी';

  @override
  String get deliveryTomorrow => 'उद्या डिलिव्हरी';

  @override
  String kmAway(String km) {
    return '$km किमी दूर';
  }

  @override
  String get noResults => 'पार्ट सापडला नाही. दुसरे काहीतरी शोधा.';

  @override
  String get sortRelevance => 'सर्वात योग्य';

  @override
  String get sortPriceLow => 'किंमत: कमी ते जास्त';

  @override
  String get sortPriceHigh => 'किंमत: जास्त ते कमी';

  @override
  String get sortRating => 'सर्वोत्तम रेटिंग';

  @override
  String forVehicle(String vehicle) {
    return '$vehicle साठी';
  }

  @override
  String get allVehicles => 'सर्व कार';

  @override
  String get nearbyShops => 'तुमच्या जवळची सर्व्हिस सेंटर';

  @override
  String get openNow => 'आत्ता उघडे';

  @override
  String get closed => 'बंद';

  @override
  String get bookService => 'सर्व्हिस बुक करा';

  @override
  String get selectServices => 'सर्व्हिस निवडा';

  @override
  String get pickSlot => 'वेळ निवडा';

  @override
  String get noSlots => 'या दिवशी स्लॉट उपलब्ध नाही';

  @override
  String get notes => 'समस्या सांगा (ऐच्छिक)';

  @override
  String get priceOnInspection => 'तपासणीनंतर किंमत';

  @override
  String startsFrom(String price) {
    return '$price पासून';
  }

  @override
  String get advanceToPay => 'आत्ता भरायचा ॲडव्हान्स';

  @override
  String get confirmBooking => 'बुकिंग निश्चित करा';

  @override
  String payNow(String amount) {
    return '$amount भरा';
  }

  @override
  String get testPaymentTitle => 'टेस्ट पेमेंट';

  @override
  String get testPaymentBody =>
      'सर्व्हर टेस्ट मोडमध्ये आहे, खरे पैसे कापले जाणार नाहीत. यशस्वी UPI पेमेंटचे सिम्युलेशन करण्यासाठी टॅप करा.';

  @override
  String get paymentSuccess => 'पेमेंट यशस्वी';

  @override
  String get paymentFailed =>
      'पेमेंट पडताळता आले नाही. पैसे कापले असल्यास परत मिळतील.';

  @override
  String get bookingTimeline => 'प्रगती';

  @override
  String get estimate => 'अंदाजपत्रक';

  @override
  String get optionalItem => 'सुचवलेले (ऐच्छिक)';

  @override
  String get approveEstimate => 'अंदाजपत्रक मंजूर करा';

  @override
  String get rejectEstimate => 'नाकारा';

  @override
  String get total => 'एकूण';

  @override
  String get subtotal => 'उप-एकूण';

  @override
  String get gst => 'GST';

  @override
  String get balanceDue => 'उरलेली रक्कम';

  @override
  String get cancelBooking => 'बुकिंग रद्द करा';

  @override
  String get myBookings => 'माझ्या बुकिंग';

  @override
  String get noBookings => 'अजून बुकिंग नाही';

  @override
  String get status_requested => 'दुकानाच्या उत्तराची वाट';

  @override
  String get status_confirmed => 'निश्चित';

  @override
  String get status_vehicle_received => 'कार पोहोचली';

  @override
  String get status_estimate_shared => 'अंदाजपत्रक तयार';

  @override
  String get status_in_progress => 'काम सुरू आहे';

  @override
  String get status_ready => 'कार तयार';

  @override
  String get status_completed => 'पूर्ण';

  @override
  String get status_rejected => 'दुकानाने नाकारले';

  @override
  String get status_cancelled => 'रद्द';

  @override
  String get status_no_show => 'आला नाहीत';

  @override
  String get language => 'भाषा';

  @override
  String get dashboard => 'डॅशबोर्ड';

  @override
  String get todayBookings => 'आजच्या बुकिंग';

  @override
  String get newOrders => 'नवीन ऑर्डर';

  @override
  String get toDispatch => 'पाठवायच्या';

  @override
  String get revenueToday => 'आजची कमाई';

  @override
  String get availableBalance => 'उपलब्ध';

  @override
  String get onHold => 'होल्डवर';

  @override
  String get needsAttention => 'तुमचे लक्ष हवे';

  @override
  String get last7Days => 'मागील 7 दिवस';

  @override
  String get todaySchedule => 'आजचे वेळापत्रक';

  @override
  String get nothingScheduled => 'आज काही नियोजित नाही';

  @override
  String get confirm => 'निश्चित करा';

  @override
  String get reject => 'नाकारा';

  @override
  String get checkIn => 'कार चेक-इन करा';

  @override
  String get startWork => 'काम सुरू करा';

  @override
  String get markReady => 'तयार म्हणून नोंदवा';

  @override
  String get sendEstimate => 'अंदाजपत्रक पाठवा';

  @override
  String get addLine => 'ओळ जोडा';

  @override
  String get description => 'वर्णन';

  @override
  String get amountRupees => 'रक्कम (₹, GST शिवाय)';

  @override
  String get notVendor => 'हा नंबर कोणत्याही दुकानाशी जोडलेला नाही.';
}
