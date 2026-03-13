# Performance Debt: Asset Optimization

## Problem

The `assets/images/` directory contains **92.33 MB** of unoptimized JPG/PNG files bundled into the Flutter web build. While these are fetched on demand (not all at once), each image is 2-5 MB, which crushes mobile users on cellular connections.

## Current State (37 image files)

| File | Size |
|---|---|
| Standard Room/Standard 3.jpg | 5.49 MB |
| Classic Room/Classic 5.jpg | 5.23 MB |
| Front View/Front View 3.jpg | 4.02 MB |
| Front View/Front View 5.JPG | 3.70 MB |
| Passage/Passage 1.jpg | 3.37 MB |
| Outside bar/Outside Bar 2.jpg | 3.33 MB |
| Front View/Front View 6.jpg | 3.02 MB |
| Front View/Front View 4.jpg | 2.93 MB |
| Outside bar/Outside Bar 1.JPG | 2.79 MB |
| VIP Bar/VIP Bar 1.JPG | 2.75 MB |
| Executive Room/Executive 3.jpg | 2.70 MB |
| Reception/Reception 4.jpg | 2.57 MB |
| Restaurant/Restaurant 1.jpg | 2.57 MB |
| Reception/Reception 2.png | 2.49 MB |
| Classic Room/Classic 4.JPG | 2.46 MB |
| *(22 more files, all 1-2.5 MB)* | |
| **Total** | **92.33 MB** |

## Recommended Fix (Next Sprint)

### Option A: Compress in-place (quick win)
- Resize all images to max 1200px wide (sufficient for web display).
- Convert to WebP or compress JPEG to quality 75-80%.
- Target: each file under 500 KB. Total under 15 MB.

### Option B: Move to Supabase Storage (long-term)
- Upload images to a Supabase Storage bucket with a public URL.
- Use `cached_network_image` (already a dependency) to load them.
- Remove from `pubspec.yaml` assets. Bundle size drops to near-zero for images.
- Guest pages load faster (CDN edge caching).

## Notes

- No custom fonts (.ttf/.otf/.woff) are bundled. Material Icons only.
- CanvasKit is NOT forced; Flutter 3.35.x uses `auto` mode (HTML on mobile, CanvasKit on desktop). No change needed.
- The -O0 to -O2 build flag change (Mar 2026) fixed the mobile OOM crash. This asset work is the next optimization target.
