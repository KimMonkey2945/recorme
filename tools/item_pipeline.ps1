# =============================================================================
# 캐릭터 꾸미기 아이템 파이프라인 (통합)
#
# 사용법:  powershell -ExecutionPolicy Bypass -File tools\item_pipeline.ps1
#          (특정 캐릭터만:  ... -Characters monkey  /  -Characters panda)
#
# 입력:
#   docs/recormeImo/item/{hat,glasses}/*.png      아이템 단독 제품샷(모자·안경용)
#   docs/recormeImo/wearItem/{monkey,panda}/{hat,glasses,top,bottom,shoes}/*.png
#                                                 "그 아이템만 착용한" 완성샷(1600x2604, 검정 배경)
# 출력:
#   app/assets/items/*.png                        풀프레임 오버레이 + 썸네일(256)
#   docs/recormeImo/checks/*.png                  검증 이미지(눈으로 확인용)
#
# 방식(확정 레시피 — tasks/030 참고):
#   모자/안경 = 하이브리드: 착용샷에서 위치 실측(진검정 침식 실측/diff 다크 블롭) 후
#               깨끗한 단독 제품샷 누끼를 그 자리에 합성 (얼굴 무오염)
#   상의     = 착용샷 몸통+팔 영역 통째 교체(베이스 반바지 색 조각은 무채검정 게이트로 제거)
#   하의     = 착용샷 허리 아래 영역 통째 교체
#   신발     = 착용샷 발 영역 통째 교체(z=29로 바지 위에 그림)
#
# 새 캐릭터 추가 시: $charCfg에 한 항목 추가(topY0만 턱 높이에 맞게) + 착용샷 5장.
# 새 모자/안경 추가 시: 단독샷 1장 + (위치 실측용) 착용샷 1장 — 이미 실측된 캐릭터는 재사용 가능.
# 실행 후 docs/recormeImo/checks/ 의 이미지를 눈으로 확인하고, 이상하면 Claude에게 좌표 조정 요청.
# =============================================================================
param([string[]]$Characters = @("monkey", "panda"))
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

# ── 경로 ─────────────────────────────────────────────────────────────────────
$repo = Split-Path $PSScriptRoot -Parent
$itemDir = Join-Path $repo "docs\recormeImo\item"
$wearDir = Join-Path $repo "docs\recormeImo\wearItem"
$charsDir = Join-Path $repo "app\assets\characters"
$outDir = Join-Path $repo "app\assets\items"
$checkDir = Join-Path $repo "docs\recormeImo\checks"
New-Item -ItemType Directory -Force $checkDir | Out-Null

# ── 캐릭터/슬롯 설정 (몸 템플릿이 통일되어 대부분 공용 상수) ─────────────────
# clothesRegion: 의류를 "영역 통째 교체"로 만들지 여부.
#   착용샷의 몸이 베이스와 잘 정렬된 캐릭터만 true(판다가 그 예).
#   원숭이 착용샷은 몸 비율이 재렌더로 틀어져 있어 false — 의류는 기존 diff 방식 결과물을 유지하며
#   이 스크립트는 모자·안경(하이브리드)과 썸네일만 갱신한다.
#   새 캐릭터는 착용샷이 베이스와 잘 맞는 컷을 고르고 true로 시작할 것.
$charCfg = @{
    monkey = @{ asset = "monkey";    topY0 = 592; clothesRegion = $false }
    panda  = @{ asset = "red_panda"; topY0 = 575; clothesRegion = $true }
}
# 공용 영역 상수(848x1400 통일 프레임 기준)
$C = @{
    topY1 = 1015; armX0 = 238; armX1 = 612; armY1 = 1170   # 상의: 몸통 밴드 + 좌우 팔 기둥
    bottomY0 = 935                                          # 하의: 허리(상의 밑단 뒤)
    shoesY0 = 1220                                          # 신발: 신발 윗선
    capUpFrac = 0.092; capHScale = 0.93; capInsetFrac = 0.022  # 모자 심미 보정(실측 대비)
}
# 슬롯 → 현재 그룹 파일명 (아이템 이름 확정 시 이 표만 갱신)
$slotFile = @{
    hat = "hat_cap_black"; glasses = "glasses_round"
    top = "outfit_love_hood"; bottom = "bottom_cargo_sand"; shoes = "shoes_max95"
}

$csharp = @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections.Generic;

