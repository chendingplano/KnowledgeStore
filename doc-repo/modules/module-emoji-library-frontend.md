# Module: Emoji Library Frontend

**Module ID:** `20261102-12`  
**Type:** frontend · **Language:** svelte · **Version:** 1.0.0  
**Status:** active — used by the WPI emoji value editor  
**Project:** shared  
**Location:** `shared/svelte/src/lib/components/emoji/`  
**Created:** 2026-11-02  
**Devdocs:** [2026110202-devdoc-emoji-library](../devdocs/202611/2026110202-devdoc-emoji-library.md)

## 1. What it is

Renders locally hosted emoji artwork and lets an author search, browse and choose an emoji. Consumers save the selected Unicode string.

## 2. Files

| File | Purpose |
|---|---|
| `shared/svelte/src/lib/stores/emojiLibrary.ts`, `shared/svelte/src/lib/stores/emojiLibrary.test.ts` | API client, types and Unicode identity tests |
| `shared/svelte/src/lib/components/emoji/Emoji.svelte` | Local image with Unicode fallback |
| `shared/svelte/src/lib/components/emoji/EmojiSearchPicker.svelte`, `shared/svelte/src/lib/components/emoji/EmojiSearchPicker.svelte.test.ts` | Search/browse picker and Chromium test |

## 3. Interface

Import `Emoji`, `EmojiSearchPicker`, `searchEmojis`, `getEmoji`, `emojiCategories`, `emojiId` and `emojiSvgUrl` from `@chendingplano/shared`. `Emoji` takes `value`, `size`, `label`, and `decorative`. The picker takes `value`, `onSelect`, `locale`, `limit`, and translated `labels` (`placeholder`, `empty`, `error`, `loading`, `all`, `category`, `more`, `attribution`).

## 4. Configuration

| Key | Default | Meaning |
|---|---|---|
| `size` | 24 | Rendered size in CSS pixels |
| `limit` | 30 | Picker page size |
| `locale` | `en` | Metadata language; `zh` selects Chinese |

## 5. Usage

```svelte
<script lang="ts">
  import { Emoji } from '@chendingplano/shared';
</script>
<Emoji value="🎉" label="party popper" />
```

## 6. Behaviour and conventions

The host supplies translations. Requests are debounced and cancelled on search changes; blank-query browse offers more pages. Buttons work with a keyboard and the picker allows text selection. The attribution link opens the locally served notices.

## 7. Scope and limits

The backing application must register shared emoji endpoints and seed the database. Unknown or unavailable images fall back to the Unicode value.
