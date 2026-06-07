-- ════════════════════════════════════════════════════════════════════
--  منصة عناية للتوقيع الإلكتروني — مخطط قاعدة البيانات الكامل (Backend حقيقي)
--  شغّل هذا الملف كاملاً مرة واحدة في: Supabase → SQL Editor → New query → Run
--  يبني: نظام أدوار (admin / sender) + جداول + سجل عمليات + سياسات أمان RLS
-- ════════════════════════════════════════════════════════════════════

-- ───────────────────────── 1) جدول الأدوار (مرتبط بـ Supabase Auth) ─────────────────────────
-- كل مستخدم مسجّل في Auth له صف هنا يحدد دوره. أنت = admin ، البقية = sender.
create table if not exists app_users (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text,
  full_name   text,
  role        text not null default 'sender'  check (role in ('admin','sender')),
  active      boolean not null default true,
  created_at  timestamptz default now()
);

-- دالة مساعدة: هل المستخدم الحالي admin؟ (تُستخدم داخل السياسات)
create or replace function is_admin()
returns boolean language sql security definer stable as $$
  select exists(
    select 1 from app_users where id = auth.uid() and role = 'admin' and active = true
  );
$$;

-- دالة مساعدة: هل المستخدم الحالي مُرسِل مفعّل (sender أو admin)؟
create or replace function is_sender()
returns boolean language sql security definer stable as $$
  select exists(
    select 1 from app_users where id = auth.uid() and active = true
  );
$$;

-- ───────────────────────── 2) العملاء ─────────────────────────
create table if not exists clients (
  id          uuid primary key default gen_random_uuid(),
  company     text not null,
  rep         text,
  jobtitle    text,
  phone       text,
  email       text,
  lic         text,
  addr        text,
  tel         text,
  po          text,
  created_by  uuid references app_users(id),
  created_at  timestamptz default now()
);

-- ───────────────────────── 3) العقود ─────────────────────────
create table if not exists contracts (
  id            uuid primary key default gen_random_uuid(),
  code          text unique not null,            -- معرّف الرابط القصير (عشوائي)
  num           text unique not null,            -- الرقم المرجعي CNT-YYYY-NNNN
  type          text not null default 'health',  -- health | general
  client_id     uuid references clients(id),

  -- نسخة من بيانات الطرف الثاني وقت الإنشاء (لثبات العقد تاريخياً)
  company text, rep text, jobtitle text, phone text, email text,
  lic text, addr text, tel text, po text,
  contract_date text,

  status        text not null default 'sent'     check (status in ('sent','opened','signed','expired','cancelled')),
  notify        text,
  notify_email  text,

  -- التوقيع
  sign_code     text,
  signed_at     timestamptz,
  signature     text,                            -- صورة التوقيع (Data URL)
  signer_name   text,

  -- البريد
  email_status  text,                            -- sent | failed | null
  email_sent_at timestamptz,

  expires_at    timestamptz default (now() + interval '7 days'),
  created_by    uuid references app_users(id),
  created_at    timestamptz default now()
);

create index if not exists contracts_num_idx    on contracts(num);
create index if not exists contracts_code_idx   on contracts(code);
create index if not exists contracts_status_idx on contracts(status);
create index if not exists contracts_creator_idx on contracts(created_by);

-- ───────────────────────── 4) سجل العمليات (Audit Log) ─────────────────────────
create table if not exists audit_log (
  id            bigint generated always as identity primary key,
  contract_id   uuid references contracts(id) on delete cascade,
  contract_code text,
  event         text not null,   -- created | sent | opened | signed | email_sent | email_failed | cancelled
  detail        text,
  actor         uuid references app_users(id),   -- من نفّذ العملية (null للعميل)
  ip            text,
  created_at    timestamptz default now()
);
create index if not exists audit_contract_idx on audit_log(contract_id);

-- توليد الرقم المرجعي التسلسلي بأمان داخل القاعدة (يمنع التعارض)
create or replace function next_ref()
returns text language plpgsql security definer as $$
declare
  y    text := to_char(now(), 'YYYY');
  n    int;
begin
  select coalesce(max( (regexp_match(num, '(\d+)$'))[1]::int ), 0) + 1
    into n from contracts where num like 'CNT-' || y || '-%';
  return 'CNT-' || y || '-' || lpad(n::text, 4, '0');
end;
$$;

-- ════════════════════════════════════════════════════════════════════
--  5) تفعيل أمان مستوى الصف (RLS) — هذا هو قلب الحماية
-- ════════════════════════════════════════════════════════════════════
alter table app_users enable row level security;
alter table clients   enable row level security;
alter table contracts enable row level security;
alter table audit_log enable row level security;

-- ── app_users: الأدمن يدير الجميع، والمستخدم يقرأ صفّه فقط ──
drop policy if exists au_admin_all on app_users;
create policy au_admin_all on app_users for all
  using (is_admin()) with check (is_admin());

