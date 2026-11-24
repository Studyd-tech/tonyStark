"""Fetch the pinned native MediaPipe runtime and hand model. No Python packages are installed."""
import hashlib
import io
from pathlib import Path
import platform
import urllib.request
import zipfile

root = Path(__file__).resolve().parents[1]
destination = root / "vendor" / "mediapipe"
destination.mkdir(parents=True, exist_ok=True)
if platform.machine() != "arm64":
    raise SystemExit("The bundled MediaPipe 1.2.3 runtime currently supports Apple Silicon Macs only.")
wheel_url = "https://files.pythonhosted.org/packages/8a/31/5dcba256f3d7c02cabc834628006aa36c7b36752f1df18082e3dae6229fa/mediapipe-1.2.3-py3-none-macosx_11_0_arm64.whl"
wheel_hash = "077ef409d79ef274b076d47a744018af5f7487c09a1d237e9d2f707d33e39867"
if not (destination / "libmediapipe.dylib").exists():
    print("Downloading MediaPipe 1.2.3 native runtime…", flush=True)
    data = urllib.request.urlopen(wheel_url, timeout=90).read()
    if hashlib.sha256(data).hexdigest() != wheel_hash:
        raise SystemExit("MediaPipe wheel checksum mismatch")
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for source, target in [
            ("mediapipe/tasks/c/libmediapipe.dylib", "libmediapipe.dylib"),
            ("mediapipe-1.2.3.dist-info/licenses/LICENSE", "LICENSE"),
            ("mediapipe-1.2.3.dist-info/licenses/NOTICE", "NOTICE"),
        ]:
            (destination / target).write_bytes(archive.read(source))
model = destination / "hand_landmarker.task"
if not model.exists():
    print("Downloading hand landmark model…", flush=True)
    model.write_bytes(urllib.request.urlopen("https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task", timeout=90).read())
print("Native hand tracker assets ready.")
