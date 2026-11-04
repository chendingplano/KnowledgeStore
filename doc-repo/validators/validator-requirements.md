---
Date: 2026/11/04
Status: Draft requirements, revised 2026/11/04 after review
---

# 1. Overview

A validator checks a value. It has a well-defined target type, configurable constraints,
and standardized validation results.

Validators are used by anything that needs to check values, normally elements. A typical
use is a form in which users enter an email address, a phone number or an age: the author
gives each input element a validator that fits its value.

Validators are a special type of WPI element (refer [1] for WPI and [2] for the WPI
Editor). Like other elements, they are highly configurable, defined as classes and used as
instances, implemented by code, and edited in the WPI Editor: authors find them in the
palette, and pick and configure them through the Properties panel. Unlike other elements, a
validator is not drawn on a page. In this respect it is like an action ([1] §5). The
element that uses a validator shows its errors.

The WPI Editor's palette lists validators in a "Validators" folder, in two levels:
validator category (§3.1–§3.11) and validators.

Validators are an add-on. What is already built keeps working unchanged. In particular, the
`input` element keeps its own rules: `required`, `max_length`, `validation` and the
`input_type` formats [3].

# 2. Validator architecture

## 2.1 Concepts

There are three concepts:

- Validator type: What kind of object is being validated, such as `email`, `integer`, or
  `date`. A validator class implements one validator type (§2.2).
- Constraint: A reusable validation rule, such as `min`, `max`, `pattern`, or `required`.
- Validation context: Additional information needed, such as country, timezone, sibling
  fields, or database state (§2.4).

The JSON below is indicative only. It shows the idea, not the format: names, nesting and
naming style are settled with the JSON shape (§2.3).

```
{
  "type": "email",
  "constraints": {
    "required": true,
    "maxLength": 254,
    "allowInternationalized": true
  }
}
```

```
{
  "type": "number",
  "constraints": {
    "numericType": "decimal",
    "minimum": 0,
    "maximum": 100,
    "exclusiveMaximum": false,
    "precision": 5,
    "scale": 2
  }
}
```

```
{
  "type": "string",
  "constraints": {
    "minLength": 3,
    "maxLength": 64,
    "pattern": "^[a-z][a-z0-9_-]*$"
  }
}
```

The benefit is that constraints can be reused across different validators, rather than
implementing `minLength`, `maxLength`, and `required` independently for email, username,
hostname, etc.

## 2.2 Validator classes and instances

Validators are defined by descriptors and saved in `kb.wpi_descriptors`, with a kind of
their own, `validator`. This is a new value of the `kind` column, added by a migration. As
with elements and actions:

- A **validator class** is one validator type, such as `email`. It lists the constraints it
  accepts and gives each a default.
- A **validator instance** is one use of a class: a whole copy of the class, kept inside the
  element instance that uses it, plus the instance's own constraint values. A later change
  to the class reaches only instances made afterwards ([1] §3.4).
- Constraints are implemented in code, once each, and shared by the validator classes that
  accept them. They are not descriptors of their own.

Like action instances, validator instances are never stored by themselves. They live in the
page descriptor, inside the element that uses them.

## 2.3 JSON shape

Each validator class must clearly define its JSON shape. The shape gives at least:

- `descriptor_id` and `schema_version`, as every descriptor does.
- `category`: what kind of value it checks (§3.1–§3.11). The palette folders come from it.
  The value-editor folder follows from `code_module_id` instead [5], but validators have
  dozens of classes in many categories, so each class must say which one it is in.
- The type of value it accepts.
- Its constraints: for each, the name, type and default, and whether an instance may change
  it.
- How it treats empty values, and its "non-empty" flag where that is ambiguous (§2.6.5).
- The error codes it reports, with their params (§2.6.3).
- Whether it is synchronous or asynchronous (§2.6.2).
- Where it runs: in the browser and the backend, or in the backend only (§2.5).

The constraint list drives the Properties panel through the data-driven property
definitions [4], so a validator needs no Svelte component of its own.

## 2.4 Using validators

An author gives an element validators in the WPI Editor: they select the element, pick a
validator in its Properties panel, and configure the validator instance there.

