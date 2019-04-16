class ProductsController < ActionController::Base
  include InheritedResources

  def show
    @resource = Product.find(params[:id])
  end

  def update
    resource = find_resource(params)
    resource.update_attributes!(app_features: nil)
    render json: resource.to_json
  end
end