public static class ItemPipe
{
    // ── 공통: 검정 배경 제거(테두리 플러드필) ──
    public static Bitmap CleanBlack(string src, int thresh)
    {
        Bitmap bmp = new Bitmap(src);
        int w = bmp.Width, h = bmp.Height;
        BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = data.Stride;
        byte[] px = new byte[stride * h];
        System.Runtime.InteropServices.Marshal.Copy(data.Scan0, px, 0, px.Length);
        bool[] removed = new bool[w * h];
        Queue<int> q = new Queue<int>();
        Action<int, int> seed = delegate(int x, int y)
        {
            int i = y * w + x;
            if (removed[i]) return;
            int o = y * stride + x * 4;
            if (px[o] <= thresh && px[o + 1] <= thresh && px[o + 2] <= thresh)
            { removed[i] = true; q.Enqueue(i); }
        };
        for (int x = 0; x < w; x++) { seed(x, 0); seed(x, h - 1); }
        for (int y = 0; y < h; y++) { seed(0, y); seed(w - 1, y); }
        int[] dx = { 1, -1, 0, 0 }; int[] dy = { 0, 0, 1, -1 };
        while (q.Count > 0)
        {
            int i = q.Dequeue(); int cx = i % w, cy = i / w;
            for (int k = 0; k < 4; k++)
            {
                int nx = cx + dx[k], ny = cy + dy[k];
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                seed(nx, ny);
            }
        }
        for (int i = 0; i < w * h; i++)
            if (removed[i]) px[(i / w) * stride + (i % w) * 4 + 3] = 0;
        System.Runtime.InteropServices.Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        return bmp;
    }

    // 테두리 색 자동 샘플링 누끼(단독 제품샷용: 흰/회색 배경) + 갇힌 배경(안경 렌즈) 제거 + 트림
    public static Bitmap CutoutAuto(string src, int tol, int enclosedMinArea)
    {
        Bitmap bmp = new Bitmap(src);
        int w = bmp.Width, h = bmp.Height;
        BitmapData data = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int stride = data.Stride;
        byte[] px = new byte[stride * h];
        System.Runtime.InteropServices.Marshal.Copy(data.Scan0, px, 0, px.Length);
        long r = 0, g0 = 0, b = 0; int n = 0;
        Action<int, int> acc = delegate(int x, int y)
        { int o = y * stride + x * 4; b += px[o]; g0 += px[o + 1]; r += px[o + 2]; n++; };
        for (int x = 0; x < w; x += 3) { acc(x, 0); acc(x, h - 1); }
        for (int y = 0; y < h; y += 3) { acc(0, y); acc(w - 1, y); }
        int bgR = (int)(r / n), bgG = (int)(g0 / n), bgB = (int)(b / n);
        Func<int, int, bool> isBg = delegate(int x, int y)
        {
            int o = y * stride + x * 4;
            int db = px[o] - bgB, dg = px[o + 1] - bgG, dr = px[o + 2] - bgR;
            return db * db + dg * dg + dr * dr <= tol * tol;
        };
        bool[] removed = new bool[w * h];
        Queue<int> q = new Queue<int>();
        Action<int, int> seed = delegate(int x, int y)
        {
            int i = y * w + x;
            if (!removed[i] && isBg(x, y)) { removed[i] = true; q.Enqueue(i); }
        };
        for (int x = 0; x < w; x++) { seed(x, 0); seed(x, h - 1); }
        for (int y = 0; y < h; y++) { seed(0, y); seed(w - 1, y); }
        int[] dx = { 1, -1, 0, 0 }; int[] dy = { 0, 0, 1, -1 };
        while (q.Count > 0)
        {
            int i = q.Dequeue(); int cx = i % w, cy = i / w;
            for (int k = 0; k < 4; k++)
            {
                int nx = cx + dx[k], ny = cy + dy[k];
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                seed(nx, ny);
            }
        }
        if (enclosedMinArea > 0)
        {
            bool[] visited = new bool[w * h];
            for (int y0 = 0; y0 < h; y0++)
                for (int x0 = 0; x0 < w; x0++)
                {
                    int i0 = y0 * w + x0;
                    if (removed[i0] || visited[i0] || !isBg(x0, y0)) continue;
                    List<int> comp = new List<int>();
                    Queue<int> q2 = new Queue<int>();
                    visited[i0] = true; q2.Enqueue(i0);
                    while (q2.Count > 0)
                    {
                        int i = q2.Dequeue(); comp.Add(i);
                        int cx = i % w, cy = i / w;
                        for (int k = 0; k < 4; k++)
                        {
                            int nx = cx + dx[k], ny = cy + dy[k];
                            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                            int ni = ny * w + nx;
                            if (!removed[ni] && !visited[ni] && isBg(nx, ny))
                            { visited[ni] = true; q2.Enqueue(ni); }
                        }
                    }
                    if (comp.Count >= enclosedMinArea)
                        foreach (int i in comp) removed[i] = true;
                }
        }
        for (int i = 0; i < w * h; i++)
            if (removed[i]) px[(i / w) * stride + (i % w) * 4 + 3] = 0;
        System.Runtime.InteropServices.Marshal.Copy(px, 0, data.Scan0, px.Length);
        bmp.UnlockBits(data);
        int[] bb = Bbox(bmp, 20);
        Bitmap trimmed = new Bitmap(bb[2] - bb[0] + 1, bb[3] - bb[1] + 1, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(trimmed))
            g.DrawImage(bmp, new Rectangle(0, 0, trimmed.Width, trimmed.Height),
                new Rectangle(bb[0], bb[1], trimmed.Width, trimmed.Height), GraphicsUnit.Pixel);
        bmp.Dispose();
        return trimmed;
    }

