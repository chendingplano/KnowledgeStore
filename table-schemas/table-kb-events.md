# Purpose
This table stores events and manages event processing lifecycle.
Table Name: kb.events

# Table Schema
```text
id: auto-generated integer, serving as the primary key
event_name: string, required, the event name
event_id: string, required, uniquely identifies an event
event_time: timestamp, optional, the event occuring time
event_subject: string, optional, the event's subject
event_payload: JSON, optional, a JSON for the event's payload
event_status: JSON, optional, a JSON doc (see below)
event_source: string, the name of the event source, such as 'JetStream'
event_notes: text, optional, a plain text field
error_msg: text, optional, records the event error messages
create_time: timestamp, auto-generated, the record creation time
modify_time: timestamp, auto-generated, the record's last modify time
```

**Field 'event_status'**
This field is an arry of JSON docs (called proc-status JSON):
```
[
    {
        "operation":"xxx",
        "proc_status":"success|fail",
        "error_msg":"xxx",              // present only when "proc_status" == "fail"
        "start_time":"xxx",             // The start time of this operation
        "ms_used":ddd,                  // The milliseconds of performing this operation
    },
    ...
]
```
Note that different operations may add additional attributes to proc-status JSON.

There are two system-defined operations:
- "operation" == "received": this proc-status JSON is set to 'event_status' automatically when an event is received
- "operation" == "consumed": this proc-status JSON is set when and only when the event is securely processed.

# Event Processing
Event processing lifecycle is:
- Event is received
- Construct the event ID for the event and insert it to 'kb.events', set the "operation" == "received" proc-status JSON.
- Respond to the event sender, such as responding to JetStream
- Process the event
- Upsert the "operation" == "consumed" proc-status JSON when it finishes the processing.
