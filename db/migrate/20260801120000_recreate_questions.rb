class RecreateQuestions < ActiveRecord::Migration[8.1]
  def change
    drop_table :questions do |t|
      t.references :product, null: false, foreign_key: true
      t.text     :body, null: false
      t.string   :asker_name, null: false
      t.string   :asker_email, null: false
      t.text     :answer_body
      t.boolean  :answered, null: false, default: false
      t.boolean  :published, null: false, default: false
      t.datetime :answered_at

      t.timestamps

      t.index [ :product_id, :published ]
    end

    create_table :questions do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text     :body, null: false
      t.text     :answer_body
      t.string   :status, null: false, default: "awaiting_answer"
      t.datetime :answered_at

      t.timestamps

      t.index [ :product_id, :status, :created_at ]
      t.index [ :status, :created_at ]
    end

    add_check_constraint :questions, "char_length(body) <= 500", name: "questions_body_length"
  end
end