A validator checks the value it is configured to read. Normally this is the current value
of the element that uses it. For example, an "Age" input picks an `integer` validator, sets
its limits (say 0 to 150), and the validator reads the input's current value. A validator
that compares values (§3.11) is also configured with the other values it reads.

An element may use more than one validator. Its value is valid only when all of them pass
(§2.6.4).

## 2.5 When and where validators run

Validators normally run at the end of editing. The element decides when editing ends:

- An input: before it loses focus.
- A pulldown menu: after a value is selected.
- An element for editing SQL statements: when the user clicks the button that sends them to
  the backend.

A validator that can run in the browser runs there, so the user sees the result without a
request to the backend.

The backend runs the same validators again on every value it receives, even when the
browser has already checked it, because it cannot assume values were checked in the
browser. Some checks can run only in the backend, such as whether a username already
exists.

To keep the browser and the backend consistent, each validator that runs in both passes one
shared file of test cases in both the Go and the TypeScript tests.

## 2.6 Design considerations

### 2.6.1 Separate parsing, validation, and normalization

For example, parsing `" 123 "` into an integer, validating that it is between 0 and 200, and
normalizing it to `123` are three distinct operations. They can be composed, but should have
explicit behavior. Where a normalized value goes is open (§4).

### 2.6.2 Support both synchronous and asynchronous validation

An email format check is local and synchronous. Checking whether a username already exists
may require a database query.

Asynchronous validators run in the backend. The browser sends the page, the element and the
value, never a table name or a statement: the backend reads the validator from the stored
page ([1] §2, principle 6) and touches only the tables actions may touch ([1] §5.2). A
result for a value that has changed since the check started is discarded.

### 2.6.3 Standardize validation errors

