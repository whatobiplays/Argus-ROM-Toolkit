import json
import hashlib
import os
import pathlib
import tempfile
import unittest
from unittest import mock

from . import readiness_probe_install_journal as journal
from .readiness_probe import ProbeError


TARGET_REFERENCE = "i74-tgt-7f6cd8181514b822"
SERIAL = "SERIAL-1"
BUILD = "brand/device:version/id/incremental:user/release-keys"
PACKAGE = "com.argusromtoolkit.argus.readinessprobe"
APK_SHA256 = "a" * 64


def session_dump(*, session_id=17, package=PACKAGE, user_id=10,
                 installer="com.android.shell", installer_uid=2000,
                 committed="true", final_status=1, section="Active"):
    return (
        f"{section} install sessions:\n"
        f"  Session {session_id}:\n"
        f"    userId={user_id}\n"
        f"    installerPackageName={installer}\n"
        f"    mInstallerUid={installer_uid}\n"
        f"    appPackageName={package}\n"
        f"    mCommitted={committed}\n"
        f"    mFinalStatus={final_status}\n"
    ).encode("ascii")


class ReadinessProbeInstallJournalTests(unittest.TestCase):
    def private_directory(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = pathlib.Path(temporary.name) / "outcomes"
        directory.mkdir(mode=0o700)
        return directory

    def create_journal(self, directory, *, attempt_id="a" * 32):
        return journal.ReadinessInstallJournal(
            directory,
            target_reference=TARGET_REFERENCE,
            serial=SERIAL,
            build_fingerprint=BUILD,
            android_user_id=10,
            package=PACKAGE,
            artifact_sha256=APK_SHA256,
            version_code=1,
            artifact_size=4096,
            baseline_session_ids=(),
            attempt_id=attempt_id,
        )

    def test_pending_record_is_durable_private_and_artifact_bound(self):
        directory = self.private_directory()

        attempt = self.create_journal(directory)

        self.assertEqual(attempt.latest["state"], "pending")
        self.assertEqual(attempt.latest["phase"], "before_install")
        self.assertEqual(attempt.latest["identity_private"]["serial"], SERIAL)
        self.assertEqual(
            attempt.latest["identity_private"]["build_fingerprint"], BUILD
        )
        self.assertEqual(attempt.latest["artifact"]["sha256"], APK_SHA256)
        path = directory / attempt.latest_filename
        metadata = path.stat(follow_symlinks=False)
        self.assertEqual(metadata.st_mode & 0o777, 0o600)
        self.assertEqual(metadata.st_uid, os.getuid())
        self.assertEqual(metadata.st_nlink, 1)
        self.assertEqual(json.loads(path.read_text()), attempt.latest)

    def test_lifecycle_events_append_with_explicit_hash_lineage(self):
        directory = self.private_directory()
        attempt = self.create_journal(directory)
        pending_digest = attempt.latest_sha256

        attempt.checkpoint("attempted", "create_started")
        attempt.checkpoint(
            "attempted", "session_created", remote_session_id=17
        )

        events = sorted(directory.glob("readiness-install-attempt-*.json"))
        records = [json.loads(path.read_text()) for path in events]
        self.assertEqual([record["event_sequence"] for record in records], [1, 2, 3])
        self.assertEqual(records[1]["previous_event_sha256"], pending_digest)
        self.assertEqual(records[2]["previous_event_sha256"], records[1]["event_sha256"])
        self.assertEqual(records[0]["state"], "pending")
        self.assertEqual(records[-1]["remote_session_id"], 17)
        self.assertTrue(all(path.stat().st_mode & 0o777 == 0o600 for path in events))

    def test_event_chain_rejects_changed_or_missing_session_identity(self):
        for mutation in ("changed", "missing"):
            with self.subTest(mutation=mutation):
                directory = self.private_directory()
                attempt = self.create_journal(directory)
                attempt.checkpoint("attempted", "create_started")
                attempt.checkpoint(
                    "attempted", "session_created", remote_session_id=17
                )
                attempt.checkpoint(
                    "attempted", "write_started", remote_session_id=17
                )

                event_path = directory / (
                    f"readiness-install-attempt-{attempt.attempt_id}-0004.json"
                )
                event = json.loads(event_path.read_text())
                if mutation == "changed":
                    event["remote_session_id"] = 18
                else:
                    event.pop("remote_session_id")
                event.pop("event_sha256")
                event["event_sha256"] = hashlib.sha256(
                    journal._canonical_json_bytes(event)
                ).hexdigest()
                event_path.write_bytes(journal._canonical_json_bytes(event))

                with self.assertRaises(ProbeError):
                    journal.read_install_journal_events(
                        directory,
                        target_reference=TARGET_REFERENCE,
                        attempt_id=attempt.attempt_id,
                    )

    def test_event_chain_rejects_changed_package_identity_after_install(self):
        for field, replacement in (
            ("package_uid_private", 10002),
            ("installed_apk_sha256", "b" * 64),
        ):
            with self.subTest(field=field):
                directory = self.private_directory()
                attempt = self.create_journal(directory)
                attempt.checkpoint("attempted", "create_started")
                attempt.checkpoint(
                    "attempted", "session_created", remote_session_id=17
                )
                attempt.checkpoint(
                    "attempted", "write_started", remote_session_id=17
                )
                attempt.checkpoint(
                    "attempted", "payload_written", remote_session_id=17
                )
                attempt.checkpoint(
                    "attempted", "commit_started", remote_session_id=17
                )
                attempt.checkpoint(
                    "completed",
                    "installed",
                    remote_session_id=17,
                    package_uid_private=10001,
                    installed_apk_sha256=APK_SHA256,
                )
                attempt.checkpoint(
                    "attempted", "cleanup_started", remote_session_id=17
                )

                event_path = directory / (
                    f"readiness-install-attempt-{attempt.attempt_id}-0008.json"
                )
                event = json.loads(event_path.read_text())
                event[field] = replacement
                event.pop("event_sha256")
                event["event_sha256"] = hashlib.sha256(
                    journal._canonical_json_bytes(event)
                ).hexdigest()
                event_path.write_bytes(journal._canonical_json_bytes(event))

                with self.assertRaises(ProbeError):
                    journal.read_install_journal_events(
                        directory,
                        target_reference=TARGET_REFERENCE,
                        attempt_id=attempt.attempt_id,
                    )

    def test_attempt_identifier_collision_never_overwrites_existing_events(self):
        directory = self.private_directory()
        self.create_journal(directory)
        original = sorted(path.read_bytes() for path in directory.glob("*.json"))

        with self.assertRaises(ProbeError):
            self.create_journal(directory)

        self.assertEqual(sorted(path.read_bytes() for path in directory.glob("*.json")), original)

    def test_session_identity_cannot_be_recorded_before_session_creation(self):
        directory = self.private_directory()
        attempt = self.create_journal(directory)

        with self.assertRaises(ProbeError):
            attempt.checkpoint(
                "attempted", "create_started", remote_session_id=17
            )

        self.assertEqual(attempt.latest["event_sequence"], 1)
        self.assertEqual(len(list(directory.glob("*.json"))), 1)

    def test_failed_fsync_does_not_advance_in_memory_journal(self):
        directory = self.private_directory()
        attempt = self.create_journal(directory)
        original_sequence = attempt.latest["event_sequence"]

        with mock.patch.object(journal.os, "fsync", side_effect=OSError("disk")):
            with self.assertRaises(ProbeError):
                attempt.checkpoint("attempted", "create_started")

        self.assertEqual(attempt.latest["event_sequence"], original_sequence)

    def test_parser_retains_only_selected_package_session_fields(self):
        output = session_dump() + session_dump(
            session_id=18,
            package="com.example.unrelated",
            user_id=0,
            installer="com.example.installer",
            installer_uid=10000,
        )

        observed = journal.parse_install_sessions(output, PACKAGE)

        self.assertEqual(observed, ({
            "session_id": 17,
            "user_id": 10,
            "installer_package": "com.android.shell",
            "installer_uid": 2000,
            "package": PACKAGE,
            "section": "active",
            "committed": True,
            "final_status": 1,
        },))
        self.assertNotIn("com.example.unrelated", repr(observed))

    def test_parser_preserves_active_and_historical_section_for_target_session(self):
        observed = journal.parse_install_sessions(
            session_dump(section="Active")
            + session_dump(session_id=18, section="Historical"),
            PACKAGE,
        )

        self.assertEqual(
            [record["section"] for record in observed],
            ["active", "historical"],
        )

    def test_parser_rejects_duplicate_selected_session_ids(self):
        output = session_dump(session_id=17) + session_dump(session_id=17)

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(output, PACKAGE)

    def test_parser_rejects_incomplete_target_session_instead_of_guessing(self):
        output = session_dump().replace(b"mFinalStatus=1\n", b"")

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(output, PACKAGE)

    def test_parser_rejects_target_session_without_package_identity(self):
        output = session_dump().replace(
            f"    appPackageName={PACKAGE}\n".encode("ascii"), b""
        )

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(output, PACKAGE)

    def test_parser_discards_an_explicit_malformed_unrelated_package(self):
        output = session_dump() + session_dump(
            session_id=18,
            package="not a package",
            user_id=0,
            installer="com.example.installer",
            installer_uid=10000,
        )

        observed = journal.parse_install_sessions(output, PACKAGE)

        self.assertEqual([record["session_id"] for record in observed], [17])

    def test_parser_rejects_malformed_package_for_the_expected_session(self):
        output = session_dump(package="not a package")

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(output, PACKAGE, expected_session_id=17)

    def test_parser_rejects_unrelated_session_without_package_as_ambiguous(self):
        unrelated = session_dump(session_id=18).replace(
            f"    appPackageName={PACKAGE}\n".encode("ascii"), b""
        )

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(session_dump() + unrelated, PACKAGE)

    def test_parser_keeps_a_truncated_unrelated_package_ambiguous(self):
        unrelated = session_dump(session_id=18, package="not a package")
        package_line_start = unrelated.index(b"    appPackageName=")
        unrelated = unrelated[:package_line_start] + b"    appPackageName=not a package"

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(session_dump() + unrelated, PACKAGE)

    def test_parser_rejects_malformed_session_header(self):
        output = session_dump() + b"Session unknown:\n"

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(output, PACKAGE)

    def test_reader_rejects_malformed_journal_prefixed_filename(self):
        directory = self.private_directory()
        attempt = self.create_journal(directory)
        malformed = directory / (
            f"readiness-install-attempt-{attempt.attempt_id}-broken.json"
        )
        malformed.write_text("{}\n")
        malformed.chmod(0o600)

        with self.assertRaises(ProbeError):
            journal.read_install_journal_events(
                directory, target_reference=TARGET_REFERENCE
            )


if __name__ == "__main__":
    unittest.main()
