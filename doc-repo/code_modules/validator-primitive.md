# Code modules: the primitive validators

**Code module IDs:** `string`, `integer`, `decimal`, `number`, `boolean`, `enum`, `null`,
`binary`, `bigint` (module type `validator`) \
**Classes using them:** nine, one per module, with the same IDs; category `primitive` \
**Implementation status:** implemented and active, 2026-11-04 \
**Catalogue rows:** `kb.code_modules`, "String Validator" … "Bigint Validator", type
`validator`, `module_doc` `validator-primitive.md`, from migration
`ChenWeb/project_migrations/20261104000002_wpi_primitive_validators.sql` \
**What each module accepts:** `ChenWeb/server/api/wpi/validators/modules.json`, read by both
languages. It is the authority; the tables below restate it. \
**Backend:** package `ChenWeb/server/api/wpi/validators` (`Run`, `CheckConstraints`); class
rows, instances and runs on save in `ChenWeb/server/api/wpi/validator_classes.go` \
**Frontend:** `ChenWeb/web/src/lib/wpi/validators/` (`runValidator`, `runValidators`, error
text in `messages.ts`); the Properties panel's groups in
`ChenWeb/web/src/lib/wpi/properties/validators.ts` \
**Shared cases:** `ChenWeb/server/api/wpi/validators/validator-cases.json` \
**OpenSpec:** ChenWeb change `wpi-primitive-validators` \
**Requirements:** [Validator requirements](../validators/validator-requirements.md) §3.1 \
**Part of:** reusable modules `20261026-01` and `20261026-02` (Web Page Interpreter frontend
and backend)

## 1. Purpose and boundary

A validator checks one value against constraints and reports standard errors. These nine
modules check the primitive JSON values: text, numbers of four kinds, booleans, choices from a
list, null, and bytes written as text.

A validator is not drawn. An `input`, `select` or value-editor element uses it, by holding
validator instances in its `validators` attribute. The element runs them when editing ends and
before a save, and shows their errors. The backend runs them again on every save.

Not part of these modules:
- other values (§3.2–§3.11 of the requirements);
- checks that need the database or that run in the backend only;
- `anyOf`, `oneOf` and `not` composition;
- writing a normalized value back into the input doc.

## 2. Class rows

The rows are kind `validator`, format `schema_version` `0.1`, version 1, status `active`, by
`seed:wpi-primitive-validators`. A class row:

