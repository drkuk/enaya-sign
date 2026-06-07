# تفعيل Supabase كـ Backend — دليل خطوة بخطوة

الهدف: تحويل المنصة من نموذج أولي يحفظ في المتصفح إلى نظام حقيقي بقاعدة بيانات ومصادقة وصلاحيات. اتبع الخطوات بالترتيب. الوقت المتوقع: ٣٠–٤٥ دقيقة.

---

## الخطوة ١ — إنشاء مشروع Supabase (مجاني)

1. ادخل https://supabase.com وسجّل بحساب GitHub أو بريد.
2. اضغط **New Project**.
3. الاسم: `enaya-contracts` — اختر منطقة قريبة (Frankfurt أو Bahrain إن توفّرت).
4. ضع كلمة مرور قوية لقاعدة البيانات واحفظها.
5. انتظر دقيقتين حتى يجهز المشروع.

## الخطوة ٢ — نسخ المفاتيح

من **Project Settings → API** انسخ:
- **Project URL** (مثل `https://abcd1234.supabase.co`)
- **anon public key** (مفتاح طويل يبدأ بـ `eyJ...`)

الصقهما في ملف `config.js`:
```js
window.ENAYA_CONFIG = {
  SUPABASE_URL: "https://abcd1234.supabase.co",
  SUPABASE_KEY: "eyJhbGci...",
  ...
};
```

> للتأكد لاحقاً أنها تعمل: افتح موقعك، اضغط F12 → Console، اكتب `window.ENAYA_CONFIG` واضغط Enter. يجب أن ترى الرابط والمفتاح، لا كلمة `PASTE_...`.

## الخطوة ٣ — بناء قاعدة البيانات

1. في Supabase افتح **SQL Editor → New query**.
2. الصق محتوى ملف `schema.sql` كاملاً.
3. اضغط **Run**. يجب أن ترى `Success`.

هذا ينشئ: جداول العملاء والعقود والتوقيعات وسجل العمليات، نظام الأدوار، ودوال الأمان.

## الخطوة ٤ — إنشاء حسابات المستخدمين (أنت + المُرسِلون)

أنت ٢–٥ أشخاص. لكل شخص:

1. افتح **Authentication → Users → Add user → Create new user**.
2. أدخل بريده (يفضّل `@enayah.org.sa`) وكلمة مرور مؤقتة.
3. كرّر لكل مُرسِل.

> ملاحظة: عطّل **Authentication → Providers → Email → "Confirm email"** مؤقتاً إن أردت دخولاً فورياً بلا تأكيد بريد، أو أبقِه مفعّلاً للأمان.

## الخطوة ٥ — تعيين الأدوار

بعد إنشاء الحسابات، افتح **SQL Editor** وشغّل لكل شخص:

```sql
-- اجعل نفسك أدمن (الصلاحية الكاملة + إدارة المستخدمين):
insert into app_users (id, email, full_name, role)
select id, email, 'اسمك الكامل', 'admin'
from auth.users where email = 'YOUR_ADMIN_EMAIL@enayah.org.sa'
on conflict (id) do update set role='admin', active=true;

-- اجعل كل مُرسِل sender (يرسل العقود فقط):
insert into app_users (id, email, full_name, role)
select id, email, 'اسم المُرسِل', 'sender'
from auth.users where email = 'sender1@enayah.org.sa'
on conflict (id) do update set role='sender', active=true;
```

من الآن: أنت ترى كل العقود وتدير المستخدمين، وكل مُرسِل يرى عقوده هو فقط.

## الخطوة ٦ — إضافة أو إيقاف مُرسِل لاحقاً

- إضافة: كرّر الخطوة ٤ ثم ٥.
- إيقاف صلاحية شخص فوراً: `update app_users set active=false where email='...';`
- ترقية شخص لأدمن: `update app_users set role='admin' where email='...';`

## الخطوة ٧ — البريد التلقائي (اختياري، بعد ما يستقر الباقي)

اتبع ملف `email-setup-plan.md` لنشر Edge Function + Resend. هذه الخطوة وحدها تجعل نسخة الـ PDF تصل للعميل تلقائياً.

---

## كيف تعرف أنك انتقلت من "واجهة فقط" إلى "نظام حقيقي"

علامات النجاح:
- توقّع عقداً على جهاز، ثم تفتح اللوحة على جهاز آخر فتجده. (لم يعد محلياً)
- مُرسِل آخر يسجّل دخوله فيرى عقوده فقط لا عقودك.
- تعديل `code` في الرابط لعقد آخر لا يكشف بياناته (RLS يمنع).
- سجل العمليات يُظهر وقت الإنشاء والفتح والتوقيع.

إن تحققت هذه — فأنت على Backend حقيقي، لا نموذج.
