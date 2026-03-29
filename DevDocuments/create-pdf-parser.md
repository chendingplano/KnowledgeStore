Use superpowers to create a PDF parser and save it in shared/go/api/parsers/pdf-parser:

- PDF Parser is a service, written in Go.
- The service uses PaddleORC (https://github.com/PaddlePaddle/PaddleOCR.git) to parse PDF docs.  Note that Paddle OCR is alredy installed in ~/Workspace/ThirdParty/paddleocr (in the subdirectory PaddleOCR)
- There is a database table: 'kb.inputs' that manages all the inputs. Each record in the table is an input, which can be a document (such as PDF, Word, Excel, PPT, text, markdown, etc.). The table has the following fields:
- The service monitors the database table 'kb.inputs'. For 'type' = 'pdf' input, if its status does not have an entry whose "operation" is "parse", it will pick up the record and start parsing the doc.
- Staging Directory: Input files are originally saved in the staging directory, specified by the env variable STAGING_DIR
- Result Directory: PDF parser will generate some result files, such as one JSON file and one image for each page. Stored the result files in 'PDF_REPO_DIR/pdf_parser/record_id/', where 'PDF_REPO_DIR' is an environment variable and 'record_id' is the record's id. 
- Backup Directory: After processing, the original file is copied to the result directory and the backup directory: DATA_BACKUP_DIR/pdf_files, where 'DATA_BACKUP_DIR' is an environment variable.
- After parsing a PDF file, this service will update the field 'status'
- There is an example file: /Users/cding/Workspace/ThirdParty/paddleocr/parse_pdf.py that shows how to use PaddleOCR to parse a PDF file.

## kb.input Table

| Field Name | Required | Explanation |
|:-----------|:---------|:------------|
| id | mandatory | Auto-incremented ID (integer) that identifies the record |
| name | optional | The name of the inputs |
| type | mandatory | The input type, such as 'word', 'pdf', ... |
| title | optional | The title if the input is a document |
| doc_no | optional | The document number, which is normally a string, if any |
| source | optional | Where the input came from |
| file_name | optional | The file name (url) at which the file is stored, applicable to files only |
| backup_filename | optional | The backup file name |
| publish_date | optional | The doc's publish date |
| authors | optional | The doc's authors |
| owner | optional | The ID of the user Who owns the input |
| status | mandatory | A JSON doc that keeps track of the operations on the input (refer below to its definition) |
| create_time | mandatory | The creation time (read-only) |
| modify_time | mandatory | The last modification time |
| public_info | optional | A JSON document that stores additional public info |
| private_info | optional | A JSON document that stores additional private info |
| notes | optional | Stores notes |
| error_msg | optional | Stores error messages, such as processing error messages |

The field "status" is a JSON of the following format:
```json
[
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "status":"success or fail", "error":"error-msg"},
    {"operation":"the-opr", "time":"timestamp-in-yyyymmdd hh:mm:ss", "status":"success or fail", "error":"error-msg"},
    ...
]
```
where:
- 'operation' specifies the operation performed on the file, such as 'parsing', 'analyzing', 'adding to knowledge', etc.
- 'time': the time when the operation was performed, 
- 'status': success or failed, and "error": the error message.