    public static int[] Bbox(Bitmap bmp, int alphaMin)
    {
        int w = bmp.Width, h = bmp.Height;
        int minX = w, minY = h, maxX = -1, maxY = -1;
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                if (bmp.GetPixel(x, y).A > alphaMin)
                {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
        return new int[] { minX, minY, maxX, maxY };
    }

    // 착용샷을 베이스 몸에 정렬해 통일 프레임 비트맵으로 돌려준다.
    // scaleByWidth=true(모자 착용샷: 모자가 높이를 왜곡하므로 팔너비 기준).
    public static Bitmap Align(string wornPath, Bitmap baseImg, bool scaleByWidth)
    {
        int[] bb = Bbox(baseImg, 40);
        Bitmap wornSrc = CleanBlack(wornPath, 14);
        int[] wb = Bbox(wornSrc, 40);
        double s = scaleByWidth
            ? (double)(bb[2] - bb[0] + 1) / (wb[2] - wb[0] + 1)
            : (double)(bb[3] - bb[1] + 1) / (wb[3] - wb[1] + 1);
        int tw = (int)((wb[2] - wb[0] + 1) * s);
        int th = (int)((wb[3] - wb[1] + 1) * s);
        double baseCx = (bb[0] + bb[2]) / 2.0;
        int ax = (int)(baseCx - tw / 2.0);
        int ay = (bb[3] + 1) - th;
        Bitmap outBmp = new Bitmap(baseImg.Width, baseImg.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(outBmp))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.DrawImage(wornSrc, new Rectangle(ax, ay, tw, th),
                new Rectangle(wb[0], wb[1], wb[2] - wb[0] + 1, wb[3] - wb[1] + 1), GraphicsUnit.Pixel);
        }
        wornSrc.Dispose();
        return outBmp;
    }

    // 영역 통째 교체 오버레이(상의/하의/신발): 정렬본에서 rects만 남긴다.
    public static void RegionOverlay(Bitmap aligned, int[][] rects, string outPath)
    {
        Bitmap outBmp = new Bitmap(aligned.Width, aligned.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(outBmp))
        {
            Region clip = new Region(new Rectangle(0, 0, 0, 0));
            foreach (int[] r in rects)
                clip.Union(new Rectangle(r[0], r[1], r[2] - r[0], r[3] - r[1]));
            g.Clip = clip;
            g.DrawImage(aligned, 0, 0, aligned.Width, aligned.Height);
        }
        outBmp.Save(outPath, ImageFormat.Png);
        outBmp.Dispose();
    }

    // 무채색 어두운 픽셀 제거(베이스 검정 반바지가 상의 영역에 딸려온 것 정리)
    public static void EraseNeutralDark(string path, int y0, int y1, int maxT, int maxSat)
    {
        Bitmap bmp = new Bitmap(path);
        for (int y = Math.Max(0, y0); y < Math.Min(bmp.Height, y1); y++)
            for (int x = 0; x < bmp.Width; x++)
            {
                Color c = bmp.GetPixel(x, y);
                if (c.A == 0) continue;
                int mx = Math.Max(c.R, Math.Max(c.G, c.B));
                int mn = Math.Min(c.R, Math.Min(c.G, c.B));
                if (mx - mn <= maxSat && mx <= maxT)
                    bmp.SetPixel(x, y, Color.FromArgb(0, 0, 0, 0));
            }
        string tmp = path + ".tmp.png";
        bmp.Save(tmp, ImageFormat.Png);
        bmp.Dispose();
        System.IO.File.Delete(path);
        System.IO.File.Move(tmp, path);
    }

