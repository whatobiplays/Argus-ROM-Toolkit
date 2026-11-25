"""Sanitize WindowManager display headers for Q7 exploratory observations."""

import secrets

def _new_aliases(references, *, prefix):
    references = set(references)
    aliases = {}
    used_aliases = set(references)
    for reference in sorted(references):
        while True:
            alias = f"{prefix}{secrets.randbelow(90_000) + 10_000:05d}"
            if alias not in used_aliases:
                used_aliases.add(alias)
                aliases[reference] = alias
                break
    return aliases


def _sanitize_display_structure(
    records,
    fields,
    relationships,
    *,
    randomize_record_refs,
    redact_all_field_values,
):
    """Anonymize display links and redact selected values in copied records."""
    records = [dict(item) for item in records]
    fields = [dict(item) for item in fields]
    relationships = [dict(item) for item in relationships]

    record_aliases = {}
    if randomize_record_refs:
        record_aliases = _new_aliases(
            (item["record_ref"] for item in records), prefix="record-"
        )
        for item in records:
            item["record_ref"] = record_aliases[item["record_ref"]]

    display_refs = {
        item["value_ref"]
        for item in fields
        if not redact_all_field_values and item.get("value_kind") == "display_ref"
    }
    display_refs.update(
        reference
        for item in relationships
        for reference in (item["source_ref"], item["target_ref"])
        if isinstance(reference, str) and reference.startswith("display-")
    )
    display_aliases = _new_aliases(display_refs, prefix="display-")

    sanitized_fields = []
    for item in fields:
        record_ref = item.get("record_ref")
        if randomize_record_refs and record_ref is not None:
            if record_ref not in record_aliases:
                continue
            item["record_ref"] = record_aliases[record_ref]
        if item.get("value_kind") == "display_ref":
            value_ref = item.get("value_ref")
            if value_ref in display_aliases:
                item["value_ref"] = display_aliases[value_ref]
        if redact_all_field_values or item.get("name") == "rootTaskCount":
            item.pop("value_ref", None)
            item.pop("value", None)
            item["value_kind"] = "redacted"
        sanitized_fields.append(item)

    sanitized_relationships = []
    for item in relationships:
        if randomize_record_refs:
            source_ref = item["source_ref"]
            target_ref = item["target_ref"]
            if source_ref not in record_aliases or target_ref not in record_aliases:
                continue
            item["source_ref"] = record_aliases[source_ref]
            item["target_ref"] = record_aliases[target_ref]
        if item["source_ref"] in display_aliases:
            item["source_ref"] = display_aliases[item["source_ref"]]
        if item["target_ref"] in display_aliases:
            item["target_ref"] = display_aliases[item["target_ref"]]
        sanitized_relationships.append(item)

    if randomize_record_refs:
        records.sort(key=lambda item: item["record_ref"])
    sanitized_fields.sort(
        key=lambda item: (
            item.get("record_ref") or "",
            item["name"],
            item["association"],
            item["value_kind"],
            item.get("value_ref", str(item.get("value", ""))),
        )
    )
    sanitized_relationships.sort(
        key=lambda item: (item["kind"], item["source_ref"], item["target_ref"])
    )
    return records, sanitized_fields, sanitized_relationships