Errors follow JSON Schema's output format (§2.7). Each error has a code, the location of the
value as a JSON Pointer (as WPI's own validation issues use), and params. The message shown
to the user is not stored text: it is made from the code and params, in English and
Chinese, like all WPI text. An instance may replace it with localized text of its own.

For example (indicative):

```
{
  "valid": false,
  "errors": [
    {
      "code": "number.maximum",
      "path": "/age",
      "params": {
        "maximum": 120,
        "actual": 135
      }
    }
  ]
}
```

### 2.6.4 Support composition

At first, an element's validators are combined as `allOf`: all must pass. `anyOf`, `oneOf`,
and `not`, similar to JSON Schema, come later, with a defined rule for which errors the user
sees when no branch passes.

### 2.6.5 Empty values

Avoid a generic `required`. Whether an empty value (absent, null or an empty string) is
valid is decided case by case, by each validator, and stated in its definition. For
`string`, an empty string is a string like any other. Where it is ambiguous, the validator
makes it explicit with a flag, such as "non-empty", that the author sets on the instance.
For example, an empty string is not an email address, but an email field may be optional:
the "non-empty" flag of an `email` instance says which.

### 2.6.6 Regular expressions

A pattern must match the whole value and use only syntax that Go (RE2) and JavaScript
(ECMAScript) read the same way, as the `input` element's patterns already do [3]. Patterns
run only on values under a length limit, because authors' patterns run in viewers'
browsers, where a bad pattern can hang the page.

### 2.6.7 Length

Length is counted in Unicode code points, as the `input` element already does [3], unless a
validator states otherwise (bytes or grapheme clusters).

### 2.6.8 Logging

Backend validation failures are logged. Failures are never silent ([1] §7).

## 2.7 Reuse existing standards

JSON Schema 2020-12 is the normative source. Validators take their constraint names and
meanings from it (`minLength`, `maximum`, `exclusiveMaximum`, `multipleOf`, `pattern`,
`enum`, `minItems`, `uniqueItems`, `dependentRequired`, `allOf`/`anyOf`/`oneOf`/`not`) and
report errors in its output format. It is the only one listed below that is data rather
than code, which WPI descriptors must be ([1] §2, principle 1).

Two differences to handle:

- In JSON Schema, `format` is only an annotation by default. A WPI validator that checks a
  format, such as an email address or a date-time, reports the failure.
- JSON Schema's `pattern` uses ECMAScript regular expressions, while Go uses RE2 (§2.6.6).

The others are written in code or annotations. Use them as catalogues of checks and as
references for behavior:

| Standard/library                                                | Main contribution                                     |
| --------------------------------------------------------------- | ----------------------------------------------------- |
| [JSON Schema](https://json-schema.org/)                         | Declarative validation of structured JSON data        |
| [Zod](https://github.com/colinhacks/zod)                        | TypeScript-first schemas and composable validation    |
| [Ajv](https://github.com/ajv-validator/ajv)                     | High-performance JSON Schema validation               |
| [Go Validator](https://github.com/go-playground/validator)      | Extensive built-in field validators                   |
| [Pydantic](https://docs.pydantic.dev/)                          | Python data models, parsing, and validation           |
| [Jakarta Bean Validation](https://beanvalidation.org/)          | Standardized constraint annotations and extensibility |

One particularly useful reference is Go Validator, which has a large collection of built-in
validators covering strings, networks, identifiers, geographic data, and cross-field
relationships.

# 3. Validators

This section lists comprehensive catalogs of commonly used validators, suitable for building
a reusable validation library, schema engine, or declarative application framework.

Their implementation is incremental (§3.12). The names are working names. Some entries,
such as `pattern`, `length` and `range`, may become constraints of another type rather than
types of their own (§4).

## 3.1 Primitive value validators

These are the most fundamental validators.

| Validator | Common constraints                                    |
| --------- | ----------------------------------------------------- |
| `string`  | min/max length, empty, blank, trimming, normalization |
| `integer` | min/max, positive, negative, zero, multipleOf         |
| `decimal` | min/max, precision, scale, rounding policy            |
| `number`  | integer/decimal, finite, min/max, multipleOf          |
| `boolean` | true/false, requiredTrue                              |
| `enum`    | allowed values, excluded values                       |
| `null`    | must be null, must not be null                        |
| `binary`  | byte length, allowed encoding                         |
| `bigint`  | min/max, sign, digit count                            |

Separate `integer`, `decimal`, and `number` because their semantics and validation
requirements differ. For example, decimal precision matters in financial calculations, while
integer overflow matters for bounded integer representations.

## 3.2 String and text validators

| Validator        | Common constraints                      |
| ---------------- | --------------------------------------- |
| `length`         | min/max/exact length                    |
| `pattern`        | regular expression                      |
| `alphanumeric`   | letters and digits only                 |
| `alphabetic`     | letters only                            |
| `numeric_string` | digits only                             |
| `ascii`          | ASCII characters only                   |
| `unicode`        | valid Unicode, normalization form       |
| `slug`           | lowercase, allowed separators, length   |
| `identifier`     | naming convention, allowed characters   |
| `username`       | length, character set, reserved names   |
| `password`       | length, complexity, prohibited values   |
| `contains`       | required substring                      |
| `prefix`         | starts with specified text              |
| `suffix`         | ends with specified text                |
| `case`           | lowercase, uppercase, title case        |
| `whitespace`     | leading/trailing whitespace, blank-only |
| `json_string`    | valid JSON-encoded string               |
| `xml_string`     | well-formed XML                         |
| `base64`         | valid Base64 encoding                   |
| `hex`            | valid hexadecimal encoding              |

Unicode-aware validators should explicitly define whether length means bytes, code points,
or grapheme clusters (§2.6.7).

## 3.3 Internet and network validators

| Validator        | Common constraints                                       |
| ---------------- | -------------------------------------------------------- |
| `email`          | syntax, local-part/domain lengths, IDN support           |
| `domain`         | valid labels, total length, IDN                          |
| `hostname`       | DNS-compatible hostname syntax                           |
| `url`            | syntax, schemes, host, port, path, length                |
| `uri`            | URI syntax, absolute/relative                            |
| `urn`            | URN syntax, namespace identifier                         |
| `ipv4`           | valid address, allowed ranges                            |
| `ipv6`           | valid IPv6, optional zone identifier                     |
| `ip_address`     | IPv4 or IPv6                                             |
| `cidr`           | valid network prefix                                     |
| `mac_address`    | valid MAC address representation                         |
| `port`           | integer range 0–65535; application-specific restrictions |
| `socket_address` | valid host and port combination                          |
| `http_header`    | valid name/value syntax                                  |
| `http_method`    | allowed HTTP methods                                     |
| `mime_type`      | valid media type syntax                                  |
| `content_type`   | media type and parameter constraints                     |
| `semver`         | semantic version syntax and optional range               |
| `user_agent`     | length and application-specific restrictions             |

For email validation, distinguish syntactic validity, domain existence, and mailbox
deliverability. These are separate checks and should not be conflated.

## 3.4 Date and time validators

| Validator      | Common constraints                     |
| -------------- | -------------------------------------- |
| `date`         | valid calendar date, min/max           |
| `time`         | valid time, precision                  |
| `datetime`     | valid date-time, timezone requirements |
| `timestamp`    | numeric epoch or formatted timestamp   |
| `timezone`     | valid IANA timezone identifier         |
| `duration`     | positive/negative, min/max duration    |
| `date_range`   | start ≤ end, maximum duration          |
| `time_range`   | start/end, overlap restrictions        |
| `age`          | min/max age                            |
| `weekday`      | allowed weekdays                       |
| `business_day` | weekdays, holidays, calendar           |
| `cron`         | valid cron expression                  |
| `iso8601`      | ISO 8601 syntax/profile                |
| `rfc3339`      | RFC 3339 date-time syntax              |

Date-time validators should explicitly handle timezone offsets, daylight-saving transitions,
and ambiguous local times.

## 3.5 Collection and structured data validators

| Validator       | Common constraints                      |
| --------------- | --------------------------------------- |
| `array`         | min/max items, item type                |
| `list`          | element constraints, order              |
| `set`           | uniqueness, item type                   |
| `tuple`         | fixed length, positional types          |
| `map`           | key/value types, size                   |
| `object`        | required properties, allowed properties |
| `record`        | field names and types                   |
| `json`          | valid JSON, schema                      |
| `xml`           | well-formedness, XSD validation         |
| `yaml`          | valid YAML, schema                      |
| `csv`           | columns, delimiters, row constraints    |
| `unique_items`  | no duplicate elements                   |
| `sorted`        | ascending/descending                    |
| `contains_item` | required element                        |
| `key_pattern`   | permitted object/map key names          |
| `schema`        | JSON Schema or another schema language  |

## 3.6 Identity and standardized identifier validators

| Validator       | Common constraints                                   |
| --------------- | ---------------------------------------------------- |
| `uuid`          | syntax, UUID version                                 |
| `ulid`          | valid ULID encoding                                  |
| `nanoid`        | alphabet and length                                  |
| `object_id`     | MongoDB ObjectId syntax                              |
| `isbn`          | ISBN-10/13, checksum                                 |
| `issn`          | ISSN syntax, checksum                                |
| `doi`           | DOI syntax                                           |
| `orcid`         | ORCID identifier and checksum                        |
| `iban`          | country format, checksum                             |
| `bic`           | ISO 9362 BIC format                                  |
| `isin`          | ISO 6166 format, checksum                            |
| `lei`           | Legal Entity Identifier, checksum                    |
| `ean`           | EAN/GTIN format, checksum                            |
| `upc`           | UPC/GTIN format, checksum                            |
| `gtin`          | GTIN-8/12/13/14, checksum                            |
| `imei`          | IMEI format, checksum                                |
| `vin`           | Vehicle Identification Number, region-specific rules |
| `country_code`  | ISO 3166 alpha-2/alpha-3                             |
| `language_code` | BCP 47 or ISO 639                                    |
| `currency_code` | ISO 4217                                             |
| `postal_code`   | country-specific postal format                       |
| `phone_number`  | E.164, country-specific numbering                    |
| `credit_card`   | card number length, issuer prefix, Luhn checksum     |
| `national_id`   | country-specific identifier formats                  |

For standardized identifiers, consider separate `format` and `checksum` constraints. A
correctly formatted identifier is not necessarily assigned or active.

## 3.7 File and media validators

| Validator        | Common constraints                                 |
| ---------------- | -------------------------------------------------- |
| `file`           | existence, readable, writable                      |
| `filename`       | length, characters, extension                      |
| `file_path`      | path syntax, allowed directories                   |
| `file_extension` | allowed extensions                                 |
| `file_size`      | min/max bytes                                      |
| `file_type`      | MIME type, magic bytes                             |
| `file_hash`      | checksum algorithm and expected digest             |
| `image`          | format, width, height, aspect ratio                |
| `video`          | format, duration, resolution, codec                |
| `audio`          | format, duration, sample rate, channels            |
| `pdf`            | recognizable PDF structure, page count, encryption |
| `archive`        | format, entries, decompressed size                 |
| `document`       | format, size, page count                           |
| `encoding`       | UTF-8, UTF-16, other encodings                     |

For security-sensitive file validation, extension and declared MIME type are insufficient.
Inspect actual content and enforce resource limits.

## 3.8 Geographic and location validators

| Validator     | Common constraints                          |
| ------------- | ------------------------------------------- |
| `latitude`    | −90 to 90                                   |
| `longitude`   | −180 to 180                                 |
| `coordinates` | valid latitude/longitude pair               |
| `altitude`    | min/max, unit                               |
| `geojson`     | valid GeoJSON structure and geometry        |
| `bbox`        | valid bounding box                          |
| `polygon`     | valid geometry, ring closure                |
| `distance`    | nonnegative, min/max, unit                  |
| `address`     | required components, country-specific rules |
| `region_code` | valid administrative subdivision code       |
| `geohash`     | alphabet, length, precision                 |

## 3.9 Numeric, mathematical, and measurement validators

Beyond basic numeric validation, these are useful for scientific, engineering, and financial
applications.

| Validator         | Common constraints                        |
| ----------------- | ----------------------------------------- |
| `range`           | inclusive/exclusive boundaries            |
| `precision`       | maximum significant digits                |
| `scale`           | maximum decimal places                    |
| `multiple_of`     | divisible by a specified value            |
| `positive`        | greater than zero                         |
| `nonnegative`     | greater than or equal to zero             |
| `finite`          | reject NaN and infinity                   |
| `percentage`      | typically 0–100                           |
| `probability`     | 0–1                                       |
| `ratio`           | min/max, denominator restrictions         |
| `angle`           | degrees/radians, range                    |
| `measurement`     | numeric value, unit, dimension            |
| `unit`            | allowed units, dimensional compatibility  |
| `currency_amount` | currency, scale, sign                     |
| `vector`          | dimension, element type, norm             |
| `matrix`          | dimensions, element types, symmetry       |
| `interval`        | valid lower/upper bounds                  |
| `uncertainty`     | nonnegative uncertainty, compatible units |

For example, a `measurement` validator could verify that `12.5 MPa` is valid, while rejecting
`12.5 kg` when the expected physical dimension is pressure.

## 3.10 Security and credential validators

| Validator           | Common constraints                                 |
| ------------------- | -------------------------------------------------- |
| `password_strength` | length, entropy estimate, breached-password policy |
| `jwt`               | structure, signature, issuer, audience, expiry     |
| `api_key`           | format, length, optionally active status           |
| `hash`              | algorithm, hexadecimal/base64 representation       |
| `signature`         | cryptographic signature verification               |
| `certificate`       | X.509 syntax, validity period, trust chain         |
| `public_key`        | key type, encoding, key size                       |
| `token`             | syntax, expiry, issuer                             |
| `permission`        | required permissions                               |
| `role`              | allowed roles                                      |
| `html_safe`         | application-specific HTML sanitization policy      |
| `sql_identifier`    | allowed database identifier syntax                 |
| `path_safety`       | traversal prevention, allowed root                 |

Some of these are better classified as verification or authorization operations, because
they depend on cryptographic keys or external state.

## 3.11 Relational and business-rule validators

These validate relationships between values rather than a single primitive value.

| Validator            | Common constraints                     |
| -------------------- | -------------------------------------- |
| `required`           | value must be present                  |
| `required_if`        | required when a condition holds        |
| `forbidden_if`       | prohibited when a condition holds      |
| `equals_field`       | equal to another field                 |
| `not_equals_field`   | different from another field           |
| `greater_than_field` | greater than another field             |
| `less_than_field`    | less than another field                |
| `mutually_exclusive` | at most one field present              |
| `exactly_one_of`     | exactly one field present              |
| `at_least_one_of`    | one or more fields present             |
| `all_or_none`        | all fields present or none             |
| `dependency`         | field A requires field B               |
| `unique`             | uniqueness in a collection or database |
| `exists`             | referenced record exists               |
| `foreign_key`        | reference integrity                    |
| `conditional`        | apply validator based on a predicate   |
| `custom_expression`  | expression-based validation            |

These validators are particularly important in declarative forms and data-driven
applications.

## 3.12 The first set

Start with a small set that proves the model (classes, instances, and runs in the browser
and the backend) before the catalogue grows.

| Category    | Validators                                       |
| ----------- | ------------------------------------------------ |
| Primitive   | `string`, `integer`, `number`, `boolean`, `enum` |
| Internet    | `email`, `url`                                   |
| Date/time   | `date`, `datetime`                               |
| Identifiers | `uuid`                                           |

Their constraints: minimum and maximum length, pattern, minimum and maximum value, and step
(multiple of).

Next, as needed: `decimal`, `alphanumeric`, `identifier`, `domain`, `ip_address`,
`phone_number`, `time`, `duration`, `country_code`, `currency_code`, `array`, `object` and
`json`. `phone_number` starts with E.164 syntax only, because full checking needs the
libphonenumber data in both Go and TypeScript.

Deferred:

- `file`, `file_size`, `file_type`: no WPI element accepts files yet.
- `schema`: full JSON Schema in both Go and TypeScript is a project of its own, and it
  overlaps `json`.
- `conditional`, `custom_expression`: they need a condition language, and descriptors are
  data, not code ([1] §2, principle 1). Either define a small declarative condition, such
  as `{field, op, value}`, or wait.
- `required`: avoided (§2.6.5).

# 4. Open questions

1. **Drag-and-drop.** How a validator is dragged from the palette, given it is not drawn on
   a page: dropped onto the element that uses it, or placed as a node of its own and linked
   to the element.
2. **Where a class names its code.** By its class ID, as action classes do, or in a
   `code_module_id`, as element classes do. The latter lets several classes share one code,
   such as an `age` class on the `integer` code with fixed limits.
3. **Types versus constraints.** The catalogue lists some constraints as validators:
   `pattern`, `length`, `range`, `precision`, `scale`, `multiple_of`, `positive`, `finite`,
   `contains`, `prefix`, `suffix`, `case`, `whitespace`, `required`. Proposed rule: a type
   says what a value is; a constraint narrows it.
4. **Naming style.** JSON Schema keywords are camelCase (`maxLength`). WPI attributes are
   snake_case (`max_length`), class IDs are kebab-case (`text-editor`), and this catalogue's
   names are snake_case (`ip_address`).
5. **Normalized values.** Where a normalized value goes, for example whether `123` replaces
   `" 123 "` in the input doc, and whether the backend normalizes the same way (§2.6.1).
6. **Other context.** Whether validators can read the locale, the user or a timezone,
   besides the values they are configured to read (§2.4).
7. **Severity.** Whether a validator can report a warning as well as an error, as WPI's own
   validation does.

# 5. References

[1] KnowledgeStore/doc-repo/devdocs/202610/2026102601-devdoc-web-page-interpreter.md

[2] KnowledgeStore/doc-repo/devdocs/202610/2026102701-devdoc-wpi-editor.md

[3] The `input` element's rules: ChenWeb `web/src/lib/wpi/input-validation.ts`,
`server/api/wpi/input_rules.go`, and the `validation` checks in `server/api/wpi/validate.go`

[4] ChenWeb OpenSpec change `wpi-property-editors` (one data-driven property editor)

[5] ChenWeb `openspec/changes/wpi-value-editor-elements/design.md`, D7 (palette folder)