drop policy if exists au_self_read on app_users;
create policy au_self_read on app_users for select
  using (id = auth.uid());

-- ── clients: المُرسِل المفعّل يضيف/يقرأ، الأدمن يرى الكل ──
drop policy if exists cl_sender_rw on clients;
create policy cl_sender_rw on clients for all
  using (is_sender()) with check (is_sender());

-- ── contracts: المُرسِل يرى عقوده فقط، الأدمن يرى الكل ──
drop policy if exists ct_select on contracts;
create policy ct_select on contracts for select
  using ( is_admin() or created_by = auth.uid() );

drop policy if exists ct_insert on contracts;
create policy ct_insert on contracts for insert
  with check ( is_sender() and created_by = auth.uid() );

drop policy if exists ct_update on contracts;
create policy ct_update on contracts for update
  using ( is_admin() or created_by = auth.uid() )
  with check ( is_admin() or created_by = auth.uid() );

-- لا حذف عام؛ الأدمن فقط
drop policy if exists ct_delete on contracts;
create policy ct_delete on contracts for delete using ( is_admin() );

-- ── audit_log: المُرسِلون يقرؤون، الأدمن الكل، والإدراج عبر الدوال الآمنة ──
drop policy if exists al_select on audit_log;
create policy al_select on audit_log for select
  using ( is_admin() or actor = auth.uid() );

-- ════════════════════════════════════════════════════════════════════
--  6) وصول العميل الآمن (بدون تسجيل دخول) — عبر دوال SECURITY DEFINER فقط
--  العميل لا يلمس الجدول مباشرة. يصل لعقد واحد فقط عبر الـ code، ولا يرى غيره.
-- ════════════════════════════════════════════════════════════════════

-- يجلب عقداً واحداً بالـ code (الحقول العامة فقط، لا created_by ولا أسرار)
create or replace function get_contract_for_signing(p_code text)
returns table (
  code text, num text, type text, company text, rep text, jobtitle text,
  phone text, email text, lic text, addr text, tel text, po text,
  contract_date text, status text, expires_at timestamptz,
  signed_at timestamptz
) language sql security definer stable as $$
  select code, num, type, company, rep, jobtitle, phone, email, lic, addr, tel, po,
         contract_date, status, expires_at, signed_at
  from contracts
  where code = p_code
    and status <> 'cancelled'
  limit 1;
$$;

-- يسجّل فتح الرابط (status: sent → opened) + حدث في السجل
create or replace function mark_opened(p_code text)
returns void language plpgsql security definer as $$
declare cid uuid;
begin
  update contracts set status = 'opened'
    where code = p_code and status = 'sent'
    returning id into cid;
  if cid is not null then
    insert into audit_log(contract_id, contract_code, event) values (cid, p_code, 'opened');
  end if;
end;
$$;

-- يثبّت التوقيع (يقبل فقط إن لم يكن موقّعاً ولم تنتهِ الصلاحية)
create or replace function submit_signature(
  p_code text, p_sign_code text, p_signature text, p_signer_name text
) returns table(ok boolean, ref text) language plpgsql security definer as $$
declare c contracts%rowtype;
begin
  select * into c from contracts where code = p_code limit 1;
  if c.id is null then return query select false, null::text; return; end if;
  if c.status = 'signed' then return query select false, c.num; return; end if;
  if c.expires_at < now() then
    update contracts set status='expired' where id = c.id;
    return query select false, c.num; return;
  end if;

  update contracts set
    status = 'signed', sign_code = p_sign_code, signed_at = now(),
    signature = p_signature, signer_name = p_signer_name
  where id = c.id;

  insert into audit_log(contract_id, contract_code, event, detail)
    values (c.id, p_code, 'signed', 'sign_code=' || p_sign_code);

  return query select true, c.num;
end;
$$;

-- اسمح للعميل المجهول (anon) باستدعاء هذه الدوال الثلاث فقط — لا شيء غيرها
grant execute on function get_contract_for_signing(text) to anon, authenticated;
grant execute on function mark_opened(text)              to anon, authenticated;
grant execute on function submit_signature(text,text,text,text) to anon, authenticated;
grant execute on function next_ref()                    to authenticated;

-- ════════════════════════════════════════════════════════════════════
--  7) تعيين نفسك كأدمن (بعد إنشاء حسابك في Authentication)
--  بدّل البريد ببريدك، ثم شغّل هذا السطر:
-- ════════════════════════════════════════════════════════════════════
-- insert into app_users (id, email, full_name, role)
-- select id, email, 'الاسم الكامل', 'admin' from auth.users where email = 'YOUR_ADMIN_EMAIL@enayah.org.sa'
-- on conflict (id) do update set role = 'admin', active = true;
