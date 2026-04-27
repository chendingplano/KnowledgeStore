# Description
This table stores all knowledge stores.

## Table Schema

| Field Name | Required | Data Type | Explanation |
|:-----------|:---------|:------------|:----|
| id | mandatory | integer | Auto-incremented ID (integer) that identifies the record |
| tenant_id | optional | string | Identifies the tenant, default to '-' |
| ks_type | optional | string | It is retrieved from kb.ks_types |
| ks_name | required | string | The name of the knowledge store |
| ks_desc | optional | text | The description of knowledge store |
| ks_sync_mode | optional | string | The knowledge store sync mode |
| ks_sources | optional | array of strings | The knowledge store sources |
| status | optional | string | Default: 'active'. Allowed values: 'active', 'suspended', 'inactive'|
| notes | optional | text | notes |
| error_msg | optional | text | Stores error messages, such as processing error messages |
| public_info | optional | JSON | A JSON document that stores additional public info |
| private_info | optional | JSON | A JSON document that stores additional private info |
| create_time | mandatory | timestamp | The creation time (read-only) |
| modify_time | mandatory | timestamp | The last modification time |

## Table 'kb.ks_types'
This table is defined in /Users/cding/Workspace/KnowledgeStore/table-schemas/table-ks-types.md.

## Field 'ks_sources'
This field specifies the knowledge store's sources, optional. It is normally a list of
local or remote directories, URLs, and database tables. When a source changes, such as
new files are added to a directory, content changed in a web page or a datatabase table,
the Knowledge Store can synchronize the changes, specified by 'ks_sync_mode'.

## Field 'ks_sync_mode'
Allowed values are:
- 'auto': it monitors the changes specified in 'ks_sources' and synchronizes the changes to the knowledge store
- 'manual': it synchronizes the changes manually (by users)