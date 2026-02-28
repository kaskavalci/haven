#!/usr/bin/env ruby
# WordPress WXR XML → Haven import script
#
# Usage:
#   AUTHOR_MAP="wp_user1:haven@email.com,wp_user2:other@email.com" \
#     bin/rails runner scripts/import_wordpress.rb /path/to/export.xml
#
# Environment variables:
#   AUTHOR_MAP  - Comma-separated wp_username:haven_email pairs for author mapping.
#                 Posts by unmapped authors fall back to the first mapped user.
#   DRY_RUN=1   - Preview import without creating any records.
#
# Parses a WordPress export XML (WXR), downloads all media (images, audio, video),
# creates ActiveStorage-backed Image records, and inserts Posts with
# proper inline content references. Imports published, private, AND draft posts.

require "nokogiri"
require "open-uri"
require "tempfile"
require "fileutils"

WP_NS = {
  "wp"      => "http://wordpress.org/export/1.2/",
  "content" => "http://purl.org/rss/1.0/modules/content/",
  "dc"      => "http://purl.org/dc/elements/1.1/",
}.freeze

xml_path = ARGV[0]
unless xml_path && File.exist?(xml_path)
  abort "Usage: bin/rails runner scripts/import_wordpress.rb /path/to/export.xml"
end

DRY_RUN = ENV["DRY_RUN"] == "1"
puts "=== DRY RUN ===" if DRY_RUN

doc = Nokogiri::XML(File.read(xml_path))

AUTHOR_MAP = ENV.fetch("AUTHOR_MAP", "").split(",").each_with_object({}) do |pair, map|
  wp_name, email = pair.strip.split(":", 2)
  map[wp_name] = email if wp_name && email
end.freeze

if AUTHOR_MAP.empty?
  abort "AUTHOR_MAP is required. Example: AUTHOR_MAP=\"alice:alice@example.com,bob:bob@example.com\""
end

haven_users = {}
AUTHOR_MAP.each do |wp_name, email|
  user = User.find_by(email: email)
  if user
    haven_users[wp_name] = user
    puts "Mapped WP author '#{wp_name}' → Haven user #{user.id} (#{user.email})"
  else
    puts "WARNING: No Haven user found for #{email}"
  end
end

fallback_author = haven_users.values.first
abort "No Haven users found matching author map. Create users first." unless fallback_author

# Pre-build a map of WP attachment URLs → their metadata from the XML.
# This lets us resolve original (non-resized) image URLs.
attachment_map = {}
doc.xpath("//item").each do |item|
  post_type = item.at_xpath("wp:post_type", WP_NS)&.text
  next unless post_type == "attachment"

  guid = item.at_xpath("guid")&.text
  attachment_url = item.at_xpath("wp:attachment_url", WP_NS)&.text
  url = attachment_url || guid
  next unless url

  attachment_map[url] = {
    filename: File.basename(URI.parse(url).path),
    url: url,
  }
end
puts "Found #{attachment_map.size} attachments in XML"

# Cache downloaded media to avoid re-downloading duplicates
download_cache = {}

def download_media(url, cache)
  return cache[url] if cache.key?(url)

  unless url.start_with?("http://", "https://")
    puts "  WARNING: Skipping non-HTTP URL: #{url}"
    cache[url] = nil
    return nil
  end

  uri = URI.parse(url)
  filename = File.basename(uri.path)
  ext = File.extname(filename).downcase

  puts "  Downloading: #{filename}"
  tempfile = Tempfile.new(["wp_import", ext])
  tempfile.binmode

  begin
    URI.open(url, "rb") do |remote|
      IO.copy_stream(remote, tempfile)
    end
    tempfile.rewind
    cache[url] = { tempfile: tempfile, filename: filename, ext: ext }
  rescue => e
    puts "  WARNING: Failed to download #{url}: #{e.message}"
    tempfile.close!
    cache[url] = nil
  end

  cache[url]
end

def create_haven_image(media)
  return nil unless media

  image = Image.new
  image.blob.attach(
    io: media[:tempfile],
    filename: media[:filename],
    content_type: content_type_for(media[:ext]),
  )
  image.save!
  media[:tempfile].rewind
  image
end

def content_type_for(ext)
  case ext
  when ".jpg", ".jpeg" then "image/jpeg"
  when ".png" then "image/png"
  when ".gif" then "image/gif"
  when ".webp" then "image/webp"
  when ".m4a" then "audio/mp4"
  when ".mp3" then "audio/mpeg"
  when ".mp4" then "video/mp4"
  when ".mov" then "video/quicktime"
  else "application/octet-stream"
  end
end

def image_tag_for(image, ext)
  path = "/images/raw/#{image.id}/#{image.blob.filename}"

  case ext
  when ".m4a", ".mp3"
    mime = ext == ".m4a" ? "audio/mp4" : "audio/mpeg"
    "\n\n<audio controls><source src=\"#{path}\" type=\"#{mime}\"></audio>\n\n"
  when ".mp4", ".mov"
    "\n\n<video controls><source src=\"#{path}\" type=\"video/mp4\"></video>\n\n"
  else
    "\n\n<img src=\"#{path}\"></img>\n\n"
  end
