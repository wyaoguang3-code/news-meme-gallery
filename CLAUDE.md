# 版本更新 · 每日新聞梗圖系統 — 交接文件

> 給任何一台機器上的 Claude：讀完這份你就擁有整個系統的脈絡。
> 系統本體跑在 Andy 的主力 Mac(下稱「元機」)上;這個 repo 是圖庫前端＋跨機介面。
> 最後更新:2026-08-02。

## 一句話

每天自動挑 10 則台灣新聞(排除政治)→ 寫「版本更新」遊戲 patch-notes 風格四行文案 → AI 生寫實背景圖 → 固定樣式合成梗圖 → Telegram 給 Kas 核准 → 圖庫網站展示＋會員投票 → 回饋歸因學習,越來越懂 Kas 的口味。

## 跨機介面(新機器只需要這個,不用連回元機)

- **機器可讀 feed**:`https://wyaoguang3-code.github.io/news-meme-gallery/data.json`
  每張卡:`{id, batch, date, category, topic, lines[4], status, verdicts, source, img}`
  - `status: "approved"` = Kas 核准可發佈;`rejected`/`pending` 不可發
  - `img` = 相對路徑,接在站網址後即可下載(**1080px WebP**,IG 可直接用)
- **會員投票站**:`https://news-meme-gallery.pages.dev`(Supabase Auth 登入＋審核名單制)
- **GitHub repo**:`wyaoguang3-code/news-meme-gallery`(main;`docs/` = 兩站共同源)

## IG 自動發文串接(在新機器上做)

建議架構——**只吃公開 feed,不碰元機**:
1. 定時抓 `data.json`,篩 `status == "approved"`
2. 用本地 `posted_log.json` 去重(key = `batch:id`),挑未發過的
3. 下載 `img`(1080px WebP → 轉 JPG),文案用 `lines` 四行 + `topic`,可附 hashtag
4. 發佈:Meta Graph API(需 IG Business/Creator 帳號綁 FB 粉專 + FB App 的
   `instagram_content_publish` 權限)。content_publish 流程:先 `POST /{ig-user-id}/media`
   (image_url 需公開網址——**直接用 GH Pages 的圖檔網址即可,不用另外上傳**),再
   `POST /{ig-user-id}/media_publish`
5. 排程建議每天 21:00 後(給 Kas 白天核准的時間差);**發送類 API 絕不自動重試**(見教訓)

## 元機上的元件(如果你就在元機上)

| 元件 | 位置 |
|---|---|
| 合成器(鎖定風格) | `~/.openclaw/workspace/scripts/make_weather_meme.py` + 同目錄 `NotoSansTC-Black.otf` |
| 每日批次 | `~/.openclaw/workspace/scripts/daily_meme_batch.sh`(可帶 MMDD 參數回補指定日期) |
| 回饋帳本 CLI | `~/.openclaw/workspace/scripts/meme_feedback.py`(log/record/rules/status) |
| 投票同步 | `~/.openclaw/workspace/scripts/sync_web_votes.py` |
| 心跳告警 | `~/.openclaw/workspace/scripts/meme_daily_heartbeat.sh` |
| launchd | `com.openclaw.meme.daily`(07:30)、`.votesync`(每15分)、`.heartbeat`(12:00) |
| 帳本/規則 | `~/.openclaw/workspace/output/weather_meme/feedback/{cards.jsonl,style_rules.md}` |
| OpenClaw skill | `~/.openclaw/workspace/skills/meme-feedback/`(TG 回饋處理＋名單管理) |
| 圖庫 repo | `~/news-meme-gallery/`(build_gallery.py → docs/;publish_gallery.sh 同步兩站) |

Python 一律 `/usr/bin/python3`(3.9,禁 PEP 604/585 語法)。CF Pages 部署:repo 目錄 `wrangler pages deploy`(wrangler OAuth 已登入 humaninterface2026@gmail.com)。

## Supabase(登入牆＋投票,照政治線模式)

- 專案:`ypkhjcbanfizysdnayee.supabase.co`(與 political-radar 共用;credentials 在元機
  `~/.openclaw/workspace/projects/political-radar-v2-lxy/.env`)
- 表:`gallery_allowlist`(審核名單,service_role 才能改)/`gallery_profiles`(註冊觸發器
  自動建,email 在名單→approved)/`gallery_votes`(一人一卡一票 upsert,RLS 僅 approved 可讀寫)
- migration:本 repo `supabase/gallery_001_auth_votes.sql`;跑法 = psycopg2 + SUPABASE_DB_URL
  (元機沒裝 psql/supabase CLI,別找)
- 名單現況:humaninterface2026@gmail.com(kas)、hyshih822@gmail.com(keny)

## 卡片規格(不可改的風格鎖)

- 直式 1080×1350;背景照片級寫實(禁卡通/動漫/插畫;不可有文字/人臉/品牌)
- 白色思源黑體 Black + 深色外框,左下,字級自動縮放;底部來源列
- 文案 V2 語氣:冷面 deadpan 手遊平衡性改版術語(套用/實裝/增益/減益/數值/上修/下修/
  機率/掉落率/觸發/模組/場域/BOSS/副本/冷卻),引號標主角,首行固定「版本更新：」,
  其後 3 行各 12–15 字,禁驚嘆號與「請/注意/別」PSA 口氣
- 選題紅線:**政治(政黨/選舉/政治人物/檢調弊案)一律不做**;不消費死傷與個人痛苦,
  諷刺箭頭只朝制度與加害者;每批 ≥5 個分類

## 回饋學習迴路

- 判定來源:TG 回覆(`C3 no 理由`)由 agent 依 skill record;網站投票由 sync 每 15 分收
- 帳本主鍵 `(id, batch, reviewer)`;kas 的判定決定發佈狀態,其他人是學習訊號
- 歸因引擎:退件理由分 語氣/配圖/題材/敏感/重複 五面向,**只有題材+敏感會懲罰新聞類別**;
  無理由票 → unspecified → 不產生規則(寧可不學不亂學)
- 兩人對同卡意見分歧 → 攤開待裁決,不自動套規則
- **產新卡前必讀** `style_rules.md`

## 事故教訓(踩過的坑,別再踩)

1. **絕不自動重試訊息發送**:openclaw send 逾時常已送達,retry 迴圈曾把 Kas 的 TG 洗版一整晚
2. **openclaw CLI 呼叫必須包外部硬逾時**(perl alarm):gateway degraded 時 CLI 會永久吊死,
   曾讓每日批次卡 4 天、launchd 因此跳過全部排程;`--timeout` 只管 agent 端救不了這個
3. gateway degraded(event loop p99 數秒)不會自癒 → `openclaw gateway restart`
4. 元機 shell 是 zsh:未加引號變數不斷詞,多旗標別塞變數
5. agent 生圖 prompt **不要點名工具**,讓它用原生生圖;晚落地的卡用批次的二次收帳撿回

## 新機器啟動(IG 專案)

1. 裝 Claude Code → `git clone https://github.com/wyaoguang3-code/news-meme-gallery`
   (或開新 repo,把本檔複製過去)
2. 開啟專案,Claude 會自動讀到這份 CLAUDE.md
3. 跟它說:「照 CLAUDE.md 的 IG 串接指南,幫我做 IG 自動發文」
