<!-- 
tags: kb.input, pdf, pdf-parser, pdf-process 
summary: The design document for converting extracted results in JSON format from a PDF document into a text 
file, where each line in the file represents one JSON element in the input file with only four attributes:
line number, page number, coordinate and content.
-->

Use superpowers to create a Go service. Its input is a markdown file. It converts the input file and saves the results into an output file.
Save the program to aas/server/api/file-converters.

- This is a service. It subsribes from the JetStream service with the subject 'kb.pdf.parsed'.
- The request it receives from JetStream should contain the following attributes:
    - record_id: identifies the record in table 'kb.input' (refer to [kb.input Table](./pdf-parser-go-service.md#kb-input-table-def) for the table schema)
    - result_filename: the input file name
    - file_format: specifies the input file format
- Upon receiving a request, it retrieves the record from kb.input by record_id. If not found, it is an error. Log the error and terminate.
- It then check its status. Refer to [Status Management](#status-management)


## [Status Management](status-management)

Field 'status' keeps track of the process status. It is an array. Each element in the array is a JSON doc with the following format:
```json
[
    {"operation":"the-opr", "start_time":"timestamp-in-yyyymmdd hh:mm:ss", "proc_status":"success or fail", "error":"error-msg"},
    {"operation":"the-opr", "start_time":"timestamp-in-yyyymmdd hh:mm:ss", "proc_status":"success or fail", "error":"error-msg"},
    ...
]
```
where:
- 'operation' specifies the operation performed on the file, such as 'parsing', 'convert', 'analyzing', 'adding to knowledge', etc.
- 'start_time': the start time when the operation was performed, 
- 'proc_status': success or failed, and "error": the error message.

For this process, its process status should be:
```json
{
    "operation": "converted",
    "start_time": "20260409 17:00:30",
    "ms-used": 12345,
    "proc-status": "success-or-failed",
    "error":"error-message-only-when-it-failed"
}
```

## [Workflow](work-flow)
- If the 'status' field does not contain an entry with "operation":"parsed" and "proc-status":"success", it is an error. Upsert an element with the error message "file not parsed" and finish.
- If the 'parser_name' field is null, empty, it is an error. Upsert an element with the error "missing parser name" and finish.
- If the parser name is not one of the allowed parser names ([Convert File](#convert-file)), upsert an element with the error "unrecognized parser name: the-parser-name" and finish.
- Depending on the value of 'parser_name', the input file format is different. Use the parser name to look up the function to convert the input file ([Convert File](#convert-file)).
- Output file name: the output file name is `<filename_root>` + "_<parser_name>.txt"
- Upon finishing, add the following entry to the 'status' field:

```json
  {
    "operation": "converted",
    "start_time": "20260409 17:00:30",
    "ms-used": 12345,
    "proc-status": "success"
  }
```

If error occurred, it should generate the following instead:
```json
  {
    "operation": "converted",
    "start_time": "20260409 17:00:30",
    "ms-used": 12345,
    "proc-status": "failed",
    "error":"error-message"
  }
```

## [Convert File](convert-file)
The supported parser names are: 
- 'paddleocr': [paddleocr Converter](#paddleocr-converter)
- 'opendata': [opendata Converter](#opendata-converter)
- 'mineru': [mineru Converter](#mineru-converter)

## [paddleocr Converter](paddleocr-converter)

Will implement this converter in the future.

## [mineru Converter](mineru-converter)

The input file is a JSON. Every entry in the JSON doc is converted to a line in the output file.
The line format is:
- Line Number: An integer starting from 1
- Page Number: from the field 'page number'
- type: from the field 'type'
- heading level: if the field 'heading level' is not empty, append "(header level)" to type
- content: from the field 'content'
- bbox: from the field 'bounding box'

## [opendata Converter](opendata-converter)

The input file is a JSON. Refer to "opendata Input File Example". Every entry in the JSON doc is converted to a line in the output file.
The line format is:
- Line Number: An integer starting from 1
- Page Number: from the field 'page number'
- type: from the field 'type'
- heading level: if the field 'heading level' is not empty, append "(header level)" to type
- content: from the field 'content'
- bbox: from the field 'bounding box'

Below is an example (the first 5 entries):
```text
1 1 paragraph ICS 35.240.80 C 07 [69.264, 779.595, 138.268, 805.755]
2 1 heading(Doctitle) 团 体 标 准 [90.744, 689.954, 498.522, 731.954]
3 1 image stdGk_3032175_images/imageFile1.png [ 100.0, 600.0, 444.0, 673.0 ]
4 1 paragraph T/CHIA 14.3-2018 [ 405.79, 639.616, 533.78, 655.576 ]
5 1 heading(Subtitle) 医疗健康物联网感知设备通信数据命名表 第 3 部分：体温计 [ 70.224, 477.805, 538.423, 539.288 ]
```

The output file is in the same directory of its input file. Output file name is the same as its input file but with the ext 'txt'.

### Process Tables

The format that tables in the JSON file is:
```json
 {
    "type" : "table",
    "id" : 99,
    "level" : "7",
    "page number" : 6,
    "bounding box" : [ 88.584, 498.31, 521.14, 752.26 ],
    "number of rows" : 9,
    "number of columns" : 3,
    "rows" : [ {
      "type" : "table row",
      "row number" : 1,
      "cells" : [ {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 89.064, 731.26, 166.342, 751.78 ],
        "row number" : 1,
        "column number" : 1,
        "row span" : 1,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 24,
          "page number" : 6,
          "bounding box" : [ 105.02, 737.074, 150.128, 746.074 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "元数据子集"
        }]
      }, {another cell}, ...  ],
    }, {another row}, ...]
 }
```

The output of a table:
```text
<line-number> <page-number> 'table-row' <one-row-in-markdown-format> <coordinates>
<line-number> <page-number> 'table-row' <one-row-in-markdown-format> <coordinates>
...
```
where:
  * if a cell contains '|' characters, they must be escaped!.
  * '<coordinates>' is the coordinates for the entire row, which is the bounding box that covers all its cells (each cell has its coordinate)

== opendata Input File Example

The input file is a JSON doc. Below is a portion of such file:
```json
{
  "file name" : "stdGk_3032175.pdf",
  "number of pages" : 13,
  "author" : "LI",
  "title" : null,
  "creation date" : "D:20181112154956+08'00",
  "modification date" : "D:20190327140003+08'00",
  "kids" : [ {
    "type" : "paragraph",
    "id" : 56,
    "page number" : 1,
    "bounding box" : [ 69.264, 779.595, 138.268, 805.755 ],
    "font" : "SimHei",
    "font size" : 10.56,
    "text color" : "[0.0]",
    "content" : "ICS 35.240.80 C 07"
  }, {
    "type" : "heading",
    "id" : 61,
    "level" : "Doctitle",
    "page number" : 1,
    "bounding box" : [ 90.744, 689.954, 498.522, 731.954 ],
    "heading level" : 1,
    "font" : "SimHei",
    "font size" : 42.0,
    "text color" : "[0.0]",
    "content" : "团 体 标 准"
  }, {
    "type" : "image",
    "id" : 53,
    "page number" : 1,
    "bounding box" : [ 100.0, 600.0, 444.0, 673.0 ],
    "source" : "stdGk_3032175_images/imageFile1.png"
  }, {
    "type" : "paragraph",
    "id" : 57,
    "page number" : 1,
    "bounding box" : [ 405.79, 639.616, 533.78, 655.576 ],
    "font" : "SimHei",
    "font size" : 15.96,
    "text color" : "[0.0]",
    "content" : "T/CHIA 14.3-2018"
  }, {
    "type" : "heading",
    "id" : 58,
    "level" : "Subtitle",
    "page number" : 1,
    "bounding box" : [ 70.224, 477.805, 538.423, 539.288 ],
    "heading level" : 2,
    "font" : "SimHei",
    "font size" : 26.04,
    "text color" : "[0.0]",
    "content" : "医疗健康物联网感知设备通信数据命名表 第 3 部分：体温计"
  }, {
    "type" : "header",
    "id" : 69,
    "page number" : 3,
    "bounding box" : [ 454.66, 776.955, 538.784, 787.515 ],
    "kids" : [ {
      "type" : "heading",
      "id" : 30,
      "page number" : 3,
      "bounding box" : [ 454.66, 776.955, 538.784, 787.515 ],
      "heading level" : 4,
      "font" : "SimHei",
      "font size" : 10.56,
      "text color" : "[0.0]",
      "content" : "T/CHIA 14.3-2018"
    } ]
  }, {
    "type" : "heading",
    "id" : 73,
    "level" : "Subtitle",
    "page number" : 3,
    "bounding box" : [ 280.73, 697.456, 328.73, 713.416 ],
    "heading level" : 3,
    "font" : "SimHei",
    "font size" : 15.96,
    "text color" : "[0.0]",
    "content" : "目 次"
  }, {
    "type" : "image",
    "id" : 71,
    "page number" : 3,
    "bounding box" : [ 100.0, 600.0, 444.0, 673.0 ],
    "source" : "stdGk_3032175_images/imageFile5.png"
  }, {
    "type" : "paragraph",
    "id" : 74,
    "page number" : 3,
    "bounding box" : [ 70.944, 639.775, 538.66, 650.335 ],
    "font" : "SimSun",
    "font size" : 10.56,
    "text color" : "[0.0]",
    "content" : "前言 ..................................................................................II"
  }, {
    "type" : "list",
    "id" : 75,
    "level" : "1",
    "page number" : 3,
    "bounding box" : [ 70.944, 538.225, 538.66, 626.815 ],
    "numbering style" : "arabic numbers",
    "number of list items" : 5,
    "list items" : [ {
      "type" : "list item",
      "page number" : 3,
      "bounding box" : [ 70.944, 616.255, 538.66, 626.815 ],
      "font" : "SimHei",
      "font size" : 10.56,
      "text color" : "[0.0]",
      "content" : "1 范围 .................................................................................1",
      "kids" : [ ]
    }, {
      "type" : "list item",
      "page number" : 3,
      "bounding box" : [ 70.944, 577.225, 538.66, 587.785 ],
      "font" : "SimHei",
      "font size" : 10.56,
      "text color" : "[0.0]",
      "content" : "3 术语和定义 ...........................................................................1",
      "kids" : [ ]
    }
    ]
  }, {
    "type" : "paragraph",
    "id" : 72,
    "page number" : 3,
    "bounding box" : [ 535.66, 56.496, 538.657, 64.677 ],
    "font" : "TimesNewRomanPSMT",
    "font size" : 9.0,
    "text color" : "[0.0]",
    "content" : "I"
  }, {
    "type" : "paragraph",
    "id" : 87,
    "page number" : 4,
    "bounding box" : [ 70.944, 312.965, 544.159, 401.525 ],
    "font" : "SimSun",
    "font size" : 10.56,
    "text color" : "[0.0]",
    "content" : "本标准主要起草人：章笠中、何国平、尹建伟、潘晓华"
  }, {
    "type" : "footer",
    "id" : 96,
    "page number" : 5,
    "bounding box" : [ 524.26, 58.014, 528.76, 67.014 ],
    "kids" : [ {
      "type" : "heading",
      "id" : 21,
      "page number" : 5,
      "bounding box" : [ 524.26, 58.014, 528.76, 67.014 ],
      "heading level" : 5,
      "font" : "SimSun",
      "font size" : 9.0,
      "text color" : "[0.0]",
      "content" : "1"
    } ]
  }, {
    "type" : "header",
    "id" : 97,
    "page number" : 6,
    "bounding box" : [ 70.944, 776.955, 155.064, 787.515 ],
    "kids" : [ {
      "type" : "heading",
      "id" : 33,
      "page number" : 6,
      "bounding box" : [ 70.944, 776.955, 155.064, 787.515 ],
      "heading level" : 4,
      "font" : "SimHei",
      "font size" : 10.56,
      "text color" : "[0.0]",
      "content" : "T/CHIA 14.3-2018"
    } ]
  }, {
    "type" : "table",
    "id" : 99,
    "level" : "7",
    "page number" : 6,
    "bounding box" : [ 88.584, 498.31, 521.14, 752.26 ],
    "number of rows" : 9,
    "number of columns" : 3,
    "rows" : [ {
      "type" : "table row",
      "row number" : 1,
      "cells" : [ {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 89.064, 731.26, 166.342, 751.78 ],
        "row number" : 1,
        "column number" : 1,
        "row span" : 1,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 24,
          "page number" : 6,
          "bounding box" : [ 105.02, 737.074, 150.128, 746.074 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "元数据子集"
        } ]
      }, {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 166.342, 731.26, 272.805, 751.78 ],
        "row number" : 1,
        "column number" : 2,
        "row span" : 1,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 25,
          "page number" : 6,
          "bounding box" : [ 201.41, 737.074, 237.518, 746.074 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "元数据项"
        } ]
      }, {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 272.805, 731.26, 520.66, 751.78 ],
        "row number" : 1,
        "column number" : 3,
        "row span" : 1,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 26,
          "page number" : 6,
          "bounding box" : [ 378.67, 737.074, 414.778, 746.074 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "元数据值"
        } ]
      } ]
    }, {
      "type" : "table row",
      "row number" : 2,
      "cells" : [ {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 89.064, 590.23, 166.342, 731.26 ],
        "row number" : 2,
        "column number" : 1,
        "row span" : 6,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 27,
          "page number" : 6,
          "bounding box" : [ 100.58, 656.194, 154.58, 665.194 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "标识信息子集"
        } ]
      }, {
        "type" : "table cell",
        "page number" : 6,
        "bounding box" : [ 272.805, 710.5, 520.66, 731.26 ],
        "row number" : 2,
        "column number" : 3,
        "row span" : 1,
        "column span" : 1,
        "kids" : [ {
          "type" : "paragraph",
          "id" : 29,
          "page number" : 6,
          "bounding box" : [ 278.09, 716.314, 515.623, 725.314 ],
          "font" : "SimSun",
          "font size" : 9.0,
          "text color" : "[0.0]",
          "content" : "医疗健康物联网 感知设备通信数据命名表第 3 部分：体温计"
        } ]
      } ]
    }
    ]
    }
  ]
}
```