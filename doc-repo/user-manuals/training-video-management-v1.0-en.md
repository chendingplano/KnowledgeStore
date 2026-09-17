---
title: Managing Training Videos
language: en
format: markdown
version: 1.0
status: Draft
author: Not specified
owner: Not specified
audience: SemOS system administrators who upload and maintain training videos
create-time: 2026-09-17T13:52:38-05:00
last-modify-time: 2026-09-17T13:56:25-05:00
keywords: training videos, video management, upload video, video upload, cover image, video metadata, System Admin, Resources, SemOS, video library, view video, download video, delete video, video storage, VIDEO_DIR, DATA_HOME_DIR, VIDEO_MAX_BYTES, environment variables, server configuration
---

# Managing Training Videos

## What this page is for

The **Videos** page is where a SemOS administrator keeps the library of training videos that
the system uses — for example, screen recordings that show staff how to use a feature, such as
the document review workflow. From this one page you can add a new video, watch an existing
one, save a copy to your computer, or remove a video that is no longer needed.

This page is useful whenever you need to:

- Publish a new walkthrough or recording for other users to learn from.
- Check what training material already exists before recording a duplicate.
- Retrieve a local copy of a video (for example, to edit it or share it outside SemOS).
- Clean up outdated or incorrect recordings.

## Who can use this page

The Videos page lives under **System Admin**, so it is intended for administrators rather than
general end users. (The exact permissions required to reach this page were not confirmed at the
time of writing — check with your SemOS administrator if you cannot see this page.)

## Where to find it

Navigate to **Development > System Admin > Resources > Videos** in the left-hand navigation
menu. The page header confirms you are in the right place: it reads "Videos" with the
description "Manage training videos — upload with metadata and a cover image, view, download,
and delete."

## Understanding the video list

The main part of the page is a table listing every training video currently stored in SemOS.
Each row is one video, with the following columns:

| Column | What it shows |
|---|---|
| **Cover** | A small thumbnail image chosen to represent the video, shown to the left of its name. |
| **Name** | The video's title (for example, "Training-003"), with a short description underneath it. The description is often written in the language of the intended audience — in the reference example, the descriptions are in Chinese. |
| **Source** | How the video is classified: "Recording" for a captured session, or "Web" for a video that also has an associated external link (a URL field appears in the upload dialog for this case). A video file is uploaded and stored either way. All three examples in the reference screenshot use "Recording". |
| **Size** | The file size of the video, shown in megabytes (MB) — for example, "27.9 MB". Larger sizes generally mean longer or higher-quality recordings. |
| **Uploaded** | The date and time the video was added to SemOS, shown in your local format (for example, "7/22/2026, 5:49:18 PM"). |
| **Actions** | Three links for working with that row's video: **View**, **Download**, and **Delete**. |

Videos are listed with the most recently uploaded video at the top.

## Uploading a new video

Use this when you have a new training recording to add to the library.

1. From the Videos page, click the **Upload video** button in the upper-right corner. An
   upload dialog opens.
2. Choose the video file you want to add. Its file name is used to suggest a name and a video
   type automatically, both of which you can edit.
3. Fill in the video's metadata:
   - **Name** and **Description** (both required) — the title and summary shown in the video
     list.
   - **Source** — "Recording" or "Web". Choosing "Web" reveals a **URL** field for linking to
     where the video is also published.
   - **Keywords**, **Category**, **Subcategory**, and **Container** (all optional) — help
     classify and later search for the video. Category and subcategory offer a dropdown of
     values already used by other videos, or you can type a new one.
   - **Status** — Draft, Published, or Archived (defaults to Draft).
   - **Video type** — normally filled in automatically from the file extension (for example,
     "mp4"), but editable if needed.
   - **Notes** (optional) — internal remarks not shown elsewhere.
