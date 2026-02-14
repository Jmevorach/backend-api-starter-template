defmodule Backend.Repo.Migrations.CreateEnterpriseBaselineTables do
  use Ecto.Migration

  def change do
    create table(:tenants, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:slug, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:tenants, [:slug]))

    create table(:entitlements, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:key, :string, null: false)
      add(:enabled, :boolean, null: false, default: true)
      add(:limits, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:entitlements, [:tenant_id, :key]))

    create table(:sso_connections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:provider, :string, null: false)
      add(:issuer, :string, null: false)
      add(:client_id, :string, null: false)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:sso_connections, [:tenant_id, :provider]))

    create table(:scim_users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:external_id, :string, null: false)
      add(:user_name, :string, null: false)
      add(:email, :string)
      add(:active, :boolean, null: false, default: true)
      add(:raw, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:scim_users, [:tenant_id, :external_id]))

    create table(:scim_groups, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:external_id, :string, null: false)
      add(:display_name, :string, null: false)
      add(:raw, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:scim_groups, [:tenant_id, :external_id]))

    create table(:roles, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:name, :string, null: false)
      add(:permissions, {:array, :string}, null: false, default: [])
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:roles, [:tenant_id, :name]))

    create table(:user_roles, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:role_id, references(:roles, type: :binary_id, on_delete: :delete_all), null: false)
      add(:user_id, :string, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:user_roles, [:tenant_id, :role_id, :user_id]))
    create(index(:user_roles, [:tenant_id, :user_id]))

    create table(:audit_events, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:actor_id, :string, null: false)
      add(:action, :string, null: false)
      add(:resource_type, :string, null: false)
      add(:resource_id, :string)
      add(:request_id, :string)
      add(:metadata, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create(index(:audit_events, [:tenant_id, :inserted_at]))

    create table(:webhook_endpoints, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:url, :string, null: false)
      add(:secret, :string, null: false)
      add(:events, {:array, :string}, null: false, default: [])
      add(:active, :boolean, null: false, default: true)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:webhook_endpoints, [:tenant_id]))

    create table(:webhook_deliveries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:webhook_endpoint_id, references(:webhook_endpoints, type: :binary_id, on_delete: :delete_all), null: false)
      add(:event_type, :string, null: false)
      add(:payload, :map, null: false, default: %{})
      add(:status, :string, null: false, default: "queued")
      add(:response_code, :integer)
      add(:attempts, :integer, null: false, default: 0)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:webhook_deliveries, [:webhook_endpoint_id, :inserted_at]))

    create table(:notification_templates, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:channel, :string, null: false)
      add(:name, :string, null: false)
      add(:subject, :string)
      add(:body, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:notification_templates, [:tenant_id, :channel, :name]))

    create table(:notification_messages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:channel, :string, null: false)
      add(:to, :string, null: false)
      add(:subject, :string)
      add(:body, :text, null: false)
      add(:status, :string, null: false, default: "queued")
      add(:provider_response, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:notification_messages, [:tenant_id, :inserted_at]))

    create table(:feature_flags, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:key, :string, null: false)
      add(:description, :text)
      add(:enabled, :boolean, null: false, default: false)
      add(:rollout, :integer, null: false, default: 100)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:feature_flags, [:tenant_id, :key]))

    create table(:jobs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:kind, :string, null: false)
      add(:payload, :map, null: false, default: %{})
      add(:status, :string, null: false, default: "queued")
      add(:result, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:jobs, [:tenant_id, :status]))

    create table(:compliance_requests, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, references(:tenants, type: :binary_id, on_delete: :delete_all), null: false)
      add(:user_id, :string, null: false)
      add(:request_type, :string, null: false)
      add(:status, :string, null: false, default: "queued")
      add(:payload, :map, null: false, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:compliance_requests, [:tenant_id, :request_type, :status]))
  end
end
