import importlib.util
import json
from pathlib import Path
import struct
import unittest
import zlib

spec = importlib.util.spec_from_file_location("android_verifier", Path(__file__).parents[1] / "scripts/verify-android.py")
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class AndroidVerifierTests(unittest.TestCase):
    def result(self):
        return {"passed": True, "failures": [], "platform": "Android", "rendered": True, "checks": 35, "stages": sorted(verifier.STAGES)}

    def test_only_complete_rendered_android_runs_pass(self):
        verifier.validate_result(self.result())
        for patch in [{"platform": "Linux"}, {"rendered": False}, {"passed": False}, {"failures": ["no attack"]}, {"stages": ["opening"]}, {"checks": 1}]:
            with self.subTest(patch=patch), self.assertRaises(ValueError):
                verifier.validate_result({**self.result(), **patch})

    def test_stale_or_unrelated_logs_cannot_supply_a_pass(self):
        self.assertIsNone(verifier.parse_record("unrelated log", "new"))
        self.assertIsNone(verifier.parse_record(verifier.MARKER + json.dumps({"runId": "old", "passed": True}), "new"))
        record = {"runId": "new", "event": "result"}
        self.assertEqual(verifier.parse_record("I/godot: " + verifier.MARKER + json.dumps(record), "new"), record)

    def test_only_known_system_fullscreen_tutorial_is_dismissed(self):
        xml = '<hierarchy><node package="com.android.systemui" text="Viewing full screen"/><node package="com.android.systemui" text="Got it" clickable="true" bounds="[100,200][300,260]"/></hierarchy>'
        self.assertEqual(verifier.fullscreen_hint_tap(xml), (200, 230))
        self.assertEqual(verifier.fullscreen_hint_tap(xml.replace('com.android.systemui', 'android')), (200, 230))
        self.assertIsNone(verifier.fullscreen_hint_tap(xml.replace('Viewing full screen', 'Grant a permission')))
        self.assertIsNone(verifier.fullscreen_hint_tap(xml.replace('com.android.systemui', 'another.app')))
        self.assertIsNone(verifier.fullscreen_hint_tap(xml.replace('[100,200][300,260]', 'invalid')))

    def png(self, varied):
        def chunk(kind, data):
            return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
        pixels = b"".join(b"\0" + b"".join(bytes((x, y, (x + y) % 256)) if varied else b"\0\0\0" for x in range(120)) for y in range(100))
        return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 120, 100, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b"")

    def test_blank_or_invalid_frames_cannot_supply_render_evidence(self):
        info = verifier.inspect_png(self.png(True))
        self.assertEqual((info["width"], info["height"]), (120, 100))
        with self.assertRaises(ValueError):
            verifier.inspect_png(self.png(False))
        with self.assertRaises(ValueError):
            verifier.inspect_png(b"not an image")


if __name__ == "__main__":
    unittest.main()
