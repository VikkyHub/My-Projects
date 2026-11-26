// Display labels for the backend's fixed values (same as the web app).

const createdByOptions = [
  ('self', 'Myself', "I'm looking for a partner"),
  ('parent', 'My son / daughter', "I'm a parent"),
  ('sibling', 'My brother / sister', "I'm a sibling"),
  ('relative', 'My relative', 'Cousin, nephew, niece…'),
  ('friend', 'My friend', 'With their permission'),
];

const maritalLabels = {'never_married': 'Never married', 'divorced': 'Divorced', 'awaiting_divorce': 'Awaiting divorce', 'widowed': 'Widowed'};
const diet = {'veg': 'Vegetarian', 'non_veg': 'Non-vegetarian', 'eggetarian': 'Eggetarian', 'vegan': 'Vegan', 'jain': 'Jain'};
const habit = {'no': 'No', 'occasionally': 'Occasionally', 'yes': 'Yes'};
const familyType = {'nuclear': 'Nuclear', 'joint': 'Joint'};
const familyStatus = {'middle': 'Middle class', 'upper_middle': 'Upper middle class', 'rich': 'Rich', 'affluent': 'Affluent'};
const familyValues = {'traditional': 'Traditional', 'moderate': 'Moderate', 'liberal': 'Liberal'};
const employedIn = {'private': 'Private sector', 'govt': 'Government / PSU', 'business': 'Business', 'self_employed': 'Self-employed', 'not_working': 'Not working'};
const manglik = {'no': 'No', 'yes': 'Yes', 'anshik': 'Anshik (partial)', 'dont_know': "Don't know"};
const visibleTo = {'accepted': 'Only people whose interest I accept', 'premium': 'Premium members', 'all': 'Everyone'};
const photoVisibility = {'all': 'Everyone', 'premium': 'Premium members', 'accepted': 'Only connections'};

const incomeBands = [
  'No income', 'Up to ₹1 lakh', '₹1 – 2 lakh', '₹2 – 3 lakh', '₹3 – 5 lakh', '₹5 – 7.5 lakh', '₹7.5 – 10 lakh',
  '₹10 – 15 lakh', '₹15 – 20 lakh', '₹20 – 30 lakh', '₹30 – 50 lakh', '₹50 lakh – 1 crore', 'Above ₹1 crore',
];

const rashis = [
  'Mesha (Aries)', 'Vrishabha (Taurus)', 'Mithuna (Gemini)', 'Karka (Cancer)', 'Simha (Leo)', 'Kanya (Virgo)',
  'Tula (Libra)', 'Vrishchika (Scorpio)', 'Dhanu (Sagittarius)', 'Makara (Capricorn)', 'Kumbha (Aquarius)', 'Meena (Pisces)',
];

const nakshatras = [
  'Ashwini', 'Bharani', 'Krittika', 'Rohini', 'Mrigashira', 'Ardra', 'Punarvasu', 'Pushya', 'Ashlesha', 'Magha',
  'Purva Phalguni', 'Uttara Phalguni', 'Hasta', 'Chitra', 'Swati', 'Vishakha', 'Anuradha', 'Jyeshtha', 'Mula',
  'Purva Ashadha', 'Uttara Ashadha', 'Shravana', 'Dhanishta', 'Shatabhisha', 'Purva Bhadrapada', 'Uttara Bhadrapada', 'Revati',
];

/// 4'6" .. 7'0"
final heights = [
  for (var i = 0; i < 31; i++) (cm: ((54 + i) * 2.54).round(), label: "${(54 + i) ~/ 12}' ${(54 + i) % 12}\""),
];

String? heightLabel(Object? cm, {bool withCm = true}) {
  if (cm is! int || cm == 0) return null;
  final inches = (cm / 2.54).round();
  final ft = "${inches ~/ 12}' ${inches % 12}\"";
  return withCm ? '$ft ($cm cm)' : ft;
}

const reportReasons = {
  'fake': 'Fake profile / not a real person',
  'married': 'Already married',
  'harassment': 'Harassment or abusive behaviour',
  'scam_money': 'Asked for money',
  'dowry': 'Dowry demand',
  'obscene': 'Obscene content',
  'underage': 'Looks under-age',
  'other': 'Something else',
};

String timeAgo(String? iso) {
  if (iso == null) return '';
  final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  final t = DateTime.parse(iso).toLocal();
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}';
}

String clock(String iso) {
  final t = DateTime.parse(iso).toLocal();
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
}
