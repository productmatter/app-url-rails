# frozen_string_literal: true

require "minitest/autorun"

class RequireTest < Minitest::Test
  def test_require_by_gem_name_with_hyphens
    assert_kind_of String, `ruby -Ilib -r app-url-rails -e "print AppUrl::VERSION"`
    assert_equal AppUrl::VERSION, `ruby -Ilib -r app-url-rails -e "print AppUrl::VERSION"`
  end

  def test_require_by_app_url_rails_underscored
    assert_equal AppUrl::VERSION, `ruby -Ilib -r app_url_rails -e "print AppUrl::VERSION"`
  end

  def test_require_by_app_url
    assert_equal AppUrl::VERSION, `ruby -Ilib -r app_url -e "print AppUrl::VERSION"`
  end

  private

  def setup
    require_relative "../lib/app_url"
  end
end
