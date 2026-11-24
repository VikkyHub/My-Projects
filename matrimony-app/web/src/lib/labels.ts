// Display labels for the backend's fixed values.

export const CREATED_BY = [
  { value: "self", label: "Myself", hint: "I'm looking for a partner" },
  { value: "parent", label: "My son / daughter", hint: "I'm a parent" },
  { value: "sibling", label: "My brother / sister", hint: "I'm a sibling" },
  { value: "relative", label: "My relative", hint: "Cousin, nephew, niece…" },
  { value: "friend", label: "My friend", hint: "With their permission" },
] as const;

export const MARITAL = {
  never_married: "Never married",
  divorced: "Divorced",
  awaiting_divorce: "Awaiting divorce",
  widowed: "Widowed",
} as const;

export const DIET = {
  veg: "Vegetarian",
  non_veg: "Non-vegetarian",
  eggetarian: "Eggetarian",
  vegan: "Vegan",
  jain: "Jain",
} as const;

export const HABIT = { no: "No", occasionally: "Occasionally", yes: "Yes" } as const;

export const FAMILY_TYPE = { nuclear: "Nuclear", joint: "Joint" } as const;
export const FAMILY_STATUS = {
  middle: "Middle class",
  upper_middle: "Upper middle class",
  rich: "Rich",
  affluent: "Affluent",
} as const;
export const FAMILY_VALUES = {
  traditional: "Traditional",
  moderate: "Moderate",
  liberal: "Liberal",
} as const;

export const EMPLOYED_IN = {
  private: "Private sector",
  govt: "Government / PSU",
  business: "Business",
  self_employed: "Self-employed",
  not_working: "Not working",
} as const;

export const INCOME_BANDS = [
  "No income",
  "Up to ₹1 lakh",
  "₹1 – 2 lakh",
  "₹2 – 3 lakh",
  "₹3 – 5 lakh",
  "₹5 – 7.5 lakh",
  "₹7.5 – 10 lakh",
  "₹10 – 15 lakh",
  "₹15 – 20 lakh",
  "₹20 – 30 lakh",
  "₹30 – 50 lakh",
  "₹50 lakh – 1 crore",
  "Above ₹1 crore",
];

export const MANGLIK = { no: "No", yes: "Yes", anshik: "Anshik (partial)", dont_know: "Don't know" } as const;

export const RASHIS = [
  "Mesha (Aries)", "Vrishabha (Taurus)", "Mithuna (Gemini)", "Karka (Cancer)", "Simha (Leo)",
  "Kanya (Virgo)", "Tula (Libra)", "Vrishchika (Scorpio)", "Dhanu (Sagittarius)",
  "Makara (Capricorn)", "Kumbha (Aquarius)", "Meena (Pisces)",
];

export const NAKSHATRAS = [
  "Ashwini", "Bharani", "Krittika", "Rohini", "Mrigashira", "Ardra", "Punarvasu", "Pushya",
  "Ashlesha", "Magha", "Purva Phalguni", "Uttara Phalguni", "Hasta", "Chitra", "Swati",
  "Vishakha", "Anuradha", "Jyeshtha", "Mula", "Purva Ashadha", "Uttara Ashadha", "Shravana",
  "Dhanishta", "Shatabhisha", "Purva Bhadrapada", "Uttara Bhadrapada", "Revati",
];

export const VISIBLE_TO = {
  accepted: "Only people whose interest I accept",
  premium: "Premium members",
  all: "Everyone",
} as const;

/** 4'6" .. 7'0" */
export const HEIGHTS = Array.from({ length: 31 }, (_, i) => {
  const inches = 54 + i;
  return { cm: Math.round(inches * 2.54), label: `${Math.floor(inches / 12)}' ${inches % 12}"` };
});

export function heightLabel(cm: number | null | undefined) {
  if (!cm) return undefined;
  const inches = Math.round(cm / 2.54);
  return `${Math.floor(inches / 12)}' ${inches % 12}" (${cm} cm)`;
}

export function options<T extends Record<string, string>>(map: T) {
  return Object.entries(map).map(([value, label]) => ({ value, label }));
}
