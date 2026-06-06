class CreateQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.references :product, null: false, foreign_key: true
      t.text     :body, null: false
      t.string   :asker_name, null: false
      t.string   :asker_email, null: false
      t.text     :answer_body
      t.boolean  :answered, null: false, default: false
      t.boolean  :published, null: false, default: false
      t.datetime :answered_at

      t.timestamps
    end

    add_index :questions, [ :product_id, :published ]
  end
end
