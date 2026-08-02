class CreateQuestionStrikes < ActiveRecord::Migration[8.1]
  def change
    create_table :question_strikes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :question, null: false, foreign_key: true, index: { unique: true }
      t.references :issued_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
      t.index [ :user_id, :created_at ]
    end
  end
end
