# frozen_string_literal: true

module Analyzers
  # Reads only the first frame of animated WebP/GIF for width/height. The stock
  # ImageMagick analyzer loads every frame, which is extremely slow for long animations.
  class FirstFrameImageAnalyzer < ActiveStorage::Analyzer::ImageAnalyzer
    def self.accept?(blob)
      ActiveStorage.variant_processor == :mini_magick && webp_or_gif?(blob)
    end

    def self.webp_or_gif?(blob)
      ct = blob.content_type.to_s.downcase
      return true if ct == "image/webp" || ct == "image/gif"

      ext = File.extname(blob.filename.to_s).downcase
      ext == ".webp" || ext == ".gif"
    end
    private_class_method :webp_or_gif?

    private

    def read_image
      begin
        require "mini_magick"
      rescue LoadError
        logger.info "Skipping image analysis because the mini_magick gem isn't installed"
        return {}
      end

      download_blob_to_tempfile do |file|
        path = first_frame_path(file.path)
        image = instrument("mini_magick") do
          MiniMagick::Image.new(path)
        end

        if image.valid?
          yield image
        else
          logger.info "Skipping image analysis because ImageMagick doesn't support the file"
          {}
        end
      rescue MiniMagick::Error => error
        logger.error "Skipping image analysis due to an ImageMagick error: #{error.message}"
        {}
      end
    end

    def rotated_image?(image)
      %w[ RightTop LeftBottom TopRight BottomLeft ].include?(image["%[orientation]"])
    end

    def first_frame_path(path)
      "#{path}[0]"
    end
  end
end
