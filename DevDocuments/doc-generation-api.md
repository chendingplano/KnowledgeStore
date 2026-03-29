# Document Generation API

## Purposes
Document generation APIs automate PDF and DOCX creation using templates and JSON data. A document generation API turns document creation into a data pipeline: define the layout once in a template, feed it structured JSON, and let the API return a finished PDF or DOCX. No one touches the document by hand. No one copy-pastes a single field.

Date: 2026/03/27 \
Reference: https://dzone.com/articles/scalable-document-generation-api

## Templates

It supports two types of templates:
- Word Template 
- Typst Template (https://typst.app/)


When the API is called, it fetches data from its source and formats it as JSON. The JSON keys 
correspond dirctly to the token names in the template. 

Example: *Invoice*

When an Invoice API is called, it retrieves the data from the database and converts it into:
```json
{
  "companyName": "Meridian Financial Group",
  "invoiceDate": "2024-01-15",
  "invoiceNumber": "INV-00471",
  "lineItems": [
    {
      "description": "API Integration Consulting",
      "qty": 10,
      "unitPrice": 150.0
    },
    { "description": "Compliance Review", "qty": 5, "unitPrice": 200.0 }
  ],
  "totalDue": 2500.0
}
```


There is a .docx Invoice Template that is configured as:
```text
{{companyName}}: the client's company name 
{{invoiceDate \@ MM/dd/yyyy}}: a formatted date like 01/15/2025, 
{{totalDue \# Currency}}: a currency value like $2,500.00
```

'companyName`, `invoceDate` and `totalDue` in the JSON match the tokens in the template.

## Database Tables

This service uses the database table 'doc_gen_log' to manage the service. The table has the following fields:
| Field Name | Mandatory/Optional | Data Type | Explanation |
|:-----------|:-------------------|:----------|:------------|
| request_name | mandatory | string | provided by the CLI |
| customer_id | mandatory | string | Identify the customer |
| customer_name | mandatory | string | Customer Name |
| email | mandatory | string | Customer email, but it can be empty |
| phone_num | optional | string | Customer phone number |
| purpose | mandatory | string | provided by the CLI |
| filename | mandatory | string | the file name of the generated doc |
| status | mandatory | string | Set to 'generated' if generation is successful, or 'failed' otherwise |
| error_msg | optional | string | The error messages if the generation failed |
| remarks | optional | string | Provided by the CLI |
| created_at | mandatory | timestamp in YYYY/MM/DD HH:MM:SS | The creation time |
| updated_at | mandatory | timestamp in YYYY/MM/DD HH:MM:SS | The last modification time |
| created_by | mandatory | string | The user who initialized the CLI call |
---------

## API 

The API receives the following parameters:
- RequestName: a string that uniquely identifies the request
- Purpose: a string that briefly specifies the purpose of the doc
- Remarks: a string (optional) to provide additional information about this call
- SQLstatement: used to retrieve data from the database
- TemplateType: currently support 'word' and 'typst'
- Template: the file name of the template
- Converter: this is a JSON that maps record fields to the parameters in the template 
- OutputDir: the directory in which the generated docs are stored is <OutputDir>/<RequestName>. If the directory exists, which means that RequestName is not unique. This is an error.
- OutputFormat: it can be 'docx', 'typst' or 'pdf'

## Implementation

A document generation API is a service that combines two inputs (a template and a data payload) to produce one output (a finished document). The template controls the visual layer: layout, fonts, branding, and placeholder tokens for dynamic content. The data comes as JSON, with keys that map directly to those placeholders. The API engine merges the two and delivers a production-ready PDF or DOCX, typically in milliseconds.

The workflow of this CLI is:
- Check whether the request ID is unique. If not, report the error and abort the operation
- Create the output directory
- Retrieve data from the database by the provided SQL statement
- Retrieve the template 
- For each retrieved record:
  - Bind the record and the template to generate a document 
  - Save the document into the specified directory 
  - Insert a record into the doc_gen_log table 

## Error Handling

Make sure the implementation checks all the errors and handle them correctly.

