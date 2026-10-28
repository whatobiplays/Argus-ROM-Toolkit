"""Tiny synthetic contract tests; no ROM files or source authentication claims."""

from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import unittest

from scripts.android_qualification import fixture_oracle as oracle


def encoded(value: object) -> bytes:
    """Independent test encoding for small, already-NFC schema fixtures."""
    return json.dumps(value, sort_keys=True, ensure_ascii=False,
                      separators=(",", ":")).encode()


def digest(value: object, prefix: bytes = b"") -> str:
    return hashlib.sha256(prefix + encoded(value)).hexdigest()


def pin(record: dict, kind: str) -> dict:
    return {"schema_version": 1, f"{kind}_ref": record[f"{kind}_ref"],
            "revision": record["revision"],
            "sha256": digest(record, f"argus.fixture-{kind}.v1\0".encode())}


def bundle(genuine: bool = False) -> tuple[dict, dict, list[dict]]:
    """All bytes and claims are fabricated; genuine mode tests only the schema."""
    fixture = {"fixture_id": "tiny", "platform": "test", "representation": "raw",
               "identity": "Synthetic test identity", "group_id": "set", "order": 0,
               "entrypoint": "disc.bin", "files": [{"path": "disc.bin", "role": "rom",
                   "size": 1, "sha256": "a" * 64}], "companions": [],
               "facts": {"edition": "test", "region": "test", "disc_set": "set"}}
    record = {"schema_version": 1, "oracle_ref": "oracle-tiny", "revision": "r1",
              "fixture": fixture, "corpus_origin": "owner_private_genuine" if genuine else "synthetic",
              "acceptance_rule_sha256": "c" * 64,
              "method": "independent_reference" if genuine else "synthetic_expectation",
              "provenance": "Fabricated unit-test data; never qualification evidence",
              "limitations": ["No real source authenticated"], "conflicts": [], "evidence_refs": []}
    records = []
    if genuine:
        item = copy.deepcopy(record)
        del item["oracle_ref"]
        item["evidence_ref"] = "evidence-tiny"
        item["reference"] = {"ref": "test-reference", "revision": "r1", "sha256": "d" * 64}
        records.append(item)
        record["evidence_refs"] = [pin(item, "evidence")]
    manifest_fixture = copy.deepcopy(fixture)
    manifest_fixture["identity_evidence"] = (
        "independent_reference_pinned_v1" if genuine else "synthetic_expectation_v2")
    manifest_fixture["oracle_pin"] = pin(record, "oracle")
    manifest = {"schema_version": 2, "source_authority": "service_protected_snapshot_v1",
                "plan_sha256": "b" * 64, "rules_sha256": "c" * 64,
                "coverage_mode": "mandatory_full_plan", "selected_fixture_ids": ["tiny"],
                "fixtures": [manifest_fixture]}
    return manifest, record, records


def validate(manifest: dict, record: dict, records: list[dict], **options):
    """Pin the current manifest while allowing tests to perturb downstream pins."""
    pins = {"authorized_manifest_sha256": digest(manifest),
            "authorized_plan_sha256": "b" * 64, "authorized_rules_sha256": "c" * 64}
    pins.update(options)
    return oracle.validate_snapshot_contract(encoded(manifest), [encoded(record)],
                                             [encoded(item) for item in records], **pins)


def repin(manifest: dict, record: dict, records: list[dict]) -> None:
    record["evidence_refs"] = [pin(item, "evidence") for item in records]
    manifest["fixtures"][0]["oracle_pin"] = pin(record, "oracle")


