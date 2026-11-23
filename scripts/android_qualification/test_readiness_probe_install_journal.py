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


def complete_session_dump(*records):
    """Wrap synthetic session records in the observed section envelope."""
    sections = {name: [] for name in (b"Active", b"Finalized", b"Historical")}
    for record in records:
        for line in record.splitlines(keepends=True):
            if line.strip().endswith(b" install sessions:"):
                section = sections[line.strip().split(b" ", 1)[0]]
            else:
                section.append(line)
    return b"".join(
        name + b" install sessions:\n" + b"".join(lines)
        for name, lines in sections.items()
    ) + b"Legacy install sessions:\n{}\n"


def wrapped_historical_session(*, session_id=17, package=PACKAGE, replace=lambda row: row):
    rows = (
        b"userId=10 mOriginalInstallerUid=2000 mOriginalInstallerPackageName="
        b"com.example.synthetic.installer installerPackageName=com.android.shell "
        b"installInitiatingPackageName=com.android.shell mInstallerUid=2000 "
        b"createdMillis=0 stageCid=null ",
        b"mode=1 installFlags=0 installLocation=0 installReason=0 "
        b"installScenario=0 sizeBytes=123 appPackageName=" + package.encode("ascii")
        + b" appIcon=false appLabel=synthetic label installerPackageName=com.example.requested "
        b"rollbackDataPolicy=0 ",
        b"mClientProgress=1.0 mProgress=1.0 mCommitted=true mSealed=true "
        b"mFinalStatus=1 mFinalMessage=synthetic result mStagedSessionErrorMessage= ",
    )
    result = bytearray(f"Historical install sessions:\n  Session {session_id}:\n".encode("ascii"))
    for row in rows:
        row = replace(row)
        prefix = b"      "
        while row:
            width = 120 - len(prefix)
            result.extend(prefix + row[:width] + b"\n")
            row = row[width:]
            prefix = b"  "
    return bytes(result)


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

    def test_parser_hides_unrelated_live_session_bindings(self):
        output = session_dump() + session_dump(
            session_id=18,
            package="com.example.unrelated",
            user_id=0,
            installer="com.example.installer",
            installer_uid=10000,
        )

        observed = journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

        self.assertEqual(observed, ({
            "session_id": 17,
            "user_id": 10,
            "installer_package": "com.android.shell",
            "installer_uid": 2000,
            "package": PACKAGE,
            "section": "active",
            "committed": True,
            "final_status": 1,
        }, {"session_id": 18, "section": "active", "package_binding": "unrelated"}))
        self.assertNotIn("com.example.unrelated", repr(observed))

    def test_parser_preserves_active_and_historical_section_for_target_session(self):
        observed = journal.parse_install_sessions(
            complete_session_dump(session_dump(section="Active"),
                                  session_dump(session_id=18, section="Historical")),
            PACKAGE,
        )

        self.assertEqual(
            [record["section"] for record in observed],
            ["active", "historical"],
        )

    def test_parser_rejects_duplicate_selected_session_ids(self):
        output = session_dump(session_id=17) + session_dump(session_id=17)

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

    def test_parser_rejects_incomplete_target_session_instead_of_guessing(self):
        output = session_dump().replace(b"mFinalStatus=1\n", b"")

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

    def test_parser_rejects_target_session_without_package_identity(self):
        output = session_dump().replace(
            f"    appPackageName={PACKAGE}\n".encode("ascii"), b""
        )

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

    def test_parser_blocks_a_malformed_package_binding(self):
        output = session_dump() + session_dump(
            session_id=18,
            package="not a package",
            user_id=0,
            installer="com.example.installer",
            installer_uid=10000,
        )

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

    def test_parser_rejects_malformed_package_for_the_expected_session(self):
        output = session_dump(package="not a package")

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(output), PACKAGE, expected_session_id=17)

    def test_parser_rejects_unrelated_session_without_package_as_ambiguous(self):
        unrelated = session_dump(session_id=18).replace(
            f"    appPackageName={PACKAGE}\n".encode("ascii"), b""
        )

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(session_dump() + unrelated), PACKAGE)

    def test_parser_keeps_a_truncated_unrelated_package_ambiguous(self):
        unrelated = session_dump(session_id=18, package="not a package")
        package_line_start = unrelated.index(b"    appPackageName=")
        unrelated = unrelated[:package_line_start] + b"    appPackageName=not a package"

        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(complete_session_dump(session_dump() + unrelated), PACKAGE)

    def test_parser_rejects_malformed_session_header(self):
        for header in (b"Session unknown:", b"  Session 17", b"  Active Child Session 17:"):
            output = session_dump().replace(b"  Session 17:", header)
            with self.subTest(header=header), self.assertRaises(ProbeError):
                journal.parse_install_sessions(complete_session_dump(output), PACKAGE)

    def test_parser_accepts_a_matching_active_session_prefix(self):
        output = session_dump().replace(b"Session 17:", b"Active Session 17:")
        observed = journal.parse_install_sessions(complete_session_dump(output), PACKAGE)
        self.assertEqual(observed[0]["section"], "active")

    def test_empty_snapshot_requires_complete_section_envelope(self):
        complete = complete_session_dump()
        self.assertEqual(journal.parse_install_sessions(complete, PACKAGE), ())
        for output in (
            b"", b"Active install sessions:\n", complete[:-1],
            complete.replace(b"Finalized install sessions:\n", b""),
            complete.replace(b"Legacy install sessions:", b"Unknown install sessions:"),
            complete + b"*** SERVICE DUMP TIMEOUT ***\n",
            complete + b"Error: incomplete\n", complete + b"{}\n",
        ):
            with self.subTest(output=output), self.assertRaises(ProbeError):
                journal.parse_install_sessions(output, PACKAGE)

    def test_wrapped_historical_rows_preserve_binding_across_chunks(self):
        dump = complete_session_dump(
            wrapped_historical_session(),
            wrapped_historical_session(session_id=18, package="com.example.unrelated"),
        )
        self.assertIn(b"installerPackag\n  eName=", dump)
        self.assertIn(b"appPackageName=com.argusro\n  mtoolkit", dump)
        parser = journal.InstallSessionParser(PACKAGE, expected_session_id=17)
        for byte in dump:
            parser.feed(bytes([byte]))
        self.assertEqual(parser.finish(), ({
            "session_id": 17,
            "section": "historical",
            "package": PACKAGE,
            "user_id": 10,
            "installer_package": "com.android.shell",
            "installer_uid": 2000,
            "committed": True,
            "final_status": 1,
        }, {"session_id": 18, "section": "historical", "package_binding": "unrelated"}))

    def test_wrapped_historical_rows_reject_ambiguous_or_incomplete_bindings(self):
        for original, replacement in (
            (b"mInstallerUid=2000 ", b"mInstallerUid=2000 mInstallerUid=2000 "),
            (b"mInstallerUid=2000 ", b"mInstallerUid=2000 mInstallerUid=10000 "),
            (b"appPackageName=", b"noPackageName="),
            (PACKAGE.encode("ascii"), PACKAGE.encode("ascii") + b" extra"),
            (b"userId=10 ", b"userId=10 userId=0 "),
            (b"rollbackDataPolicy=0 ", b""),
            (b"mStagedSessionErrorMessage= ", b""),
        ):
            record = wrapped_historical_session(
                replace=lambda row: row.replace(original, replacement),
            )
            with self.subTest(original=original, replacement=replacement), self.assertRaises(ProbeError):
                journal.parse_install_sessions(complete_session_dump(record), PACKAGE)

    def test_only_complete_unattributed_history_is_opaque(self):
        historical = complete_session_dump(wrapped_historical_session(package="null"))
        self.assertEqual(
            journal.parse_install_sessions(historical, PACKAGE),
            ({"session_id": 17, "section": "historical", "package_binding": "unattributed"},),
        )
        for output, expected in (
            (historical, 17),
            (historical[:-1], None),
            (complete_session_dump(session_dump(section="Active", package="null")), None),
            (complete_session_dump(session_dump(section="Finalized", package="null")), None),
            (complete_session_dump(session_dump(
                section="Historical", package="null", committed="unknown",
            )), None),
            (complete_session_dump(session_dump(
                section="Active", package="com.example.unrelated", committed="unknown",
            )), None),
        ):
            with self.subTest(expected=expected, output=output), self.assertRaises(ProbeError):
                journal.parse_install_sessions(output, PACKAGE, expected_session_id=expected)

    def test_wrapped_historical_rows_reject_truncation_and_internal_timeout(self):
        record = wrapped_historical_session()
        envelope = complete_session_dump(record)
        for broken in (
            record[:record.index(b"\n", record.index(b"userId=")) + 1],
            record.replace(b"\n  ", b"\n*** SERVICE DUMP TIMEOUT ***\n  ", 2),
        ):
            with self.assertRaises(ProbeError):
                journal.parse_install_sessions(complete_session_dump(broken), PACKAGE)
        with self.assertRaises(ProbeError):
            journal.parse_install_sessions(envelope[:-1], PACKAGE)

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