4. Provide a cover image — the thumbnail that will appear in the **Cover** column. Either click
   **Pick an Image** to choose one already in the image library, or click **Auto-Generate** to
   have the system create one based on the Name and Description you entered (each click
   produces a new image, so you can try again if you don't like the result).
5. Click **Upload**. A progress bar tracks the upload; once it finishes, the dialog closes and
   the new video appears at the top of the video list with the metadata and cover image you
   provided.

**Tip:** Choosing a clear, descriptive title and cover image makes it much easier for other
administrators to find the right video later, especially as the library grows.

## Viewing a video

Use this to watch a video without downloading it first.

1. Find the video you want to watch in the list.
2. Click **View** in that row's Actions column.
3. A player opens directly above the video list, showing the video's name and standard playback
   controls (play/pause, seek, volume). Click **Close** next to the player when you are done.

## Downloading a video

Use this when you need a copy of the video file on your own computer — for example, to share it
outside SemOS or edit it in another tool.

1. Find the video you want in the list.
2. Click **Download** in that row's Actions column.
3. Your browser saves the video file, following its normal download behavior.

## Deleting a video

Use this to remove a video that is outdated, incorrect, or no longer needed.

1. Find the video you want to remove in the list.
2. Click **Delete** in that row's Actions column (shown in red to signal a destructive action).
3. A confirmation prompt names the video and warns that the action cannot be undone. Confirm to
   proceed, or cancel to keep the video.

**Caution:** Deleting a video removes it from the library. Before deleting, make sure you have
selected the correct row — double-check the Name column, since some videos may have similar
titles — and that you do not still need a copy; download the video first if you might need it
later.

## Where video files are stored

This section is for administrators who manage the SemOS server or need to troubleshoot an
upload problem; it is not needed for day-to-day use of the page.

When you upload a video, SemOS saves the video file itself on the server's file system — it is
not stored inside the database. The information you type into the upload dialog (name,
description, source, keywords, category, status, and so on) is kept separately, alongside a
reference to the saved file, so the page can display and manage everything as one video entry.

Each uploaded file is renamed on disk to a unique name before it is saved, so two videos can
never overwrite each other even if they were uploaded with the same original file name. Your
original file name is preserved and still shown when the video is downloaded.

Deleting a video (see above) removes both the stored file and its recorded information
together, in one step.

## Environment variables used by this page

The folder where video files are saved, and the largest file size accepted, are controlled by
settings on the SemOS server rather than anything you configure from within the page. These are
called environment variables. They matter to you mainly when an upload fails for a
configuration reason — for example, an error about storage not being set up, or a file being
rejected as "too large" — in which case check these with whoever manages the SemOS server.

| Environment variable | Purpose | If not set |
|---|---|---|
| `VIDEO_DIR` | The folder on the server where uploaded video files are saved. | The system falls back to a `Videos` subfolder inside `DATA_HOME_DIR` (see below). |
| `DATA_HOME_DIR` | A shared base folder used by several SemOS features. Supplies the fallback `Videos` subfolder when `VIDEO_DIR` is not set. | If this is also not set, video uploads are disabled until an administrator configures one of these two settings. |
| `VIDEO_MAX_BYTES` | The largest video file size accepted for upload, in bytes. | Defaults to 2 GiB (2,147,483,648 bytes). |

## Change Log

| Version | Timestamp | Author | Reason | Summary |
|---|---|---|---|---|
| 1.0 | 2026-09-17T13:56:25-05:00 | Not specified | Requested addition: storage location and environment variables | Added "Where video files are stored" and "Environment variables used by this page" sections (VIDEO_DIR, DATA_HOME_DIR, VIDEO_MAX_BYTES), based on the ChenWeb `videohandler` source code and the video-management upload dialog. Also corrected earlier "needs confirmation" notes on upload metadata fields, the View player, the Delete confirmation prompt, and the Source column's allowed values, now that the underlying implementation was reviewed. |
| 1.0 | 2026-09-17T13:52:38-05:00 | Not specified | Initial creation | Documented the Videos admin page: table columns (Cover, Name, Source, Size, Uploaded, Actions) and the upload, view, download, and delete workflows, based on a reference screenshot of the page. |
