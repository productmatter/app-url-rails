# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require "open3"

require_relative "../lib/git/treeline/rails/gtl_adapter"

class GtlAdapterTest < Minitest::Test
  GtlAdapter = Git::Treeline::Rails::GtlAdapter

  def stub_capture3(stdout, stderr = "", success: true)
    status = Object.new
    status.define_singleton_method(:success?) { success }
    Open3.stub :capture3, [stdout, stderr, status] do
      yield
    end
  end

  def test_returns_tunnel_url_from_routes_json
    json = '{"branch":"feature","project":"salt","tunnel":"https://feature.gtltunnel.dev"}'
    stub_capture3(json) do
      assert_equal "https://feature.gtltunnel.dev", GtlAdapter.tunnel_url
    end
  end

  def test_raises_when_tunnel_field_missing
    stub_capture3('{"branch":"feature","project":"salt","routes":[]}') do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/no tunnel URL/, err.message)
    end
  end

  def test_raises_when_tunnel_field_is_empty_string
    stub_capture3('{"tunnel":""}') do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/no tunnel URL/, err.message)
    end
  end

  def test_raises_when_tunnel_field_is_null
    stub_capture3('{"tunnel":null}') do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/no tunnel URL/, err.message)
    end
  end

  def test_raises_when_gtl_exits_nonzero
    stub_capture3("", "not a configured worktree", success: false) do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/not a configured worktree/, err.message)
      assert_match(/configured git-treeline worktree/, err.message)
    end
  end

  def test_raises_when_gtl_exits_nonzero_with_empty_stderr
    stub_capture3("", "", success: false) do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/unknown error/, err.message)
    end
  end

  def test_raises_with_install_hint_when_gtl_not_on_path
    Open3.stub :capture3, ->(*) { raise Errno::ENOENT, "gtl" } do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/command not found/, err.message)
      assert_match(/brew install git-treeline/, err.message)
    end
  end

  def test_raises_on_invalid_json
    stub_capture3("not json at all") do
      err = assert_raises(GtlAdapter::Error) { GtlAdapter.tunnel_url }
      assert_match(/invalid JSON/, err.message)
    end
  end

  def test_invokes_gtl_routes_json
    captured_args = nil
    capture = lambda do |*args|
      captured_args = args
      status = Object.new
      status.define_singleton_method(:success?) { true }
      ['{"tunnel":"https://x.example.com"}', "", status]
    end
    Open3.stub :capture3, capture do
      GtlAdapter.tunnel_url
    end
    assert_equal ["gtl", "routes", "--json"], captured_args
  end
end
