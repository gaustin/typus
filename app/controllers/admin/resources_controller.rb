class Admin::ResourcesController < Admin::BaseController

  include Typus::Actions
  include Typus::Filters
  include Typus::Format

  before_filter :get_model
  before_filter :set_scope
  before_filter :get_object, :only => [:show, :edit, :update, :destroy, :toggle, :position, :relate, :unrelate, :detach]
  before_filter :check_resource_ownership, :only => [:edit, :update, :destroy, :toggle, :position, :relate, :unrelate ]
  before_filter :check_if_user_can_perform_action_on_resources
  before_filter :set_order, :only => [:index]
  before_filter :set_fields, :only => [:index, :new, :edit, :create, :update, :show, :detach]

  ##
  # This is the main index of the model. With filters, conditions and more.
  #
  # By default application can respond to html, csv and xml, but you can add
  # your formats.
  #
  def index
    add_action(:action_name => default_action.titleize, :action => default_action)
    add_action(:action_name => "Trash", :action => "destroy", :confirm => Typus::I18n.t("Trash %{resource}?", :resource => @resource.model_name.human), :method => 'delete')

    get_objects

    respond_to do |format|
      format.html { generate_html }
      @resource.typus_export_formats.each { |f| format.send(f) { send("generate_#{f}") } }
    end
  end

  def new
    item_params = params.dup
    rejections = %w(controller action resource resource_id back_to selected)
    item_params.delete_if { |k, v| rejections.include?(k) }
    @item = @resource.new(item_params)
  end

  ##
  # Create new items. There's an special case when we create an item from
  # another item. In this case, after the item is created we also create the
  # relationship between these items.
  #
  def create
    @item = @resource.new(params[@object_name])

    set_attributes_on_create

    if @item.save
      params[:back_to] ? create_with_back_to : redirect_on_success
    else
      render :new
    end
  end

  def edit
    add_action(:action_name => default_action.titleize, :action => default_action)
    add_action(:action_name => "Unrelate",
               :action => "unrelate",
               :confirm => "#{Typus::I18n.t("Unrelate")}?",
               :resource => @resource.name, :resource_id => @item.id)
  end

  def show
    check_resource_ownership if @resource.typus_options_for(:only_user_items)
  end

  def update
    respond_to do |format|
      if @item.update_attributes(params[@object_name])
        set_attributes_on_update
        reload_locales
        format.html { redirect_on_success }
        format.json { render :json => @item }
      else
        format.html { render :edit }
        format.json { render :json => @item.errors.full_messages }
      end
    end
  end

  def detach
    if @item.update_attributes(params[:attribute] => nil)
      redirect_on_success
    else
      render :edit
    end
  end

  def destroy
    @item.destroy
    notice = Typus::I18n.t("%{model} successfully removed.", :model => @resource.model_name.human)
    redirect_to set_path, :notice => notice
  end

  def toggle
    @item.toggle(params[:field])
    @item.save!

    notice = Typus::I18n.t("%{model} successfully updated.", :model => @resource.model_name.human)

    respond_to do |format|
      format.html { redirect_to set_path, :notice => notice }
      format.json { render :json => @item }
    end
  end

  ##
  # Change item position:
  #
  #   params[:go] = 'move_to_top'
  #
  # Available positions are move_to_top, move_higher, move_lower, move_to_bottom.
  #
  # NOTE: Only works if `acts_as_list` is installed.
  #
  def position
    @item.send(params[:go])
    notice = Typus::I18n.t("Record moved to position %{to}.", :to => params[:go].gsub(/move_/, '').humanize.downcase)
    redirect_to set_path, :notice => notice
  end

  ##
  # Relate a model object to another, this action is used only by the
  # `has_and_belongs_to_many` and `has_many` relationships.
  #
  def relate
    resource_class = params[:related][:model].typus_constantize
    resource_tableized = params[:related][:model].tableize

    if @item.send(resource_tableized) << resource_class.find(params[:related][:id])
      flash[:notice] = Typus::I18n.t("%{model} successfully updated.", :model => @resource.model_name.human)
    end

    redirect_to set_path
  end

  ##
  # Remove relationship between models, this action never removes items!
  #
  def unrelate
    resource_class = params[:resource].typus_constantize
    resource_tableized = params[:resource].tableize
    resource = resource_class.find(params[:resource_id])

    # We consider that we are unrelating a has_many or has_and_belongs_to_many

    reflection = @resource.reflect_on_association(resource_class.table_name.to_sym)
    macro = reflection.try(:macro)
    options = reflection.try(:options)

    case macro
    # when :has_one
    #   attribute = resource_tableized.singularize
    #   saved_succesfully = @item.update_attribute attribute, nil
    when :has_many
      if options.has_key?(:as) # We are in a polymorphic relationship
        interface = options[:as]
        saved_succesfully = resource.update_attributes("#{interface}_type" => nil, "#{interface}_id" => nil)
      elsif options.has_key?(:through)
        resource_parent = reflection.active_record.find(params[:id])
        saved_succesfully = resource_parent.send(resource_tableized).delete(resource)
      else
        # We have to verify we can unrelate. For example: A Category which has
        # many posts and Post validates_presence_of Category should not be removed.
        attribute = @resource.table_name.singularize
        saved_succesfully = resource.update_attributes(attribute => nil)
      end
    when :has_and_belongs_to_many
      attribute = resource_tableized
      saved_succesfully = @item.send(attribute).delete(resource)
    else
      saved_succesfully = false
    end

    if saved_succesfully
      flash[:notice] = Typus::I18n.t("%{model} successfully updated.", :model => @resource.model_name.human)
    end

    redirect_to set_path
  end

  private

  def get_model
    @resource = params[:controller].extract_class
    @object_name = ActiveModel::Naming.singular(@resource)
  end

  def set_scope
    @resource = @resource.unscoped
  end

  def get_object
    @item = @resource.find(params[:id])
  end

  def get_objects
    eager_loading = @resource.reflect_on_all_associations(:belongs_to).reject { |i| i.options[:polymorphic] }.map { |i| i.name }

    @resource.build_conditions(params).each do |condition|
      @resource = @resource.where(condition)
    end

    if @resource.typus_options_for(:only_user_items)
      check_resources_ownership
    end

    @items = @resource.order(set_order).includes(eager_loading)
  end

  def set_fields
    @fields = @resource.typus_fields_for(params[:action].action_mapper)
  end

  def set_order
    params[:sort_order] ||= "desc"
    params[:order_by] ? "#{@resource.table_name}.#{params[:order_by]} #{params[:sort_order]}" : @resource.typus_order_by
  end

  def redirect_on_success
    action = @resource.typus_options_for(:action_after_save)

    case params[:action]
    when "create"
      path = { :action => action }
      path.merge!(:id => @item.id) unless action.eql?("index")
      notice = Typus::I18n.t("%{model} successfully created.", :model => @resource.model_name.human)
    when "update", "detach"
      path = case action
             when "index"
               params[:back_to] ? "#{params[:back_to]}##{@resource.to_resource}" : { :action => action }
             else
               { :action => action, :id => @item.id, :back_to => params[:back_to] }
             end
      notice = Typus::I18n.t("%{model} successfully updated.", :model => @resource.model_name.human)
    end

    redirect_to path, :notice => notice
  end

  ##
  # When `params[:back_to]` is defined this action is used.
  #
  # - `has_and_belongs_to_many` relationships.
  # - `has_many` relationships (polymorphic ones).
  #
  def create_with_back_to
    association = @resource.reflect_on_association(params[:resource].to_sym)

    if params[:resource_id]
      resource_class = params[:resource].classify.typus_constantize
      resource_id = params[:resource_id]
      resource = resource_class.find(resource_id)
    end

    message = Typus::I18n.t("%{model} successfully updated.", :model => resource_class.model_name.human)

    macro = association.macro unless association.nil?
    case macro
    when :has_and_belongs_to_many
      @item.send(params[:resource]) << resource
    when :has_many
      if resource
        @item.send(params[:resource]) << resource
      else
        path = "#{params[:back_to]}?#{association.primary_key_name}=#{@item.id}"
      end
    when :polymorphic
      resource.send(@item.class.to_resource).create(params[@object_name])
    end

    redirect_to (path || params[:back_to]), :notice => message
  end

  def default_action
    @resource.typus_options_for(:default_action_on_item)
  end

end
