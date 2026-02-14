defmodule Backend.Enterprise do
  @moduledoc """
  Enterprise-focused context that provides baseline APIs for:
  - SSO/SCIM
  - RBAC and policy evaluation
  - Audit trails
  - Webhooks and notifications
  - Feature flags and tenant entitlements
  - Async jobs and compliance workflows
  - Lightweight cross-domain search
  """

  import Ecto.Query, warn: false

  alias Backend.Enterprise.AuditEvent
  alias Backend.Enterprise.ComplianceRequest
  alias Backend.Enterprise.Entitlement
  alias Backend.Enterprise.FeatureFlag
  alias Backend.Enterprise.Job
  alias Backend.Enterprise.NotificationMessage
  alias Backend.Enterprise.NotificationTemplate
  alias Backend.Enterprise.Role
  alias Backend.Enterprise.ScimGroup
  alias Backend.Enterprise.ScimUser
  alias Backend.Enterprise.SsoConnection
  alias Backend.Enterprise.Tenant
  alias Backend.Enterprise.UserRole
  alias Backend.Enterprise.WebhookDelivery
  alias Backend.Enterprise.WebhookEndpoint
  alias Backend.Notes.Note
  alias Backend.Projects.Project
  alias Backend.Projects.Task
  alias Backend.Repo

  # ---------------------------------------------------------------------------
  # Tenants and Entitlements
  # ---------------------------------------------------------------------------

  def create_tenant(attrs), do: struct(Tenant) |> Tenant.changeset(attrs) |> Repo.insert()
  def get_tenant(id), do: Repo.get(Tenant, id)

  def list_entitlements(tenant_id) do
    Entitlement
    |> where([e], e.tenant_id == ^tenant_id)
    |> order_by([e], asc: e.inserted_at)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # SSO and SCIM
  # ---------------------------------------------------------------------------

  def list_sso_providers(tenant_id) do
    configured =
      SsoConnection
      |> where([s], s.tenant_id == ^tenant_id)
      |> select([s], s.provider)
      |> distinct(true)
      |> Repo.all()

    Enum.uniq(configured ++ ["okta", "entra", "google-workspace"])
  end

  def create_sso_connection(attrs),
    do: struct(SsoConnection) |> SsoConnection.changeset(attrs) |> Repo.insert()

  def list_scim_users(tenant_id) do
    ScimUser
    |> where([u], u.tenant_id == ^tenant_id)
    |> order_by([u], asc: u.user_name)
    |> Repo.all()
  end

  def create_scim_user(attrs), do: struct(ScimUser) |> ScimUser.changeset(attrs) |> Repo.insert()

  def update_scim_user(id, tenant_id, attrs) do
    with user when not is_nil(user) <- Repo.get(ScimUser, id),
         true <- user.tenant_id == tenant_id,
         {:ok, updated} <- user |> ScimUser.changeset(attrs) |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  def list_scim_groups(tenant_id) do
    ScimGroup
    |> where([g], g.tenant_id == ^tenant_id)
    |> order_by([g], asc: g.display_name)
    |> Repo.all()
  end

  def create_scim_group(attrs),
    do: struct(ScimGroup) |> ScimGroup.changeset(attrs) |> Repo.insert()

  def update_scim_group(id, tenant_id, attrs) do
    with group when not is_nil(group) <- Repo.get(ScimGroup, id),
         true <- group.tenant_id == tenant_id,
         {:ok, updated} <- group |> ScimGroup.changeset(attrs) |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # ---------------------------------------------------------------------------
  # Roles and Policy
  # ---------------------------------------------------------------------------

  def list_roles(tenant_id) do
    Role
    |> where([r], r.tenant_id == ^tenant_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  def create_role(attrs), do: struct(Role) |> Role.changeset(attrs) |> Repo.insert()

  def assign_role(attrs), do: struct(UserRole) |> UserRole.changeset(attrs) |> Repo.insert()

  def evaluate_policy(tenant_id, user_id, permission) do
    allowed? =
      UserRole
      |> join(:inner, [ur], r in Role, on: ur.role_id == r.id)
      |> where(
        [ur, r],
        ur.tenant_id == ^tenant_id and ur.user_id == ^user_id and r.tenant_id == ^tenant_id
      )
      |> select([_ur, r], r.permissions)
      |> Repo.all()
      |> List.flatten()
      |> Enum.uniq()
      |> Enum.member?(permission)

    {:ok, %{allowed: allowed?, permission: permission, user_id: user_id, tenant_id: tenant_id}}
  end

  # ---------------------------------------------------------------------------
  # Audit
  # ---------------------------------------------------------------------------

  def list_audit_events(tenant_id, limit \\ 50) do
    AuditEvent
    |> where([a], a.tenant_id == ^tenant_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^min(limit, 200))
    |> Repo.all()
  end

  def get_audit_event(id, tenant_id) do
    AuditEvent
    |> where([a], a.id == ^id and a.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  def log_audit_event(attrs),
    do: struct(AuditEvent) |> AuditEvent.changeset(attrs) |> Repo.insert()

  # ---------------------------------------------------------------------------
  # Webhooks
  # ---------------------------------------------------------------------------

  def create_webhook_endpoint(attrs),
    do: struct(WebhookEndpoint) |> WebhookEndpoint.changeset(attrs) |> Repo.insert()

  def list_webhook_deliveries(tenant_id) do
    WebhookDelivery
    |> join(:inner, [d], e in WebhookEndpoint, on: d.webhook_endpoint_id == e.id)
    |> where([_d, e], e.tenant_id == ^tenant_id)
    |> order_by([d, _e], desc: d.inserted_at)
    |> select([d, _e], d)
    |> Repo.all()
  end

  def replay_webhook_delivery(id, tenant_id) do
    with delivery when not is_nil(delivery) <- Repo.get(WebhookDelivery, id),
         endpoint when not is_nil(endpoint) <-
           Repo.get(WebhookEndpoint, delivery.webhook_endpoint_id),
         true <- endpoint.tenant_id == tenant_id,
         {:ok, updated} <-
           delivery
           |> WebhookDelivery.changeset(%{
             "status" => "queued",
             "attempts" => delivery.attempts + 1
           })
           |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :not_found}
      false -> {:error, :not_found}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # ---------------------------------------------------------------------------
  # Notifications
  # ---------------------------------------------------------------------------

  def create_notification_template(attrs),
    do: struct(NotificationTemplate) |> NotificationTemplate.changeset(attrs) |> Repo.insert()

  def send_notification(attrs) do
    struct(NotificationMessage)
    |> NotificationMessage.changeset(Map.put(attrs, "status", "queued"))
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Feature Flags
  # ---------------------------------------------------------------------------

  def list_feature_flags(tenant_id) do
    FeatureFlag
    |> where([f], f.tenant_id == ^tenant_id)
    |> order_by([f], asc: f.key)
    |> Repo.all()
  end

  def create_feature_flag(attrs),
    do: struct(FeatureFlag) |> FeatureFlag.changeset(attrs) |> Repo.insert()

  # ---------------------------------------------------------------------------
  # Jobs and Compliance
  # ---------------------------------------------------------------------------

  def create_job(attrs),
    do: struct(Job) |> Job.changeset(Map.put(attrs, "status", "queued")) |> Repo.insert()

  def get_job(id, tenant_id) do
    Job
    |> where([j], j.id == ^id and j.tenant_id == ^tenant_id)
    |> Repo.one()
  end

  def create_compliance_request(attrs) do
    struct(ComplianceRequest)
    |> ComplianceRequest.changeset(Map.put(attrs, "status", "queued"))
    |> Repo.insert()
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  def search(user_id, query, limit \\ 20)

  def search(_user_id, query, _limit) when query in [nil, ""], do: []

  def search(user_id, query, limit) do
    like = "%" <> query <> "%"
    limit = min(limit, 50)

    notes =
      Note
      |> where(
        [n],
        n.user_id == ^user_id and
          (ilike(n.title, ^like) or ilike(fragment("coalesce(?, '')", n.content), ^like))
      )
      |> limit(^limit)
      |> select([n], %{type: "note", id: n.id, label: n.title, detail: n.content})
      |> Repo.all()

    projects =
      Project
      |> where(
        [p],
        p.user_id == ^user_id and
          (ilike(p.name, ^like) or ilike(fragment("coalesce(?, '')", p.description), ^like))
      )
      |> limit(^limit)
      |> select([p], %{type: "project", id: p.id, label: p.name, detail: p.description})
      |> Repo.all()

    tasks =
      Task
      |> where(
        [t],
        t.user_id == ^user_id and
          (ilike(t.title, ^like) or ilike(fragment("coalesce(?, '')", t.details), ^like))
      )
      |> limit(^limit)
      |> select([t], %{type: "task", id: t.id, label: t.title, detail: t.details})
      |> Repo.all()

    Enum.take(notes ++ projects ++ tasks, limit)
  end

  # ---------------------------------------------------------------------------
  # Schemas
  # ---------------------------------------------------------------------------

  defmodule Tenant do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "tenants" do
      field(:name, :string)
      field(:slug, :string)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(tenant, attrs) do
      tenant
      |> cast(attrs, [:name, :slug])
      |> validate_required([:name, :slug])
      |> validate_length(:name, min: 2, max: 120)
      |> validate_format(:slug, ~r/^[a-z0-9-]+$/)
      |> unique_constraint(:slug)
    end
  end

  defmodule Entitlement do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "entitlements" do
      field(:key, :string)
      field(:enabled, :boolean, default: true)
      field(:limits, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(entitlement, attrs) do
      entitlement
      |> cast(attrs, [:tenant_id, :key, :enabled, :limits])
      |> validate_required([:tenant_id, :key])
      |> unique_constraint([:tenant_id, :key])
    end
  end

  defmodule SsoConnection do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "sso_connections" do
      field(:provider, :string)
      field(:issuer, :string)
      field(:client_id, :string)
      field(:metadata, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(connection, attrs) do
      connection
      |> cast(attrs, [:tenant_id, :provider, :issuer, :client_id, :metadata])
      |> validate_required([:tenant_id, :provider, :issuer, :client_id])
    end
  end

  defmodule ScimUser do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "scim_users" do
      field(:external_id, :string)
      field(:user_name, :string)
      field(:email, :string)
      field(:active, :boolean, default: true)
      field(:raw, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(user, attrs) do
      user
      |> cast(attrs, [:tenant_id, :external_id, :user_name, :email, :active, :raw])
      |> validate_required([:tenant_id, :external_id, :user_name])
    end
  end

  defmodule ScimGroup do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "scim_groups" do
      field(:external_id, :string)
      field(:display_name, :string)
      field(:raw, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(group, attrs) do
      group
      |> cast(attrs, [:tenant_id, :external_id, :display_name, :raw])
      |> validate_required([:tenant_id, :external_id, :display_name])
    end
  end

  defmodule Role do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "roles" do
      field(:name, :string)
      field(:permissions, {:array, :string}, default: [])
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(role, attrs) do
      role
      |> cast(attrs, [:tenant_id, :name, :permissions])
      |> validate_required([:tenant_id, :name])
      |> unique_constraint([:tenant_id, :name])
    end
  end

  defmodule UserRole do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "user_roles" do
      field(:user_id, :string)
      belongs_to(:tenant, Tenant, type: :binary_id)
      belongs_to(:role, Role, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(user_role, attrs) do
      user_role
      |> cast(attrs, [:tenant_id, :role_id, :user_id])
      |> validate_required([:tenant_id, :role_id, :user_id])
      |> unique_constraint([:tenant_id, :role_id, :user_id])
    end
  end

  defmodule AuditEvent do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "audit_events" do
      field(:actor_id, :string)
      field(:action, :string)
      field(:resource_type, :string)
      field(:resource_id, :string)
      field(:request_id, :string)
      field(:metadata, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    def changeset(event, attrs) do
      event
      |> cast(attrs, [
        :tenant_id,
        :actor_id,
        :action,
        :resource_type,
        :resource_id,
        :request_id,
        :metadata
      ])
      |> validate_required([:tenant_id, :actor_id, :action, :resource_type])
    end
  end

  defmodule WebhookEndpoint do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "webhook_endpoints" do
      field(:url, :string)
      field(:secret, :string)
      field(:events, {:array, :string}, default: [])
      field(:active, :boolean, default: true)
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(endpoint, attrs) do
      endpoint
      |> cast(attrs, [:tenant_id, :url, :secret, :events, :active])
      |> validate_required([:tenant_id, :url, :secret])
      |> validate_format(:url, ~r/^https?:\/\//)
    end
  end

  defmodule WebhookDelivery do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "webhook_deliveries" do
      field(:event_type, :string)
      field(:payload, :map, default: %{})
      field(:status, :string, default: "queued")
      field(:response_code, :integer)
      field(:attempts, :integer, default: 0)
      belongs_to(:webhook_endpoint, WebhookEndpoint, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(delivery, attrs) do
      delivery
      |> cast(attrs, [
        :webhook_endpoint_id,
        :event_type,
        :payload,
        :status,
        :response_code,
        :attempts
      ])
      |> validate_required([:webhook_endpoint_id, :event_type, :status])
    end
  end

  defmodule NotificationTemplate do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "notification_templates" do
      field(:channel, :string)
      field(:name, :string)
      field(:subject, :string)
      field(:body, :string)
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(template, attrs) do
      template
      |> cast(attrs, [:tenant_id, :channel, :name, :subject, :body])
      |> validate_required([:tenant_id, :channel, :name, :body])
      |> unique_constraint([:tenant_id, :channel, :name])
    end
  end

  defmodule NotificationMessage do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "notification_messages" do
      field(:channel, :string)
      field(:to, :string)
      field(:subject, :string)
      field(:body, :string)
      field(:status, :string, default: "queued")
      field(:provider_response, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(message, attrs) do
      message
      |> cast(attrs, [:tenant_id, :channel, :to, :subject, :body, :status, :provider_response])
      |> validate_required([:tenant_id, :channel, :to, :body, :status])
    end
  end

  defmodule FeatureFlag do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "feature_flags" do
      field(:key, :string)
      field(:description, :string)
      field(:enabled, :boolean, default: false)
      field(:rollout, :integer, default: 100)
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(flag, attrs) do
      flag
      |> cast(attrs, [:tenant_id, :key, :description, :enabled, :rollout])
      |> validate_required([:tenant_id, :key])
      |> validate_number(:rollout, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
      |> unique_constraint([:tenant_id, :key])
    end
  end

  defmodule Job do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "jobs" do
      field(:kind, :string)
      field(:payload, :map, default: %{})
      field(:status, :string, default: "queued")
      field(:result, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(job, attrs) do
      job
      |> cast(attrs, [:tenant_id, :kind, :payload, :status, :result])
      |> validate_required([:tenant_id, :kind, :status])
    end
  end

  defmodule ComplianceRequest do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    schema "compliance_requests" do
      field(:user_id, :string)
      field(:request_type, :string)
      field(:status, :string, default: "queued")
      field(:payload, :map, default: %{})
      belongs_to(:tenant, Tenant, type: :binary_id)
      timestamps(type: :utc_datetime_usec)
    end

    def changeset(request, attrs) do
      request
      |> cast(attrs, [:tenant_id, :user_id, :request_type, :status, :payload])
      |> validate_required([:tenant_id, :user_id, :request_type, :status])
      |> validate_inclusion(:request_type, ["export", "delete"])
    end
  end
end
