-- ============================================================================
-- gallery_001_auth_votes.sql — 版本更新梗圖庫：審核名單 + 個人檔案 + 具名投票
-- 跑在政治線同一個 Supabase 專案；表名以 gallery_ 前綴隔離。
-- 模式仿 political-radar migrations/002_rls_and_grants.sql：
--   - auto-expose OFF → 顯式 GRANT
--   - 寫入預設只有 service_role；authenticated 依 RLS 限制
-- ============================================================================

-- 1. 審核名單：只有 service_role 能改（= Kas 透過本機腳本/agent 管理）
CREATE TABLE IF NOT EXISTS gallery_allowlist (
  email    text PRIMARY KEY,
  note     text,
  added_at timestamptz NOT NULL DEFAULT now()
);

-- 2. 個人檔案：註冊時觸發器自動建；approved = email 是否在審核名單
CREATE TABLE IF NOT EXISTS gallery_profiles (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      text NOT NULL,
  approved   boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION handle_gallery_signup()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.gallery_profiles (user_id, email, approved)
  VALUES (NEW.id, NEW.email,
          EXISTS (SELECT 1 FROM public.gallery_allowlist a
                  WHERE lower(a.email) = lower(NEW.email)))
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS on_auth_user_created_gallery ON auth.users;
CREATE TRIGGER on_auth_user_created_gallery
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_gallery_signup();

-- 3. 投票：一人一卡一票（upsert 改票）
CREATE TABLE IF NOT EXISTS gallery_votes (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch      text NOT NULL,
  card       text NOT NULL,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  email      text NOT NULL,
  verdict    text NOT NULL CHECK (verdict IN ('ok','no')),
  reason     text NOT NULL DEFAULT '',
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (batch, card, user_id)
);

CREATE OR REPLACE FUNCTION touch_gallery_vote()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

DROP TRIGGER IF EXISTS gallery_votes_touch ON gallery_votes;
CREATE TRIGGER gallery_votes_touch
  BEFORE UPDATE ON gallery_votes
  FOR EACH ROW EXECUTE FUNCTION touch_gallery_vote();

-- 4. RLS
ALTER TABLE gallery_allowlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE gallery_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE gallery_votes     ENABLE ROW LEVEL SECURITY;

-- allowlist：前端角色全不可見（service_role 繞過 RLS）
-- profiles：本人只能讀自己那列（拿 approved 狀態）
DROP POLICY IF EXISTS "read own profile" ON gallery_profiles;
CREATE POLICY "read own profile" ON gallery_profiles
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- votes：審核通過者可讀全部票；只能寫/改自己的票
DROP POLICY IF EXISTS "approved read votes" ON gallery_votes;
CREATE POLICY "approved read votes" ON gallery_votes
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM gallery_profiles p
                 WHERE p.user_id = auth.uid() AND p.approved));

DROP POLICY IF EXISTS "approved insert own vote" ON gallery_votes;
CREATE POLICY "approved insert own vote" ON gallery_votes
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM gallery_profiles p
                WHERE p.user_id = auth.uid() AND p.approved));

DROP POLICY IF EXISTS "approved update own vote" ON gallery_votes;
CREATE POLICY "approved update own vote" ON gallery_votes
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM gallery_profiles p
                WHERE p.user_id = auth.uid() AND p.approved));

-- 顯式 GRANT（專案 auto-expose OFF）
GRANT SELECT ON gallery_profiles TO authenticated;
GRANT SELECT, INSERT, UPDATE ON gallery_votes TO authenticated;

-- 5. 預先核准的名單（owner + keny；之後增減由 service_role 腳本管理）
INSERT INTO gallery_allowlist (email, note) VALUES
  ('humaninterface2026@gmail.com', 'owner / kas'),
  ('hyshih822@gmail.com', 'keny')
ON CONFLICT (email) DO NOTHING;

-- 已存在的帳號回填 approved
UPDATE gallery_profiles p SET approved = true
WHERE EXISTS (SELECT 1 FROM gallery_allowlist a
              WHERE lower(a.email) = lower(p.email));