class CanonicalContractTests(unittest.TestCase):
    def test_ascii_sort_utf8_nfc_and_integer_boolean_distinction(self) -> None:
        value = {"z": None, "name": "Café", "min": -(2**63), "max": 2**63 - 1,
                 "b": 1, "a": True}
        expected = ('{"a":true,"b":1,"max":9223372036854775807,'
                    '"min":-9223372036854775808,"name":"Café","z":null}').encode()
        self.assertEqual(oracle.canonical_json(value), expected)
        self.assertEqual(oracle.decode_document(expected), value)

    def test_domain_digests_match_independent_openssl_literals(self) -> None:
        value = {"z": None, "name": "Café", "min": -(2**63), "max": 2**63 - 1,
                 "b": 1, "a": True}
        self.assertEqual(oracle.manifest_sha256(value),
                         "843d3351adb6c379030493e952aa27680890618920fec7a5025b82c7f1689ef7")
        self.assertEqual(oracle.oracle_sha256(value),
                         "6732f297f4e2aa76f7f9a5532ab0739234742fb460b911d328c7ae19f700fe36")
        self.assertEqual(oracle.evidence_sha256(value),
                         "f023a4499fa582c1e1dda15140c7604ef9ee71ccaa207182f8ca88cb43c81d4b")

    def test_ambiguous_or_nonportable_values_are_rejected(self) -> None:
        for value in (1.0, float("nan"), 2**63, -(2**63) - 1,
                      "Cafe\u0301", "\ud800", {"é": 1}, {1: 1}, (1,), object()):
            with self.subTest(value=repr(value)), self.assertRaises(oracle.OracleError):
                oracle.canonical_json(value)

    def test_decoder_rejects_duplicates_numbers_invalid_utf8_and_nonobjects(self) -> None:
        for raw in (b'{"a":1,"a":2}', b'{"x":{"a":1,"a":2}}', b'{"a":1.0}',
                    b'{"a":1e2}', b'{"a":NaN}', b'{"a":Infinity}', b'{"a":-0}',
                    b'{"a":9223372036854775808}', b'{"a":"\xff"}', b'[]', b'null',
                    b'\xef\xbb\xbf{}', b'{', b'{"a":"Cafe\\u0301"}'):
            with self.subTest(raw=raw), self.assertRaises(oracle.OracleError):
                oracle.decode_document(raw)

    def test_document_limit_and_depth_are_bounded(self) -> None:
        with self.assertRaises(oracle.OracleError):
            oracle.decode_document(b' ' * 65537)
        value = {"x": "a" * (65536 - 8)}
        self.assertEqual(len(oracle.canonical_json(value)), 65536)
        with self.assertRaises(oracle.OracleError):
            oracle.canonical_json({"x": "a" * (65536 - 7)})
        deep = b'{"x":' + b'[' * 34 + b'0' + b']' * 34 + b'}'
        with self.assertRaises(oracle.OracleError):
            oracle.decode_document(deep)

    def test_decoder_requires_bytes_and_handles_cyclic_python_values(self) -> None:
        for value in ("{}", bytearray(b"{}"), None):
            with self.subTest(value=value), self.assertRaises(oracle.OracleError):
                oracle.decode_document(value)
        cyclic = []
        cyclic.append(cyclic)
        with self.assertRaises(oracle.OracleError):
            oracle.canonical_json(cyclic)

    def test_shared_native_vectors_have_literal_bytes_and_digests(self) -> None:
        path = Path(__file__).resolve().parents[2] / "native/fixture-staging/fixtures/oracle-contract-v1-golden.json"
        vectors = json.loads(path.read_bytes())
        for vector in vectors["canonical_vectors"]:
            with self.subTest(vector=vector["id"]):
                value = oracle.decode_document(vector["input_json"].encode())
                self.assertEqual(oracle.canonical_json(value), vector["canonical_utf8"].encode())
                self.assertEqual(oracle.canonical_json(value).hex(), vector["canonical_utf8_hex"])
                self.assertEqual(oracle.manifest_sha256(value), vector["manifest_sha256"])
                self.assertEqual(oracle.oracle_sha256(value), vector["oracle_sha256"])
                self.assertEqual(oracle.evidence_sha256(value), vector["evidence_sha256"])
        for vector in vectors["invalid_json_vectors"]:
            with self.subTest(vector=vector["id"]):
                if vector.get("parse_only_valid"):
                    self.assertEqual(oracle.decode_document(vector["input_json"].encode()), {"schema_version": 99})
                else:
                    with self.assertRaises(oracle.OracleError):
                        oracle.decode_document(vector["input_json"].encode())
        graph = vectors["snapshot_vector"]
        self.assertEqual(oracle.canonical_json(graph["manifest"]), graph["manifest_canonical_utf8"].encode())
        for kind in ("oracle", "evidence"):
            records = graph["oracles" if kind == "oracle" else "evidence"]
            for record, expected_bytes, expected_digest in zip(
                    records, graph[f"{kind}_canonical_utf8"], graph[f"{kind}_sha256"], strict=True):
                self.assertEqual(oracle.canonical_json(record), expected_bytes.encode())
                self.assertEqual(getattr(oracle, f"{kind}_sha256")(record), expected_digest)
        result = oracle.validate_snapshot_contract(
            encoded(graph["manifest"]), [encoded(record) for record in graph["oracles"]],
            [encoded(record) for record in graph["evidence"]],
            **{key: graph[key] for key in ("authorized_manifest_sha256", "authorized_plan_sha256",
                                          "authorized_rules_sha256")})
        self.assertEqual(result.manifest_sha256, graph["authorized_manifest_sha256"])
        self.assertEqual(result.fixtures[0].independent_support, graph["expected_independent_support"])


