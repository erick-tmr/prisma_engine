class CreateCannedAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :canned_answers do |t|
      t.string :label, null: false
      t.text :body, null: false
      t.timestamps
      t.index :label, unique: true
    end
  end
end