    // 모자 위치 실측: 정렬본 상단 42%의 진검정(<=85) 픽셀을 침식(r6)해
    // 얇은 외곽선을 제거하고 최대 덩어리(캡)의 bbox를 돌려준다.
    public static int[] MeasureCap(Bitmap aligned)
    {
        int W = aligned.Width, H = aligned.Height;
        int limY = (int)(H * 0.55);
        bool[] dark = new bool[W * H];
        for (int y = 0; y < limY; y++)
            for (int x = 0; x < W; x++)
            {
                Color c = aligned.GetPixel(x, y);
                if (c.A <= 40) continue;
                int mx = Math.Max(c.R, Math.Max(c.G, c.B));
                if (mx <= 85) dark[y * W + x] = true;
            }
        return ErodedLargestBbox(dark, W, H, limY, 6);
    }

    // 안경 위치 실측: 베이스와의 diff(임계 55) ∧ 어두움(<=110) 마스크를 침식(r2)해 최대 블롭 bbox.
    public static int[] MeasureGlasses(Bitmap aligned, Bitmap baseImg)
    {
        int W = aligned.Width, H = aligned.Height;
        int y0 = (int)(H * 0.18), y1 = (int)(H * 0.42);
        bool[] m = new bool[W * H];
        for (int y = y0; y < y1; y++)
            for (int x = 0; x < W; x++)
            {
                Color wc = aligned.GetPixel(x, y);
                if (wc.A <= 40) continue;
                int mx = Math.Max(wc.R, Math.Max(wc.G, wc.B));
                if (mx > 110) continue;
                Color bc = baseImg.GetPixel(x, y);
                int dr = wc.R - bc.R, dg = wc.G - bc.G, db = wc.B - bc.B;
                if (bc.A <= 40 || dr * dr + dg * dg + db * db > 55 * 55)
                    m[y * W + x] = true;
            }
        return ErodedLargestBbox(m, W, H, H, 2);
    }

    static int[] ErodedLargestBbox(bool[] mask, int W, int H, int limY, int er)
    {
        bool[] eroded = new bool[W * H];
        for (int y = 0; y < limY; y++)
            for (int x = 0; x < W; x++)
            {
                bool all = true;
                for (int ky = -er; ky <= er && all; ky++)
                    for (int kx = -er; kx <= er; kx++)
                    {
                        int nx = x + kx, ny = y + ky;
                        if (nx < 0 || ny < 0 || nx >= W || ny >= H || !mask[ny * W + nx]) { all = false; break; }
                    }
                eroded[y * W + x] = all;
            }
        int[] label = new int[W * H];
        int next = 1, bestLabel = 0, bestArea = 0;
        int[] dx = { 1, -1, 0, 0 }; int[] dy = { 0, 0, 1, -1 };
        for (int i0 = 0; i0 < W * H; i0++)
        {
            if (!eroded[i0] || label[i0] != 0) continue;
            int area = 0;
            Queue<int> q = new Queue<int>();
            label[i0] = next; q.Enqueue(i0);
            while (q.Count > 0)
            {
                int i = q.Dequeue(); area++;
                int cx = i % W, cy = i / W;
                for (int k = 0; k < 4; k++)
                {
                    int nx = cx + dx[k], ny = cy + dy[k];
                    if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
                    int ni = ny * W + nx;
                    if (eroded[ni] && label[ni] == 0) { label[ni] = next; q.Enqueue(ni); }
                }
            }
            if (area > bestArea) { bestArea = area; bestLabel = next; }
            next++;
        }
        int minX = W, minY = H, maxX = -1, maxY = -1;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                if (label[y * W + x] == bestLabel)
                {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
        return new int[] { minX - er, minY - er, maxX + er, maxY + er };
    }

    // 단독샷 누끼를 지정 rect에 합성한 풀프레임 오버레이 저장
    public static void ComposeAt(Bitmap item, int x0, int y0, int x1, int y1, int W, int H, string outPath)
    {
        Bitmap outBmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(outBmp))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.SmoothingMode = SmoothingMode.HighQuality;
            g.DrawImage(item, new Rectangle(x0, y0, x1 - x0 + 1, y1 - y0 + 1));
        }
        outBmp.Save(outPath, ImageFormat.Png);
        outBmp.Dispose();
    }

    public static void Thumb(Bitmap item, string outPath)
    {
        int size = 256; double pad = 0.10;
        double avail = size * (1 - 2 * pad);
        double s = Math.Min(avail / item.Width, avail / item.Height);
        int tw = (int)(item.Width * s), th = (int)(item.Height * s);
        Bitmap thumb = new Bitmap(size, size, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(thumb))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(item, (size - tw) / 2, (size - th) / 2, tw, th);
        }
        thumb.Save(outPath, ImageFormat.Png);
        thumb.Dispose();
    }

    public static void Check(Bitmap baseImg, string overlayPath, string outPath)
    {
        Bitmap ov = new Bitmap(overlayPath);
        Bitmap check = new Bitmap(baseImg.Width, baseImg.Height, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(check))
        {
            g.Clear(Color.FromArgb(255, 245, 243, 238));
            g.DrawImage(baseImg, 0, 0, baseImg.Width, baseImg.Height);
            g.DrawImage(ov, 0, 0, baseImg.Width, baseImg.Height);
        }
        check.Save(outPath, ImageFormat.Png);
        check.Dispose(); ov.Dispose();
    }
}
"@