class SnapshotContractTests(unittest.TestCase):
    def test_synthetic_contract_never_confers_authenticity_or_approval(self) -> None:
        contract = validate(*bundle())
        result = contract.fixtures[0]
        self.assertEqual(result.fixture_id, "tiny")
        self.assertEqual(result.oracle_revision, "r1")
        self.assertEqual(result.independent_support, "synthetic_only")
        self.assertEqual(result.byte_integrity, "not_checked")
        self.assertEqual(result.structural_expectation, "validated")
        self.assertEqual(result.owner_approval, "not_checked")

    def test_pinned_self_declarations_remain_unverified(self) -> None:
        result = validate(*bundle(genuine=True)).fixtures[0]
        self.assertEqual(result.independent_support, "pinned_unverified")
        self.assertEqual(result.owner_approval, "not_checked")

    def test_caller_callable_cannot_claim_independent_reference(self) -> None:
        manifest, record, records = bundle(genuine=True)
        with self.assertRaises(TypeError):
            validate(manifest, record, records, reference_verifier=lambda _: True)

        result = validate(manifest, record, records).fixtures[0]
        self.assertEqual(result.independent_support, "pinned_unverified")
        self.assertEqual(result.owner_approval, "not_checked")

    def test_authorization_manifest_plan_and_rules_pins_are_required(self) -> None:
        for key in ("authorized_manifest_sha256", "authorized_plan_sha256", "authorized_rules_sha256"):
            with self.subTest(key=key), self.assertRaises(oracle.OracleError) as caught:
                validate(*bundle(), **{key: "0" * 64})
            self.assertEqual(caught.exception.code, "PIN_MISMATCH")

    def test_changed_oracle_revision_and_digest_are_rejected(self) -> None:
        for key, value in (("revision", "r2"), ("provenance", "changed declaration")):
            manifest, record, records = bundle()
            record[key] = value
            with self.subTest(key=key), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "PIN_MISMATCH")

    def test_changed_evidence_revision_and_digest_are_rejected(self) -> None:
        for key, value in (("revision", "r2"), ("provenance", "changed declaration")):
            manifest, record, records = bundle(genuine=True)
            records[0][key] = value
            with self.subTest(key=key), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "PIN_MISMATCH")

    def test_missing_oracle_and_evidence_references_are_explicit(self) -> None:
        for kind in ("oracle", "evidence"):
            manifest, record, records = bundle(genuine=True)
            if kind == "oracle":
                manifest["fixtures"][0]["oracle_pin"]["oracle_ref"] = "absent"
            else:
                records = []
            with self.subTest(kind=kind), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "MISSING_REFERENCE")

    def test_cycles_are_detected_before_impossible_cyclic_hashes(self) -> None:
        for two_nodes in (False, True):
            manifest, record, records = bundle(genuine=True)
            first = records[0]
            last = copy.deepcopy(first) if two_nodes else first
            if two_nodes:
                last["evidence_ref"] = "second"
                records.append(last)
            first["evidence_refs"] = [pin(last, "evidence")]
            last["evidence_refs"] = [pin(first, "evidence")]
            repin(manifest, record, records[:1])
            with self.subTest(two_nodes=two_nodes), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "REFERENCE_CYCLE")

    def test_conflicts_block_before_reference_classification(self) -> None:
        for location in ("oracle", "evidence"):
            manifest, record, records = bundle(genuine=True)
            (record if location == "oracle" else records[0])["conflicts"] = ["identity disagreement"]
            repin(manifest, record, records)
            with self.subTest(location=location), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "EVIDENCE_CONFLICT")

    def test_all_claims_are_bound_exactly(self) -> None:
        changes = {"identity": "different", "platform": "different", "representation": "different",
                   "group_id": "different", "order": 1, "facts": {"region": "other"},
                   "files": [{"path": "disc.bin", "role": "rom", "size": 2, "sha256": "f" * 64}]}
        for key, value in changes.items():
            for location in ("oracle", "evidence"):
                manifest, record, records = bundle(genuine=True)
                (record if location == "oracle" else records[0])["fixture"][key] = value
                repin(manifest, record, records)
                with self.subTest(key=key, location=location), self.assertRaises(oracle.OracleError) as caught:
                    validate(manifest, record, records)
                self.assertEqual(caught.exception.code, "EVIDENCE_CONFLICT")

    def test_rule_and_corpus_disagreement_are_conflicts(self) -> None:
        for key, value in (("acceptance_rule_sha256", "e" * 64), ("corpus_origin", "synthetic")):
            manifest, record, records = bundle(genuine=True)
            records[0][key] = value
            if key == "corpus_origin":
                records[0]["method"] = "synthetic_expectation"
                del records[0]["reference"]
            repin(manifest, record, records)
            with self.subTest(key=key), self.assertRaises(oracle.OracleError) as caught:
                validate(manifest, record, records)
            self.assertEqual(caught.exception.code, "EVIDENCE_CONFLICT")

    def test_shared_source_reference_cannot_change_revision_or_digest(self) -> None:
        for key, value in (("revision", "r2"), ("sha256", "e" * 64)):
            manifest, record, records = bundle(genuine=True)
            other = copy.deepcopy(records[0])
            other["evidence_ref"] = "second"
            other["reference"][key] = value
            records.append(other)
            repin(manifest, record, records)
            with self.subTest(key=key):
                with self.assertRaises(oracle.OracleError) as caught:
                    validate(manifest, record, records)
                self.assertEqual(caught.exception.code, "EVIDENCE_CONFLICT")

    def test_genuine_identity_requires_pinned_independent_reference(self) -> None:
        for mutation in ("no_evidence", "no_reference", "filename", "header", "argus_output", "synthetic_expectation"):
            manifest, record, records = bundle(genuine=True)
            if mutation == "no_evidence":
                records = []
            elif mutation == "no_reference":
                del records[0]["reference"]
            else:
                records[0]["method"] = mutation
            repin(manifest, record, records)
            with self.subTest(mutation=mutation), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_legacy_and_unsupported_schemas_are_never_upgraded(self) -> None:
        for location in ("manifest", "oracle", "evidence", "oracle_pin", "evidence_pin"):
            for version in (True, 0, 3, "1"):
                manifest, record, records = bundle(genuine=True)
                target = {"manifest": manifest, "oracle": record, "evidence": records[0],
                          "oracle_pin": manifest["fixtures"][0]["oracle_pin"],
                          "evidence_pin": record["evidence_refs"][0]}[location]
                target["schema_version"] = version
                with self.subTest(location=location, version=version), self.assertRaises(oracle.OracleError):
                    validate(manifest, record, records)
        manifest, record, records = bundle()
        manifest["schema_version"] = 1
        with self.assertRaises(oracle.OracleError):
            validate(manifest, record, records)

    def test_unknowns_and_manifest_backreferences_are_rejected_everywhere(self) -> None:
        for location in ("manifest", "fixture", "oracle", "evidence", "reference", "facts", "file", "pin"):
            manifest, record, records = bundle(genuine=True)
            target = {"manifest": manifest, "fixture": manifest["fixtures"][0], "oracle": record,
                      "evidence": records[0], "reference": records[0]["reference"],
                      "facts": record["fixture"]["facts"], "file": record["fixture"]["files"][0],
                      "pin": manifest["fixtures"][0]["oracle_pin"]}[location]
            target["manifest_sha256"] = "e" * 64
            with self.subTest(location=location), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_unused_and_duplicate_records_are_rejected(self) -> None:
        manifest, record, records = bundle(genuine=True)
        extra = copy.deepcopy(records[0])
        extra["evidence_ref"] = "unused"
        with self.assertRaises(oracle.OracleError) as caught:
            validate(manifest, record, records + [extra])
        self.assertEqual(caught.exception.code, "UNUSED_RECORD")
        with self.assertRaises(oracle.OracleError):
            validate(manifest, record, records * 2)

    def test_registry_limit_and_unbounded_iterators_are_rejected(self) -> None:
        manifest, record, records = bundle()
        for supplied in ([encoded(record)] * 129, iter([encoded(record)])):
            with self.subTest(type=type(supplied)), self.assertRaises(oracle.OracleError):
                oracle.validate_snapshot_contract(encoded(manifest), supplied, [],
                    authorized_manifest_sha256=digest(manifest),
                    authorized_plan_sha256="b" * 64, authorized_rules_sha256="c" * 64)

    def test_shared_acyclic_evidence_is_visited_once(self) -> None:
        manifest, record, records = bundle(genuine=True)
        leaf = records[0]
        parents = []
        for name in ("first", "second"):
            parent = copy.deepcopy(leaf)
            parent["evidence_ref"] = name
            parent["evidence_refs"] = [pin(leaf, "evidence")]
            parents.append(parent)
        repin(manifest, record, parents + [leaf])
        result = validate(manifest, record, parents + [leaf])
        self.assertEqual(result.fixtures[0].independent_support, "pinned_unverified")

    def test_malformed_manifest_fields_are_not_coerced(self) -> None:
        mutations = (
            ((), "source_authority", "legacy"), ((), "coverage_mode", "partial"),
            ((), "selected_fixture_ids", ["tiny", "TINY"]),
            ((), "selected_fixture_ids", ["other"]), ((), "fixtures", None),
            (("fixtures", 0), "fixture_id", ".."), (("fixtures", 0), "platform", " test"),
            (("fixtures", 0), "identity", ""), (("fixtures", 0), "group_id", "a\nb"),
            (("fixtures", 0), "platform", "a" * 257),
            (("fixtures", 0), "facts", {}),
            (("fixtures", 0), "identity_evidence", "owner_approved_expectation_match"),
            (("fixtures", 0, "files", 0), "sha256", "A" * 64),
            (("fixtures", 0, "files", 0), "sha256", "a" * 63),
        )
        for path, field, value in mutations:
            manifest, record, records = bundle()
            target = manifest
            for key in path:
                target = target[key]
            target[field] = value
            with self.subTest(path=path, field=field, value=value), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_duplicate_members_and_casefolded_directory_aliases_are_rejected(self) -> None:
        for paths in (("disc.bin", "disc.bin"), ("Dir/disc.bin", "dir/track.bin"),
                      ("Straße/a", "STRASSE/b")):
            manifest, record, records = bundle()
            fixture = manifest["fixtures"][0]
            fixture["entrypoint"] = paths[0]
            fixture["files"] = [{"path": path, "role": "rom", "size": 1, "sha256": "a" * 64}
                                for path in paths]
            fixture["companions"] = [{"source": paths[0], "target": paths[1]}]
            with self.subTest(paths=paths), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_duplicate_or_reversed_order_within_group_is_rejected(self) -> None:
        for order in (0, 1):
            manifest, record, records = bundle()
            fixture = manifest["fixtures"][0]
            fixture["order"] = 1
            second = copy.deepcopy(fixture)
            second["fixture_id"] = "second"
            second["order"] = order
            manifest["fixtures"].append(second)
            manifest["selected_fixture_ids"].append("second")
            with self.subTest(order=order), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_duplicate_references_and_limitations_and_synthetic_source_are_rejected(self) -> None:
        for field in ("evidence_refs", "limitations", "reference"):
            manifest, record, records = bundle(genuine=True)
            if field == "reference":
                records[0]["corpus_origin"] = "synthetic"
                records[0]["method"] = "synthetic_expectation"
            elif field == "limitations":
                record[field] *= 2
            else:
                record[field] *= 2
            with self.subTest(field=field), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_array_order_and_companion_edges_are_bound_to_the_oracle(self) -> None:
        manifest, record, records = bundle()
        extra = {"path": "track.bin", "role": "track", "size": 1, "sha256": "b" * 64}
        for fixture in (record["fixture"], manifest["fixtures"][0]):
            fixture["files"].append(copy.deepcopy(extra))
            fixture["companions"] = [{"source": "disc.bin", "target": "track.bin"}]
        repin(manifest, record, records)
        self.assertEqual(validate(manifest, record, records).fixtures[0].structural_expectation, "validated")
        record["fixture"]["files"].reverse()
        repin(manifest, record, records)
        with self.assertRaises(oracle.OracleError) as caught:
            validate(manifest, record, records)
        self.assertEqual(caught.exception.code, "EVIDENCE_CONFLICT")

    def test_bundle_graph_requires_complete_connected_acyclic_membership(self) -> None:
        cases = (
            ([{"path": "other.bin", "role": "rom", "size": 1, "sha256": "a" * 64}], []),
            ([], [{"source": "disc.bin", "target": "absent"}]),
            ([], [{"source": "disc.bin", "target": "disc.bin"}]),
            ([{"path": "DISC.bin", "role": "rom", "size": 1, "sha256": "a" * 64}], []),
            ([{"path": "disc.bin/child", "role": "rom", "size": 1, "sha256": "a" * 64}], []),
        )
        for additional, edges in cases:
            manifest, record, records = bundle()
            fixture = manifest["fixtures"][0]
            fixture["files"].extend(additional)
            fixture["companions"] = edges
            with self.subTest(additional=additional, edges=edges), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)

    def test_safe_relative_member_paths_and_strict_integer_fields(self) -> None:
        for path in ("/disc.bin", "../disc.bin", "a//b", "a/./b", "a\\b", "a:b"):
            manifest, record, records = bundle()
            manifest["fixtures"][0]["files"][0]["path"] = path
            with self.subTest(path=path), self.assertRaises(oracle.OracleError):
                validate(manifest, record, records)
        for field in ("order", "size"):
            for value in (True, -1, 2**63):
                manifest, record, records = bundle()
                target = manifest["fixtures"][0]
                if field == "size":
                    target = target["files"][0]
                target[field] = value
                with self.subTest(field=field, value=value), self.assertRaises(oracle.OracleError):
                    validate(manifest, record, records)


if __name__ == "__main__":
    unittest.main()
