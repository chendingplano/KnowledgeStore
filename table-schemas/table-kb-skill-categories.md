# Description
This table stores skill categories.

## Table Schema

| Field Name | Required | Data Type | Explanation |
|:-----------|:---------|:------------|:----|
| id | mandatory | integer | Auto-incremented ID (integer) that identifies the record |
| tenant_id | optional | string | Identifies the tenant, default to '-' |
| skill_category | required | string | the name of the skill category |
| category_level | required | integer | the category level: 1, 2, 3, ... |
| category_desc | optional | text | description of the category |
| notes | optional | text | notes |
| error_msg | optional | text | Stores error messages, such as processing error messages |
| public_info | optional | JSON | A JSON document that stores additional public info |
| private_info | optional | JSON | A JSON document that stores additional private info |
| creator | mandatory | string | the user id of the user who created it |
| modifier | mandatory | string | the user id of the user who last modified it |
| create_time | mandatory | timestamp | The creation time (read-only) |
| modify_time | mandatory | timestamp | The last modification time |
