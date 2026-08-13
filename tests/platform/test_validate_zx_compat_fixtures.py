#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
PLATFORM_TOOLS = REPO_ROOT / "tests" / "platform" / "tools"
sys.path.insert(0, str(PLATFORM_TOOLS))

from validate_zx_compat_fixtures import (  # noqa: E402
    canonical_name_sha256,
    load_manifest,
    sha256_file,
    validate_fixture_set,
)


FILENAMES = {
    "driver": "CUDA 11.7 driver api.xlsx",
    "runtime": "CUDA 11.7 runtime API.xlsx",
    "libraries": "科学计算库实现列表.xlsx",
}
DERIVED = {
    "source_row_count": 900,
    "api_row_count": 816,
    "unique_api_count": 830,
    "forbidden_api_count": 315,
    "unique_api_sha256": "a" * 64,
    "forbidden_api_sha256": "b" * 64,
}


class FixtureValidationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "fixtures"
        self.source.mkdir()
        self.contents = {
            "driver": b"driver fixture\n",
            "runtime": b"runtime fixture\n",
            "libraries": b"libraries fixture\n",
        }
        for role, content in self.contents.items():
            (self.source / FILENAMES[role]).write_bytes(content)
        (self.source / "unrelated.pdf").write_bytes(b"allowed extra file")
        self.manifest = self.root / "manifest.json"
        self.write_manifest()

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def manifest_payload(self) -> dict:
        return {
            "schema_version": "zx_compat_fixture_manifest_v1",
            "fixture_set": "test-fixtures",
            "files": {
                role: {
                    "filename": FILENAMES[role],
                    "size_bytes": len(content),
                    "sha256": hashlib.sha256(content).hexdigest(),
                }
                for role, content in self.contents.items()
            },
            "derived_expectations": DERIVED,
        }

    def write_manifest(self, payload: dict | None = None) -> None:
        self.manifest.write_text(
            json.dumps(payload or self.manifest_payload(), ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

    def test_valid_fixture_set_is_deterministic_and_allows_extra_files(self) -> None:
        first = validate_fixture_set(self.source, self.manifest)
        second = validate_fixture_set(self.source, self.manifest)
        self.assertEqual(first, second)
        self.assertEqual(first["status"], "passed")
        self.assertEqual(first["source_manifest_sha256"], sha256_file(self.manifest))

    def test_missing_fixture_fails(self) -> None:
        (self.source / FILENAMES["driver"]).unlink()
        with self.assertRaisesRegex(ValueError, "regular non-symlink"):
            validate_fixture_set(self.source, self.manifest)

    def test_single_byte_tamper_fails(self) -> None:
        (self.source / FILENAMES["runtime"]).write_bytes(b"Runtime fixture\n")
        with self.assertRaisesRegex(ValueError, "mismatch"):
            validate_fixture_set(self.source, self.manifest)

    def test_swapped_fixture_contents_fail(self) -> None:
        driver = self.source / FILENAMES["driver"]
        runtime = self.source / FILENAMES["runtime"]
        driver.write_bytes(self.contents["runtime"])
        runtime.write_bytes(self.contents["driver"])
        with self.assertRaisesRegex(ValueError, "mismatch"):
            validate_fixture_set(self.source, self.manifest)

    def test_duplicate_manifest_key_fails(self) -> None:
        self.manifest.write_text(
            '{"schema_version":"zx_compat_fixture_manifest_v1",'
            '"schema_version":"duplicate","fixture_set":"x","files":{},'
            '"derived_expectations":{}}\n',
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            load_manifest(self.manifest)

    def test_bad_schema_and_extra_key_fail(self) -> None:
        payload = self.manifest_payload()
        payload["schema_version"] = "wrong"
        self.write_manifest(payload)
        with self.assertRaisesRegex(ValueError, "unsupported"):
            load_manifest(self.manifest)
        payload = self.manifest_payload()
        payload["unexpected"] = True
        self.write_manifest(payload)
        with self.assertRaisesRegex(ValueError, "keys must be exactly"):
            load_manifest(self.manifest)

    def test_path_traversal_filename_fails(self) -> None:
        payload = self.manifest_payload()
        payload["files"]["driver"]["filename"] = "../driver.xlsx"
        self.write_manifest(payload)
        with self.assertRaisesRegex(ValueError, "basename"):
            load_manifest(self.manifest)

    def test_symlink_fixture_fails(self) -> None:
        driver = self.source / FILENAMES["driver"]
        target = self.root / "driver-target.xlsx"
        target.write_bytes(driver.read_bytes())
        driver.unlink()
        try:
            driver.symlink_to(target)
        except OSError as error:
            self.skipTest(f"symlinks unavailable: {error}")
        with self.assertRaisesRegex(ValueError, "regular non-symlink"):
            validate_fixture_set(self.source, self.manifest)

    def test_derived_summary_identity_and_counts_are_checked(self) -> None:
        identity = validate_fixture_set(self.source, self.manifest)
        summary = self.root / "summary.json"
        payload = {
            **DERIVED,
            "fixture_set": identity["fixture_set"],
            "source_manifest_sha256": identity["source_manifest_sha256"],
            "source_files": identity["files"],
        }
        summary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        validated = validate_fixture_set(self.source, self.manifest, summary)
        self.assertEqual(validated["derived_summary"], dict(sorted(DERIVED.items())))
        payload["forbidden_api_count"] -= 1
        summary.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "identities do not match"):
            validate_fixture_set(self.source, self.manifest, summary)

    def test_scanner_rejects_jointly_tampered_matrix_and_forbidden_file(self) -> None:
        original_api = "cudaForbidden"
        payload = self.manifest_payload()
        payload["derived_expectations"] = {
            "source_row_count": 2,
            "api_row_count": 2,
            "unique_api_count": 1,
            "forbidden_api_count": 1,
            "unique_api_sha256": canonical_name_sha256([original_api]),
            "forbidden_api_sha256": canonical_name_sha256([original_api]),
        }
        self.write_manifest(payload)
        identity = validate_fixture_set(self.source, self.manifest)
        matrix = self.root / "matrix.json"
        forbidden = self.root / "forbidden.txt"
        exceptions = self.root / "exceptions.json"
        source_root = self.root / "sources"
        source_root.mkdir()
        matrix_payload = {
            "summary": {
                **payload["derived_expectations"],
                "status": "passed",
                "fixture_set": identity["fixture_set"],
                "source_manifest_sha256": identity["source_manifest_sha256"],
                "source_files": identity["files"],
            },
            "rows": [
                {
                    "row_kind": "api",
                    "support": "unsupported",
                    "api_names": [original_api],
                },
                {
                    "row_kind": "api",
                    "support": "unsupported",
                    "api_names": [original_api],
                },
            ],
        }
        matrix.write_text(json.dumps(matrix_payload), encoding="utf-8")
        forbidden.write_text(f"{original_api}\n", encoding="utf-8")
        exceptions.write_text(
            json.dumps(
                {
                    "apis": {
                        "cudaDocumented": {
                            "reason": "test",
                            "verification": "zx_compat_runtime_probes",
                        }
                    }
                }
            ),
            encoding="utf-8",
        )
        output = self.root / "api-usage.json"
        command = [
            sys.executable,
            str(PLATFORM_TOOLS / "scan_zx_api_usage.py"),
            "--matrix",
            str(matrix),
            "--forbidden",
            str(forbidden),
            "--source-dir",
            str(self.source),
            "--source-manifest",
            str(self.manifest),
            "--exceptions",
            str(exceptions),
            "--roots",
            str(source_root),
            "--output",
            str(output),
        ]
        valid = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertEqual(valid.returncode, 0, valid.stderr)

        matrix_payload["rows"] = matrix_payload["rows"][:1]
        matrix.write_text(json.dumps(matrix_payload), encoding="utf-8")
        folded = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertNotEqual(folded.returncode, 0)
        self.assertFalse(output.exists())

        tampered_api = "cudaHarmless"
        matrix_payload["rows"] = [
            {
                "row_kind": "api",
                "support": "unsupported",
                "api_names": [tampered_api],
            },
            {
                "row_kind": "api",
                "support": "unsupported",
                "api_names": [tampered_api],
            },
        ]
        matrix.write_text(json.dumps(matrix_payload), encoding="utf-8")
        forbidden.write_text(f"{tampered_api}\n", encoding="utf-8")
        tampered = subprocess.run(command, text=True, capture_output=True, check=False)
        self.assertNotEqual(tampered.returncode, 0)
        self.assertFalse(output.exists())

    def test_failed_cli_removes_stale_validation_output(self) -> None:
        output = self.root / "validation.json"
        output.write_text('{"status":"passed"}\n', encoding="utf-8")
        (self.source / FILENAMES["libraries"]).unlink()
        result = subprocess.run(
            [
                sys.executable,
                str(PLATFORM_TOOLS / "validate_zx_compat_fixtures.py"),
                "--source-dir",
                str(self.source),
                "--manifest",
                str(self.manifest),
                "--output",
                str(output),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

if __name__ == "__main__":
    unittest.main()
