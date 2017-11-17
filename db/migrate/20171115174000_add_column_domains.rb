class AddColumnDomains < ActiveRecord::Migration[5.1]
  def change
    add_column :domains, :cert_req, :boolean
  end
end
