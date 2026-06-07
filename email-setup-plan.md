# إرسال نسخة PDF موقّعة تلقائياً بالإيميل — خطة التنفيذ

## لماذا هذا الجزء غير ممكن على GitHub Pages وحده

GitHub Pages يستضيف **صفحات ثابتة فقط** — لا خادم. إرسال إيميل برفق ملف يتطلب مفتاح خدمة بريد سرّياً لا يجوز وضعه في كود علني (وإلا سُرق). لذلك الإرسال التلقائي يحتاج **طبقة خادمية**. الخبر الجيد: أنت تملك Supabase أصلاً، وهي تقدّم **Edge Functions** مجاناً — وهذا هو المكان الصحيح.

النظام الحالي يفتح `mailto:` (مسودة بريد تتطلب ضغط "إرسال" يدوياً، ولا تدعم إرفاق PDF). هذا هو سبب "النسخة لا تصل".

## المعمارية المقترحة (يولّد العميل الـ PDF، والخادم يرسله فقط)

```
sign.html (المتصفح)
  ├─ يولّد PDF موقّع (html2pdf) → base64   ← جاهز عندنا الآن
  └─ يستدعي Edge Function ويمرّر: { code, pdfBase64 }
        │
        ▼
Supabase Edge Function (send-signed-contract)
  ├─ يقرأ صف العقد من قاعدة البيانات (الرقم المرجعي، إيميل العميل، إيميل المسؤول)
  ├─ يرسل الإيميل عبر Resend مع إرفاق الـ PDF (للعميل + للمسؤول)
  ├─ عنوان البريد: "تم توقيع العقد بنجاح - رقم المرجع: CNT-2026-0001"
  └─ يحدّث الصف: email_status = 'sent' | 'failed' ، email_sent_at = الوقت
```

## الخطوات

### ١) أنشئ حساب Resend وفعّل النطاق
- سجّل في resend.com (مجاني حتى ٣٠٠٠ إيميل/شهر).
- أضف نطاق `enayah.org.sa` وفعّل سجلات DNS (SPF/DKIM) ليصل البريد لصندوق الوارد لا السبام.
- أنشئ API Key.

### ٢) أضف الأعمدة لسجل حالة الإرسال
```sql
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS email_status text;
ALTER TABLE contracts ADD COLUMN IF NOT EXISTS email_sent_at timestamptz;
```

### ٣) خزّن مفتاح Resend كسرّ في Supabase
```bash
supabase secrets set RESEND_API_KEY=re_xxxxxxxxxxxx
supabase secrets set ADMIN_EMAIL=info@enayah.org.sa
```

### ٤) كود الدالة الخادمية
أنشئ `supabase/functions/send-signed-contract/index.ts`:

```ts
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const { code, pdfBase64 } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // اقرأ العقد
    const { data: rows } = await supabase
      .from("contracts").select("*").eq("code", code).limit(1);
    const c = rows?.[0];
    if (!c) return new Response("not found", { status: 404, headers: cors });

    const subject = `تم توقيع العقد بنجاح - رقم المرجع: ${c.num}`;
    const adminEmail = Deno.env.get("ADMIN_EMAIL") ?? c.notify_email;
    const attachment = { filename: `${c.num}.pdf`, content: pdfBase64 };

    // أرسل عبر Resend (نسخة للعميل ونسخة للمسؤول)
    const send = (to: string) => fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "عناية <contracts@enayah.org.sa>",
        to, subject,
        html: `<div dir="rtl">تم توقيع الاتفاقية رقم <b>${c.num}</b> بنجاح.<br>مرفق نسخة PDF موقّعة من الطرفين.</div>`,
        attachments: [attachment],
      }),
    });

    const results = await Promise.allSettled([send(c.email), send(adminEmail)]);
    const ok = results.every(r => r.status === "fulfilled");

    // سجّل الحالة
    await supabase.from("contracts").update({
      email_status: ok ? "sent" : "failed",
      email_sent_at: new Date().toISOString(),
    }).eq("code", code);

    return new Response(JSON.stringify({ ok }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ ok: false, error: String(e) }), {
      status: 500, headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
```

### ٥) انشر الدالة
```bash
supabase functions deploy send-signed-contract --no-verify-jwt
```

### ٦) اربط صفحة التوقيع بالدالة
في `sign.html` داخل `submitSignature` بعد توليد الـ PDF، استبدل مسودة `mailto` بالاستدعاء التالي:

```js
// بعد توليد PDF كـ base64 (نفس آلية downloadClientPDF لكن نُرجع base64 بدل الحفظ)
async function sendSignedEmail(pdfBase64){
  try {
    const res = await fetch(SUPABASE_URL + "/functions/v1/send-signed-contract", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": "Bearer " + SUPABASE_KEY },
      body: JSON.stringify({ code: P.code, pdfBase64 }),
    });
    const j = await res.json();
    if (j.ok) showSuccessMsg("✅ تم إرسال نسخة موقّعة لبريدك وبريد الجمعية");
    else      showSuccessMsg("⚠️ تعذّر إرسال البريد — سيتواصل معك فريق الجمعية");
  } catch(e){ showSuccessMsg("⚠️ تعذّر إرسال البريد"); }
}
```

(لتحويل الـ PDF إلى base64 بدل التحميل: استخدم `html2pdf().from(el).outputPdf('datauristring')` ثم خذ ما بعد الفاصلة.)

### ٧) النتيجة بعد التنفيذ
- إيميل تلقائي للعميل والمسؤول فور التوقيع، مع PDF مرفق.
- عنوان البريد يحمل الرقم المرجعي.
- رسالة تأكيد داخل النظام (نجاح/فشل).
- سجل `email_status` و `email_sent_at` في قاعدة البيانات — يظهر في لوحة التحكم.

## ما يعمل الآن بدون هذه الخطوة
- توليد وتنزيل نسخة PDF موقّعة يدوياً (من صفحة العميل ومن لوحة التحكم).
- إشعار واتساب فوري للمسؤول.
- مسودة بريد جاهزة (تتطلب ضغط إرسال يدوي، بلا إرفاق).
