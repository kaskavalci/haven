module ImageHelpers
  extend ActiveSupport::Concern

  HEIF_CONTENT_TYPES = /\b(heic|heif)\b/i
  HEIF_EXTENSIONS = [".heic", ".heif"].freeze

  def haven_image_path(image)
    "/images/raw/#{image.id}/#{image.blob.filename}"
  end

  def haven_image_resized_path(image)
    "/images/resized/#{image.id}/#{image.blob.filename}"
  end

  def create_haven_image(file = nil, io: nil, filename: nil, content_type: nil)
    if file
      io = file.respond_to?(:tempfile) ? file.tempfile : file
      filename = file.original_filename
      content_type = file.content_type
    end

    if heif?(content_type, filename)
      jpg_io = convert_heif_to_jpg(io)
      jpg_io.rewind
      filename = "#{File.basename(filename, '.*')}.jpg"
      content_type = "image/jpeg"
      image = Image.new
      image.blob.attach(io: jpg_io, filename: filename, content_type: content_type)
    else
      image = Image.new
      if file
        image.blob.attach(file)
      else
        image.blob.attach(io: io, filename: filename, content_type: content_type)
      end
    end
    image.save!
    image
  end

  def media_tag_for(image)
    ext = image.blob.filename.to_s.split(".").last.downcase

    case ext
    when "mp3"
      "\n\n<audio controls><source src=\"#{haven_image_path(image)}\" type=\"audio/mpeg\"></audio>"
    when "mp4", "mov", "hevc"
      "\n\n<video controls><source src=\"#{haven_image_path(image)}\" type=\"video/mp4\"></video>"
    else
      image_meta = ActiveStorage::Analyzer::ImageAnalyzer::ImageMagick.new(image.blob).metadata
      if image_meta[:width] && image_meta[:width] > 1600
        "\n\n[![photo](#{haven_image_resized_path(image)})](#{haven_image_path(image)})"
      else
        "\n\n![photo](#{haven_image_path(image)})"
      end
    end
  end

  def media_type_for(image)
    ext = image.blob.filename.to_s.split(".").last.downcase
    case ext
    when "mp3" then "audio"
    when "mp4", "mov", "hevc" then "video"
    else "image"
    end
  end

  private

  def heif?(content_type, filename)
    return true if content_type.to_s.match?(HEIF_CONTENT_TYPES)
    HEIF_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
  end

  def convert_heif_to_jpg(io)
    path = io.respond_to?(:tempfile) ? io.tempfile.path : io.path
    io.rewind if io.respond_to?(:rewind)
    ImageProcessing::MiniMagick.source(path).convert("jpg").call
  end
end
