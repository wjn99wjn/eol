# Name is used for storing different variations of names of species (TaxonConcept)
#
# These names are not "official."  If they have a CanonicalForm, the CanonicalForm is the "accepted" scientific name for the
# species.
#
# Even common names have an italicized form, which the PHP side auto-generates.  They can't always be trusted, but there are cases
# where a name is both common and scientific, so it must be populated.
#
class Name < SpeciesSchemaModel

  belongs_to :canonical_form
  belongs_to :ranked_canonical_form, :class_name => CanonicalForm.to_s, :foreign_key => :ranked_canonical_form_id

  has_many :taxon_concept_names
  has_many :hierarchy_entries

  validates_presence_of   :string
  # this is being commented out because we are enforcing the uniqueness of clean_name not string
  # string is not indexed so that was creating a query that took a long time to run
  # we could do soemthing better with before_save callbacks - checking the clean_name and making sure its unique there
  # validates_uniqueness_of :string
  validates_presence_of   :italicized
  validates_presence_of   :canonical_form

  validate :clean_name_must_be_unique
  before_validation_on_create :set_default_values
  before_validation_on_create :create_clean_name
  before_validation_on_create :create_canonical_form
  before_validation_on_create :create_italicized

  def taxon_concepts
    return taxon_concept_names.collect {|tc_name| tc_name.taxon_concept}.flatten
  end

  def canonical
    return canonical_form.nil? ? 'not assigned' : canonical_form.string
  end

  def italicized_canonical
    # hoping these short-circuit messages help with debugging ... likely due to bad/incomplete fixture data?
    # return "(no canonical form, tc: #{ taxon_concepts.map(&:id).join(',') })" unless canonical_form
    return 'not assigned' unless canonical_form and canonical_form.string and not canonical_form.string.empty?
    return "<i>#{canonical_form.string}</i>"
  end

  # String representation of a Name is its Name#string
  def to_s
    string
  end

  # Takes a name string and returns a normalized string. The result of this method *must* be identical
  # to a result generated by eol_php_code method Functions::clean_name
  # TODO: Write a test that is universal for php and ruby code for this method to ensure both methods are in sync
  def self.prepare_clean_name(name)
    name = name.gsub(/[.,;]/," ").gsub(/[\-\(\)\[\]\{\}:&\*?×]/,' \0 ').gsub(/ (and|et) /," & ")
    name = name.gsub(/ +/, " ").downcase
    name = name.gsub("À","à").gsub("Â","â").gsub("Å","å").gsub("Ã","ã").gsub("Ä","ä")
    name = name.gsub("Á","á").gsub("Æ","æ").gsub("C","c").gsub("Ç","ç").gsub("Č","č")
    name = name.gsub("É","é").gsub("È","è").gsub("Ë","ë").gsub("Í","í").gsub("Ì","ì")
    name = name.gsub("Ï","ï").gsub("Ň","ň").gsub("Ñ","ñ").gsub("Ñ","ñ").gsub("Ó","ó")
    name = name.gsub("Ò","ò").gsub("Ô","ô").gsub("Ø","ø").gsub("Õ","õ").gsub("Ö","ö")
    name = name.gsub("Ú","ú").gsub("Ù","ù").gsub("Ü","ü").gsub("R","r").gsub("Ŕ","ŕ")
    name = name.gsub("Ř","ř").gsub("Ŗ","ŗ").gsub("Š","š").gsub("Š","š").gsub("Ş","ş")
    name.gsub("Ž","ž").gsub("Œ","œ").strip
  end


  # Takes a name strings and creates new records for ... models.
  # Currently this method works well only for common (vernacular)
  # names, because we do not need insertion of scientific names
  # from ruby code at the moment. If we will need scientific names
  # in the future it migt make sense to overload 'create' method
  # of the model with this logic and speed everything up as well.
  def self.create_common_name(name_string, given_canonical_form = "")
    name_string = name_string.strip.gsub(/\s+/,' ') if name_string.class == String
    return nil if name_string.blank?

    common_name = Name.find_by_string(name_string)
    if !common_name.blank?
      common_name_to_edit = common_name unless name_string == common_name.string
      common_name.update_attributes(:string => name_string) unless common_name_to_edit.blank?
      return common_name
    end

    common_name = Name.new
    common_name.string = name_string
    common_name.namebank_id = 0

    if !given_canonical_form.blank?
      common_name.canonical_form_id = CanonicalForm.find_or_create_by_string(given_canonical_form).id
      common_name.canonical_verified = 1
    end

    common_name.save!
    return common_name
  end

  def self.find_or_create_by_string(string)
    if n = Name.find_by_string(string)
      return n
    end
    return Name.create(:string => string)
  end

  def self.find_by_string(string)
    clean_string = Name.prepare_clean_name(string)
    return Name.find_by_clean_name(clean_string)
  end

  def is_surrogate_or_hybrid?
    # return true if ranked_canonical_form_id.blank?
    red_flag_words = [ 'incertae sedis', 'incertaesedis', 'culture', 'clone', 'isolate',
                       'phage', 'sp', 'cf', 'uncultured', 'DNA', 'unclassified', 'sect',
                       'ß', 'str', 'biovar', 'type', 'strain', 'serotype', 'hybrid',
                       'cultivar', 'x', '×', 'pop', 'group', 'environmental', 'sample',
                       'endosymbiont']
    return true if string.match(/(^|[^\w])(#{red_flag_words.join('|')})([^\w]|$)/i)
    return true if string.match(/[0-9][a-z]/i)
    return true if string.match(/[a-z][0-9]/i)
    return true if string.match(/[a-z]-[0-9]/i)
    return true if string.match(/ [0-9]{1,3}$/)
    return true if string.match(/virus([^\w]|$)/i)
    return false
  end


  private
  def clean_name_must_be_unique
    found_name = Name.find_by_string(self.string)
    errors.add_to_base("Name string must be unique") unless found_name.nil?
  end

  def set_default_values
    self.namebank_id = 0
  end

  def create_clean_name
    self.namebank_id = 0
    if self.clean_name.nil? || self.clean_name.blank?
      self.clean_name = Name.prepare_clean_name(self.string)
    end
  end

  def create_canonical_form
    if self.canonical_form_id.nil? || self.canonical_form_id == 0
      self.canonical_form = CanonicalForm.find_or_create_by_string(self.string) #all we need to do for common names
      self.canonical_verified = 0
    else
      self.canonical_verified = 1
    end
  end

  def create_italicized
    if self.italicized.nil? || self.italicized.blank?
      self.italicized = "<i>#{string}</i>" #all we need to do for common names
      self.italicized_verified = 0
    else
      self.italicized_verified = 1
    end
  end
end
