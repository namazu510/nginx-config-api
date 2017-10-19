class CreateDomains < ActiveRecord::Migration[5.1]
  def change
    create_table :domains do |t|
      t.string :sub_domain
      t.string :domain
      t.boolean :use_auth
      t.string :conf_path
      t.timestamps
    end
  end
end
