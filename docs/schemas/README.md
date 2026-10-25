# eagar schemas

Canonical JSON Schema 2020-12 files for the shared `eagar-rules` format (PRD Appendix F, BD-22). Eagar (Swift) and Mark's Windows mail app both read and write these formats. This folder is the source of truth. `Packages/EagarRules/Sources/EagarRules/Resources/` holds byte-identical copies, and a test fails if they drift. After editing a schema here, copy it there.

| File | What it describes |
|---|---|
| `eagar-rules-1.0.schema.json` | One rules document: lanes, sender rules, guards, playbooks, autonomy grants, institution policy (F.1–F.4). |
| `eagar-approval-ledger-1.0.schema.json` | The content-free approval ledger export (F.6, FR-SEND-19). |

## Conventions

- Plain JSON, UTF-8, one document per file. Unknown properties are rejected everywhere. The only exception is root keys of a rules document that start with `x-`: consumers must preserve these and may ignore them. The ledger allows no extension keys.
- **`format` is an assertion.** `documentId` must be a UUID, and every `date-time` must be RFC 3339 with real calendar values. JSON Schema 2020-12 treats `format` as an annotation by default, so a consumer using a general-purpose validator must switch format assertion on (and, in Python's `jsonschema`, install its RFC 3339 checker).
- `pattern` values use only syntax that ECMA-262, ICU and .NET agree on.
- The schemas use only this keyword subset, which the in-house Swift validator (`JSONSchemaValidator`) supports: `type`, `const`, `enum`, `required`, `properties`, `additionalProperties`, `patternProperties`, `items`, `$ref` (local `#/$defs/...`), `$defs`, `oneOf`, `anyOf`, `allOf`, `not`, `minimum`, `pattern`, `format` (`uuid`, `date-time`). The Swift validator refuses a schema that uses anything else, so adding a keyword here means extending the validator first.
- The ledger is content-free by construction. It has no subject, body, address or name fields. Lane, category and edit-class values are limited to letters, digits, `.`, `_` and `-`, so free text and addresses (`@`) cannot appear in them.

## Normative rules outside the schema (Appendix F)

- Rule 1 (autonomy limits): an L3 grant on a `localOnly` lane is refused, and a grant above `policy.maxAutonomy` is flagged and ignored. `RulesSemanticValidator` checks this at read and write time.
- Rule 3 (`crossAccountLeak` cannot be disabled): the schema's `const` enforces it, and `RulesSemanticValidator` checks it again.
- Rules 2, 4, 5 and 6 (body conditions on rules-only lanes, unapproved playbooks, approve-before-send, unresolved placeholders) govern the rules engine at run time. They are implemented with the engine in M3, not here.

## Fixtures

`fixtures/valid/` holds documents that must validate and round-trip unchanged. `fixtures/invalid/` holds documents with exactly one defect each, and the filename names the defect. The Swift tests (`Packages/EagarRules/Tests/EagarRulesTests/FixtureTests.swift`) keep an entry for every invalid fixture giving the JSON Pointer and keyword it must fail on, so a new fixture without an expectation fails the suite. `rules-l3-on-local-only-lane.json` is valid under the schema and fails semantic rule 1.

All fixture data is synthetic (`example.ie`, `example.com`). Never add real names, addresses or mail content.

The conformance fixtures of Appendix F.5 (synthetic input message headers with expected lane, score, state and guard findings) belong to the rules engine and arrive with it in M3.