if (-not ([System.Management.Automation.PSTypeName]'ItemPipe').Type) {
    Add-Type -TypeDefinition $csharp -ReferencedAssemblies System.Drawing
}

# ── 단독샷 누끼(모자·안경) — 캐릭터와 무관하게 1회 ───────────────────────────
function Get-FirstPng([string]$dir) {
    if (-not (Test-Path $dir)) { return $null }
    $f = Get-ChildItem $dir -Filter *.png -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { $f.FullName } else { $null }
}

$hatSrc = Get-FirstPng (Join-Path $itemDir "hat")
$glSrc = Get-FirstPng (Join-Path $itemDir "glasses")
$hatCut = $null; $glCut = $null
if ($hatSrc) { $hatCut = [ItemPipe]::CutoutAuto($hatSrc, 32, 0); "hat standalone: $hatSrc" }
if ($glSrc) { $glCut = [ItemPipe]::CutoutAuto($glSrc, 40, 300); "glasses standalone: $glSrc" }

# 썸네일(단독샷 기준 — 상의/하의/신발은 item/ 폴더에 단독샷이 있으면 갱신)
foreach ($slot in @("hat", "glasses", "top", "bottom", "shoes")) {
    $src = Get-FirstPng (Join-Path $itemDir $slot)
    if ($src) {
        $tol = if ($slot -eq "top") { 58 } elseif ($slot -eq "glasses") { 40 } elseif ($slot -eq "hat") { 32 } else { 26 }
        $encl = if ($slot -eq "glasses") { 300 } else { 0 }
        $cut = [ItemPipe]::CutoutAuto($src, $tol, $encl)
        [ItemPipe]::Thumb($cut, (Join-Path $outDir "$($slotFile[$slot]).png"))
        $cut.Dispose()
        "thumb: $($slotFile[$slot]).png"
    }
}

