import SwiftUI

/// Arabic is a complete interface language here, not a subtitle under every
/// English label. The English string is the lookup key, so a view that has not
/// been localised yet still renders correct English rather than a raw token.
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case arabic  = "ar"

    /// Each language names itself in its own script. Never a flag: a flag names
    /// a country, and Arabic is not one country.
    var endonym: String { self == .arabic ? "العربية" : "English" }
    var isArabic: Bool { self == .arabic }
    var layoutDirection: LayoutDirection { self == .arabic ? .rightToLeft : .leftToRight }
    var locale: Locale { Locale(identifier: rawValue) }
}

/// Holds the chosen interface language. The root view carries this as an
/// `.id(...)`, so switching rebuilds the whole tree rather than leaving half a
/// screen in the previous direction.
final class Localization: ObservableObject {
    static let shared = Localization()
    private static let defaultsKey = "jaddati.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func toggle() { language = language == .arabic ? .english : .arabic }
}

/// Look up an interface string. The argument is the English wording, which is
/// also what is returned when the language is English or a key is missing.
func L(_ english: String) -> String {
    guard Localization.shared.language == .arabic else { return english }
    return arabicStrings[english] ?? english
}

/// True when the interface — not the content — is Arabic.
var uiIsArabic: Bool { Localization.shared.language == .arabic }

// MARK: - Interface strings

