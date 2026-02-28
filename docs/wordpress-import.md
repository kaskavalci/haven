# WordPress to Haven Migration Guide

**Date:** 2026-02-28
**Author:** claude-4.6-opus

## Overview

Import posts from a WordPress blog into Haven, preserving:

- All post content (published, private, and draft)
- Inline images at their original positions
- Audio and video attachments
- Author attribution (mapped to existing Haven users)
- Original publication dates (drafts use last-modified date)

## Prerequisites

1. A running Haven instance with users already created for each WordPress author.
2. A WordPress WXR export file (XML). Export from **WP Admin → Tools → Export → All content**.
3. Network access from the Haven instance to your WordPress site (for downloading media).

## Usage

Run the import script inside the Haven Rails environment:

```bash
AUTHOR_MAP="wp_user:haven@email.com,wp_user2:other@email.com" \
  bin/rails runner scripts/import_wordpress.rb /path/to/export.xml
```

### Environment Variables

| Variable     | Required | Description                                                                 |
|-------------|----------|-----------------------------------------------------------------------------|
| `AUTHOR_MAP` | Yes      | Comma-separated `wp_username:haven_email` pairs. Posts by unmapped authors fall back to the first mapped user. |
| `DRY_RUN`    | No       | Set to `1` to preview the import without creating records.                  |

### Docker / Docker Compose

If Haven runs in a container, copy the script and XML export into the container first:

```bash
# Copy files into the container
docker cp scripts/import_wordpress.rb haven-container:/app/scripts/
docker cp /path/to/export.xml haven-container:/tmp/export.xml

# Run the import
docker exec haven-container bash -c \
  'AUTHOR_MAP="alice:alice@example.com,bob:bob@example.com" \
   bin/rails runner scripts/import_wordpress.rb /tmp/export.xml'
```

## How It Works

1. Parses the WordPress WXR XML using Nokogiri.
2. Builds an attachment map from all `<wp:attachment>` entries.
3. Iterates through all `<item>` elements with `<wp:post_type>post</wp:post_type>`.
4. For each post:
   - Downloads referenced images, audio, and video files (cached to avoid duplicates).
   - Creates Haven `Image` records via ActiveStorage.
   - Converts WordPress block HTML to Haven-compatible markdown with inline media tags.
   - Creates the `Post` record assigned to the mapped Haven user.

## Content Conversion

The script converts WordPress block HTML to Haven markdown:

| WordPress                          | Haven                              |
|------------------------------------|------------------------------------|
| `<p>text</p>`                      | `text`                             |
| `<h2>heading</h2>`                 | `## heading`                       |
| `<figure class="wp-block-image">` + `<img>` | `![photo](/images/raw/ID/file.jpg)` |
| `<figure class="wp-block-audio">` + `<audio>` | `<audio controls>...</audio>`    |
| `<figcaption>caption</figcaption>` | `*caption*`                        |
| `<blockquote>`                     | `> quoted text`                    |
| `<pre><code>`                      | `` ```code``` ``                   |
| `<ul><li>`                         | `- item`                           |

## Troubleshooting

- **"No Haven user found for email"**: Create the user in Haven's admin UI before running the import.
- **Media download failures**: The script logs warnings and continues. Re-run to retry, or manually add missing media later.
- **`file:///` URLs**: Local file references in the export are skipped with a warning. Upload those files manually.
- **Duplicate imports**: The script does not check for existing posts. If you need to re-import, delete existing posts first (`Post.destroy_all` via `bin/rails runner`).
