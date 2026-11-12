# Document pipeline defaults — administrator configuration

**Date:** 2026-11-12  
**Scope:** Defaults for document processors and upload processing mode.  
**Code root:** `ChenWeb/server/api/doc-processing` and `ChenWeb/web/src/lib/components/home3`

## Summary

System administrators can choose the processors used for new document runs and the initial Auto-Run Mode under Development → System Admin → Doc Process Pipeline → Config. Required pipeline stages remain enabled. Uploaders can still choose another mode for an individual upload. Processor changes take effect when the document processor service restarts; the upload page reads the saved mode when opened.

## Details

The admin-only `PUT /api/v1/kb/pipeline-defaults` validates the selected processor names against `doc-processing.required_processors`, requires at least one, and accepts the four upload modes `auto_offpeak`, `auto`, `upload_only`, and `pdf_parsing`. It atomically writes `doc-pipeline-defaults.json` beside the configuration file; this operator-specific file is ignored by version control. `GET /api/v1/kb/config` exposes the effective settings. Without the file, existing configured processor defaults and the upload page's off-peak default are retained. Upload and pending-file requests that omit a mode use the saved mode, or retain their former `auto` fallback when no saved mode exists.

The document processor reads the file at startup before consulting `doc-processing.default_processors`. The API and processor must resolve to the same configuration directory, including when `KB_CONFIG_FILE` or the processor's config environment variables are set. The required processors list determines which processors can be selected; it does not itself change through this page. Existing documents and already-running work are not altered. The browser keeps an unsaved draft per tab while navigating.

## Known limitations

- The API and processor need a shared configuration directory; settings are not synchronized between hosts.
- Restart the document processor service after changing processor defaults.
