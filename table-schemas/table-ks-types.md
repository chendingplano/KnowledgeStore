# Description
This table stores knowledge store types.

## Table Schema

| Field Name | Required | Data Type | Explanation |
|:-----------|:---------|:------------|:----|
| id | mandatory | integer | Auto-incremented ID that identifies the record |
| tenant_id | optional | string | Identifies the tenant, default to '-' |
| ks_type_name | required | string | The display name of knowledge store types|
| ks_type_id | required | string | The id of knowledge store types, unique per tenant |
| ks_type_desc | optional | string | The description |
| status | optional | string | Default: 'active'. Allowed values: 'active', 'suspended', 'inactive'|
| notes | optional | text | notes |
| public_info | optional | JSON | A JSON document that stores additional public info |
| private_info | optional | JSON | A JSON document that stores additional private info |
| creator | mandatory | string | The user id of the user who created the record |
| modifier | mandatory | string | The user id of the user who last modified the record |
| create_time | mandatory | timestamp | The creation time (read-only) |
| modify_time | mandatory | timestamp | The last modification time |