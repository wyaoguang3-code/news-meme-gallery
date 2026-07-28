#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_gallery.py -- 把回饋帳本 cards.jsonl 轉成靜態瀑布流圖庫 (docs/)。

流程：
  1. 讀 ~/.openclaw/workspace/output/weather_meme/feedback/cards.jsonl
  2. 以 (id, batch) 去重（多評審時以 kas 的判定為發佈依據，其他人的判定列為參考）
  3. 每張卡輸出壓縮過的 WebP（寬 720，原檔 ~1.8MB → ~100KB）到 docs/cards/<batch>/
  4. 產 docs/data.json 給前端渲染

Python 3.9 相容。每天產完卡跑一次即可（冪等，可重跑）。
"""
import json
import os
import time

from PIL import Image

LEDGER = "/Users/andy/.openclaw/workspace/output/weather_meme/feedback/cards.jsonl"
HERE = os.path.dirname(os.path.abspath(__file__))
DOCS = os.path.join(HERE, "docs")
CARDS_DIR = os.path.join(DOCS, "cards")
OWNER = "kas"          # 誰的判定決定「能不能發」
WEB_WIDTH = 720
WEBP_QUALITY = 82


def read_ledger():
    rows = []
    if not os.path.exists(LEDGER):
        return rows
    with open(LEDGER, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def dedupe(rows):
    """(id,batch) 一組；owner 判定優先，其餘評審的判定收進 verdicts。"""
    groups = {}
    for r in rows:
        key = (r.get("id"), r.get("batch"))
        groups.setdefault(key, []).append(r)
    items = []
    for key in groups:
        g = groups[key]
        primary = None
        for r in g:
            if (r.get("reviewer") or OWNER) == OWNER:
                primary = r
                break
        if primary is None:
            primary = g[0]
        verdicts = {}
        for r in g:
            rev = r.get("reviewer") or OWNER
            v = r.get("status", "pending")
            if r.get("reason"):
                v = "%s（%s）" % (v, r["reason"])
            verdicts[rev] = v
        primary = dict(primary)
        primary["verdicts"] = verdicts
        items.append(primary)
    return items


def optimize_image(src, dst):
    """寬 720 WebP；來源沒變就不重做（拿 mtime 當簡易快取）。"""
    if not (src and os.path.exists(src)):
        return False
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return True
    img = Image.open(src).convert("RGB")
    if img.width > WEB_WIDTH:
        h = int(round(img.height * (WEB_WIDTH / float(img.width))))
        img = img.resize((WEB_WIDTH, h), Image.LANCZOS)
    if not os.path.isdir(os.path.dirname(dst)):
        os.makedirs(os.path.dirname(dst))
    img.save(dst, "WEBP", quality=WEBP_QUALITY)
    return True


def main():
    rows = read_ledger()
    items = dedupe(rows)
    out = []
    for r in items:
        batch = r.get("batch") or "misc"
        cid = r.get("id") or "X"
        rel = "cards/%s/%s.webp" % (batch, cid)
        ok = optimize_image(r.get("card"), os.path.join(DOCS, rel))
        if not ok:
            continue
        # 日期以 batch（MMDD＝新聞日期）為準，回補舊日新聞才不會全掛在「今天」
        date = ""
        if r.get("logged_at"):
            date = time.strftime("%Y-%m-%d", time.localtime(r["logged_at"]))
        if len(batch) == 4 and batch.isdigit():
            year = date[:4] if date else time.strftime("%Y")
            date = "%s-%s-%s" % (year, batch[:2], batch[2:])
        out.append({
            "id": cid,
            "batch": batch,
            "date": date,
            "category": r.get("category") or "未分類",
            "topic": r.get("topic") or "",
            "lines": r.get("lines") or [],
            "status": r.get("status") or "pending",
            "verdicts": r.get("verdicts") or {},
            "source": r.get("source") or "",
            "img": rel,
        })
    # 新的在前
    out.sort(key=lambda x: (x["date"], x["batch"], x["id"]), reverse=True)
    with open(os.path.join(DOCS, "data.json"), "w") as fh:
        json.dump({"generated_at": int(time.time()), "cards": out},
                  fh, ensure_ascii=False, indent=1)
    print("gallery: %d cards -> docs/data.json" % len(out))


if __name__ == "__main__":
    main()
