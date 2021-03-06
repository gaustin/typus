require "test_helper"

class Admin::CategoriesControllerTest < ActionController::TestCase

  setup do
    @request.session[:typus_user_id] = Factory(:typus_user).id
    @request.env['HTTP_REFERER'] = '/admin/categories'
  end

  context "Categories Views" do

    should "verify form partial can overrided by model" do
      get :new
      assert_match "categories#_form.html.erb", @response.body
    end

  end

  context "Categories List" do

    setup do
      @first_category = Factory(:category, :position => 1)
      @second_category = Factory(:category, :position => 2)
    end

    should "verify referer" do
      get :position, { :id => @first_category.id, :go => 'move_lower' }
      assert_response :redirect
      assert_redirected_to @request.env['HTTP_REFERER']
    end

    should "position item one step down" do
      get :position, { :id => @first_category.id, :go => 'move_lower' }

      assert_equal "Record moved to position lower.", flash[:notice]
      assert_equal 2, @first_category.reload.position
      assert_equal 1, @second_category.reload.position
    end

    should "position item one step up" do
      get :position, { :id => @second_category.id, :go => 'move_higher' }

      assert_equal "Record moved to position higher.", flash[:notice]
      assert_equal 2, @first_category.reload.position
      assert_equal 1, @second_category.reload.position
    end

    should "position top item to bottom" do
      get :position, { :id => @first_category.id, :go => 'move_to_bottom' }
      assert_equal "Record moved to position to bottom.", flash[:notice]
      assert_equal 2, @first_category.reload.position
    end

    should "position bottom item to top" do
      get :position, { :id => @second_category.id, :go => 'move_to_top' }
      assert_equal "Record moved to position to top.", flash[:notice]
      assert_equal 1, @second_category.reload.position
    end

  end

end