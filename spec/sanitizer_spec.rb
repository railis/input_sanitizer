require 'spec_helper'
require 'pry'

class BasicSanitizer < InputSanitizer::Sanitizer
  string :x, :y, :z
  integer :num
  date :birthday
  time :updated_at
  custom :cust1, :cust2, :converter => lambda { |v| v.reverse }
end

class BrokenCustomSanitizer < InputSanitizer::Sanitizer

end

class ExtendedSanitizer < BasicSanitizer
  boolean :is_nice
end

class OverridingSanitizer < BasicSanitizer
  integer :is_nice
end

class RequiredParameters < BasicSanitizer
  integer :is_nice, :required => true
end

class RequiredCustom < BasicSanitizer
  custom :c1, :required => true, :converter => lambda { |v| v }
end

class DefaultParameters < BasicSanitizer
  integer :funky_number, :default => 5
  custom :fixed_stuff, :converter => lambda {|v| v }, :default => "default string"
end

describe InputSanitizer::Sanitizer do
  let(:sanitizer) { BasicSanitizer.new(@params) }

  describe ".clean" do
    it "returns cleaned data" do
      clean_data = mock()
      BasicSanitizer.any_instance.should_receive(:cleaned).and_return(clean_data)
      BasicSanitizer.clean({}).should be(clean_data)
    end
  end

  describe "#cleaned" do
    let(:cleaned) { sanitizer.cleaned }
    let(:required) { RequiredParameters.new(@params) }

    it "includes specified params" do
      @params = {"x" => 3, "y" => "tom", "z" => "mike"}

      cleaned.should have_key(:x)
      cleaned.should have_key(:y)
      cleaned.should have_key(:z)
    end

    it "strips not specified params" do
      @params = {"d" => 3}

      cleaned.should_not have_key(:d)
    end

    it "freezes cleaned hash" do
      @params = {}

      cleaned.should be_frozen
    end

    it "uses RestrictedHash" do
      @params = {}

      lambda{cleaned[:does_not_exist]}.should raise_error(InputSanitizer::KeyNotAllowedError)
    end

    it "includes specified keys and strips rest" do
      @params = {"d" => 3, "x" => "ddd"}

      cleaned.should have_key(:x)
      cleaned.should_not have_key(:d)
    end

    it "works with symbols as input keys" do
      @params = {:d => 3, :x => "ddd"}

      cleaned.should have_key(:x)
      cleaned.should_not have_key(:d)
    end

    it "silently discards cast errors" do
      @params = {:num => "f"}

      cleaned.should_not have_key(:num)
    end

    it "inherits converters from superclass" do
      sanitizer = ExtendedSanitizer.new({:num => "23", :is_nice => 'false'})
      cleaned = sanitizer.cleaned

      cleaned.should have_key(:num)
      cleaned[:num].should == 23
      cleaned[:is_nice].should be_false
    end

    it "overrides inherited fields" do
      sanitizer = OverridingSanitizer.new({:is_nice => "42"})
      cleaned = sanitizer.cleaned

      cleaned.should have_key(:is_nice)
      cleaned[:is_nice].should == 42
    end

    context "when sanitizer is initialized with default values" do
      context "when paremeters are not overwriten" do
        let(:sanitizer) { DefaultParameters.new({}) }

        it "returns default value for non custom key" do
          sanitizer.cleaned[:funky_number].should == 5
        end

        it "returns default value for custom key" do
          sanitizer.cleaned[:fixed_stuff].should == "default string"
        end
      end

      context "when parameters are overwriten" do
        let(:sanitizer) { DefaultParameters.new({ :funky_number => 2, :fixed_stuff => "fixed" }) }

        it "returns default value for non custom key" do
          sanitizer.cleaned[:funky_number].should == 2
        end

        it "returns default value for custom key" do
          sanitizer.cleaned[:fixed_stuff].should == "fixed"
        end
      end
    end

  end

  describe ".custom" do
    let(:sanitizer) { BasicSanitizer.new(@params) }
    let(:cleaned) { sanitizer.cleaned }

    it "converts using custom converter" do
      @params = {:cust1 => "cigam"}

      cleaned.should have_key(:cust1)
      cleaned[:cust1].should == "magic"
    end

    it "raises an error when converter is not defined" do
      expect do
        BrokenCustomSanitizer.custom(:x)
      end.to raise_error
    end
  end

  describe ".converters" do
    let(:sanitizer) { InputSanitizer::Sanitizer }

    it "includes :integer type" do
      sanitizer.converters.should have_key(:integer)
      sanitizer.converters[:integer].should be_a(InputSanitizer::IntegerConverter)
    end

    it "includes :string type" do
      sanitizer.converters.should have_key(:string)
      sanitizer.converters[:string].should be_a(InputSanitizer::StringConverter)
    end

    it "includes :date type" do
      sanitizer.converters.should have_key(:date)
      sanitizer.converters[:date].should be_a(InputSanitizer::DateConverter)
    end

    it "includes :boolean type" do
      sanitizer.converters.should have_key(:boolean)
      sanitizer.converters[:boolean].should be_a(InputSanitizer::BooleanConverter)
    end
  end

  describe '.extract_options' do

    it "extracts hash from array if is last" do
      options = { :a => 1}
      array = [1,2, options]
      BasicSanitizer.extract_options(array).should == options
      array.should == [1,2, options]
    end

    it "does not extract the last element if not a hash and returns default empty hash" do
      array = [1,2]
      BasicSanitizer.extract_options(array).should_not == 2
      BasicSanitizer.extract_options(array).should == {}
      array.should == [1,2]
    end

  end

  describe '.extract_options!' do

    it "extracts hash from array if is last" do
      options = { :a => 1}
      array = [1,2, options]
      BasicSanitizer.extract_options!(array).should == options
      array.should == [1,2]
    end

    it "leaves other arrays alone" do
      array = [1,2]
      BasicSanitizer.extract_options!(array).should == {}
      array.should == [1,2]
    end

  end

  describe "#valid?" do
    it "is valid when params are ok" do
      @params = {:num => "3"}

      sanitizer.should be_valid
    end

    it "is not valid when missing params" do
      @params = {:num => "mike"}

      sanitizer.should_not be_valid
    end
  end

  describe "#[]" do
    it "accesses cleaned data" do
      @params = {:num => "3"}

      sanitizer[:num].should == 3
    end
  end

  describe "#errors" do
    it "returns array containing hashes describing error" do
      @params = {:num => "mike"}

      errors = sanitizer.errors
      errors.size.should == 1
      errors[0][:field].should == :num
      errors[0][:type].should == :invalid_value
      errors[0][:description].should == "invalid integer"
      errors[0][:value].should == "mike"
    end

    it "returns error type missing if value is missing" do
      sanitizer = RequiredParameters.new({})
      error = sanitizer.errors[0]
      error[:type].should == :missing
    end

    it "handles required custom params" do
      sanitizer = RequiredCustom.new({})

      sanitizer.should_not be_valid
      error = sanitizer.errors[0]
      error[:type].should == :missing
      error[:field].should == :c1
    end
  end
end
