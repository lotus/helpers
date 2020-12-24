# frozen_string_literal: true

RSpec.describe Hanami::Helpers::EscapeHelper do
  before do
    @view = EscapeView.new
  end

  it "auto-escape evil string" do
    expect(@view.evil_string).to eq(%(&lt;script&gt;alert(&apos;xss&apos;)&lt;&#x2F;script&gt;))
  end

  it "don't auto-escape safe string" do
    expect(@view.good_string).to eq(%(this is a good string))
  end

  it "auto-escape attributes evil string" do
    expect(@view.good_attributes_string).to eq(%(<a title='foo'>link</a>))
  end

  it "don't auto-escape attributes safe string" do
    expect(@view.evil_attributes_string).to eq(%(<a title='&lt;script&gt;alert&#x28;&#x27;xss&#x27;&#x29;&lt;&#x2f;script&gt;'>link</a>))
  end

  it "auto-escape url evil string" do
    expect(@view.good_url_string).to eq(%(http://hanamirb.org))
  end

  it "don't auto-escape url evil string" do
    expect(@view.evil_url_string).to be_empty
  end

  it "raw string is returned" do
    expect(@view.raw_string).to eq(%(<div>I'm a raw string</div>))
  end

  it "raw string is a Hanami::Helpers::Escape::SafeString class" do
    expect(@view.raw_string.class).to eq(Hanami::Utils::Escape::SafeString)
  end

  it "html helper alias" do
    expect(@view.html_string_alias).to eq(%(this is a good string))
  end

  it "html attribute helper alias" do
    expect(@view.html_attribute_string_alias).to eq(%(<a title='foo'>link</a>))
  end

  it "url helper alias" do
    expect(@view.url_string_alias).to eq(%(http://hanamirb.org))
  end
end
