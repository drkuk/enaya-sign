// ════════════════════════════════════════════════════════════
//  إعدادات عناية المشتركة — عدّلها هنا مرة واحدة فقط
//  يقرأ هذا الملف كلٌّ من index.html (لوحة الإرسال) و sign.html (صفحة التوقيع)
//  ضع هذا الملف في نفس مجلد الصفحتين على GitHub.
// ════════════════════════════════════════════════════════════
window.ENAYA_CONFIG = {
  // ── Supabase ──
  // رابط مشروع Supabase — مثال: https://abcd1234.supabase.co
  SUPABASE_URL: "PASTE_SUPABASE_URL_HERE",
  // مفتاح anon العام (آمن للنشر طالما أن RLS مفعّل على الجدول)
  SUPABASE_KEY: "PASTE_SUPABASE_ANON_KEY_HERE",

  // ── إشعارات التوقيع (تصلك أنت عند توقيع العميل) ──
  // رقم واتساب يستقبل الإشعار — بصيغة دولية بدون + ، مثال: 9665xxxxxxxx
  NOTIFY_WHATSAPP: "",
  // إيميل يستقبل الإشعار (اتركه فارغاً لتعطيل إشعار الإيميل)
  NOTIFY_EMAIL: "",

  // ── رابط الموقع الأساسي (لبناء رابط التوقيع المختصر) ──
  // اتركه فارغاً ليُحسب تلقائياً من عنوان الصفحة، أو اضبطه يدوياً:
  // مثال: https://drkuk.github.io/enaya-sign
  BASE_URL: ""
};

/* ════════════════════════════════════════════════════════════
   إعداد جدول Supabase لأول مرة (شغّله مرة واحدة في SQL Editor):

   CREATE TABLE contracts (
     id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
     code text UNIQUE,
     num text, type text, company text, rep text,
     jobtitle text, phone text, email text,
     addr text, lic text, tel text, po text,
     contract_date text, notify text, notify_email text,
     status text DEFAULT 'sent',
     sign_code text, signed_at text,
     created_at timestamptz DEFAULT now()
   );
   ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
   CREATE POLICY "public_all" ON contracts FOR ALL USING (true) WITH CHECK (true);

   أو إذا كان لديك جدول قديم، أضف الأعمدة الجديدة فقط:

   ALTER TABLE contracts ADD COLUMN IF NOT EXISTS code text;
   ALTER TABLE contracts ADD COLUMN IF NOT EXISTS notify text;
   ALTER TABLE contracts ADD COLUMN IF NOT EXISTS notify_email text;
   CREATE UNIQUE INDEX IF NOT EXISTS contracts_code_idx ON contracts(code);
   ════════════════════════════════════════════════════════════ */
