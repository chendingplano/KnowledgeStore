# Module: WPI Emoji Value Editor

**Module ID:** `20261102-13`  
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0  
**Status:** active — used by the WPI Editor and value-editor elements  
**Project:** ChenWeb (web front end)  
**Location:** `ChenWeb/web/src/lib/components/shared-ui/value-editors/`  
**Created:** 2026-11-02

## 1. What it is

Adapts the shared emoji search picker to WPI's common value-editor interface. It stores the selected Unicode sequence, and can edit an instance property or a bound field on a WPI page.

## 2. Files

| File | Purpose |
|---|---|
| `ChenWeb/web/src/lib/components/shared-ui/value-editors/EmojiPickerEditor.svelte` | WPI adapter, validation, focus and localization |
| `ChenWeb/project_migrations/20261102000004_wpi_emoji_picker.sql` | Active standalone `emoji-picker` class |
| `ChenWeb/web/tests/wpi-emoji/Harness.svelte`, `ChenWeb/web/tests/wpi-emoji/index.html`, `ChenWeb/web/tests/wpi-emoji/main.ts`, `ChenWeb/web/tests/wpi-emoji/test_editor.py`, `ChenWeb/web/tests/wpi-emoji/vite.config.ts` | Browser harness and focused interaction tests |

## 3. Interface

Uses `ValueEditorProps`: `id`, `label`, `value`, `options`, optional `check`, and `onChange`. Selection calls `onChange` with a Unicode string after validation; clear calls it with `undefined`.

## 4. Configuration

None.

## 5. Usage

Configure a class attribute's value editor as `{"id":"emoji-picker","options":{}}`, or add the `emoji-picker` value-editor class to a page and bind it to an input-document field.

## 6. Behaviour and conventions

UI text comes from Paraglide in English and Chinese. Escape closes the picker and restores focus. The property editor supplies undo, reset and validation context.

## 7. Scope and limits

Search needs the shared emoji service and BM25 index; unavailable artwork falls back to Unicode.
