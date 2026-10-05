"""Encode tutorial recordings as short, silent Godot-compatible Theora clips.

python tools/encode_moves.py ABSOLUTE_CAPTURE_DIR
Requires imageio-ffmpeg, or pass --ffmpeg PATH to an existing FFmpeg binary.
"""
import argparse
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("capture", type=Path)
parser.add_argument("--ffmpeg")
args = parser.parse_args()
if args.ffmpeg:
    ffmpeg = args.ffmpeg
else:
    import imageio_ffmpeg
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()

destination = Path(__file__).resolve().parents[1] / "assets" / "moves"
destination.mkdir(parents=True, exist_ok=True)
manifest = json.loads((args.capture / "manifest.json").read_text(encoding="utf-8"))
for clip in manifest:
    clip["lesson"] = int(clip["lesson"])
    clip["frames"] = int(clip["frames"])
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y",
        "-framerate", "30", "-i", str(args.capture / f"{clip['lesson']:02d}" / "%04d.png"),
        "-vf", "scale=640:360:flags=lanczos", "-c:v", "libtheora", "-q:v", "7",
        "-g", "30", "-pix_fmt", "yuv420p", "-an",
        str(destination / f"{clip['lesson']:02d}.ogv"),
    ], check=True)
    print(f"ENCODED {clip['name']}", flush=True)
# Keep the clip/input timeline beside the videos for regeneration and review.
(destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
