# Overview

## Table `kb.artifact_categories`
This table stores all artifact categories.

```sql
CREATE TABLE kb.artifact_categories (
	category_id int8 GENERATED ALWAYS AS IDENTITY( INCREMENT BY 1 MINVALUE 1 MAXVALUE 9223372036854775807 START 1 CACHE 1 NO CYCLE) NOT NULL,
	category_key text NOT NULL,
	category_type text NOT NULL,
	status text DEFAULT 'pending_review'::text NOT NULL,
	canonical_of text NULL,
	display_names jsonb DEFAULT '[]'::jsonb NOT NULL,
	required_attrs jsonb DEFAULT '[]'::jsonb NOT NULL,
	specs jsonb DEFAULT '{}'::jsonb NOT NULL,
	plausible_ranges jsonb DEFAULT '{}'::jsonb NOT NULL,
	embedding jsonb DEFAULT '[]'::jsonb NOT NULL,
	seen_count int8 DEFAULT 0 NOT NULL,
	first_seen_at timestamptz DEFAULT now() NOT NULL,
	last_seen_at timestamptz DEFAULT now() NOT NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	modify_time timestamptz DEFAULT now() NOT NULL,
	CONSTRAINT categories_pkey PRIMARY KEY (category_key),
	CONSTRAINT categories_status_check CHECK ((status = ANY (ARRAY['pending_review'::text, 'approved'::text, 'rejected'::text, 'merged'::text])))
);
CREATE INDEX idx_kb_categories_canonical_of ON kb.categories USING btree (canonical_of);
CREATE INDEX idx_kb_categories_seen_count ON kb.categories USING btree (seen_count DESC);
CREATE INDEX idx_kb_categories_status ON kb.categories USING btree (status);
```

## Table `kb.category_instance`
This is a relation table that connects artifacts to artifact categories.
It has the following fields:
- category_id
- artifact_id
- input_record_id
- extra_info (JSON)
- create_time