# ── 캐릭터별 처리 ────────────────────────────────────────────────────────────
foreach ($ch in $Characters) {
    if (-not $charCfg.ContainsKey($ch)) { Write-Warning "unknown character: $ch"; continue }
    $cfg = $charCfg[$ch]
    $baseImg = New-Object System.Drawing.Bitmap((Join-Path $charsDir "$($cfg.asset).png"))
    "── $ch ($($cfg.asset)) ──"

    # 모자: 착용샷 실측 → 단독샷 합성
    $wornHat = Get-FirstPng (Join-Path $wearDir "$ch\hat")
    if ($wornHat -and $hatCut) {
        $al = [ItemPipe]::Align($wornHat, $baseImg, $true)
        $m = [ItemPipe]::MeasureCap($al); $al.Dispose()
        $w = $m[2] - $m[0]; $h = $m[3] - $m[1]
        $x0 = [int]($m[0] + $C.capInsetFrac * $w); $x1 = [int]($m[2] - $C.capInsetFrac * $w)
        $y0 = [int]($m[1] - $C.capUpFrac * $h); $y1 = [int]($y0 + $C.capHScale * $h)
        $out = Join-Path $outDir "$($slotFile.hat)_$($cfg.asset).png"
        [ItemPipe]::ComposeAt($hatCut, $x0, $y0, $x1, $y1, $baseImg.Width, $baseImg.Height, $out)
        [ItemPipe]::Check($baseImg, $out, (Join-Path $checkDir "hat_$ch.png"))
        "  hat: 실측 $($m -join ',') → 보정 $x0,$y0,$x1,$y1"
    }

    # 안경: 착용샷 diff 실측 → 단독샷 합성
    $wornGl = Get-FirstPng (Join-Path $wearDir "$ch\glasses")
    if ($wornGl -and $glCut) {
        $al = [ItemPipe]::Align($wornGl, $baseImg, $false)
        $g = [ItemPipe]::MeasureGlasses($al, $baseImg); $al.Dispose()
        $out = Join-Path $outDir "$($slotFile.glasses)_$($cfg.asset).png"
        [ItemPipe]::ComposeAt($glCut, $g[0], $g[1], $g[2], $g[3], $baseImg.Width, $baseImg.Height, $out)
        [ItemPipe]::Check($baseImg, $out, (Join-Path $checkDir "glasses_$ch.png"))
        "  glasses: $($g -join ',')"
    }

    if (-not $cfg.clothesRegion) {
        "  clothes: 영역 교체 생략(diff 방식 결과물 유지 — 스크립트 상단 주석 참고)"
        $baseImg.Dispose()
        continue
    }

    # 상의: 몸통 밴드 + 팔 기둥 영역 통째 교체, 베이스 반바지(무채검정) 제거
    $wornTop = Get-FirstPng (Join-Path $wearDir "$ch\top")
    if ($wornTop) {
        $al = [ItemPipe]::Align($wornTop, $baseImg, $false)
        $rects = @(
            @(0, $cfg.topY0, $baseImg.Width, $C.topY1),
            @(0, $C.topY1, $C.armX0, $C.armY1),
            @($C.armX1, $C.topY1, $baseImg.Width, $C.armY1)
        )
        $out = Join-Path $outDir "$($slotFile.top)_$($cfg.asset).png"
        [ItemPipe]::RegionOverlay($al, $rects, $out); $al.Dispose()
        [ItemPipe]::EraseNeutralDark($out, 920, 1180, 70, 14)
        [ItemPipe]::Check($baseImg, $out, (Join-Path $checkDir "top_$ch.png"))
        "  top: 영역 교체 완료"
    }

    # 하의: 허리 아래 통째 교체
    $wornBottom = Get-FirstPng (Join-Path $wearDir "$ch\bottom")
    if ($wornBottom) {
        $al = [ItemPipe]::Align($wornBottom, $baseImg, $false)
        $out = Join-Path $outDir "$($slotFile.bottom)_$($cfg.asset).png"
        [ItemPipe]::RegionOverlay($al, @(, @(0, $C.bottomY0, $baseImg.Width, 1400)), $out); $al.Dispose()
        [ItemPipe]::Check($baseImg, $out, (Join-Path $checkDir "bottom_$ch.png"))
        "  bottom: 영역 교체 완료"
    }

    # 신발: 발 영역 통째 교체 (variant z=29로 바지 위에 그린다)
    $wornShoes = Get-FirstPng (Join-Path $wearDir "$ch\shoes")
    if ($wornShoes) {
        $al = [ItemPipe]::Align($wornShoes, $baseImg, $false)
        $out = Join-Path $outDir "$($slotFile.shoes)_$($cfg.asset).png"
        [ItemPipe]::RegionOverlay($al, @(, @(0, $C.shoesY0, $baseImg.Width, 1400)), $out); $al.Dispose()
        [ItemPipe]::Check($baseImg, $out, (Join-Path $checkDir "shoes_$ch.png"))
        "  shoes: 영역 교체 완료"
    }

    $baseImg.Dispose()
}

if ($hatCut) { $hatCut.Dispose() }
if ($glCut) { $glCut.Dispose() }
""
"완료. 검증 이미지: docs/recormeImo/checks/ 를 눈으로 확인하세요."
"새 그룹이면 Fake 시드(fake_character_repository.dart)와 V15 시드에 행 추가가 필요합니다."
