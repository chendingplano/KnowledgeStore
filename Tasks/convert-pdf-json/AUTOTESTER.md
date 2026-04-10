# Environment
GitRepo: https://github.com/deepdocs-cd/pdf-proc.git
Local Directory: ~/Workspace/shared-projects/pdf-proc (note that this directory has not been created yet)

# Initialize the Test Environment
1. The service uses the table 'kb_input_testonly'. If the table is empty, report an error.
2. Configure the service to read from 'kb_input_testonly' (the production system normally reads from 'kb_input')
3. The field 'notes' must be 'test-only' for all records in 'kb_input_testonly'. Otherwise, set them to 'test-only'
4. The field 'status' must be empty. If not, report errors. These records will not participate the test.
5. The field 'result_filename' in 'kb_input_testonly' table is the input JSON file name in the 'asserts' directory. The converted file should be saved in the same directory.
6. Configure the service to read 'kb_input_testonly' every 1 second
7. Start the service.

# Test Loop
The test loop is:
- Pick a test record from kb.input (refer to 'Pick Record' section)
- Change the record type to a normal record (refer to 'Change Record Type' section), i.e., set its 'status' field to:
```json
[
  {
    "time": "20260328 16:58:44",
    "error": "",
    "status": "success",
    "operation": "parse"
  }
]
```
- The service will pick up this record, process it and save the result in the 'asserts' directory.
- Wait for 2 seconds. 
- Verify the results (refer to 'Verify Results' section). 
- If the verification succeeds, add the following entry to the 'status' field:
```json
  {
    "time": "20260328 16:58:44",
    "error": "",
    "status": "success",
    "operation": "compact"
  }
```
This finishes testing one record. Do the following:
  1. Add an entry summarize this test to the 'Test Report' document.
  2. 'Test Report' is a markdown document. Its file name is: 'compact_json_test_yyyymmdd_\<version\>' in the 'asserts' directory, where the last. If the file already exists, Repeat this loop until all records are tested and successful.
- If the verification fails: 
  1. Use the superpowers skill to solve the problem
  2. Remove the result file, if it generated
  3. Restore the 'status', if it is modified
  4. Retest this record

# Pick Record 
Pick a record whose 'status' field does not have the entry:
```json
[
  {
    "time": "20260328 16:58:44",
    "error": "",
    "status": "success",
    "operation": "compact"
  }
]
```
