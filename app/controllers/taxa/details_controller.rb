class Taxa::DetailsController < TaxaController

  before_filter :instantiate_taxon_concept, :redirect_if_superceded, :instantiate_preferred_names
  before_filter :add_page_view_log_entry, :literatures_and_resources_links

  # GET /pages/:taxon_id/details
  def index
    
    @text_objects = @taxon_concept.details_text_for_user(current_user)
    @toc_items_to_show = @taxon_concept.table_of_contents_for_text(@text_objects)
    
    @data_objects_in_other_languages = @taxon_concept.text_for_user(current_user, {
      :language_ids_to_ignore => [ current_language.id, 0 ],
      :allow_nil_languages => false,
      :preload_select => { :data_objects => [ :id, :guid, :language_id ] },
      :skip_preload => true,
      :toc_ids_to_ignore => TocItem.exclude_from_details.collect{ |toc_item| toc_item.id } })
    DataObject.preload_associations(@data_objects_in_other_languages, :language)
    @details_count_by_language = {}
    @data_objects_in_other_languages.each do |obj|
      @details_count_by_language[obj.language] ||= 0
      @details_count_by_language[obj.language] += 1
    end
    
    @exemplar_image = @taxon_concept.exemplar_or_best_image_from_solr(@selected_hierarchy_entry)
    @assistive_section_header = I18n.t(:assistive_details_header)
    @rel_canonical_href = @selected_hierarchy_entry ?
      taxon_hierarchy_entry_details_url(@taxon_concept, @selected_hierarchy_entry) :
      taxon_details_url(@taxon_concept)
    current_user.log_activity(:viewed_taxon_concept_details, :taxon_concept_id => @taxon_concept.id)
  end

protected
  def meta_description
    chapter_list = @toc_items_to_show.collect{|i| i.label}.uniq.compact.join("; ") unless @toc_items_to_show.blank?
    translation_vars = scoped_variables_for_translations.dup
    translation_vars[:chapter_list] = chapter_list unless chapter_list.blank?
    I18n.t("meta_description#{translation_vars[:preferred_common_name] ? '_with_common_name' :
           ''}#{translation_vars[:chapter_list] ? '_with_chapter_list' : '_no_data'}",
           translation_vars)
  end
  def meta_keywords
    keywords = super
    toc_subjects = @toc_items_to_show.collect{|i| i.label}.compact.join(", ")
    [keywords, toc_subjects].compact.join(', ')
  end
  
private
  def literatures_and_resources_links
    $show_resources_links = []
    $show_literature_references_link = false
    
    $show_resources_links << 'partner_links' unless @taxon_concept.content_partners_links.blank?
    
    @identification_resources_count = @taxon_concept.text_for_user(current_user, {
      :language_ids => [ current_language.id ],
      :toc_ids => [ TocItem.identification_resources.id ] })
    $show_resources_links << 'identification_resources' unless @identification_resources_count.blank?
    
    citizen_science = TocItem.cached_find_translated(:label, 'Citizen Science', 'en')
    citizen_science_links = TocItem.cached_find_translated(:label, 'Citizen Science links', 'en')
    @citizen_science_contents_count = @taxon_concept.text_for_user(current_user, {
      :language_ids => [ current_language.id ],
      :toc_ids => [ citizen_science.id, citizen_science_links.id ] })
    $show_resources_links << 'citizen_science' unless @citizen_science_contents_count.blank?
    
    # there are two education chapters - one is the parent of the other
    education_root = TocItem.cached_find_translated(:label, 'Education', 'en', :find_all => true).detect{ |toc_item| toc_item.is_parent? }
    education_chapters = [ education_root ] + education_root.children
    @education_contents_count = @taxon_concept.text_for_user(current_user, {
      :language_ids => [ current_language.id ],
      :toc_ids => education_chapters.collect{ |toc_item| toc_item.id } })
    $show_resources_links << 'education' unless @education_contents_count.blank?
    
    if !Resource.ligercat.nil? && HierarchyEntry.find_by_hierarchy_id_and_taxon_concept_id(Resource.ligercat.hierarchy.id, @taxon_concept.id)
      $show_resources_links << 'biomedical_terms'
    end

    $show_resources_links << 'nucleotide_sequences' unless @taxon_concept.nucleotide_sequences_hierarchy_entry_for_taxon.nil?
  
    $show_literature_references_link = true if Ref.literature_references_for?(@taxon_concept.id)
  end
end