end

# Convert WordPress block HTML content to Haven-compatible content.
# Haven stores markdown with inline HTML for media. We:
# 1. Strip WP block comments
# 2. Replace <img> tags with Haven ActiveStorage references
# 3. Replace <audio> tags with Haven audio references
# 4. Convert <p> to plain text, <h*> to markdown headers
# 5. Preserve <figure> captions as italic text
def convert_content(html, download_cache)
  return "" if html.nil? || html.strip.empty?

  content_doc = Nokogiri::HTML.fragment(html)
  output = ""

  content_doc.children.each do |node|
    case node.name
    when "text"
      # Top-level text (between blocks)
      text = node.text.strip
      output << text << "\n" unless text.empty?

    when "comment"
      # WordPress block comments -- skip
      next

    when "figure"
      css_class = node["class"] || ""

      if css_class.include?("wp-block-audio")
        audio = node.at_css("audio")
        if audio
          src = audio["src"]
          if src
            media = download_media(src, download_cache)
            if media
              haven_image = create_haven_image(media)
              output << image_tag_for(haven_image, media[:ext]) if haven_image
            end
          end
        end

      elsif css_class.include?("wp-block-image")
        img = node.at_css("img")
        if img
          src = img["src"]
          if src
            media = download_media(src, download_cache)
            if media
              haven_image = create_haven_image(media)
              output << image_tag_for(haven_image, media[:ext]) if haven_image
            end
          end
        end
        caption = node.at_css("figcaption")
        output << "*#{caption.text.strip}*\n\n" if caption && !caption.text.strip.empty?

      else
        output << node.text.strip << "\n\n"
      end

    when "p"
      output << node.inner_html.strip.gsub(/<br\s*\/?>/, "\n") << "\n\n"

    when "h1"
      output << "# #{node.text.strip}\n\n"
    when "h2"
      output << "## #{node.text.strip}\n\n"
    when "h3"
      output << "### #{node.text.strip}\n\n"
    when "h4"
      output << "#### #{node.text.strip}\n\n"

    when "ul"
      node.css("li").each { |li| output << "- #{li.text.strip}\n" }
      output << "\n"
    when "ol"
      node.css("li").each_with_index { |li, i| output << "#{i + 1}. #{li.text.strip}\n" }
      output << "\n"

    when "blockquote"
      node.text.strip.each_line { |line| output << "> #{line.strip}\n" }
      output << "\n"

    when "pre"
      code = node.at_css("code")
      text = code ? code.text : node.text
      output << "```\n#{text}\n```\n\n"

    when "hr"
      output << "---\n\n"

    when "div"
      inner = node.inner_html.strip
      output << inner << "\n\n" unless inner.empty?

    else
      text = node.text.strip
      output << text << "\n\n" unless text.empty?
    end
  end

  output.gsub(/\n{3,}/, "\n\n").strip
end

# Parse and import posts
posts = doc.xpath("//item").select do |item|
  item.at_xpath("wp:post_type", WP_NS)&.text == "post"
end

puts "\nFound #{posts.size} posts to import"
imported = 0
skipped = 0

posts.sort_by { |p| p.at_xpath("wp:post_date", WP_NS)&.text || "9999" }.each do |item|
  title = item.at_xpath("title")&.text || "(untitled)"
  status = item.at_xpath("wp:status", WP_NS)&.text || "unknown"
  date_str = item.at_xpath("wp:post_date", WP_NS)&.text
  content_html = item.at_xpath("content:encoded", WP_NS)&.text

  # Skip the "Hello world" default post if it has no real content
  if title == "Hello world" && (content_html.nil? || content_html.include?("Welcome to WordPress"))
    puts "\nSkipping default WordPress post: #{title}"
    skipped += 1
    next
  end

  wp_creator = item.at_xpath("dc:creator", WP_NS)&.text || ""
  post_author = haven_users[wp_creator] || fallback_author

  puts "\n--- Importing: #{title} [#{status}] by #{wp_creator}→#{post_author.email}"

  # Parse date, fall back to post_modified for drafts without dates
  post_date = if date_str && !date_str.strip.empty? && date_str != "0000-00-00 00:00:00"
    DateTime.parse(date_str)
  else
    modified = item.at_xpath("wp:post_modified", WP_NS)&.text
    if modified && !modified.strip.empty? && modified != "0000-00-00 00:00:00"
      DateTime.parse(modified)
    else
      DateTime.now
    end
  end

  if DRY_RUN
    puts "  Date: #{post_date}"
    puts "  Content length: #{content_html&.length || 0} chars"
    imported += 1
    next
  end

  # Convert content: add title as H1, then converted body
  haven_content = "# #{title}\n\n"
  haven_content << convert_content(content_html, download_cache)

  post = Post.new(
    content: haven_content,
    datetime: post_date,
    author: post_author,
  )
  post.save!
  puts "  Created post ##{post.id} (#{post_date.strftime('%Y-%m-%d')})"
  imported += 1
end

puts "\n=== Import complete ==="
puts "Imported: #{imported}"
puts "Skipped: #{skipped}"
puts "Media downloaded: #{download_cache.count { |_, v| v }}"
