# frozen_string_literal: true

require "rails"

module AppUrlTestSupport
  INVALID_ENVIRONMENT_URLS = {
    "blank" => [" \t ", "must not be blank"],
    "scheme-less" => ["credential-sentinel.example", "must include an http:// or https:// scheme"],
    "unsupported scheme" => ["ftp://credential-sentinel.example", "must include an http:// or https:// scheme"],
    "missing host" => ["https://?query-sentinel", "must include a host"],
    "userinfo" => ["https://user:credential-sentinel@example.com", "must not include userinfo"],
    "empty userinfo" => ["https://@credential-sentinel.example", "must not include userinfo"],
    "path" => ["https://example.com/path-sentinel", "must not include a path beyond a trailing slash"],
    "query" => ["https://example.com?query-sentinel", "must not include a query"],
    "fragment" => ["https://example.com#fragment-sentinel", "must not include a fragment"],
    "empty port" => ["https://credential-sentinel.example:", "port must be an integer from 1 through 65535"],
    "non-integer port" => ["https://example.com:port-sentinel", "port must be an integer from 1 through 65535"],
    "zero port" => ["https://credential-sentinel.example:0", "port must be an integer from 1 through 65535"],
    "oversized port" => ["https://credential-sentinel.example:65536", "port must be an integer from 1 through 65535"],
    "unbracketed IPv6" => ["https://::1/path-sentinel", "must bracket an IPv6 host"],
    "malformed" => ["https://[malformed-sentinel", "is malformed"],
    "invalid encoding" => ["https://example.com/encoding-sentinel\xFF".b, "is malformed"]
  }.freeze

  INVALID_ENVIRONMENT_HOSTS = {
    "blank" => [" \t ", "must not be blank"],
    "scheme" => ["https://credential-sentinel.example", "must not include a scheme"],
    "port" => ["credential-sentinel.example:443", "must not include a port"],
    "path" => ["example.com/path-sentinel", "must not include a path, query, or fragment"],
    "query" => ["example.com?query-sentinel", "must not include a path, query, or fragment"],
    "userinfo" => ["user@credential-sentinel.example", "must not include userinfo"],
    "leading dot" => [".credential-sentinel.example", "must not start or end with a dot"],
    "trailing dot" => ["credential-sentinel.example.", "must not start or end with a dot"],
    "single label" => ["label-sentinel", "must be a dotted hostname"],
    "invalid characters" => ["bad_label-sentinel.example", "must be a dotted hostname"],
    "whitespace inside" => ["space-sentinel .example", "must be a dotted hostname"],
    "invalid encoding" => ["encoding-sentinel.example\xFF".b, "is malformed"]
  }.freeze

  def setup
    super
    @saved_application = Rails.application
    @saved_app_class = Rails.app_class
    Rails.application = Class.new(Rails::Application).new
  end

  def teardown
    Rails.application = @saved_application
    Rails.app_class = @saved_app_class
    super
  end

  def assert_safe_configuration_error(error, setting, category, value, reason,
                                      expected: /expected an absolute http:\/\/ or https:\/\//)
    assert_match(/\A#{setting} #{Regexp.escape(reason)};/, error.message, category)
    assert_match(expected, error.message, category)
    assert_nil error.cause, category
    sentinel = value.b[/[a-z]+-sentinel/]
    refute_includes error.full_message, sentinel, category if sentinel
  end
end
