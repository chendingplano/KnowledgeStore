# Description
This table stores skills.

## Table Schema

| Field Name | Required | Data Type | Explanation |
|:-----------|:---------|:------------|:----|
| id | mandatory | integer | Auto-incremented ID (integer) that identifies the record |
| tenant_id | optional | string | Identifies the tenant, default to '-' |
| prompt_name | required | string | The name of the prompt |
| model_name | required | string | The model name |
|  | optional | string | how we know the skill |
| skill_desc | optional | text | the description of the skill |
| skill_frontmatter | optional | text | the frontmatter of the skill |
| self_dev | optional | boolean | whether it is self developed |
| skill_status | optional | string | Default: 'candidate'. Possible values: 'activated', 'installed', 'candidate' |
| skill_url | optional | string | The url where we can get the skill |
| security_level | optional | string | Default: 'unknown' |
| activated_models | optional | array of strings | The names of the activated models |
| home_dir | optional | string | The name of the directory in which the skill is installed |
| notes | optional | text | notes |
| error_msg | optional | text | Stores error messages, such as processing error messages |
| public_info | optional | JSON | A JSON document that stores additional public info |
| private_info | optional | JSON | A JSON document that stores additional private info |
| creator | mandatory | string | the user id of the user who created it |
| modifier | mandatory | string | the user id of the user who last modified it |
| create_time | mandatory | timestamp | The creation time (read-only) |
| modify_time | mandatory | timestamp | The last modification time |

## Field 'skill_status'
- 'candidate': not activated in any model, nor installed. 
- 'installed': installed in the system but not activated in any model yet
- 'activated': activated in the models listed in 'activated_models'

## Field 'skill_category'
Skill categories are stored in the table 'kb.skill_categories' (refer to 'table-kb-skill-categories.md')