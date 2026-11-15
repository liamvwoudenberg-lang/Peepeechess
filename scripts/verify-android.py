#!/usr/bin/env python3
"""Install and exercise the actual debug APK on one Android device/emulator.

Requires adb and a fresh test install. The normal APK boots its normal scene;
a private debug-app request enables the same in-app smoke runner used locally.
No command-line-intent security bypass or separate test APK is used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import shlex
import struct
import subprocess
import threading
import time
import uuid
import zipfile
import zlib

PACKAGE = "com.peepeechess.game"
MARKER = "PEEPEECHESS_SMOKE "
STAGES = {"opening", "menu", "classic-3d", "combat", "battle-result", "returned-board", "rematch", "final-menu"}
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|^ERROR:|Fatal signal|FATAL EXCEPTION|SIGSEGV|SIGABRT", re.M)


def parse_record(line, run_id):
    if MARKER not in line:
        return None
    record = json.loads(line.split(MARKER, 1)[1])
    return record if isinstance(record, dict) and record.get("runId") == run_id else None


def validate_result(result):
    if result.get("passed") is not True or result.get("failures") != []:
        raise ValueError("App smoke failed: " + str(result.get("failures")))
    if result.get("platform") != "Android" or result.get("rendered") is not True:
        raise ValueError("A rendered Android runtime result is required, not an export or desktop result.")
    if not isinstance(result.get("checks"), int) or result["checks"] < 20 or not STAGES.issubset(set(result.get("stages", []))):
        raise ValueError("The complete session was not verified.")


def inspect_png(data):
    """Decode Android's 8-bit RGB/RGBA screenshot enough to reject blank frames."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("Device did not return a PNG screenshot.")
    offset, compressed, header = 8, bytearray(), None
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        if kind == b"IDAT":
            compressed.extend(payload)
        offset += length + 12
    if not header:
        raise ValueError("PNG header is missing.")
    width, height, depth, color, _compression, _filter, interlace = header
    if width < 100 or height < 100 or width * height > 20000000 or depth != 8 or color not in (2, 6) or interlace:
        raise ValueError("Unsupported or invalid Android screenshot dimensions/format.")
    bpp = 4 if color == 6 else 3
    stride = width * bpp
    raw = zlib.decompress(compressed)
    if len(raw) != (stride + 1) * height:
        raise ValueError("Incomplete PNG pixels.")
    previous = bytearray(stride)
    colors = set()
    for y in range(height):
        start = y * (stride + 1)
        mode = raw[start]
        row = bytearray(raw[start + 1:start + 1 + stride])
        if mode not in range(5):
            raise ValueError("Invalid PNG filter.")
        if mode:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                up = previous[i]
                upper_left = previous[i - bpp] if i >= bpp else 0
                if mode == 1:
                    predictor = left
                elif mode == 2:
                    predictor = up
                elif mode == 3:
                    predictor = (left + up) // 2
                else:
                    p = left + up - upper_left
                    distances = (abs(p - left), abs(p - up), abs(p - upper_left))
                    predictor = (left, up, upper_left)[distances.index(min(distances))]
                row[i] = (row[i] + predictor) & 255
        if y % max(1, height // 24) == 0:
            for x in range(0, width, max(1, width // 24)):
                colors.add(bytes(row[x * bpp:x * bpp + 3]))
        previous = row
    if len(colors) < 8:
        raise ValueError("Rendered screenshot appears blank or nearly uniform.")
    return {"width": width, "height": height, "sampledColors": len(colors)}


class Adb:
    def __init__(self, binary, serial=None):
        self.command = [binary] + (["-s", serial] if serial else [])

    def run(self, *args, input=None, check=True, binary=False, timeout=30):
        result = subprocess.run(self.command + list(args), input=input, capture_output=True, text=not binary, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError("adb command failed: " + " ".join(args) + "\n" + str(result.stderr))
        return result.stdout


def verify(args):
    apk = Path(args.apk).resolve()
    output = Path(args.output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    summary = {"passed": False, "apk": apk.name}
    logcat = None
    try:
        if not apk.is_file():
            raise ValueError("APK does not exist: " + str(apk))
        adb = Adb(args.adb)
        if args.serial:
            serial = args.serial
        else:
            devices = [line.split()[0] for line in adb.run("devices").splitlines()[1:] if len(line.split()) >= 2 and line.split()[1] == "device"]
            if len(devices) != 1:
                raise ValueError("Connect one test device/emulator or specify --serial.")
            serial = devices[0]
        adb = Adb(args.adb, serial)
        summary["serial"] = serial
        summary["device"] = {key: adb.run("shell", "getprop", prop).strip() for key, prop in {
            "model": "ro.product.model", "api": "ro.build.version.sdk", "abis": "ro.product.cpu.abilist", "emulator": "ro.kernel.qemu"}.items()}
        summary["runtimeKind"] = "emulator" if summary["device"]["emulator"] == "1" else "device"
        if int(summary["device"]["api"]) < 26:
            raise ValueError("The APK requires Android API 26 or later.")
        with zipfile.ZipFile(apk) as archive:
            abis = sorted({name.split("/")[1] for name in archive.namelist() if name.startswith("lib/") and name.endswith(".so")})
        summary["apkAbis"] = abis
        if not set(abis).intersection(summary["device"]["abis"].split(",")):
            raise ValueError("APK ABI does not match this Android runtime.")
        if adb.run("shell", "pm", "path", PACKAGE, check=False).strip().startswith("package:") and not args.reuse_test_install:
            raise ValueError("Package is already installed. Use a fresh test device or --reuse-test-install for a disposable test profile.")
        digest = hashlib.sha256()
        with apk.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        summary["apkSha256"] = digest.hexdigest()
        adb.run("install", "-r", "-t", str(apk), timeout=180)
        adb.run("shell", "am", "force-stop", PACKAGE)
        adb.run("shell", "run-as", PACKAGE, "mkdir", "-p", "files")  # also verifies the APK is debuggable
        run_id = uuid.uuid4().hex
        summary["runId"] = run_id
        request = json.dumps({"runId": run_id, "input": "adb"}) + "\n"
        adb.run("shell", "run-as", PACKAGE, "sh", "-c", shlex.quote("cat > files/playability-smoke.request"), input=request)
        activity_lines = adb.run("shell", "cmd", "package", "resolve-activity", "--brief", "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", PACKAGE).splitlines()
        activity = next((line.strip() for line in activity_lines if line.strip().startswith(PACKAGE + "/")), None)
        if not activity:
            raise ValueError("Cannot resolve the APK launcher activity.")
        since = adb.run("shell", "date", shlex.quote("+%m-%d %H:%M:%S.000")).strip()
        adb.run("shell", "am", "start", "-W", "-n", activity)
        pid = ""
        for _attempt in range(30):
            pid = adb.run("shell", "pidof", "-s", PACKAGE, check=False).strip()
            if pid:
                break
            time.sleep(0.2)
        if not pid:
            raise ValueError("APK exited before the smoke runner started.")
        summary["pid"] = pid
        logcat = subprocess.Popen(adb.command + ["logcat", "--pid=" + pid, "-v", "raw", "-T", since], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        lines = queue.Queue()
        def read_lines():
            for line in logcat.stdout:
                lines.put(line)
        threading.Thread(target=read_lines, daemon=True).start()
        deadline = time.monotonic() + args.timeout
        completed_at = None
        result = None
        screenshots = []
        with (output / "logcat.txt").open("w", encoding="utf-8") as log, (output / "events.jsonl").open("w", encoding="utf-8") as events:
            while time.monotonic() < deadline:
                if completed_at is not None and time.monotonic() - completed_at >= 3:
                    break
                try:
                    line = lines.get(timeout=0.2)
                except queue.Empty:
                    if logcat.poll() is not None and completed_at is None:
                        raise ValueError("Android log stream ended without a result.")
                    continue
                log.write(line)
                log.flush()
                if ERRORS.search(line):
                    raise ValueError("Android runtime reported an error: " + line.strip())
                record = parse_record(line, run_id)
                if record is None:
                    continue
                events.write(json.dumps(record) + "\n")
                events.flush()
                if record.get("event") == "stage":
                    name = record["name"]
                    if name not in STAGES:
                        raise ValueError("Unexpected smoke stage.")
                    data = adb.run("exec-out", "screencap", "-p", binary=True)
                    image_info = inspect_png(data)
                    path = output / (name + ".png")
                    path.write_bytes(data)
                    screenshots.append({"stage": name, "file": path.name, **image_info})
                    adb.run("shell", "run-as", PACKAGE, "touch", "files/playability-smoke.ack")
                    print("PASS Android stage: " + name, flush=True)
                elif record.get("event") == "input":
                    if record.get("action") != "tap" or not all(isinstance(record.get(k), int) and 0 <= record[k] <= 20000 for k in ("x", "y")):
                        raise ValueError("Invalid requested test input.")
                    adb.run("shell", "input", "tap", str(record["x"]), str(record["y"]))
                elif record.get("event") == "result":
                    validate_result(record)
                    result = record
                    completed_at = time.monotonic()
        if result is None:
            raise ValueError("Timed out without a complete Android runtime result.")
        if {shot["stage"] for shot in screenshots} != STAGES:
            raise ValueError("Missing rendered-stage screenshots.")
        summary.update({"passed": True, "result": result, "screenshots": screenshots})
        print("PASS: installed Android APK completed chess, touch combat, pit return, result and rematch; SHA256=" + summary["apkSha256"])
    except Exception as error:
        summary["error"] = str(error)
        print("FAIL Android verification: " + str(error), flush=True)
    finally:
        if logcat is not None:
            logcat.terminate()
            try:
                logcat.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logcat.kill()
        (output / "verification.json").write_text(json.dumps(summary, indent=2) + "\n")
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", required=True)
    parser.add_argument("--serial")
    parser.add_argument("--adb", default=os.environ.get("ADB", "adb"))
    parser.add_argument("--output", default="artifacts/android-smoke")
    parser.add_argument("--timeout", type=int, default=300)
    parser.add_argument("--reuse-test-install", action="store_true", help="Use only for an existing disposable debug-test profile; the test changes its local preferences/matches.")
    raise SystemExit(verify(parser.parse_args()))