let arabicStrings: [String: String] = [
    "JADDATI": "جدّتي",
    "Jaddati": "جدّتي",
    "Voices, carefully kept.": "أصوات نحفظها بعناية.",
    "Keep their recordings. Create new words in a recreated voice.": "احفظوا تسجيلاتهم، وأنشئوا كلمات جديدة بصوت يُعاد إنشاؤه بالذكاء الاصطناعي.",
    "Home": "الرئيسية", "People": "الأشخاص", "Saved": "المحفوظات", "Books": "الكتب", "Settings": "الإعدادات",
    "English": "English", "Arabic": "العربية", "Language": "اللغة",
    "Back": "رجوع", "Close": "إغلاق", "Done": "تم", "Cancel": "إلغاء", "Continue": "متابعة",
    "Next": "التالي", "Previous": "السابق", "Try again": "حاول مجددًا", "Retry": "إعادة المحاولة",
    "Learn more": "معرفة المزيد", "View all": "عرض الكل",
    "Add someone": "إضافة شخص", "Add a person": "إضافة شخص", "Add their voice": "إضافة صوت",
    "A place for voices you want to keep.": "مكان للأصوات التي تريد الاحتفاظ بها.",
    "Start with a name. Add a recording when you are ready.": "ابدأ باسم، وأضف تسجيلًا عندما تكون مستعدًا.",
    "No people yet": "لم تُضِف أحدًا بعد",
    "No voice yet": "لم يُنشأ الصوت بعد",
    "No recordings yet": "لا توجد تسجيلات بعد",
    "No saved clips yet": "لا توجد مقاطع محفوظة بعد",
    "Original recordings": "التسجيلات الأصلية",
    "Saved clips": "المقاطع المحفوظة",
    "Name": "الاسم", "Relationship": "صلة القرابة",
    "Grandmother": "الجدة", "Grandfather": "الجد", "Mother": "الأم", "Father": "الأب", "Friend": "صديق",
    "Voice service not connected": "خدمة الصوت غير متصلة",
    "Connect a voice service to create a voice or new audio. Original recordings remain available.": "اربط خدمة صوت لإنشاء صوت أو مقاطع جديدة. تظل التسجيلات الأصلية متاحة.",
    "Set up voice service": "إعداد خدمة الصوت",
    "Voice ready": "الصوت جاهز",
    "Recreated voice ready": "الصوت المُعاد إنشاؤه جاهز",
    "No recreated voice yet": "لم يُنشأ الصوت بعد",
    "Ready to create audio": "جاهز لإنشاء مقاطع صوتية",
    "Add an original recording to create a voice.": "أضف تسجيلًا أصليًا لإنشاء الصوت.",
    "Voice is being prepared": "يجري تجهيز الصوت",
    "The voice has been created, but the service has not made it available yet.": "أُنشئ الصوت، لكن الخدمة لم تُتِحه للاستخدام بعد.",
    "Check availability": "التحقّق من الجاهزية",
    "Test voice only": "صوت تجريبي فقط",
    "Test voice · No real voice was created.": "صوت تجريبي · لم يُنشأ صوت حقيقي.",
    "Created in offline test mode. This is not a usable voice.": "أُنشئ في وضع اختبار بلا اتصال. لا يمكن استخدامه لإنشاء مقاطع صوتية.",
    "Create a real voice": "إنشاء صوت قابل للاستخدام",
    "Voice unavailable": "الصوت غير متاح",
    "This voice can no longer generate audio. Create a new voice to continue.": "لم يعد هذا الصوت قادرًا على إنشاء مقاطع. أنشئ صوتًا جديدًا للمتابعة.",
    "Re-create voice": "إعادة إنشاء الصوت",
    "Everything saved": "كل المحفوظات",
    "Manage voice": "إدارة الصوت",
    "Delete person and audio": "حذف الشخص ومقاطع الصوت",
    "Delete this person?": "هل تريد حذف هذا الشخص؟",
    "This removes their profile, original recordings, and saved clips from Jaddati.": "سيُحذف الملف والتسجيلات الأصلية والمقاطع المحفوظة من جدّتي.",
    "Deleting from Jaddati does not confirm deletion by the voice service.": "الحذف من جدّتي لا يؤكّد أن خدمة الصوت حذفت بياناتها.",
    "Delete permanently": "الحذف نهائيًا",
    "Say something": "كلمات تختارها",
    "Words you choose, spoken in their recreated voice.": "كلمات تختارها، بصوت يُعاد إنشاؤه بالذكاء الاصطناعي.",
    "Words of comfort": "كلمات للمواساة",
    "A short line to help you feel steadier.": "كلمات قصيرة تمنحك بعض السكينة.",
    "A bedtime story": "قصة قبل النوم",
    "An invented bedtime story in their recreated voice.": "قصة متخيّلة قبل النوم، بصوت يُعاد إنشاؤه بالذكاء الاصطناعي.",
    "Kept words": "كلمات محفوظة",
    "Words & memories": "كلمات وذكريات",
    "The words you have kept, in one place": "الكلمات التي احتفظت بها، في مكان واحد",
    "Words you choose, in a recreated voice": "كلمات تختارها، بصوت يُعاد إنشاؤه",
    "A short, steadying line you choose": "عبارة قصيرة تختارها لتمنحك السكينة",
    "An invented story for a quiet moment": "قصة متخيّلة للحظة هادئة",
    "Your own text, a page at a time": "نصّك أنت، صفحةً صفحة",
    "Words you have kept, together in one place.": "كلمات احتفظت بها، مجتمعة في مكان واحد.",
    "Read me a book": "قراءة كتاب",
    "A text you bring, read one page at a time.": "نص تختاره، يُقرأ صفحةً صفحة.",
    "Add a voice": "إضافة صوت",
    "Create a new voice version": "إنشاء نسخة صوت جديدة",
    "Choose a recording": "اختر تسجيلًا",
    "Choose a file": "اختيار ملف",
    "Use a saved recording": "اختيار تسجيل محفوظ",
    "Record now": "سجّل الآن",
    "From this person’s recordings": "من تسجيلات هذا الشخص",
    "A clear sample makes a difference.": "وضوح التسجيل يصنع فرقًا.",
    "About a minute. One voice. A quiet room.": "نحو دقيقة، بصوت شخص واحد، ومن دون ضجيج.",
    "Choose a recording without background music or overlapping voices.": "اختر تسجيلًا بلا موسيقى في الخلفية أو أصوات متداخلة.",
    "Nothing selected": "لم يُختَر تسجيل بعد",
    "Selected recording": "التسجيل المختار",
    "Duration": "المدة",
    "Change recording": "تغيير التسجيل",
    "This recording may be too short.": "قد يكون هذا التسجيل قصيرًا جدًا.",
    "A longer, clear sample may produce a more consistent voice.": "قد يساعد تسجيل أوضح وأطول على إنشاء صوت أكثر ثباتًا.",
    "Before you create this voice": "قبل إنشاء هذا الصوت",
    "This recording will be uploaded to a third-party voice service.": "سيُرفع هذا التسجيل إلى خدمة صوت تابعة لجهة خارجية.",
    "Voice service": "خدمة الصوت",
    "Review the provider’s data policy": "مراجعة سياسة بيانات المزوّد",
    "If the person has died, this app requires authorization from the family or the representative responsible for granting it. Jaddati cannot verify that authorization.": "إذا كان صاحب الصوت متوفّى، يشترط هذا التطبيق وجود صلاحية من أسرته أو من الممثّل المسؤول عن منحها. لا يستطيع جدّتي التحقّق من هذه الصلاحية.",
    "I have the right to use this recording and to create new speech in this voice.": "أؤكّد أن لديّ الحق في استخدام هذا التسجيل وإنشاء كلام جديد بهذا الصوت.",
    "I understand that this creates new AI audio, not a recording of words this person actually said.": "أفهم أن هذا ينشئ مقاطع جديدة بالذكاء الاصطناعي، وليست تسجيلًا لكلمات قالها هذا الشخص فعلًا.",
    "Create voice": "إنشاء الصوت",
    "Choose a recording and confirm your rights to continue.": "اختر تسجيلًا وأكّد حقك في استخدامه للمتابعة.",
    "Confirm your rights to continue.": "أكّد حقك في الاستخدام للمتابعة.",
    "Uploading recording…": "جارٍ رفع التسجيل…",
    "Creating voice…": "جارٍ إنشاء الصوت…",
    "Voice creation failed": "تعذّر إنشاء الصوت",
    "The service could not create this voice. Your original recording is still available.": "لم تتمكّن الخدمة من إنشاء الصوت. ما زال التسجيل الأصلي متاحًا.",
    "This creates another voice. The previous voice is not deleted.": "هذا ينشئ صوتًا آخر، ولا يحذف الصوت السابق.",
    "Existing saved clips keep their original audio.": "تحتفظ المقاطع المحفوظة بملفاتها الصوتية الحالية.",
    "Create": "إنشاء",
    "Your words": "كلماتك",
    "Words to be spoken": "الكلمات التي سيقرؤها الصوت",
    "Write the words here…": "اكتب الكلمات هنا…",
    "You can write in Arabic, English, or both.": "يمكنك الكتابة بالعربية أو الإنجليزية أو بهما معًا.",
    "Characters": "الأحرف",
    "Character limit reached": "بلغت الحد الأقصى للأحرف",
    "Shorten the text to continue.": "اختصر النص للمتابعة.",
    "Add words to continue.": "أدخل كلمات لإنشاء مقطع صوتي.",
    "Voice delivery": "طريقة الإلقاء",
    "Natural": "طبيعي", "Gentle": "هادئ", "Storytelling": "قصصي",
    "Steadiness": "ثبات الإلقاء",
    "More expressive": "أكثر تعبيرًا", "More steady": "أكثر ثباتًا",
    "Likeness to the original": "التشابه مع الصوت الأصلي",
    "Less similar": "تشابه أقل", "More similar": "تشابه أكبر",
    "Pace": "سرعة الإلقاء", "Slower": "أبطأ", "Faster": "أسرع",
    "Playback speed": "سرعة التشغيل", "Normal": "عادي",
    "Results may differ from the original recording.": "قد تختلف النتيجة عن التسجيل الأصلي.",
    "Source quality and language both affect the result. A high likeness value is not a guarantee.": "تؤثّر جودة التسجيل واللغة في النتيجة. وارتفاع قيمة التشابه ليس ضمانًا.",
    "Generate audio": "إنشاء المقطع",
    "Create audio": "إنشاء مقطع صوتي",
    "Creating audio…": "جارٍ إنشاء المقطع…",
    "Audio creation failed": "تعذّر إنشاء المقطع",
    "Your words are still here. Try again when the service is available.": "ما زالت كلماتك محفوظة هنا. حاول مجددًا عندما تصبح الخدمة متاحة.",
    "Saved lines": "عباراتك المحفوظة",
    "Your lines": "عباراتك",
    "Ready-made lines": "عبارات مقترحة",
    "Save this line": "حفظ العبارة",
    "Remove line": "إزالة العبارة",
    "Load in English": "استخدام النص الإنجليزي",
    "Load in Arabic": "استخدام النص العربي",
    "Choose a story": "اختر قصة",
    "Invented stories": "قصص متخيّلة",
    "These are invented stories, not memories or stories told by this person.": "هذه قصص متخيّلة، وليست ذكريات أو قصصًا رواها هذا الشخص.",
    "Previously kept": "ما احتفظت به",
    "Use these words": "استخدام هذه الكلمات",
    "Use": "استخدام",
    "This clip · example quote": "هذا المقطع · تقدير توضيحي",
    "Costs shown are examples. A real quote comes from the provider before anything is charged.": "التكاليف المعروضة أمثلة توضيحية. يأتي السعر الحقيقي من المزوّد قبل أي خصم.",
    "Choose someone first": "اختر شخصًا أولًا",
    "Open a person to see what is kept for them.": "افتح ملف شخص لترى ما احتفظت به له.",
    "Open a person to bring them a text.": "افتح ملف شخص لتضيف له نصًا.",
    "A place for a familiar voice.": "مكان لصوت مألوف.",
    "The recordings you have. The words you choose.": "التسجيلات التي لديك. والكلمات التي تختارها.",
    "Original and recreated. Always distinct.": "الأصلي والمُعاد إنشاؤه. متمايزان دائمًا.",
    "People you keep here": "الأشخاص الذين تحتفظ بهم هنا",
    "A family archive": "أرشيف عائلي",
    "Carefully kept.": "محفوظة بعناية.",
    "Original recordings and the new words you chose to save.": "التسجيلات الأصلية والكلمات الجديدة التي اخترت حفظها.",
    "A shelf of familiar pages.": "رفٌّ من صفحات مألوفة.",
    "Bring a text. Hear it in a recreated voice, one page at a time.": "أضف نصًا، واسمعه بصوت يُعاد إنشاؤه، صفحةً صفحة.",
    "Words of your choosing.": "كلمات من اختيارك.",
    "Write something new to be spoken in a recreated voice.": "اكتب شيئًا جديدًا ليُقال بصوت يُعاد إنشاؤه.",
    "How it is spoken": "طريقة الإلقاء",
    "Fine-tune the voice": "ضبط دقيق للصوت",

    // Screen headlines, from the design's own copy deck. The line breaks are
    // the designer's — they are set, not wrapped.
    "Words of\nyour choosing.": "كلماتٌ تختارها.",
    "A little\nsteadiness.": "شيءٌ من السكينة.",
    "A small story.\nA quiet moment.": "حكاية صغيرة.\nلحظة هادئة.",
    "Words worth\nkeeping.": "كلمات تستحق\nأن تبقى.",
    "A shelf of\nfamiliar pages.": "رفٌّ لصفحاتٍ\nمألوفة.",
    "A voice deserves\ncareful permission.": "الصوت أمانة.\nوالإذن أولًا.",
    "Begin with\na recording.": "ابدأ بتسجيل.",
    "A new voice\nversion.": "إصدار جديد\nللصوت.",
    "Your recording, played\nexactly as it is.": "تسجيلك،\nكما هو.",
    "The recordings you have.\nThe words you choose.": "تسجيلاتٌ تحتفظ بها.\nوكلماتٌ تختارها.",

    "Choose a line, or write what feels right to you.": "اختر عبارة، أو اكتب ما يناسب شعورك.",
    "A place for your memories and the words you have chosen.": "مكان لذكرياتك والكلمات التي اخترتها.",
    "A small light, and a bird finding its way.": "ضوء صغير، وعصفور يجد طريقه.",
    "Your own saved lines will appear here first.": "ستظهر عباراتك المحفوظة هنا أولًا.",
    "Words saved here and in Say something will appear together.": "ستجتمع هنا الكلمات التي تحفظها من هذه الشاشة ومن «كلمات تختارها».",
    "A clear sample helps preserve the qualities of their voice.": "تسجيل واضح يساعد على الاحتفاظ بملامح الصوت.",
    "Choose a recording, then review both permissions.": "اختر تسجيلًا ثم راجع الإذنين.",
    "Both permissions are needed before upload.": "يلزم تأكيد الإذنين قبل الرفع.",
    "There is no hurry. Your archive can grow in your own time.": "على مهل. لكلّ ذكرى وقتها.",
    "No original recordings yet.": "لا توجد تسجيلات أصلية بعد.",
    "Your first book belongs here.": "هنا مكان كتابك الأول.",
    "A place for what matters.": "مكانٌ لما يهمّك.",
    "Nothing in this view.": "لا توجد مقاطع هنا.",
    "There is no previous page.": "لا توجد صفحة سابقة.",
    "You have reached the last page.": "وصلت إلى الصفحة الأخيرة.",
    "Uses existing audio. No new generation or charge.": "يستخدم الصوت الموجود. لا إنشاء جديد ولا رسوم جديدة.",
    "Only this page is included. No automatic reading or charging.": "تتضمن العملية هذه الصفحة فقط. لا قراءة تلقائية أو رسوم تلقائية.",
    "Enter some words to create a clip.": "أدخل كلمات لإنشاء مقطع.",
    "Shorten the text to fit the limit.": "اختصر النص ضمن الحد المسموح.",
    "The words are still here.": "الكلمات ما زالت هنا.",
    "An original family recording.": "تسجيل أصلي من العائلة.",
    "Add a voice before creating audio.": "أضف صوتًا قبل إنشاء مقطع.",
    "This voice is still being prepared.": "لا يزال الصوت قيد التجهيز.",
    "The test voice is not a real voice. Create one to continue.": "الصوت التجريبي ليس صوتًا حقيقيًا. أنشئ صوتًا للمتابعة.",
    "Voice service is not connected.": "خدمة الصوت غير متصلة.",
    "Re-create the voice to continue.": "أعد إنشاء الصوت للمتابعة.",
    "I have the right to have this text read aloud.": "لديّ الإذن بإنشاء قراءة صوتية لهذا النص.",
    "Length unknown": "المدة غير معروفة",
    "Nothing kept here yet": "لم تحفظ شيئًا هنا بعد",
    "Original recording": "تسجيل أصلي",
    "Their own voice": "الصوت الأصلي",
    "AI-recreated voice": "صوت مُعاد إنشاؤه بالذكاء الاصطناعي",
    "AI recreated": "مُعاد بالذكاء الاصطناعي",
    "Recreated": "مُعاد إنشاؤه",
    "Invented story": "قصة متخيّلة",
    "Words supplied by you": "كلمات اخترتها",
    "Answer to a question": "إجابة عن سؤال",
    "A question asked while reading": "سؤال طُرح أثناء القراءة",
    "From an imported file": "من ملف مستورد",
    "Comfort line": "عبارة للمواساة",
    "Saved words": "كلمات محفوظة",
    "Playing": "قيد التشغيل", "Paused": "متوقف مؤقتًا", "Finished": "انتهى المقطع",
    "Play": "تشغيل", "Pause": "إيقاف مؤقت", "Replay": "إعادة التشغيل",
    "Playback position": "موضع التشغيل",
    "Keep this clip": "الاحتفاظ بالمقطع",
    "Discard": "تجاهل المقطع",
    "Clip saved": "حُفظ المقطع",
    "Audio file missing": "الملف الصوتي مفقود",
    "This audio file is not available. Playback is unavailable.": "هذا الملف الصوتي غير متاح، لذلك لا يمكن تشغيله.",
    "Create again": "إنشاء مقطع جديد",
    "All": "الكل", "All kinds": "كل الأنواع", "All experiences": "كل التجارب",
    "Filter": "تصفية", "Kind": "النوع", "Origin": "المصدر", "Experience": "التجربة",
    "Clear filters": "إلغاء التصفية",
    "Nothing saved yet": "لا توجد محفوظات بعد",
    "Clips you choose to keep will appear here.": "ستظهر هنا المقاطع التي تختار الاحتفاظ بها.",
    "No clips match this filter": "لا توجد مقاطع مطابقة",
    "Try another filter or show all clips.": "اختر تصفية أخرى أو اعرض كل المقاطع.",
    "Show all clips": "عرض كل المقاطع",
    "Delete clip": "حذف المقطع",
    "Import a text": "استيراد نص",
    "Import book": "استيراد كتاب",
    "Your bookshelf": "مكتبتك",
    "No books yet": "لا توجد كتب بعد",
    "Bring a text to read one page at a time.": "أضف نصًا لقراءته صفحةً صفحة.",
    "Only import text you have the right to have read aloud.": "لا تستورد إلا نصوصًا تملك الحق في تحويلها إلى قراءة صوتية.",
    "Importing…": "جارٍ الاستيراد…",
    "Import failed": "تعذّر الاستيراد",
    "We could not read this file. Try another supported text file.": "تعذّرت قراءة هذا الملف. جرّب ملفًا نصيًا آخر بصيغة مدعومة.",
    "Choose another file": "اختيار ملف آخر",
    "Title": "العنوان", "Pages": "الصفحات", "Pages read": "الصفحات المقروءة",
    "Whole text estimate": "التكلفة التقديرية للنص كاملًا",
    "Delete book": "حذف الكتاب",
    "Delete this book?": "هل تريد حذف هذا الكتاب؟",
    "This removes the imported text and its generated page audio.": "سيُحذف النص المستورد والمقاطع الصوتية التي أُنشئت لصفحاته.",
    "Page": "صفحة", "of": "من",
    "First page": "الصفحة الأولى", "Last page": "الصفحة الأخيرة",
    "Previous page": "الصفحة السابقة", "Next page": "الصفحة التالية",
    "Page not yet read": "لم تُقرأ هذه الصفحة بعد",
    "Page already read": "سبق إنشاء مقطع لهذه الصفحة",
    "Read this page": "قراءة هذه الصفحة",
    "Replay this page": "إعادة تشغيل هذه الصفحة",
    "From your imported text": "من النص الذي استوردته",
    "Page audio is an AI recreation of the voice.": "صوت قراءة الصفحة مُعاد إنشاؤه بالذكاء الاصطناعي.",
    "You are on the first page.": "أنت في الصفحة الأولى.",
    "You are on the last page.": "أنت في الصفحة الأخيرة.",
    "Recorded by the person": "تسجيل بصوت الشخص نفسه",
    "Created with AI": "أُنشئ بالذكاء الاصطناعي",
    "Stop and ask": "أوقِف واسأل",
    "What do you want to ask?": "ما الذي تريد أن تسأل عنه؟",
    "Ask": "اسأل", "Thinking…": "جارٍ التفكير…",
    "Say the question instead": "انطق السؤال بدلًا من كتابته",
    "Speak instead": "تحدّث بدلًا من الكتابة",
    "Writing it down…": "جارٍ تحويل الكلام إلى نص…",
    "Hear it again": "استمع مرة أخرى",
    "Continue the story": "متابعة القصة",
    "Answers are written by AI. They are not their words and not their memories.": "الإجابات يكتبها الذكاء الاصطناعي. ليست كلماتهم ولا ذكرياتهم.",
]

