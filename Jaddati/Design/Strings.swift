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

    // The rebuilt navigation: People, Letters and You, and a person screen
    // that offers one action instead of seven rows.
    "Letters": "رسائل",
    "Dark mode": "الوضع الداكن",
    "This archive is too large to send by code. Use the file instead.": "هذا الأرشيف أكبر من أن يُرسَل برمز. استخدم الملف بدلًا من ذلك.",
    "No archive for that code. Codes last a day.": "لا يوجد أرشيف بهذا الرمز. تدوم الرموز يومًا واحدًا.",
    "That code could not be checked. Try again.": "تعذّر التحقّق من هذا الرمز. حاول مرة أخرى.",
    "A code needs the internet. Use the file instead.": "يحتاج الرمز إلى اتصال بالإنترنت. استخدم الملف بدلًا من ذلك.",
    "The code could not be created. Try again.": "تعذّر إنشاء الرمز. حاول مرة أخرى.",
    "Read them this:": "اقرأ لهم هذا:",
    "They open Jaddati, choose Bring someone from another phone, and type it.": "يفتحون جدّتي، ويختارون «أحضر شخصًا من هاتف آخر»، ثم يكتبونه.",
    "The code works for a day.": "يعمل الرمز لمدة يوم واحد.",
    "Save it as a file instead": "احفظه كملف بدلًا من ذلك",
    "Their code": "رمزهم",
    "Backup": "النسخ الاحتياطي",
    "Sign in with Google": "تسجيل الدخول بجوجل",
    "Sign out of Google": "تسجيل الخروج من جوجل",
    "Signed in": "تم تسجيل الدخول",
    "Back up now": "انسخ احتياطيًا الآن",
    "Bring everything back": "استعد كل شيء",
    "Working…": "جارٍ العمل…",
    "Backed up.": "تم النسخ الاحتياطي.",
    "Brought back.": "تمت الاستعادة.",
    "Some were too large and were left out.": "بعضها كان كبيرًا جدًا فتُرك خارجًا.",
    "That did not work. Try again.": "لم ينجح ذلك. حاول مرة أخرى.",
    "Keep a copy of the people you hold here in your own Google Drive, so a lost phone is not a lost voice.": "احتفظ بنسخة من الأشخاص الذين تحفظهم هنا في جوجل درايف الخاص بك، حتى لا يعني فقدان الهاتف فقدان الصوت.",
    "This is not how you give someone to the family — that is the code on their Setup screen. A backup goes to your Drive and nobody else's.": "هذه ليست طريقة إعطاء شخص للعائلة — تلك هي الرمز في شاشة الإعداد الخاصة به. النسخة الاحتياطية تذهب إلى درايفك وحدك.",
    "Signing in is not set up on this build.": "تسجيل الدخول غير مُعدّ في هذه النسخة.",
    "That sign-in could not be completed. Try again.": "تعذّر إكمال تسجيل الدخول. حاول مرة أخرى.",
    "Sign in to Google first.": "سجّل الدخول بجوجل أولًا.",
    "Google access has ended. Sign in again.": "انتهى وصول جوجل. سجّل الدخول مرة أخرى.",
    "Google Drive refused that. Try again.": "رفض جوجل درايف ذلك. حاول مرة أخرى.",
    "Send the file": "أرسل الملف",
    "Enter their code": "أدخل رمزهم",
    "Bring them in": "أحضرهم",
    "Looking…": "جارٍ البحث…",
    "Bring them in from a file instead": "أحضرهم من ملف بدلًا من ذلك",
    "On the phone that has them, open that person, tap the gear, and choose Give this to the family. Type the code it shows here.": "على الهاتف الذي يحتويهم، افتح ذلك الشخص، واضغط على الترس، ثم اختر «أعطِ هذا للعائلة». اكتب الرمز الذي يظهر هنا.",
    "Give another family member a short code. It carries this person, your notes, anything still sealed, and the recreated voice itself — so they can hear them straight away without making the voice a second time.": "أعطِ فردًا آخر من العائلة رمزًا قصيرًا. يحمل هذا الشخص، وملاحظاتك، وكل ما لا يزال مختومًا، والصوت المُعاد إنشاؤه نفسه — ليسمعوه فورًا دون إنشاء الصوت مرة ثانية.",
    "Voices made here are removed automatically about every ten minutes, so that everyone seeing the demonstration gets a turn. The recording you add stays on this device.": "تُحذف الأصوات المُنشأة هنا تلقائيًا كل عشر دقائق تقريبًا، ليحصل كل من يشاهد العرض على دوره. أما التسجيل الذي تضيفه فيبقى على هذا الجهاز.",
    "Change the language?": "تغيير اللغة؟",
    "Everything changes, including what is on screen now.": "يتغيّر كل شيء، بما في ذلك ما يظهر على الشاشة الآن.",
    "Arabic lays the whole app out right to left.": "العربية تعرض التطبيق كاملًا من اليمين إلى اليسار.",
    "The app opens light. This keeps it dark.": "يفتح التطبيق فاتحًا. هذا يبقيه داكنًا.",
    "You": "أنت",
    "This app": "هذا التطبيق",
    "Setup": "الإعداد",
    "Their voice": "صوته",
    "Replace their voice": "استبدال صوته",
    "Check if it is ready": "تحقّق إن كان جاهزًا",
    "Type the words. Hear them in their voice.": "اكتب الكلمات، واسمعها بصوته.",
    "They are still here? Record them now": "ما زال معك؟ سجّل صوته الآن",
    "Bring them a text": "أحضر له نصًا",
    "For a day you choose": "ليوم تختاره",
    "A letter": "رسالة",
    "No letters yet": "لا رسائل بعد",
    "Words you seal now and hear on a day you choose.": "كلمات تختمها الآن وتسمعها في يوم تختاره.",
    "Open someone and write words for a day that has not come yet.": "افتح شخصًا واكتب له كلمات ليوم لم يأتِ بعد.",
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
    "This build has no voice service key, so no new audio can be created. Original recordings still play.": "لا يحتوي هذا الإصدار على مفتاح خدمة الصوت، لذا لا يمكن إنشاء مقاطع جديدة. التسجيلات الأصلية ما زالت تُشغَّل.",
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
        "Deleting from Jaddati does not confirm deletion by the voice service.": "الحذف من تطبيق جدّتي لا يؤكّد أن خدمة الصوت حذفت بياناتها.",
    "Delete permanently": "الحذف نهائيًا",
    "Say something": "كلمات تختارها",

    // From the adversarial review.
    "Keep this as a memory": "احفظ هذا كذكرى",
    "Kept as a memory.": "حُفظ كذكرى.",
    "What your family has written down": "ما دوّنته عائلتك",
    "These are what an answer is built from, and nothing else is.": "من هذه وحدها تُبنى الإجابة، ولا شيء غيرها.",
    "Remove this memory?": "إزالة هذه الذكرى؟",
    "It will no longer be used to answer questions about them.": "لن تُستخدم بعد الآن للإجابة عن الأسئلة عنه.",
    "This person came from another family member's phone, so the voice is shared. It is left alone at the voice service — removing it here would take it from everyone who has them.": "جاء هذا الشخص من جهاز فرد آخر في العائلة، فالصوت مشترك. ولذلك يُترك كما هو لدى خدمة الصوت — فحذفه من هنا يسلبه من كل من لديه هذا الشخص.",
    "some original recordings could not be saved.": "تعذّر حفظ بعض التسجيلات الأصلية.",
    "That screen could not be opened. Nothing has been deleted.": "تعذّر فتح هذه الشاشة. ولم يُحذف شيء.",

    // Recorded before it is needed.
    "Recorded before it is needed": "سُجّل قبل الحاجة إليه",
    "Ask for the recording while they are still here to give it": "اطلب التسجيل ما دام قادرًا على إعطائه",
    "While they are\nstill here.": "ما داموا\nهنا بعد.",
    "Most families find they have nothing usable — a few seconds of someone laughing behind a video, and that is all. These are worth having whatever happens, and together they are what a voice needs.": "تكتشف معظم العائلات أنه لا يوجد لديها ما يصلح — ثوانٍ من ضحكة خلف مقطع مصوّر، وهذا كل شيء. هذه التسجيلات تستحق الاقتناء مهما حدث، وهي مجتمعةً ما يحتاجه الصوت.",
    "Nothing here is sent anywhere. These are recordings, kept on this phone like any other.": "لا يُرسَل شيء من هنا إلى أي جهة. هذه تسجيلات تُحفظ على هذا الجهاز كغيرها.",
    "Record this": "سجّل هذا",
    "Stop recording": "إيقاف التسجيل",
    "Recorded": "مُسجَّل",
    "Say the name of everyone in the family, one by one, the way you always say them.": "اذكر اسم كل فرد في العائلة، واحدًا واحدًا، بالطريقة التي تناديهم بها دائمًا.",
    "Tell the story of how you met — take your time with it.": "احكِ قصة كيف تقابلتما — وخذ وقتك فيها.",
    "Describe the house you grew up in, room by room.": "صف البيت الذي نشأت فيه، غرفة غرفة.",
    "Talk me through making the dish you are known for.": "اشرح لي طريقة تحضير الأكلة التي تشتهر بها.",
    "What would you want said at a wedding, years from now?": "ماذا تودّ أن يُقال في عرس بعد سنوات من الآن؟",
    "Read a page of anything at all, in your ordinary reading voice.": "اقرأ صفحة من أي شيء، بصوت القراءة المعتاد لديك.",

    // One voice, the whole family.
    "One voice, the whole family": "صوت واحد، والعائلة كلها",
    "Give this to the family": "أعطِ هذا للعائلة",
    "Bring someone from another phone": "أحضر شخصًا من جهاز آخر",
    "Make a file another family member can open on their own phone. It carries this person, your notes, anything still sealed, and the recreated voice itself — so they can hear them straight away without making the voice a second time.": "أنشئ ملفًا يفتحه فرد آخر من العائلة على جهازه. يحمل الملف هذا الشخص، ومذكراتك، وكل ما لا يزال مختومًا، والصوت المُعاد إنشاؤه نفسه — ليسمعه فورًا دون إنشاء الصوت مرة ثانية.",
    "Clips already created are not included. They can be made again on the other phone.": "لا تُضمَّن المقاطع التي أُنشئت من قبل. ويمكن إنشاؤها مجددًا على الجهاز الآخر.",
    "Preparing…": "جارٍ التحضير…",
    "Ready to send.": "جاهز للإرسال.",
    "Some recordings could not be read from this phone and were left out.": "تعذّرت قراءة بعض التسجيلات من هذا الجهاز فلم تُضمَّن.",
    "Make it again, with the latest": "أنشئه من جديد بأحدث ما لديك",
    "Ready to send. No original recordings were included.": "جاهز للإرسال. لم تُضمَّن أي تسجيلات أصلية.",
    "Sent without some recordings — the file would have been too large.": "أُرسل دون بعض التسجيلات — كان حجم الملف سيصبح كبيرًا جدًا.",
    "Brought in": "أُحضر",
    "That file is not a Jaddati archive.": "هذا الملف ليس أرشيف جدّتي.",
    "That archive was made by a newer version of Jaddati. Update this one first.": "أُنشئ هذا الأرشيف بإصدار أحدث من جدّتي. حدّث هذا الإصدار أولًا.",
    "That archive has no one in it.": "لا يوجد أحد في هذا الأرشيف.",
    "That person could not be found.": "تعذّر العثور على هذا الشخص.",
    "That file could not be read.": "تعذّرت قراءة هذا الملف.",

    // Words that arrive later.
    "Words that arrive later": "كلمات تصل لاحقًا",
    "Sealed now.\nHeard later.": "تُختم الآن.\nوتُسمع لاحقًا.",
    "Write something now and choose the day it can be heard. Nothing is created until you open it, and until then the words stay sealed on this phone.": "اكتب شيئًا الآن واختر اليوم الذي يمكن سماعه فيه. لا يُنشأ شيء حتى تفتحه، وتبقى الكلمات حتى ذلك الحين مختومة على هذا الجهاز.",
    "Sealed now, heard on a day you choose": "تُختم الآن، وتُسمع في يوم تختاره",
    "Write what they should say when the day comes…": "اكتب ما تريد أن يقوله عندما يحين اليوم…",
    "A birthday, a graduation, a wedding…": "عيد ميلاد، تخرّج، زفاف…",
    "Seal it": "اختمها",
    "Sealed. It will be here on the day.": "خُتمت. ستكون هنا في يومها.",
    "Sealed on": "خُتمت في",
    "A letter for today": "رسالة لهذا اليوم",
    "Ready": "جاهزة",
    "Open it": "افتحها",
    "Opening…": "أفتحها…",
    "Sealed words": "كلمات مختومة",
    "Sealed until the day": "مختومة حتى اليوم المحدد",
    "Remove this letter?": "إزالة هذه الرسالة؟",
    "Remove": "إزالة",
    "The words are deleted from this phone. This cannot be undone.": "تُحذف الكلمات من هذا الجهاز. ولا يمكن التراجع عن ذلك.",
    "Waiting for you": "بانتظارك",
    "Seal something new": "اختم شيئًا جديدًا",
    "The occasion": "المناسبة",
    "The day it can be heard": "اليوم الذي يمكن سماعها فيه",
    "Sealed": "مختومة",
    "Already opened": "فُتحت من قبل",
    "Nothing sealed yet": "لا شيء مختوم بعد",
    "Write something for a day that has not come.": "اكتب شيئًا ليومٍ لم يأتِ بعد.",

    // The two experiences added for the 2026 contest build.
    "Ask about them": "اسأل عنه",
    "Say it in their language": "قلها بلغته",
    "A question, answered only from what your family wrote down": "سؤال، تُجاب عنه من مذكرات عائلتك وحدها",
    "Your words, carried across the language they spoke": "كلماتك، محمولة إلى اللغة التي كان يتحدثها",
    "What the family\nwrote down.": "ما دوّنته\nالعائلة.",
    "Across the\nlanguage.": "عبر\nاللغة.",
    "The answer is assembled only from the memories your family has written here. If the answer is not among them, it says so rather than inventing one.": "تُبنى الإجابة من الذكريات التي دوّنتها عائلتك هنا وحدها. وإن لم تكن الإجابة بينها، قيل لك ذلك بدل اختلاق إجابة.",
    "Write in either language. It is spoken in the other, in a recreated voice.": "اكتب بأي من اللغتين. ويُنطق النص باللغة الأخرى، بصوت مُعاد إنشاؤه.",
    "Assembled from your family's notes. Nothing here was invented.": "مبنيّ على مذكرات عائلتك. لم يُختلق شيء هنا.",
    "A translation of your words, not their own phrasing.": "ترجمة لكلماتك، وليست صياغته هو.",
    "From your family's notes": "من مذكرات عائلتك",
    "Translated words": "كلمات مترجمة",
    "That is not in the memories your family has written down. Add it under Words & memories and ask again.": "هذا ليس ضمن الذكريات التي دوّنتها عائلتك. أضفه في «كلمات وذكريات» ثم اسأل مجددًا.",
    "Ask a question about them.": "اطرح سؤالًا عنه.",
    "Write something to carry across.": "اكتب شيئًا ليُحمل إلى اللغة الأخرى.",
    "You asked:": "سألت:",
    "You wrote:": "كتبت:",
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
    "If the person has died, this app requires authorization from the family or the representative responsible for granting it. Jaddati cannot verify that authorization.": "إذا كان صاحب الصوت متوفّى، يشترط هذا التطبيق وجود صلاحية من أسرته أو من الممثّل المسؤول عن منحها. لا يستطيع تطبيق جدّتي التحقّق من هذه الصلاحية.",
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
    "How it is spoken": "الأسلوب",
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
    "Discard": "حذف المقطع",
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

    // MARK: Chrome, confirmations and every failure the user can see
    //
    // These were English-only. An Arabic demo fell back into English at exactly
    // the moment it mattered — the moment something went wrong on stage.
    "Go to People": "الذهاب إلى الأشخاص",
    "Add photo": "إضافة صورة",
    "Change photo": "تغيير الصورة",
    "Remove photo": "إزالة الصورة",
    "Remove this person": "إزالة هذا الشخص",
    "This removes their profile, original recordings, saved clips and imported books from Jaddati.": "سيُحذف الملف والتسجيلات الأصلية والمقاطع المحفوظة والكتب المستوردة من تطبيق جدّتي.",
    "Choose a line": "اختر عبارة",
    "Type something for them to say.": "اكتب كلمات ليقولوها.",
    "Choose a story, or write your own.": "اختر قصة، أو اكتب قصتك.",
    "An invented story. Not a real memory.": "قصة متخيّلة، وليست ذكرى حقيقية.",
    "Read from a file you provided.": "تُقرأ من ملف قدّمته أنت.",
    "Faster, slightly plainer voice": "أسرع، بصوت أقل تعبيرًا",
    "Comfort you have kept": "كلمات المواساة التي حفظتها",
    "Stories you have kept": "القصص التي حفظتها",
    "Everything you have kept": "كل ما حفظته",
    "Tell me a story": "احكِ لي قصة",
    "FAMILY SHELF": "رفّ العائلة",
    "USD": "دولار",
    "Estimated remaining cost": "التكلفة المتبقية التقديرية",
    "Untitled book": "كتاب بلا عنوان",
    "Book removed": "حُذف الكتاب",
    "This book is no longer on the phone.": "لم يعد هذا الكتاب على الهاتف.",
    "Delete book and its audio": "حذف الكتاب ومقاطعه الصوتية",
    "There is nothing on this page to read.": "لا يوجد نص في هذه الصفحة لقراءته.",
    "Discard this clip?": "هل تريد حذف هذا المقطع؟",
    "The audio is deleted from this phone. Creating it again costs credits.": "سيُحذف المقطع من هذا الهاتف، وإنشاؤه من جديد يستهلك رصيدًا.",
    "Recorded just now": "سُجِّل الآن",
    "Discard recording": "حذف التسجيل",
    "Stop": "إيقاف",
    "Checking…": "جارٍ التحقّق…",
    "Checking asks the service to say one short word.": "التحقّق يطلب من الخدمة نطق كلمة واحدة قصيرة.",
    "The service has not made this voice available yet.": "لم تُتِح الخدمة هذا الصوت بعد.",
    "Hello": "مرحبًا",

    // Failures
    "Something went wrong. Try again.": "حدث خطأ ما. حاول مجددًا.",
    "The audio arrived but could not be saved to this phone.": "وصل المقطع الصوتي لكن تعذّر حفظه على هذا الهاتف.",
    "The page was read but the audio could not be saved to this phone.": "قُرئت الصفحة لكن تعذّر حفظ المقطع على هذا الهاتف.",
    "The answer was written but the audio could not be saved to this phone.": "كُتبت الإجابة لكن تعذّر حفظ المقطع على هذا الهاتف.",
    "That page could not be read. Try again.": "تعذّرت قراءة هذه الصفحة. حاول مجددًا.",
    "That question could not be answered. Try again.": "تعذّرت الإجابة عن هذا السؤال. حاول مجددًا.",
    "That file could not be opened.": "تعذّر فتح هذا الملف.",
    "That file could not be read from its location.": "تعذّرت قراءة الملف من مكانه.",
    "That file could not be turned into pages.": "تعذّر تحويل هذا الملف إلى صفحات.",
    "That file could not be read as text. Plain text works best; a scanned PDF has no text in it to read.": "تعذّرت قراءة هذا الملف كنص. الملفات النصية البسيطة هي الأنسب، وملف PDF الممسوح ضوئيًا لا يحتوي على نص يمكن قراءته.",
    "There was no text in that file.": "لا يوجد نص في هذا الملف.",
    "That file is larger than this app will take. Import a chapter rather than a whole book.": "هذا الملف أكبر مما يقبله التطبيق. استورد فصلًا واحدًا بدل الكتاب كاملًا.",
    "The voice could not be created. Try again.": "تعذّر إنشاء الصوت. حاول مجددًا.",
    "The voice service is not set up on this build.": "خدمة الصوت غير مُعدّة في هذه النسخة.",
    "The voice service rejected the key on this build.": "رفضت خدمة الصوت المفتاح المستخدم في هذه النسخة.",
    "The voice service is busy. Wait a moment and try again.": "خدمة الصوت مشغولة. انتظر قليلًا ثم حاول مجددًا.",
    "The voice service took too long. Your words are still here — try again.": "استغرقت خدمة الصوت وقتًا طويلًا. كلماتك لا تزال هنا — حاول مجددًا.",
    "The voice service returned an error.": "أعادت خدمة الصوت رسالة خطأ.",
    "The voice service sent something unexpected.": "أرسلت خدمة الصوت ردًّا غير متوقّع.",
    "The voice service would not accept that recording.": "لم تقبل خدمة الصوت هذا التسجيل.",
    "Try a longer, clearer one.": "جرّب تسجيلًا أطول وأوضح.",
    "That recording could not be read from this phone. Try importing it again.": "تعذّرت قراءة هذا التسجيل من الهاتف. جرّب استيراده مرة أخرى.",
    "That voice is not available at the voice service.": "هذا الصوت غير متاح لدى خدمة الصوت.",
    "Add their voice again to create a new one.": "أضف صوتهم مرة أخرى لإنشاء صوت جديد.",
    "This month's voice credits are used up. Saved memories still play.": "نفد رصيد هذا الشهر. المقاطع المحفوظة ما زالت تُشغَّل.",
    "This phone already holds a recreated voice. Remove that person, or the voice on their Setup screen, before making another.": "هذا الهاتف يحتفظ بصوت مُعاد إنشاؤه بالفعل. احذف ذلك الشخص، أو الصوت من شاشة الإعداد، قبل إنشاء صوت آخر.",
    "Saved memories could not be read on this phone, so nothing new can be made until that is sorted out.": "تعذّرت قراءة الذكريات المحفوظة على هذا الهاتف، فلا يمكن إنشاء شيء جديد حتى تُحلّ المشكلة.",
    "Nothing was backed up.": "لم يُنسخ أي شيء احتياطيًا.",
    "Some recordings could not be read, so those people were left as they were rather than overwritten.": "تعذّرت قراءة بعض التسجيلات، فتُركت تلك النسخ كما هي بدل الكتابة فوقها.",
    "Some could not be read and were left in Drive.": "تعذّرت قراءة بعضها فبقيت في درايف.",
    "Some were already here and were left alone.": "بعضهم كان موجودًا هنا فعلًا فتُرك كما هو.",
    "This account has no free voice slots left. Remove an unused voice at the voice service, then try again.": "لم تعد في الحساب خانات أصوات متاحة. احذف صوتًا غير مستخدم لدى خدمة الصوت ثم حاول مجددًا.",
    "No connection. New audio needs the internet — saved memories still play.": "لا يوجد اتصال. إنشاء مقاطع جديدة يحتاج إلى الإنترنت — والمقاطع المحفوظة ما زالت تُشغَّل.",
    "No internet connection.": "لا يوجد اتصال بالإنترنت.",
    "Questions are not set up on this build.": "ميزة الأسئلة غير مُعدّة في هذه النسخة.",
    "The question service is busy right now. Wait a few seconds and ask again.": "خدمة الأسئلة مشغولة الآن. انتظر ثوانٍ ثم اسأل مجددًا.",
    "The question service reported a problem.": "أبلغت خدمة الأسئلة عن مشكلة.",
    "The question service replied in a shape the app did not understand.": "ردّت خدمة الأسئلة بصيغة لم يفهمها التطبيق.",
    "No answer came back. Try asking it a different way.": "لم تصل أي إجابة. جرّب صياغة السؤال بطريقة أخرى.",
    "That model is not available on this key.": "هذا النموذج غير متاح بهذا المفتاح.",
    "Speaking into the app is not set up on this build.": "ميزة التحدّث غير مُعدّة في هذه النسخة.",
    "Nothing was heard. Hold the phone closer and try again.": "لم يُسمع شيء. قرّب الهاتف وحاول مجددًا.",
    "Nothing was heard. Check the microphone and try again.": "لم يُسمع شيء. تحقّق من الميكروفون وحاول مجددًا.",
    "The transcription service is busy. Wait a few seconds and try again.": "خدمة تحويل الكلام إلى نص مشغولة. انتظر ثوانٍ ثم حاول مجددًا.",
    "The transcription came back in a shape the app did not understand.": "عاد النص بصيغة لم يفهمها التطبيق.",
    "That could not be written down. Try again.": "تعذّر تحويل الكلام إلى نص. حاول مجددًا.",
    "Microphone access is off. Turn it on in Settings.": "إذن الميكروفون غير مفعّل. فعّله من الإعدادات.",
    "Microphone access was not granted.": "لم يُمنح إذن الميكروفون.",
    "That photo could not be saved to this phone.": "تعذّر حفظ هذه الصورة على هذا الهاتف.",
    "Could not save the audio to this phone.": "تعذّر حفظ المقطع الصوتي على هذا الهاتف.",
    "Changes could not be saved.": "تعذّر حفظ التغييرات.",
    "Saved memories could not be read, so they have been set aside rather than overwritten. The audio files are still on this phone.": "تعذّرت قراءة المحفوظات، فوُضعت جانبًا بدل الكتابة فوقها. ملفات الصوت ما زالت على هذا الهاتف.",
    "Saved memories could not be read and could not be set aside, so nothing new will be saved until this is resolved. No audio has been deleted.": "تعذّرت قراءة المحفوظات وتعذّر وضعها جانبًا، فلن يُحفظ شيء جديد حتى تُحلّ المشكلة. لم يُحذف أي مقطع صوتي.",

    // Third lap: labels, confirmations and diagnostics that were still English
    "Add person": "إضافة الشخص",
    "Open book": "فتح الكتاب",
    "Import from Files": "استيراد من الملفات",
    "Words you have kept": "كلمات احتفظت بها",
    "Roughly": "نحو",
    "credits": "رصيدًا",
    "credits left to read": "رصيدًا لبقية الصفحات",
    "Not kept yet. This clip is removed when you leave.": "لم يُحفظ بعد. سيُحذف هذا المقطع عند مغادرة الشاشة.",
    "Delete this recording": "حذف هذا التسجيل",
    "Delete this recording?": "هل تريد حذف هذا التسجيل؟",
    "This is a real recording of them and the only copy on this phone. It cannot be recovered.": "هذا تسجيل حقيقي بصوتهم، وهو النسخة الوحيدة على هذا الهاتف. لا يمكن استرجاعه.",
    "Remove this line?": "هل تريد إزالة هذه العبارة؟",
    "It keeps occupying a voice slot at the voice service until you delete it there.": "يظل يشغل خانة صوت لدى خدمة الصوت إلى أن تحذفه من هناك.",
    "Keep going — about a minute is what the voice needs.": "تابع — تحتاج الخدمة إلى دقيقة تقريبًا.",
    "That is enough. Stop whenever you like.": "هذا يكفي. أوقف التسجيل متى شئت.",
    "too short to build a voice from": "أقصر من أن يُبنى منه صوت",
    "shorter than recommended": "أقصر من الطول المستحسن",
    "That recording came out silent. Nothing reached the microphone — check nothing is covering it and try again.": "جاء التسجيل صامتًا. لم يصل شيء إلى الميكروفون — تأكّد أن لا شيء يغطّيه وحاول مجددًا.",
    "The microphone could not be started.": "تعذّر تشغيل الميكروفون.",
    "That audio file is missing from this phone.": "ملف الصوت هذا غير موجود على الهاتف.",
    "This audio could not be played. It may be an unsupported format.": "تعذّر تشغيل هذا المقطع. قد تكون صيغته غير مدعومة.",
    "Playback stopped unexpectedly.": "توقّف التشغيل بشكل غير متوقّع.",
    "The key for the question service was refused.": "رُفض مفتاح خدمة الأسئلة.",
    // Stopping an upload that is already in flight
    "Stop creating the voice?": "هل تريد إيقاف إنشاء الصوت؟",
    "Stop and close": "إيقاف وإغلاق",
    "Keep waiting": "متابعة الانتظار",
    "The recording may already have reached the voice service. If it has, the voice is created and a slot is used.": "قد يكون التسجيل قد وصل إلى خدمة الصوت بالفعل. إن حدث ذلك، يكون الصوت قد أُنشئ واستُهلكت خانة من الحساب.",
    "The voice was created, but the original recording could not be saved to this phone. Import it again from the profile so it appears in the archive.": "أُنشئ الصوت، لكن تعذّر حفظ التسجيل الأصلي على هذا الهاتف. استورده مرة أخرى من صفحة الشخص ليظهر في الأرشيف.",

    // MARK: Consent, privacy and data

    "Before you begin": "قبل أن تبدأ",
    "Some of this\nleaves the phone.": "بعض هذا\nيغادر الهاتف.",
    "Jaddati can work entirely on this phone. Three things cannot, because they are done by companies outside it. Here is exactly what they are.": "يستطيع جدّتي أن يعمل داخل هذا الهاتف بالكامل. ثلاثة أشياء لا تستطيع ذلك، لأن شركات خارجه هي التي تقوم بها. وهذه هي بالضبط.",
    "Questions and dictation": "الأسئلة والإملاء",
    "The recording you choose, and the words you ask to be spoken.": "التسجيل الذي تختاره، والكلمات التي تطلب نطقها.",
    "It builds the voice and reads your words in it. The voice it builds is kept on their servers, not only here.": "تُنشئ الصوت وتقرأ كلماتك به. والصوت الذي تُنشئه يُحفظ على خوادمها، لا هنا وحده.",
    "A question typed or spoken during a story, with the page it is about — and the audio itself when you speak instead of typing.": "سؤال يُكتب أو يُقال أثناء القصة، ومعه الصفحة التي يتعلق بها — والصوت نفسه حين تتحدث بدل الكتابة.",
    "It writes the answer, and turns speech into text. It is never told whose voice will read the answer out.": "تكتب الإجابة، وتحوّل الكلام إلى نص. ولا تُخبَر أبدًا بصاحب الصوت الذي سيقرأ الإجابة.",
    "What is sent": "ما الذي يُرسَل",
    "What they do with it": "ماذا تفعل به",
    "Allow these three things": "أوافق على هذه الأمور الثلاثة",
    "Not now — keep everything on this phone": "ليس الآن — احتفظ بكل شيء في هذا الهاتف",
    "Choosing to keep everything here still opens the app. You can play recordings, add people, and keep an archive. Creating a new voice, asking questions and speaking instead of typing stay switched off until you change this.": "اختيارك الاحتفاظ بكل شيء هنا يفتح التطبيق أيضًا. يمكنك تشغيل التسجيلات وإضافة الأشخاص والاحتفاظ بأرشيف. أما إنشاء صوت جديد وطرح الأسئلة والتحدث بدل الكتابة فتبقى مغلقة حتى تغيّر هذا الاختيار.",
    "Read the full privacy notice": "اقرأ إشعار الخصوصية كاملًا",

    "What Jaddati\ndoes with data.": "ماذا يفعل جدّتي\nبالبيانات.",
    "Stays on this phone": "يبقى في هذا الهاتف",
    "Recordings you add, and every clip the app creates.": "التسجيلات التي تضيفها، وكل مقطع ينشئه التطبيق.",
    "Names, relationships and photos.": "الأسماء وصلات القرابة والصور.",
    "Which language you read the app in.": "اللغة التي تقرأ بها التطبيق.",
    "These are held in the app's own storage. There is no account, and Jaddati has no server of its own — nothing here is uploaded to us, because there is no us to upload it to.": "تُحفظ هذه في مساحة التطبيق الخاصة. لا يوجد حساب، ولا خادم خاص بجدّتي — لا يُرفع منها شيء إلينا، لأنه لا يوجد \u{201C}إلينا\u{201D} أصلًا.",
    "Sent to others, only if you allow it": "يُرسَل إلى غيرنا، وبإذنك وحدك",
    "ElevenLabs receives the recording you choose and the words you want spoken. The voice it builds is stored under this app's account there.": "تستقبل ElevenLabs التسجيل الذي تختاره والكلمات التي تريد نطقها. والصوت الذي تُنشئه يُخزَّن لديها ضمن حساب هذا التطبيق.",
    "Groq receives a question and the page it is about, and the audio when you speak instead of typing.": "تستقبل Groq السؤال والصفحة التي يتعلق بها، والصوت حين تتحدث بدل الكتابة.",
    "A code identifying this phone, so that one phone cannot use up everyone's allowance. It is not a name and is not linked to one.": "رمز يميّز هذا الهاتف، حتى لا يستهلك هاتف واحد حصة الجميع. وهو ليس اسمًا ولا مرتبطًا باسم.",
    "Both are bound by their own terms, which require them to protect what they are sent. Jaddati does not send them anything else, and does not send anything anywhere else.": "كلتاهما ملتزمة بشروطها التي تُلزمها بحماية ما يصلها. ولا يرسل جدّتي إليهما شيئًا آخر، ولا يرسل شيئًا إلى أي جهة أخرى.",
    "Keeping and deleting": "الحفظ والحذف",
    "Deleting a person here deletes their recordings and clips from this phone straight away.": "حذف شخص من هنا يحذف تسجيلاته ومقاطعه من هذا الهاتف فورًا.",
    "Removing the app removes all of it.": "وإزالة التطبيق تزيلها جميعًا.",
    "A voice built at the voice service stays there until it is deleted there. The app tells you this when it creates one, and the screen for that voice says so again.": "الصوت المُنشأ لدى خدمة الصوت يبقى هناك إلى أن يُحذف من هناك. ينبّهك التطبيق إلى ذلك عند إنشائه، وتكرّره شاشة ذلك الصوت.",
    "Neither service is asked to keep anything for Jaddati, and Jaddati keeps no copy of what it sends.": "لا يُطلب من أي من الخدمتين الاحتفاظ بشيء لحساب جدّتي، ولا يحتفظ جدّتي بنسخة مما يرسله.",
    "Your answer": "اختيارك",
    "You allowed the app to use the two services above.": "سمحت للتطبيق باستخدام الخدمتين أعلاه.",
    "Everything is being kept on this phone. Nothing is sent anywhere.": "كل شيء محفوظ في هذا الهاتف. ولا يُرسَل شيء إلى أي جهة.",
    "You chose this on": "اخترت هذا في",
    "Stop sending anything off this phone": "أوقف إرسال أي شيء خارج هذا الهاتف",
    "Allow the three things above": "اسمح بالأمور الثلاثة أعلاه",
    "Questions about any of this": "أسئلة عن أي من هذا",

    "This needs to send data to a service outside the phone, and that is currently turned off.": "يحتاج هذا إلى إرسال بيانات إلى خدمة خارج الهاتف، وهو معطَّل حاليًا.",
    "Everything is being kept on this phone, so this is switched off. You can change that under Privacy and data.": "كل شيء محفوظ في هذا الهاتف، لذلك هذه الميزة مغلقة. يمكنك تغيير ذلك من \u{201C}الخصوصية والبيانات\u{201D}.",
    "Kept on this phone": "محفوظ في هذا الهاتف",
    "Privacy and data": "الخصوصية والبيانات",
    "Two services outside this phone are in use.": "تُستخدم خدمتان خارج هذا الهاتف.",
    "Everything is being kept on this phone.": "كل شيء محفوظ في هذا الهاتف.",

    // MARK: Deleting a person, and the voice held at the provider

    "Nothing was ever sent to the voice service for this person.": "لم يُرسَل أي شيء إلى خدمة الصوت لهذا الشخص.",
    "The voice built for them is deleted from the voice service first. If that fails, nothing here is removed, so you can try again.": "يُحذف الصوت المُنشأ له من خدمة الصوت أولًا. وإذا تعذّر ذلك، لا يُحذف شيء من هنا، فيمكنك المحاولة مرة أخرى.",
    "Remove from this phone anyway?": "هل تريد الإزالة من هذا الهاتف على أي حال؟",
    "Remove from this phone": "إزالة من هذا الهاتف",
    "The voice will stay at the voice service and this app will no longer know its name, so it cannot be removed from here later.": "سيبقى الصوت لدى خدمة الصوت، ولن يعرف هذا التطبيق اسمه بعد الآن، فلن يمكن حذفه من هنا لاحقًا.",
    "Removing the voice from the voice service…": "جارٍ حذف الصوت من خدمة الصوت…",
    "The voice could not be removed from the voice service.": "تعذّر حذف الصوت من خدمة الصوت.",
    "Removing a person also deletes the voice built for them at the voice service. That happens first, and if it fails nothing here is removed, so it can be tried again.": "إزالة شخص تحذف أيضًا الصوت المُنشأ له لدى خدمة الصوت. يحدث ذلك أولًا، وإذا تعذّر لا يُحذف شيء من هنا، فيمكن إعادة المحاولة.",

    "Keep for now": "الاحتفاظ به الآن",
    "When Jaddati reaches these services through a relay we run, requests carry a code identifying this phone, so one phone cannot use up everyone's allowance. It is not a name, is not linked to one, and is not sent when the app calls the two services directly.": "حين يصل جدّتي إلى هاتين الخدمتين عبر وسيط نُشغّله، تحمل الطلبات رمزًا يميّز هذا الهاتف، حتى لا يستهلك هاتف واحد حصة الجميع. وهو ليس اسمًا ولا مرتبطًا باسم، ولا يُرسَل حين يتصل التطبيق بالخدمتين مباشرة.",
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

    /// Recordings an arriving archive was carrying that could not be read.
    ///
    /// Built here rather than with an interpolated `L()`: a key with a number
    /// inside it never matches the table, so the Arabic would never have been
    /// found. Worded without naming the person, because the Arabic verb would
    /// then have to agree with a gender the app does not know.
    static func recordingsNotRead(_ count: Int) -> String {
        let tail = uiIsArabic ? " الأصل ما يزال على الهاتف الآخر."
                              : " The originals are still only on the other phone."
        guard uiIsArabic else {
            return (count == 1
                ? "1 recording could not be read."
                : "\(number(count)) recordings could not be read.") + tail
        }
        switch count {
        case 1:      return "تعذّرت قراءة تسجيل واحد." + tail
        case 2:      return "تعذّرت قراءة تسجيلين." + tail
        case 3...10: return "تعذّرت قراءة \(number(count)) تسجيلات." + tail
        default:     return "تعذّرت قراءة \(number(count)) تسجيلًا." + tail
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

    /// The two counts the person screen's cards need. Same shapes as the web's,
    /// because the two versions have to say the same thing.
    static func books(_ count: Int) -> String {
        guard uiIsArabic else {
            return count == 1 ? "1 book" : "\(number(count)) books"
        }
        switch count {
        case 1:      return "كتاب واحد"
        case 2:      return "كتابان"
        case 3...10: return "\(number(count)) كتب"
        default:     return "\(number(count)) كتابًا"
        }
    }

    static func sealed(_ count: Int) -> String {
        guard uiIsArabic else {
            return count == 1 ? "1 sealed letter" : "\(number(count)) sealed letters"
        }
        switch count {
        case 1:      return "رسالة مختومة واحدة"
        case 2:      return "رسالتان مختومتان"
        case 3...10: return "\(number(count)) رسائل مختومة"
        default:     return "\(number(count)) رسالة مختومة"
        }
    }

    static func pagesRead(_ read: Int, of total: Int) -> String {
        guard uiIsArabic else { return "\(number(read)) of \(number(total)) pages read" }
        // The counted noun changes ending with the number, and "read" was
        // missing altogether — it said "3 of 12 pages" and stopped there.
        let pages = (3...10).contains(total) ? "صفحات" : "صفحة"
        return "قُرئت \(number(read)) من \(number(total)) \(pages)"
    }

    /// "Page 2 of 12" — the fraction is isolated so the two numerals do not
    /// swap places around the separator in an RTL paragraph.
    static func pagePosition(_ page: Int, of total: Int) -> String {
        uiIsArabic
            ? "صفحة \(number(page)) من \(number(total))"
            : "Page \(number(page)) of \(number(total))"
    }

    /// "0 / 800", and it has to stay in that order.
    ///
    /// Right to left, the bidi algorithm reorders a bare "0 / 800" into
    /// "800 / 0" — the limit sits where the count belongs, and an empty box
    /// appears to have a limit of zero. Isolating the pair as left-to-right
    /// pins it. Affects every compose screen, not only the newest.
    static func characters(_ used: Int, limit: Int) -> String {
        let pair = "\(number(used)) / \(number(limit))"
        return uiIsArabic ? "\u{2066}" + pair + "\u{2069}" : pair
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
