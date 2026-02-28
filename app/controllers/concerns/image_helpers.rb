module ImageHelpers
  extend ActiveSupport::Concern

  def haven_image_path(image)
    "/images/raw/#{image.id}/#{image.blob.filename}"
  end

  def haven_image_resized_path(image)
    "/images/resized/#{image.id}/#{image.blob.filename}"
  end

  def create_haven_image(file)
    image = Image.new
    image.blob.attach(file)
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
end