| Attribute | Meaning |
| --- | --- |
| `descriptor_id`, `schema_version`, `description`, `implement_notes` | As for every class. `description` is required, in English and Chinese. |
| `code_module_id` | The validator module that runs the class. Several classes may share one, such as an `age` class on `integer`. |
| `category` | The palette sub-folder, one of `primitive`, `text`, `network`, `datetime`, `collection`, `identifier`, `file`, `geographic`, `numeric`, `security`, `relational` (requirements §3.1–§3.11). It may differ from the module's. |
| `constraints` | The constraints instances may set. Each is an object: `type` (and `choices`), `help_tip`, `default_value` (`null`: every instance must set it; absent: not applied until set), `instance_modifiable` (`false` fixes the default) and optionally `value_editor` (`{id, options}`, overriding the Properties panel's editor). |
| `value_types`, `empty_values`, `empty_constraint`, `execution`, `runs_in`, `error_codes` | Facts about the code, stated so the row describes itself. A row that disagrees with its code is refused. |

A class may list only some of its module's constraints. Instances may set only the ones it
lists, and a constraint it does not list keeps the code default.

## 3. Instances

A validator instance lives in the `validators` array of the element that uses it:

```json
{"validator": "integer", "class": {"…": "the whole class row"},
 "constraints": {"minimum": 0, "maximum": 150},
 "messages": {"integer.maximum": {"en": "Age is at most {maximum}.", "zh-cn": "年龄不超过 {maximum}。"}}}
```

- **Effective constraints**, in increasing priority: the code defaults, the copy's
  `default_value`s, then the instance's `constraints`. A constraint the copy fixes keeps its
  value.
- **Messages.** `messages` replaces the built-in text of the codes it names. `{param}` is
  filled in from the error's params.
- **The list.** All validators of an element must pass (`allOf`).
- **Copies.** A page save fills a missing `class` from the latest active class row.

## 4. Empty values

An empty value is absent, `null` or `""`. Every module but `null` has the constraint `empty`:

| `empty` | Effect |
| --- | --- |
| `pass` | Accepted, with no other check. The default for all modules but `string`. |
| `fail` | Rejected with `<module>.empty`; this makes the value required. |
| `check` | Read as the type's empty value and checked like any other: `""` for `string` (the default there, so `min_length: 1` rejects it), `false` for `boolean`, and for `enum` the value itself, absent read as `null`. Only these three modules offer it. |

`null` checks null-ness itself (`mode`), and `absent_is_null` and `empty_string_is_null` say
what counts as null.

## 5. Constraints

Constraint names are snake_case forms of JSON Schema 2020-12 keywords, with their meanings.
The checks run in the order listed in `modules.json`. A type error ends them; otherwise every
failing constraint is reported.

| Module | Value it reads | Constraints (code default) |
| --- | --- | --- |
| `string` | A string; absent and `null` are empty | `empty` (check), `trim` none/both/start/end (none), `normalization` none/nfc/nfd/nfkc/nfkd (none), `length_unit` code_points/utf16_units/utf8_bytes (code_points), `min_length`, `max_length`, `non_blank` (false), `single_line` (false), `pattern`, `prefix`, `suffix`, `contains` |
| `integer` | A JSON number that is whole, or with `accept_strings` digits such as `" 42 "`; at most ±(2⁵³−1) | `empty` (pass), `accept_strings` (true), `minimum`, `maximum`, `exclusive_minimum`, `exclusive_maximum`, `sign` any/positive/negative/non_negative/non_positive/non_zero (any), `multiple_of`, `representation` any/int8/int16/int32/uint8/uint16/uint32 (any) |
| `number` | A JSON number, or with `accept_strings` decimal text | `empty` (pass), `accept_strings` (true), `allow_non_finite` (false), `integer_only` (false), the bounds, `sign`, `multiple_of` |
| `decimal` | Decimal text, kept exactly, or with `accept_numbers` a JSON number by its shortest form | `empty` (pass), `accept_numbers` (true), `scale`, `rounding` reject/half_up/half_even/down/up/floor/ceiling (reject), `precision`, the bounds, `sign`, `multiple_of` |
| `boolean` | `true`/`false`; with `accept_strings` the text true/false in any case; with `accept_numbers` 1 and 0 | `empty` (pass), `accept_strings` (false), `accept_numbers` (false), `must_be` either/true/false (either) |
| `enum` | Any JSON value; objects compare by content | `empty` (pass), `allowed_values` (every instance must set it), `excluded_values`, `case_sensitive` (true), `type_sensitive` (true; when false `1` equals `"1"`) |
| `null` | Any value | `mode` must_be_null/must_not_be_null (must_be_null), `absent_is_null` (true), `empty_string_is_null` (false) |
| `binary` | Text that encodes bytes | `empty` (pass), `encoding` base64/base64url/hex (base64), `ignore_whitespace` (false), `padding` optional/required/forbidden (optional), `hex_case` any/lower/upper (any), `min_bytes`, `max_bytes` |
| `bigint` | Digits of any length, or with `accept_numbers` a JSON number up to ±(2⁵³−1) | `empty` (pass), `accept_numbers` (true), `allow_leading_zeros` (true), `min_digits`, `max_digits`, the bounds, `sign`, `multiple_of`, `representation` unbounded/int64/uint64/int128/uint128 (unbounded) |

Rules that apply to several of them:
- **Exact numbers.** `integer`, `number`, `decimal` and `bigint` compare, round and divide
  exactly, as decimals. A JSON number is read by its shortest round-trip form, so `0.3` is a
  multiple of `0.1`. Text longer than 1 000 characters, or with an exponent beyond ±1 000, is
  not a number.
- **Precision and scale** follow SQL `NUMERIC(p, s)`. `precision` is the most digits in all.
  With `scale` set, at most `precision − scale` digits may come before the point. Trailing
  zeros after the point and leading zeros before it do not count.
- **Patterns** match the whole value. They must compile in Go and use no inline flags or
  named groups, and none of `\A \z \Q \E \p \P`. A value longer than 10 000 code points fails
  with `string.pattern_limit` instead of being matched.
- **Whitespace** is the Unicode White_Space set plus U+FEFF, in both languages. Line breaks
  are `\n`, `\r`, U+2028 and U+2029.
- **Length** counts code points unless `length_unit` says otherwise.
- **Case.** `enum` without case sensitivity lowercases with `toLowerCase`/`strings.ToLower`.
  These differ for a few characters, such as U+0130 İ.

## 6. Results and errors

A result is `{valid, errors, value}`. `value` is the normalized value (trimmed text, the
parsed number, the plain decimal or digit string) when the value is valid. Nothing writes it
back yet. An error is `{code, path, params, validator}`:
- `path` is the JSON Pointer of the bound value (`$input_doc.address.city` →
  `/address/city`);
- `params` holds the constraint values involved, plus `actual` for counts;
- `validator` is the validator's index in the element's list.

| Codes | Params |
| --- | --- |
| `<module>.type`, `<module>.empty` | — |
| `string.min_length`, `string.max_length` | the limit, `length_unit`, `actual` |
| `string.blank`, `string.line_break` | — |
| `string.pattern` · `string.pattern_limit` | `pattern` · `limit` |
| `string.prefix`, `string.suffix`, `string.contains` | the text |
| `<module>.minimum`, `.maximum`, `.exclusive_minimum`, `.exclusive_maximum`, `.multiple_of` | the limit as configured |
| `<module>.sign` | `sign` |
| `integer.range`, `bigint.range` | `representation`, `lowest`, `highest` (text) |
| `integer.unsafe`, `bigint.unsafe_number`, `number.finite`, `number.integer`, `bigint.leading_zeros` | — |
| `decimal.scale` · `decimal.precision` · `decimal.integer_digits` | the limit and `actual` |
| `boolean.must_be` | `must_be` |
| `enum.not_allowed` · `enum.excluded` | `allowed_values` · `excluded_values` |
| `null.must_be_null`, `null.must_not_be_null` | — |
| `binary.encoding` · `binary.padding` · `binary.case` | `encoding` · `padding` · `hex_case` |
| `binary.min_bytes`, `binary.max_bytes`, `bigint.min_digits`, `bigint.max_digits` | the limit and `actual` |

The browser makes the text from Paraglide messages `wpi_vld_e_*`, in English and Chinese. It
looks up the full code first (`integer.type`), then the part after the dot (`maximum`). The
backend refuses a failing save with 422:

```json
{"field_errors": {}, "validation_errors": {"age": [{"code": "integer.maximum", "path": "/age", "params": {"maximum": 150}, "validator": 0}]}}
```

## 7. Property editor

An element that takes validators (`input`, `select`, value-editor) has a **Validators** group.
Its one property, `validators`, lists the instances (move up, move down, remove) and offers
"Add validator". Then each instance has a group, "Validator *n*: *class*", whose help is the
class description. That group has one property per constraint its copy lists, in the code's
order, and a final **Messages** property drawn as JSON. Labels and choice labels come from
Paraglide (`wpi_vld_c_*`, `wpi_vld_choice_*`); help tips, defaults and the fixed and required
marks come from the copy.

| Constraint type | Value editor |
| --- | --- |
| `boolean` | switch |
| `integer`, `non_negative_integer`, `positive_integer` | number (whole; at least 0 or 1) |
| `number`, `positive_number` | number |
| `decimal`, `positive_decimal`, `bigint`, `positive_bigint` | text, refused unless it is a decimal or whole number |
| `string` | text |
| `pattern` | text, refused unless the browser compiles it and it avoids the non-portable syntax |
| `choice` | value-picker |
| `json_array` | json, refused unless it is an array |

Dropping a validator from the palette's **VALIDATORS → PRIMITIVE** folder onto such an element
on the canvas page adds an instance with a copy of the class and selects the element.

## 8. Changing these modules

- **Change both languages.** Change `modules.json` first, then the Go and TypeScript checks,
  and add cases to `validator-cases.json`. Both suites run every case:
  `go test ./server/api/wpi/validators/` and `bun test src/lib/wpi/validators/`.
- **Keep the seed rows in step.** `TestSeedValidatorClasses` (`server/api/wpi/seed_test.go`)
  refuses seeded rows that miss a constraint or error code, or disagree with the code. A new
  constraint therefore also needs a new class version.
- **New error codes** need a `wpi_vld_e_*` text in both message files.
  `messages.test.ts` fails for a code without one.
- **A new validator module** needs:
  - a `kb.code_modules` row of type `validator`;
  - its code in both registries (`run.go`, `run.ts`);
  - a class row;
  - this document or one of its own.
- **Another element module that should take validators** goes into `validatorModules`, in
  both `validator_classes.go` and `validators/index.ts`.
