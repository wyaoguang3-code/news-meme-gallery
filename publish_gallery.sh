#!/bin/bash
# publish_gallery.sh -- 重建圖庫並推上 GitHub Pages。冪等、無變更就不 commit。
set -e
cd /Users/andy/news-meme-gallery
/usr/bin/python3 build_gallery.py
git add docs
if git diff --cached --quiet; then
  echo "gallery: no changes"
  exit 0
fi
git commit -q -m "gallery: update $(date +%Y-%m-%d\ %H:%M)"
git push -q origin main
echo "gallery: pushed"
