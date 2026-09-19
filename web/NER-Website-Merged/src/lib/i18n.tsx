import { createContext, useContext, useEffect, useMemo, useState } from 'react';

export const LANGUAGES = [
  { code: 'en', label: 'English', native: 'English' },
  { code: 'hi', label: 'Hindi', native: 'हिन्दी' },
  { code: 'as', label: 'Assamese', native: 'অসমীয়া' },
  { code: 'bn', label: 'Bengali', native: 'বাংলা' },
  { code: 'nsm', label: 'Naga', native: 'Tenyidie' },
  { code: 'lus', label: 'Mizo', native: 'Mizo Ṭawng' },
] as const;

export type LanguageCode = (typeof LANGUAGES)[number]['code'];

const STORAGE_KEY = 'ner-language';

/**
 * gettext-style dictionary: English source string -> translated string.
 * Only English and Hindi are fully translated today. The remaining
 * languages are selectable, persisted and applied (the `lang` attribute
 * and every screen re-renders through this dictionary), but fall back to
 * English strings until a verified regional translation is supplied —
 * this avoids shipping guessed/unverified government-facing copy.
 */
const dictionaries: Partial<Record<LanguageCode, Record<string, string>>> = {
  hi: {
    Dashboard: 'डैशबोर्ड',
    'Field Dashboard': 'फील्ड डैशबोर्ड',
    'District Map': 'जिला मानचित्र',
    'Regional Map': 'क्षेत्रीय मानचित्र',
    Incidents: 'घटनाएं',
    Routes: 'मार्ग',
    Logistics: 'रसद',
    'Live Logistics': 'लाइव रसद',
    Tasks: 'कार्य',
    'My Tasks': 'मेरे कार्य',
    'AI Insights': 'एआई अंतर्दृष्टि',
    'AI Predictions': 'एआई भविष्यवाणियां',
    Alerts: 'अलर्ट',
    Reports: 'रिपोर्ट',
    Analytics: 'विश्लेषिकी',
    'Report Incident': 'घटना दर्ज करें',
    'Route Status': 'मार्ग की स्थिति',
    'Command Center': 'कमांड सेंटर',
    'Main Menu': 'मुख्य मेनू',
    'Role set by your account': 'भूमिका आपके खाते से निर्धारित है',
    'Viewing As': 'इस रूप में देखें',
    'Help & Support': 'सहायता एवं समर्थन',
    Logout: 'लॉगआउट',
    'JANRAKSHAK AI': 'जनरक्षक एआई',
    'Search incidents, routes, officers…': 'घटनाएं, मार्ग, अधिकारी खोजें…',
    ONLINE: 'ऑनलाइन',
    'OFFLINE DEMO': 'ऑफलाइन डेमो',
    'Active Region': 'सक्रिय क्षेत्र',
    'Active District': 'सक्रिय जिला',
    'Assigned Area': 'निर्धारित क्षेत्र',
    'Offline demo — live data unavailable.': 'ऑफलाइन डेमो — लाइव डेटा उपलब्ध नहीं है।',
    'Operations desk': 'ऑपरेशन डेस्क',
    'Support mail': 'सहायता मेल',
    'Call Desk': 'डेस्क को कॉल करें',
    'Email Support': 'ईमेल सहायता',
    Account: 'खाता',
    Profile: 'प्रोफाइल',
    Settings: 'सेटिंग्स',
    'Full Name': 'पूरा नाम',
    Role: 'भूमिका',
    'Assigned District / Region': 'निर्धारित जिला / क्षेत्र',
    Contact: 'संपर्क',
    Email: 'ईमेल',
    'Last Login': 'अंतिम लॉगिन',
    'Account Status': 'खाता स्थिति',
    'Edit Profile': 'प्रोफाइल संपादित करें',
    Notifications: 'सूचनाएं',
    'Theme & Appearance': 'थीम और रूप',
    Language: 'भाषा',
    'Security & Password': 'सुरक्षा और पासवर्ड',
    Phone: 'फोन',
    'District / Region': 'जिला / क्षेत्र',
    'Change photo': 'फोटो बदलें',
    'Save Changes': 'परिवर्तन सहेजें',
    Cancel: 'रद्द करें',
    Light: 'हल्का',
    Dark: 'गहरा',
    System: 'सिस्टम',
    'Default platform theme': 'डिफ़ॉल्ट प्लेटफॉर्म थीम',
    'Reduced eye strain at night': 'रात में आंखों पर कम दबाव',
    'Follows OS preference': 'ओएस वरीयता का पालन करता है',
    'Apply Language': 'भाषा लागू करें',
    'Save Preferences': 'प्राथमिकताएं सहेजें',
    'Two-Factor Authentication': 'दो-चरणीय सत्यापन',
    'Change Password': 'पासवर्ड बदलें',
    'Update Password': 'पासवर्ड अपडेट करें',
    'Active Sessions': 'सक्रिय सत्र',
  },
};

function loadLanguage(): LanguageCode {
  if (typeof window === 'undefined') return 'en';
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    return LANGUAGES.some((l) => l.code === stored) ? (stored as LanguageCode) : 'en';
  } catch {
    return 'en';
  }
}

interface LanguageContextValue {
  language: LanguageCode;
  setLanguage: (l: LanguageCode) => void;
  t: (source: string) => string;
}

const LanguageContext = createContext<LanguageContextValue | null>(null);

export function LanguageProvider({ children }: { children: React.ReactNode }) {
  const [language, setLanguageState] = useState<LanguageCode>(() => loadLanguage());

  // Apply + persist immediately so every screen re-renders in the chosen language.
  useEffect(() => {
    document.documentElement.lang = language;
    try {
      window.localStorage.setItem(STORAGE_KEY, language);
    } catch {
      /* storage unavailable: language still applies for this page load */
    }
  }, [language]);

  const value = useMemo<LanguageContextValue>(() => {
    const dict = dictionaries[language];
    return {
      language,
      setLanguage: setLanguageState,
      t: (source: string) => dict?.[source] ?? source,
    };
  }, [language]);

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage(): LanguageContextValue {
  const ctx = useContext(LanguageContext);
  if (!ctx) throw new Error('useLanguage must be used within a LanguageProvider');
  return ctx;
}