class Q7WindowDisplayStructuralFilter:
    """Keep safe display structure from a supplied Q7 parser."""

    def __init__(self, *, parser, category_deriver):
        self._parser = parser
        self._category_deriver = category_deriver

    @property
    def failure_diagnostic(self):
        return self._parser.failure_diagnostic

    def feed(self, chunk):
        self._parser.feed(chunk)

    def _project_unowned_display_headers(self):
        records, fields, relationships = self._parser.projection_candidates(
            record_types={"display_content"},
            field_names={"displayId", "rootTaskCount"},
            relationship_kinds={"layout_parent"},
        )
        if not records:
            return None
        allowed_field_kinds = {"displayId": "display_ref", "rootTaskCount": "value_ref"}
        fields = [
            item
            for item in fields
            if item.get("name") in allowed_field_kinds
            and item.get("value_kind") == allowed_field_kinds[item["name"]]
        ]
        display_id_record_refs = {
            item["record_ref"]
            for item in fields
            if item["name"] == "displayId" and item.get("record_ref") is not None
        }
        records = [
            item for item in records if item["record_ref"] in display_id_record_refs
        ]
        if not records:
            return None
        retained_refs = {item["record_ref"] for item in records}
        fields = [item for item in fields if item.get("record_ref") in retained_refs]
        relationships = [
            item
            for item in relationships
            if item["source_ref"] in retained_refs
            and item["target_ref"] in retained_refs
        ]
        records, fields, relationships = _sanitize_display_structure(
            records,
            fields,
            relationships,
            randomize_record_refs=True,
            redact_all_field_values=True,
        )
        record_types = sorted({item["record_type"] for item in records})
        field_names = sorted({item["name"] for item in fields})
        return {
            "record_type_names": record_types,
            "field_names": field_names,
            "records": records,
            "fields": fields,
            "relationships": relationships,
        }

    def _retain_target_display_context(self, observation):
        """Drop display records outside a target record's unique parent path."""
        structure = dict(observation["structure"])
        records = [dict(item) for item in structure["records"]]
        fields = [dict(item) for item in structure["fields"]]
        relationships = [dict(item) for item in structure["relationships"]]
        display_record_refs = {
            item["record_ref"]
            for item in records
            if item["record_type"] == "display_content"
        }
        if not display_record_refs:
            return observation

        target_component_refs = {
            item["value_ref"]
            for item in fields
            if item["value_kind"] == "component_ref"
        }
        target_record_refs = {
            item["source_ref"]
            for item in relationships
            if item["kind"] == "record_component"
            and item["target_ref"] in target_component_refs
        }
        parents_by_child = {}
        for item in relationships:
            if item["kind"] == "layout_parent":
                parents_by_child.setdefault(item["target_ref"], set()).add(
                    item["source_ref"]
                )

        retained_display_refs = set()
        for target_record_ref in target_record_refs:
            current_ref = target_record_ref
            visited = set()
            while current_ref not in visited:
                visited.add(current_ref)
                parents = parents_by_child.get(current_ref, set())
                if len(parents) != 1:
                    break
                parent_ref = next(iter(parents))
                if parent_ref in display_record_refs:
                    retained_display_refs.add(parent_ref)
                    break
                current_ref = parent_ref

        dropped_display_refs = display_record_refs - retained_display_refs
        if not dropped_display_refs:
            return observation

        structure["records"] = [
            item for item in records if item["record_ref"] not in dropped_display_refs
        ]
        structure["fields"] = [
            item for item in fields if item.get("record_ref") not in dropped_display_refs
        ]
        structure["relationships"] = [
            item
            for item in relationships
            if item["source_ref"] not in dropped_display_refs
            and item["target_ref"] not in dropped_display_refs
        ]
        structure["record_type_names"] = sorted(
            {item["record_type"] for item in structure["records"]}
        )
        structure["field_names"] = sorted(
            {item["name"] for item in structure["fields"]}
        )
        redacted_names = sorted(
            {
                item["name"]
                for item in structure["fields"]
                if item["value_kind"] == "redacted"
            }
        )
        observation = dict(observation)
        observation.update(
            {
                "available_field_categories": self._category_deriver(
                    structure["record_type_names"], structure["field_names"]
                ),
                "redacted_field_names": redacted_names,
                "structure": structure,
            }
        )
        return observation

    def _redact_target_display_values(self, observation):
        observation = self._retain_target_display_context(observation)
        structure = dict(observation["structure"])
        records, fields, relationships = _sanitize_display_structure(
            structure["records"],
            structure["fields"],
            structure["relationships"],
            randomize_record_refs=False,
            redact_all_field_values=False,
        )
        structure["records"] = records
        structure["fields"] = fields
        structure["relationships"] = relationships
        redacted_names = sorted(
            set(observation["redacted_field_names"])
            | {item["name"] for item in fields if item["value_kind"] == "redacted"}
        )
        observation = dict(observation)
        observation.update(
            {
                "redacted_field_names": redacted_names,
                "structure": structure,
            }
        )
        return observation

    def finish(self):
        parser_result = self._parser.finish(preserve_structure=True)
        try:
            if parser_result["target_component_observed"]:
                return self._redact_target_display_values(parser_result)

            display_structure = self._project_unowned_display_headers()
            if display_structure is None:
                display_structure = {
                    "record_type_names": [],
                    "field_names": [],
                    "records": [],
                    "fields": [],
                    "relationships": [],
                }

            structure = {
                **display_structure,
                "unclassified_line_count": 0,
                "unrecognized_field_count": 0,
                "empty_field_value_count": 0,
                "sensitive_tail_truncated_count": 0,
            }
            field_names = structure["field_names"]
            redacted_names = sorted(
                {
                    item["name"]
                    for item in structure["fields"]
                    if item["value_kind"] == "redacted"
                }
            )
            return {
                "lines_observed": parser_result["lines_observed"],
                "max_line_bytes": parser_result["max_line_bytes"],
                "available_field_categories": self._category_deriver(
                    structure["record_type_names"], field_names
                ),
                "timeout_indicator_observed": parser_result["timeout_indicator_observed"],
                "timeout_indicator_count": parser_result["timeout_indicator_count"],
                "completion_indicator_observed": parser_result["completion_indicator_observed"],
                "completion_indicator_count": parser_result["completion_indicator_count"],
                "intent_content_observed": False,
                "redacted_field_names": redacted_names,
                "target_component_observed": False,
                "eof_observed": parser_result["eof_observed"],
                "completion_verified": False,
                "target_binding_established": False,
                "task_continuity_established": False,
                "structure": structure,
            }
        finally:
            self._parser.discard()

    def discard(self):
        return self._parser.discard()
