# frozen_string_literal: true

require "test_helper"

class Analyzers::FirstFrameImageAnalyzerTest < ActiveSupport::TestCase
  setup do
    skip "ImageMagick convert not available" unless convert_available?
  end

  test "accepts webp and gif blobs" do
    b = build_blob(filename: "x.webp", content_type: "image/webp")
    assert Analyzers::FirstFrameImageAnalyzer.accept?(b)

    b = build_blob(filename: "x.gif", content_type: "image/gif")
    assert Analyzers::FirstFrameImageAnalyzer.accept?(b)

    b = build_blob(filename: "x.webp", content_type: "application/octet-stream")
    assert Analyzers::FirstFrameImageAnalyzer.accept?(b)
  end

  test "rejects non-webp non-gif images" do
    b = build_blob(filename: "x.png", content_type: "image/png")
    assert_not Analyzers::FirstFrameImageAnalyzer.accept?(b)
  end

  test "animated gif metadata uses first frame dimensions only" do
    gif = generate_two_frame_gif
    blob = create_blob(io: StringIO.new(gif), filename: "anim.gif", content_type: "image/gif")

    assert Analyzers::FirstFrameImageAnalyzer.accept?(blob)

    meta = Analyzers::FirstFrameImageAnalyzer.new(blob).metadata
    assert_equal 10, meta[:width]
    assert_equal 10, meta[:height]
  end

  test "analyzer chain picks FirstFrameImageAnalyzer before ImageMagick for gif" do
    gif = generate_two_frame_gif
    blob = create_blob(io: StringIO.new(gif), filename: "anim.gif", content_type: "image/gif")

    klass = ActiveStorage.analyzers.detect { |k| k.accept?(blob) }
    assert_equal Analyzers::FirstFrameImageAnalyzer, klass
  end

  private

  def convert_available?
    system("which convert", out: File::NULL, err: File::NULL)
  end

  def build_blob(filename:, content_type:)
    ActiveStorage::Blob.new(filename: filename, content_type: content_type)
  end

  def create_blob(io:, filename:, content_type:)
    ActiveStorage::Blob.create_and_upload!(
      io: io,
      filename: filename,
      content_type: content_type
    )
  end

  def generate_two_frame_gif
    require "mini_magick"
    Dir.mktmpdir do |dir|
      path = File.join(dir, "out.gif")
      MiniMagick::Tool::Convert.new do |c|
        c.delay "10"
        c << "-size" << "10x10"
        c << "xc:red"
        c << "xc:blue"
        c.loop("0")
        c << path
      end
      File.binread(path)
    end
  end
end
