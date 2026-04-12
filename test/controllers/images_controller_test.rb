require "test_helper"

# Stub used by test_upload_heic_converts_to_jpg so we can inject a JPG without a real HEIC file
module ImagesControllerHeicStub
  def convert_heif_to_jpg(io)
    return $heic_convert_stub.call(io) if defined?($heic_convert_stub) && $heic_convert_stub
    super(io)
  end
end
ImagesController.prepend(ImagesControllerHeicStub)

class ImagesControllerTest < ActionDispatch::IntegrationTest
  test "upload heic converts to jpg and returns image tag with jpg" do
    sign_in_as_washington

    # Stub conversion so we don't need a real HEIC file or ImageMagick HEIC read
    jpeg_temp = ImageProcessing::MiniMagick
      .source(Rails.root.join("test", "fixtures", "files", "test_image.png"))
      .convert("jpg")
      .call
    jpeg_content = jpeg_temp.read
    jpeg_temp.close

    stub_return_jpeg = ->(_io) {
      t = Tempfile.new(["heic2jpg", ".jpg"])
      t.binmode
      t.write(jpeg_content)
      t.rewind
      t
    }

    # Upload a file that presents as HEIC (content type + filename)
    temp_heic = Tempfile.new(["test", ".heic"])
    FileUtils.cp(Rails.root.join("test", "fixtures", "files", "test_image.png"), temp_heic.path)
    file = Rack::Test::UploadedFile.new(
      temp_heic.path,
      "image/heic",
      original_filename: "photo.heic"
    )

    $heic_convert_stub = stub_return_jpeg
    post upload_image_path, params: { file: file }, headers: csrf_headers
    assert_heic_upload_response
  ensure
    $heic_convert_stub = nil
  end

  test "upload animated gif returns image markdown" do
    skip "ImageMagick convert not available" unless convert_available?

    sign_in_as_washington

    gif = generate_two_frame_gif
    file = Rack::Test::UploadedFile.new(
      StringIO.new(gif),
      "image/gif",
      original_filename: "anim.gif"
    )

    post upload_image_path, params: { file: file }, headers: csrf_headers.merge("Accept" => "application/json")
    assert_response :created
    json = JSON.parse(response.body)
    assert_includes json["tag"], "![photo]"
    assert_equal "image", json["type"]

    image = Image.order(created_at: :desc).first
    assert_equal "image/gif", image.blob.content_type
  end

  def assert_heic_upload_response
    assert_response :created
    json = JSON.parse(response.body)
    assert json["tag"].include?(".jpg"), "Response tag should reference .jpg (converted from HEIC)"
    assert_equal "image", json["type"]

    image = Image.order(created_at: :desc).first
    assert_equal "image/jpeg", image.blob.content_type
    assert image.blob.filename.to_s.end_with?(".jpg"), "Stored filename should end with .jpg"
  end

  private

  def convert_available?
    system("which convert", out: File::NULL, err: File::NULL)
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

  def sign_in_as_washington
    post user_session_path, params: {
      user: { email: users(:washington).email, password: "georgepass" }
    }
    follow_redirect!
  end

  def csrf_headers
    get new_post_path
    token = response.body[/meta name="csrf-token" content="([^"]+)"/, 1]
    { "X-CSRF-Token" => token }
  end
end
