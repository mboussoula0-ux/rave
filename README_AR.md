# Layan — تعديل ريف

## الملفات
- `Tweak.m` الكود، `Makefile`، `.github/workflows/build.yml` (يبني `Layan.dylib` على GitHub)
- `tools/patch_ipa.py` يغيّر اسم التطبيق تحت الأيقونة + الأيقونة (يشتغل على مجلد Rave.app المفكوك)
- `icons/` أيقونات Layan الجاهزة

## الخطوات
1. ارفع كل الملفات للريبو (مع `.github`)، شغّل Actions ← Build Layan، نزّل `Layan-dylib`.
2. فك الـ IPA، ثم: `python3 tools/patch_ipa.py Payload/Rave.app` (الاسم + الأيقونة).
3. أعد الضغط كـ IPA، وحقن `Layan.dylib` بـ Feather/ESign/Sideloadly ووقّع.

## ملاحظات
- لوقو الواجهة (35x25 فوق) يتبدل بالكود وقت التشغيل إلى نص Layan.
- لوقو شاشة الإقلاع (LaunchScreen) داخل storyboard ما يتغير بالـ dylib.
- الدعوات: صارت تتجاهل الشاشات المخفية وتختار القائمة اللي فيها أزرار دعوة. لو ما اشتغلت: افتح شاشة الدعوة، ثم الإعدادات ← متقدم ← نسخ تقرير تشخيصي (فيه قسم "invite screen") وأرسله لي.
- الكود ما انجرّب على جهاز ولا انبنى عندي (ما عندي Xcode/Theos). لو فشل البناء أرسل نص الخطأ.
