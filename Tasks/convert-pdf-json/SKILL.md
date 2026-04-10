Use superpowers skill

# Environment
GitRepo: https://github.com/deepdocs-cd/pdf-proc.git
Local Directory: ~/Workspace/shared-projects/pdf-proc (note that this directory has not been created yet)

# Description
Develop a Go service. It monitors the table `ks.input` (below is the table's schema):

```sql
CREATE TABLE kb.inputs (
	id bigserial NOT NULL,
	"name" text NULL,
	"type" varchar(50) NOT NULL,
	title text NULL,
	doc_no varchar(255) NULL,
	"source" text NULL,
	file_name text NULL,
	backup_filename text NULL,
	result_filename text NULL,
	publish_date date NULL,
	authors text NULL,
	"owner" int8 NULL,
	status jsonb DEFAULT '[]'::jsonb NOT NULL,
	create_time timestamptz DEFAULT now() NOT NULL,
	modify_time timestamptz DEFAULT now() NOT NULL,
	public_info jsonb NULL,
	private_info jsonb NULL,
	notes text NULL,
	error_msg text NULL,
	md5 varchar(64) NULL,
	CONSTRAINT inputs_pkey PRIMARY KEY (id)
);
```

'status' is a JSON doc. Below is an example:
```json
[
  {
    "status": "active",
    "progress": "100%",
    "operation": "parsing",
    "start_time": "20260330 16:05:33",
    "sec_elapsed": 559
  },
  {
    "time": "20260330 16:14:53",
    "error": "",
    "status": "success",
    "operation": "parse"
  }
]
```

The service checks the table every N (configurable, default to 10) seconds. If a record 'status'
field has an entry:
```json
  {
    "time": "20260330 16:14:53",
    "error": "",
    "status": "success",
    "operation": "parse"
  }
```

but does not have an entry with "operation" = "convert-json" and its 'type' is 'pdf', this means
the record is for a PDF document. Its content has been extracted and saved in a file whose name is in 'result_filename'. 

This task converts the file into a compact form.

# ConvertLogic
The input is a JSON file from the field 'result_filename'. In addition, the directory also has an image file for each of the pages. The image file names are 'page_ddd.png', such as page_1.png, page_2.png, ..., page_28.png. 

Below is a portion of the input file ('result_filename'):
```json

{
  "input_id": 22,
  "source_pdf": "/Users/cding/Apps/Staging/stdGk_3031867.pdf",
  "generated_at": "2026-03-31T02:27:09.904455+00:00",
  "engine": "paddleocr",
  "pages": [
    {
      "res": {
        "input_path": null,
        "page_index": null,
        "page_count": null,
        "width": 1191,
        "height": 1684,
        "model_settings": {
          "use_doc_preprocessor": false,
          "use_layout_detection": true,
          "use_chart_recognition": false,
          "use_seal_recognition": false,
          "use_ocr_for_image_block": false,
          "format_block_content": false,
          "merge_layout_blocks": true,
          "markdown_ignore_labels": [
            "number",
            "footnote",
            "header",
            "header_image",
            "footer",
            "footer_image",
            "aside_text"
          ],
          "return_layout_polygon_points": true
        },
        "parsing_res_list": [
          {
            "block_label": "text",
            "block_content": "ICS 11.020",
            "block_bbox": [
              137,
              147,
              254,
              172
            ],
            "block_id": 0,
            "block_order": 1,
            "group_id": 0,
            "block_polygon_points": [
              [
                137.0,
                147.0
              ],
              [
                254.0,
                147.0
              ],
              [
                254.0,
                172.0
              ],
              [
                137.0,
                172.0
              ]
            ]
          },
          {
            "block_label": "text",
            "block_content": "C 05",
            "block_bbox": [
              136,
              178,
              191,
              204
            ],
            "block_id": 1,
            "block_order": 2,
            "group_id": 1,
            "block_polygon_points": [
              [
                136.0,
                178.0
              ],
              [
                190.0,
                178.0
              ],
              [
                190.0,
                203.0
              ],
              [
                136.0,
                203.0
              ]
            ]
          },
          ...
      }
    }
}
```

For a complete example, refer to `assets/ocr_rslt_22.json`. There are multiple "parsing_res_list" entries in the above JSON file, one per page in the file.

This service extracts all the entries in all the "parsing_res_list", convert them to the following format:
```json
{
    "page_no": ddd,
    "block_id": ddd,
    "block_label": "xxx",
    "block_content": "xxx",
    "block_bbox": [ddd, ddd, ddd, ddd],
    "image": "xxx"
}
```

The output file name is '<origin_filename_without_ext>' + '_comp.json'. For instance, if the input file name is 'ocr_rslt_22.json', the output file name is 'ocr_rslt_22_comp.json'.

After the conversion, it set an entry to 'status' field:
```json
{
  {
    "time": "yyyymmdd hh:mm:ss",
    "status": "success",
    "operation": "converted"
  }
}
```

If the conversion failed, set an entry to 'status' field:
```json
{
  {
    "time": "yyyymmdd hh:mm:ss",
    "status": "failed",
    "error": "error-message",
    "operation": "converted"
  }
}
```

Note it `sets` the entry, which means if the entry with "operation" = "converted" already exists, replace it.

# Test
Refer to AUTOTESTER.md for testing. 
