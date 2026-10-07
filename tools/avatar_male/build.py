"""
男性アバター(ハギワラ用)の16フレームを、提供された透過PNG(2048x2048)から組み立てる。

  python build.py <素材フォルダ(processed_transparent)> <出力フォルダ>

方針(AIRAのアニメ版と同じ考え方):
  - 土台は male_mouth_neutral(= neutral / eyes_open と同一)。
  - 口8種は、素材ごとの全体画像をそのまま使うと、顔全体の質感が微妙に変わって
    切り替えのたびにちらつくため、「口まわりの楕円」だけを土台に重ねる。
  - 目を閉じた版は、eyes_closed の「目まわりの楕円」だけを重ねる。
  - 重ねる前に、境界の外側のリングで色(LAB)を土台に合わせ、継ぎ目を目立たなくする。
  - 出力は 768x768。ファイル名は AIRA と同じ AIRA_combo_{open|closed}_{口}.png。
"""
import sys
import numpy as np
import cv2
from PIL import Image

SRC_NAME = {  # アプリの口キー -> 素材ファイル
    "neutral": "mouth_neutral", "A": "mouth_A", "E": "mouth_EE", "FV": "mouth_FV",
    "L": "mouth_L", "MPB": "mouth_MBP", "O": "mouth_OO", "TH": "mouth_TH",
}
OUT = 768

# 2048px 座標。口は顎の動きまで含める。目は眉を含めない範囲。
MOUTH = dict(cx=1020, cy=925, rx=165, ry=170, feather=40)
EYES = dict(cx=1030, cy=585, rx=215, ry=62, feather=22)


def load(folder, name):
    return np.asarray(Image.open(f"{folder}/male_{name}.png").convert("RGBA"))


def ellipse_mask(shape, p, grow=0):
    h, w = shape[:2]
    m = np.zeros((h, w), np.float32)
    cv2.ellipse(m, (p["cx"], p["cy"]), (p["rx"] + grow, p["ry"] + grow), 0, 0, 360, 1.0, -1)
    return m


def soft(p):
    m = ellipse_mask((2048, 2048), p)
    k = int(p["feather"]) * 2 + 1
    return cv2.GaussianBlur(m, (k, k), p["feather"] / 2.0)


def match_color(src_rgb, base_rgb, p):
    """境界のすぐ外側のリングで、src の色を base に合わせる(LABの平均・分散)。"""
    outer = ellipse_mask((2048, 2048), p, grow=int(p["feather"]) + 60)
    inner = ellipse_mask((2048, 2048), p, grow=int(p["feather"]) + 10)
    ring = (outer - inner) > 0.5
    s = cv2.cvtColor(src_rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    b = cv2.cvtColor(base_rgb, cv2.COLOR_RGB2LAB).astype(np.float32)
    out = s.copy()
    for c in range(3):
        sm, ss = s[..., c][ring].mean(), s[..., c][ring].std() + 1e-3
        bm, bs = b[..., c][ring].mean(), b[..., c][ring].std() + 1e-3
        out[..., c] = (s[..., c] - sm) * (bs / ss) + bm if c == 0 else (s[..., c] - sm) + bm
    out[..., 0] = np.clip(out[..., 0], 0, 255)
    out = np.clip(out, 0, 255).astype(np.uint8)
    return cv2.cvtColor(out, cv2.COLOR_LAB2RGB)


def paste(base_rgb, src_rgb, p):
    matched = match_color(src_rgb, base_rgb, p)
    m = soft(p)[..., None]
    return (base_rgb * (1 - m) + matched * m).astype(np.uint8)


def save(rgb, alpha, path):
    im = np.dstack([rgb, alpha])
    Image.fromarray(im, "RGBA").resize((OUT, OUT), Image.LANCZOS).save(path, optimize=True)


def main(src, out):
    import os
    os.makedirs(f"{out}/combined", exist_ok=True)
    base = load(src, "mouth_neutral")
    base_rgb, alpha = base[..., :3], base[..., 3]
    closed_rgb = load(src, "eyes_closed")[..., :3]

    save(base_rgb, alpha, f"{out}/AIRA_base_neutral.png")
    for key, name in SRC_NAME.items():
        open_rgb = base_rgb if key == "neutral" else paste(base_rgb, load(src, name)[..., :3], MOUTH)
        save(open_rgb, alpha, f"{out}/combined/AIRA_combo_open_{key}.png")
        closed = paste(open_rgb, closed_rgb, EYES)
        save(closed, alpha, f"{out}/combined/AIRA_combo_closed_{key}.png")
    print("done:", out)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
