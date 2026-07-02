class AddKindAndDescriptionToBrindes < ActiveRecord::Migration[8.1]
  def change
    add_column :brindes, :kind, :string
    add_column :brindes, :description, :text
  end
end