// MARK: - Counts

/// Live counts, in the counting language of the interface.
///
/// Arabic does not have one plural. It has singular, dual, a 3–10 form and an
/// 11-and-up form, and they take different noun endings — so translating an
/// English "1 recording / N recordings" template produces wrong Arabic at
/// almost every number. These are written out rather than pluralised by rule.
/// Numerals go through a formatter so Arabic gets Arabic-Indic digits instead
/// of a manually reversed string.
enum Counts {

    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Localization.shared.language.locale
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func originals(_ count: Int) -> String {
        guard uiIsArabic else {
            return count == 1 ? "1 original recording" : "\(number(count)) original recordings"
        }
        switch count {
        case 1:      return "تسجيل أصلي واحد"
        case 2:      return "تسجيلان أصليان"
        case 3...10: return "\(number(count)) تسجيلات أصلية"
        default:     return "\(number(count)) تسجيلًا أصليًا"
        }
    }

    static func savedClips(_ count: Int) -> String {
        guard uiIsArabic else {
            return count == 1 ? "1 saved clip" : "\(number(count)) saved clips"
        }
        switch count {
        case 1:      return "مقطع محفوظ واحد"
        case 2:      return "مقطعان محفوظان"
        case 3...10: return "\(number(count)) مقاطع محفوظة"
        default:     return "\(number(count)) مقطعًا محفوظًا"
        }
    }

    static func pagesRead(_ read: Int, of total: Int) -> String {
        uiIsArabic
            ? "\(number(read)) من \(number(total)) صفحة"
            : "\(number(read)) of \(number(total)) pages read"
    }

    /// "Page 2 of 12" — the fraction is isolated so the two numerals do not
    /// swap places around the separator in an RTL paragraph.
    static func pagePosition(_ page: Int, of total: Int) -> String {
        uiIsArabic
            ? "صفحة \(number(page)) من \(number(total))"
            : "Page \(number(page)) of \(number(total))"
    }

    static func characters(_ used: Int, limit: Int) -> String {
        "\(number(used)) / \(number(limit))"
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return L("Duration") }
        let total = Int(seconds.rounded())
        let minutes = total / 60, remainder = total % 60
        if uiIsArabic {
            return minutes > 0
                ? "\(number(minutes)) د \(number(remainder)) ث"
                : "\(number(remainder)) ثانية"
        }
        return minutes > 0 ? "\(minutes)m \(remainder)s" : "\(total)s"
    }
}
