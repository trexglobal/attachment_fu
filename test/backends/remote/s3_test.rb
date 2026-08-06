require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'test_helper'))
require 'net/http'

class S3Test < Test::Unit::TestCase
  def self.test_S3?
    true unless ENV["TEST_S3"] == "false"
  end
  
  if test_S3? && File.exist?(File.join(File.dirname(__FILE__), '../../amazon_s3.yml'))
    include BaseAttachmentTests
    attachment_model S3Attachment

    def test_should_create_correct_bucket_name(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      assert_equal attachment.s3_config[:bucket_name], attachment.bucket_name
    end

    test_against_subclass :test_should_create_correct_bucket_name, S3Attachment

    def test_should_create_default_path_prefix(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      assert_equal File.join(attachment_model.table_name, attachment.attachment_path_id), attachment.base_path
    end

    test_against_subclass :test_should_create_default_path_prefix, S3Attachment

    def test_should_create_custom_path_prefix(klass = S3WithPathPrefixAttachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      assert_equal File.join('some/custom/path/prefix', attachment.attachment_path_id), attachment.base_path
    end

    test_against_subclass :test_should_create_custom_path_prefix, S3WithPathPrefixAttachment

    def test_should_create_valid_url(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      assert_equal "#{s3_protocol}#{s3_hostname}#{s3_port_string}/#{attachment.bucket_name}/#{attachment.full_filename}", attachment.s3_url
    end

    test_against_subclass :test_should_create_valid_url, S3Attachment

    def test_should_create_authenticated_url(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      assert_match /^http.+AWSAccessKeyId.+Expires.+Signature.+/, attachment.authenticated_s3_url(:use_ssl => true)
    end

    test_against_subclass :test_should_create_authenticated_url, S3Attachment
    
    def test_should_create_authenticated_url_for_thumbnail(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'
      ['large', :large].each do |thumbnail|
        assert_match(
          /^http.+rails_large\.png.+AWSAccessKeyId.+Expires.+Signature/, 
          attachment.authenticated_s3_url(thumbnail), 
          "authenticated_s3_url failed with #{thumbnail.class} parameter"
        )
      end
    end

    def test_should_save_attachment(klass = S3Attachment)
      attachment_model klass
      assert_created do
        attachment = upload_file :filename => '/files/rails.png'
        assert_valid attachment
        assert attachment.image?
        assert !attachment.size.zero?
        assert_kind_of Net::HTTPOK, http_response_for(attachment.s3_url)
      end
    end

    test_against_subclass :test_should_save_attachment, S3Attachment

    def test_should_delete_attachment_from_s3_when_attachment_record_destroyed(klass = S3Attachment)
      attachment_model klass
      attachment = upload_file :filename => '/files/rails.png'

      urls = [attachment.s3_url] + attachment.thumbnails.collect(&:s3_url)

      urls.each {|url| assert_kind_of Net::HTTPOK, http_response_for(url) }
      attachment.destroy
      urls.each do |url|
        begin
          http_response_for(url)
        rescue Net::HTTPForbidden, Net::HTTPNotFound
          nil
        end
      end
    end

    test_against_subclass :test_should_delete_attachment_from_s3_when_attachment_record_destroyed, S3Attachment

    def test_temp_bucket_defaults_to_own_bucket(klass = S3Attachment)
      attachment_model klass
      assert_equal klass.new.bucket_name, klass.new.temp_bucket.name
    end

    test_against_subclass :test_temp_bucket_defaults_to_own_bucket, S3Attachment

    def test_should_save_from_temp_key(klass = S3Attachment)
      attachment_model klass
      temp_key = "test-upload-#{Process.pid}-#{rand(1_000_000)}"

      attachment = attachment_model.new
      temp_full_filename = File.join(attachment.attachment_options[:temp_path_prefix], temp_key)
      attachment.temp_bucket.objects[temp_full_filename].write(
        :file => File.open(File.join(FIXTURE_PATH, 'files', 'rails.png')),
        :acl  => :public_read
      )

      assert_created do
        attachment.save_from_temp_key!(temp_key, :filename => 'rails.png')
      end

      assert_equal 'rails.png', attachment.filename
      assert_equal 'image/png', attachment.content_type
      assert !attachment.size.zero?
      assert_kind_of Net::HTTPOK, http_response_for(attachment.s3_url)
      assert !attachment.temp_bucket.objects[temp_full_filename].exists?,
        "temp key should be deleted once adopted"
    end

    test_against_subclass :test_should_save_from_temp_key, S3Attachment

    def test_should_raise_when_temp_key_missing(klass = S3Attachment)
      attachment_model klass
      attachment = attachment_model.new
      assert_not_created do
        assert_raise(Technoweenie::AttachmentFu::Backends::S3Backend::TempKeyNotFoundError) do
          attachment.save_from_temp_key!('does-not-exist', :filename => 'rails.png')
        end
      end
    end

    test_against_subclass :test_should_raise_when_temp_key_missing, S3Attachment

    # NOTE: exercises new SDK surface (AWS::S3::Bucket#presigned_post) that
    # nothing else in this file calls -- if this fails, check the installed
    # aws-sdk-v1 version's presigned_post option names first.
    def test_should_create_authenticated_s3_post(klass = S3Attachment)
      attachment_model klass
      temp_key = "test-post-#{Process.pid}-#{rand(1_000_000)}"
      post = attachment_model.new.authenticated_s3_post(temp_key, :max_size => 5.megabytes)
      assert post, "authenticated_s3_post returned nil"
    end

    test_against_subclass :test_should_create_authenticated_s3_post, S3Attachment

    def test_should_create_authenticated_s3_posts_in_batch(klass = S3Attachment)
      attachment_model klass
      temp_keys = (1..3).map { |n| "test-post-#{Process.pid}-#{n}-#{rand(1_000_000)}" }
      posts = attachment_model.new.authenticated_s3_posts(temp_keys, :max_size => 5.megabytes)

      assert_equal temp_keys.sort, posts.keys.sort
      posts.each_value { |post| assert post, "authenticated_s3_post returned nil" }
    end

    test_against_subclass :test_should_create_authenticated_s3_posts_in_batch, S3Attachment

    def test_authenticated_s3_post_falls_back_to_attachment_max_size(klass = S3Attachment)
      attachment_model klass
      post = attachment_model.new.authenticated_s3_post('some-temp-key')
      assert post, "authenticated_s3_post should fall back to attachment_options[:max_size] rather than requiring :temp_max_size"
    end

    test_against_subclass :test_authenticated_s3_post_falls_back_to_attachment_max_size, S3Attachment

    protected
      def http_response_for(url)
        url = URI.parse(url)
        Net::HTTP.start(url.host, url.port) {|http| http.request_head(url.path) }
      end
      
      def s3_protocol
        Technoweenie::AttachmentFu::Backends::S3Backend.protocol
      end
      
      def s3_hostname
        Technoweenie::AttachmentFu::Backends::S3Backend.hostname
      end

      def s3_port_string
        Technoweenie::AttachmentFu::Backends::S3Backend.port_string
      end
  else
    def test_flunk_s3
      puts "s3 config file not loaded, tests not running"
    end
  end
end