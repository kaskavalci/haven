Rails.application.config.active_storage.service_urls_expire_in

Rails.application.config.active_storage.variant_processor = :mini_magick

# Animated WebP/GIF: only analyze first frame (see Analyzers::FirstFrameImageAnalyzer).
# Registered in after_initialize so Zeitwerk has loaded app/models.
Rails.application.config.after_initialize do
  list = Rails.application.config.active_storage.analyzers
  klass = Analyzers::FirstFrameImageAnalyzer
  list.delete(klass)
  list.unshift(klass)
  ActiveStorage.analyzers = list
end
