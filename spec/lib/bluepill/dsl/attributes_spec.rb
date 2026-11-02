# frozen_string_literal: true

describe Bluepill::DSL::Attributes do
  let(:proxy_class) do
    Class.new do
      include Bluepill::DSL::Attributes

      attribute :uid, :gid, :auto_start

      def initialize(attributes = {})
        @attributes = attributes
      end

      private

      def attribute_owner = "thing 'it'"
    end
  end

  let(:proxy) { proxy_class.new }

  it "names the attributes" do
    expect(proxy_class.attribute_names).to eq(%i[uid gid auto_start])
  end

  it "freezes the names" do
    expect(proxy_class.attribute_names).to be_frozen
  end

  it "sets an attribute with its writer" do
    proxy.uid = "user"
    expect(proxy.attributes).to eq(uid: "user")
  end

  it "returns the value from the writer" do
    expect(proxy.public_send(:gid=, "staff")).to eq("staff")
  end

  it "reads an attribute that is set" do
    proxy.gid = "staff"
    expect([proxy.gid, proxy.uid]).to eq(["staff", nil])
  end

  it "reads an attribute from the attributes it starts with" do
    expect(proxy_class.new(uid: "user").uid).to eq("user")
  end

  it "keeps false" do
    proxy.auto_start = false
    expect(proxy.auto_start).to be(false)
  end

  it "rejects an unknown attribute that is set, and suggests the closest one" do
    expect { proxy.uidd = "user" }
      .to raise_error(Bluepill::ConfigError, "Unknown attribute 'uidd' for thing 'it'. Did you mean 'uid'?")
  end

  it "rejects an unknown attribute that is read" do
    expect { proxy.gidd }.to raise_error(Bluepill::ConfigError, "Unknown attribute 'gidd' for thing 'it'. Did you mean 'gid'?")
  end

  it "rejects an unknown attribute with any arguments, or a block" do
    expect { proxy.auto_strt(1, 2) { nil } }
      .to raise_error(Bluepill::ConfigError, "Unknown attribute 'auto_strt' for thing 'it'. Did you mean 'auto_start'?")
  end

  it "suggests nothing for an attribute unlike any other" do
    expect { proxy.frobnicate = 1 }.to raise_error(Bluepill::ConfigError, "Unknown attribute 'frobnicate' for thing 'it'")
  end

  it "only removes a trailing equals sign from the attribute" do
    expect { proxy.public_send(:"u=id=", 1) }.to raise_error(Bluepill::ConfigError, /Unknown attribute 'u=id' /)
  end

  it "does not respond to an unknown attribute" do
    expect([proxy.respond_to?(:uidd=), proxy.send(:respond_to_missing?, :uidd=, false)]).to eq([false, false])
  end

  it "rejects a reader or writer given the wrong number of values" do
    expect([-> { proxy.uid("user") }, -> { proxy.public_send(:uid=) }]).to all(raise_error(ArgumentError))
  end

  describe "suggestions" do
    let(:proxy_class) do
      Class.new do
        include Bluepill::DSL::Attributes

        attribute(*Bluepill::ProcessProxy.attribute_names)

        def initialize
          @attributes = {}
        end
      end
    end

    def suggest(name) = proxy.send(:suggest, name)

    it "suggests the closest attribute by its name" do
      expect(suggest("start_comand")).to eq("start_command")
    end

    it "suggests an attribute for a short misspelling too" do
      expect(%w[auto_srt uidx gids ui].collect { |name| suggest(name) }).to eq(%w[auto_start uid gid uid])
    end

    it "suggests the first in order among attributes as close as each other" do
      expect(suggest("xid")).to eq("gid")
    end
  end
end
