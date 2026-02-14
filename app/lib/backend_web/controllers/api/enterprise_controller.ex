defmodule BackendWeb.API.EnterpriseController do
  use BackendWeb, :controller

  alias Backend.Enterprise
  alias BackendWeb.ErrorResponse

  action_fallback(BackendWeb.FallbackController)

  # ---------------------------------------------------------------------------
  # SSO
  # ---------------------------------------------------------------------------

  def sso_providers(conn, %{"tenant_id" => tenant_id}) do
    json(conn, %{data: %{providers: Enterprise.list_sso_providers(tenant_id)}})
  end

  def sso_providers(conn, _params) do
    ErrorResponse.send(conn, :bad_request, "invalid_request", "tenant_id is required")
  end

  def sso_callback(conn, %{"tenant_id" => tenant_id} = params) do
    attrs = %{
      "tenant_id" => tenant_id,
      "provider" => params["provider"] || "oidc",
      "issuer" => params["issuer"] || "https://example-idp.invalid",
      "client_id" => params["client_id"] || "mobile-app",
      "metadata" => Map.drop(params, ["tenant_id", "provider", "issuer", "client_id"])
    }

    with {:ok, connection} <- Enterprise.create_sso_connection(attrs) do
      record_audit(
        tenant_id,
        current_user_id(conn),
        "sso.callback",
        "sso_connection",
        connection.id,
        conn
      )

      conn |> put_status(:created) |> json(%{data: sso_json(connection)})
    end
  end

  # ---------------------------------------------------------------------------
  # SCIM
  # ---------------------------------------------------------------------------

  def scim_list_users(conn, %{"tenant_id" => tenant_id}) do
    users = Enterprise.list_scim_users(tenant_id)
    json(conn, %{data: Enum.map(users, &scim_user_json/1)})
  end

  def scim_create_user(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, user} <- Enterprise.create_scim_user(params) do
      conn |> put_status(:created) |> json(%{data: scim_user_json(user)})
    end
  end

  def scim_patch_user(conn, %{"id" => id, "tenant_id" => tenant_id} = params) do
    with {:ok, user} <- Enterprise.update_scim_user(id, tenant_id, params) do
      json(conn, %{data: scim_user_json(user)})
    end
  end

  def scim_list_groups(conn, %{"tenant_id" => tenant_id}) do
    groups = Enterprise.list_scim_groups(tenant_id)
    json(conn, %{data: Enum.map(groups, &scim_group_json/1)})
  end

  def scim_create_group(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, group} <- Enterprise.create_scim_group(params) do
      conn |> put_status(:created) |> json(%{data: scim_group_json(group)})
    end
  end

  def scim_patch_group(conn, %{"id" => id, "tenant_id" => tenant_id} = params) do
    with {:ok, group} <- Enterprise.update_scim_group(id, tenant_id, params) do
      json(conn, %{data: scim_group_json(group)})
    end
  end

  # ---------------------------------------------------------------------------
  # RBAC / Policy
  # ---------------------------------------------------------------------------

  def roles_index(conn, %{"tenant_id" => tenant_id}) do
    roles = Enterprise.list_roles(tenant_id)
    json(conn, %{data: Enum.map(roles, &role_json/1)})
  end

  def roles_create(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, role} <- Enterprise.create_role(params) do
      if params["user_id"],
        do:
          Enterprise.assign_role(%{
            "tenant_id" => params["tenant_id"],
            "role_id" => role.id,
            "user_id" => params["user_id"]
          })

      conn |> put_status(:created) |> json(%{data: role_json(role)})
    end
  end

  def policy_evaluate(conn, %{"tenant_id" => tenant_id, "permission" => permission} = params) do
    user_id = params["user_id"] || current_user_id(conn)

    with {:ok, result} <- Enterprise.evaluate_policy(tenant_id, user_id, permission) do
      json(conn, %{data: result})
    end
  end

  # ---------------------------------------------------------------------------
  # Audit
  # ---------------------------------------------------------------------------

  def audit_index(conn, %{"tenant_id" => tenant_id} = params) do
    limit = params |> Map.get("limit", "50") |> to_int(50)
    events = Enterprise.list_audit_events(tenant_id, limit)
    json(conn, %{data: Enum.map(events, &audit_json/1)})
  end

  def audit_show(conn, %{"tenant_id" => tenant_id, "id" => id}) do
    case Enterprise.get_audit_event(id, tenant_id) do
      nil ->
        ErrorResponse.send(conn, :not_found, "audit_event_not_found", "Audit event not found")

      event ->
        json(conn, %{data: audit_json(event)})
    end
  end

  # ---------------------------------------------------------------------------
  # Webhooks
  # ---------------------------------------------------------------------------

  def webhooks_create_endpoint(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, endpoint} <- Enterprise.create_webhook_endpoint(params) do
      conn |> put_status(:created) |> json(%{data: webhook_endpoint_json(endpoint)})
    end
  end

  def webhooks_list_deliveries(conn, %{"tenant_id" => tenant_id}) do
    deliveries = Enterprise.list_webhook_deliveries(tenant_id)
    json(conn, %{data: Enum.map(deliveries, &webhook_delivery_json/1)})
  end

  def webhooks_replay_delivery(conn, %{"tenant_id" => tenant_id, "id" => id}) do
    with {:ok, delivery} <- Enterprise.replay_webhook_delivery(id, tenant_id) do
      json(conn, %{data: webhook_delivery_json(delivery)})
    end
  end

  # ---------------------------------------------------------------------------
  # Notifications
  # ---------------------------------------------------------------------------

  def notifications_send(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, message} <- Enterprise.send_notification(params) do
      conn |> put_status(:created) |> json(%{data: notification_message_json(message)})
    end
  end

  def notifications_create_template(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, template} <- Enterprise.create_notification_template(params) do
      conn |> put_status(:created) |> json(%{data: notification_template_json(template)})
    end
  end

  # ---------------------------------------------------------------------------
  # Feature Flags
  # ---------------------------------------------------------------------------

  def feature_flags_index(conn, %{"tenant_id" => tenant_id}) do
    flags = Enterprise.list_feature_flags(tenant_id)
    json(conn, %{data: Enum.map(flags, &feature_flag_json/1)})
  end

  def feature_flags_create(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, flag} <- Enterprise.create_feature_flag(params) do
      conn |> put_status(:created) |> json(%{data: feature_flag_json(flag)})
    end
  end

  # ---------------------------------------------------------------------------
  # Tenant / Entitlements
  # ---------------------------------------------------------------------------

  def tenants_create(conn, params) do
    with {:ok, tenant} <- Enterprise.create_tenant(params) do
      conn |> put_status(:created) |> json(%{data: tenant_json(tenant)})
    end
  end

  def tenants_show(conn, %{"id" => id}) do
    case Enterprise.get_tenant(id) do
      nil -> ErrorResponse.send(conn, :not_found, "tenant_not_found", "Tenant not found")
      tenant -> json(conn, %{data: tenant_json(tenant)})
    end
  end

  def entitlements_index(conn, %{"tenant_id" => tenant_id}) do
    entitlements = Enterprise.list_entitlements(tenant_id)

    json(conn, %{
      data:
        Enum.map(entitlements, fn ent ->
          %{id: ent.id, key: ent.key, enabled: ent.enabled, limits: ent.limits}
        end)
    })
  end

  # ---------------------------------------------------------------------------
  # Jobs and Compliance
  # ---------------------------------------------------------------------------

  def jobs_create(conn, %{"tenant_id" => _tenant_id} = params) do
    with {:ok, job} <- Enterprise.create_job(params) do
      conn |> put_status(:created) |> json(%{data: job_json(job)})
    end
  end

  def jobs_show(conn, %{"tenant_id" => tenant_id, "id" => id}) do
    case Enterprise.get_job(id, tenant_id) do
      nil -> ErrorResponse.send(conn, :not_found, "job_not_found", "Job not found")
      job -> json(conn, %{data: job_json(job)})
    end
  end

  def compliance_export(conn, %{"tenant_id" => tenant_id} = params) do
    attrs =
      params
      |> Map.put("tenant_id", tenant_id)
      |> Map.put("request_type", "export")
      |> Map.put_new("user_id", current_user_id(conn))

    with {:ok, req} <- Enterprise.create_compliance_request(attrs) do
      conn |> put_status(:accepted) |> json(%{data: compliance_request_json(req)})
    end
  end

  def compliance_delete(conn, %{"tenant_id" => tenant_id} = params) do
    attrs =
      params
      |> Map.put("tenant_id", tenant_id)
      |> Map.put("request_type", "delete")
      |> Map.put_new("user_id", current_user_id(conn))

    with {:ok, req} <- Enterprise.create_compliance_request(attrs) do
      conn |> put_status(:accepted) |> json(%{data: compliance_request_json(req)})
    end
  end

  # ---------------------------------------------------------------------------
  # Search
  # ---------------------------------------------------------------------------

  def search(conn, %{"q" => q} = params) do
    limit = params |> Map.get("limit", "20") |> to_int(20)
    results = Enterprise.search(current_user_id(conn), q, limit)
    json(conn, %{data: results, meta: %{query: q, count: length(results)}})
  end

  def search(conn, _params) do
    ErrorResponse.send(conn, :bad_request, "invalid_request", "q is required")
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp current_user_id(conn) do
    user = get_session(conn, :current_user) || %{}
    user["provider_uid"] || user[:provider_uid] || "unknown"
  end

  defp current_request_id(conn),
    do: List.first(get_resp_header(conn, "x-request-id")) || conn.assigns[:request_id]

  defp record_audit(tenant_id, actor_id, action, resource_type, resource_id, conn) do
    Enterprise.log_audit_event(%{
      "tenant_id" => tenant_id,
      "actor_id" => actor_id,
      "action" => action,
      "resource_type" => resource_type,
      "resource_id" => to_string(resource_id),
      "request_id" => current_request_id(conn),
      "metadata" => %{"path" => conn.request_path, "method" => conn.method}
    })
  end

  defp to_int(value, _default) when is_integer(value), do: value

  defp to_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {num, _} -> num
      :error -> default
    end
  end

  defp to_int(_, default), do: default

  defp sso_json(connection) do
    %{
      id: connection.id,
      tenant_id: connection.tenant_id,
      provider: connection.provider,
      issuer: connection.issuer,
      client_id: connection.client_id,
      metadata: connection.metadata
    }
  end

  defp scim_user_json(user) do
    %{
      id: user.id,
      tenant_id: user.tenant_id,
      external_id: user.external_id,
      user_name: user.user_name,
      email: user.email,
      active: user.active
    }
  end

  defp scim_group_json(group) do
    %{
      id: group.id,
      tenant_id: group.tenant_id,
      external_id: group.external_id,
      display_name: group.display_name
    }
  end

  defp role_json(role) do
    %{
      id: role.id,
      tenant_id: role.tenant_id,
      name: role.name,
      permissions: role.permissions
    }
  end

  defp audit_json(event) do
    %{
      id: event.id,
      tenant_id: event.tenant_id,
      actor_id: event.actor_id,
      action: event.action,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      request_id: event.request_id,
      metadata: event.metadata,
      inserted_at: event.inserted_at
    }
  end

  defp webhook_endpoint_json(endpoint) do
    %{
      id: endpoint.id,
      tenant_id: endpoint.tenant_id,
      url: endpoint.url,
      events: endpoint.events,
      active: endpoint.active
    }
  end

  defp webhook_delivery_json(delivery) do
    %{
      id: delivery.id,
      webhook_endpoint_id: delivery.webhook_endpoint_id,
      event_type: delivery.event_type,
      status: delivery.status,
      response_code: delivery.response_code,
      attempts: delivery.attempts,
      inserted_at: delivery.inserted_at,
      updated_at: delivery.updated_at
    }
  end

  defp notification_template_json(template) do
    %{
      id: template.id,
      tenant_id: template.tenant_id,
      channel: template.channel,
      name: template.name,
      subject: template.subject,
      body: template.body
    }
  end

  defp notification_message_json(message) do
    %{
      id: message.id,
      tenant_id: message.tenant_id,
      channel: message.channel,
      to: message.to,
      subject: message.subject,
      status: message.status,
      inserted_at: message.inserted_at
    }
  end

  defp feature_flag_json(flag) do
    %{
      id: flag.id,
      tenant_id: flag.tenant_id,
      key: flag.key,
      description: flag.description,
      enabled: flag.enabled,
      rollout: flag.rollout
    }
  end

  defp tenant_json(tenant) do
    %{
      id: tenant.id,
      name: tenant.name,
      slug: tenant.slug,
      inserted_at: tenant.inserted_at,
      updated_at: tenant.updated_at
    }
  end

  defp job_json(job) do
    %{
      id: job.id,
      tenant_id: job.tenant_id,
      kind: job.kind,
      status: job.status,
      payload: job.payload,
      result: job.result,
      inserted_at: job.inserted_at,
      updated_at: job.updated_at
    }
  end

  defp compliance_request_json(req) do
    %{
      id: req.id,
      tenant_id: req.tenant_id,
      user_id: req.user_id,
      request_type: req.request_type,
      status: req.status,
      payload: req.payload,
      inserted_at: req.inserted_at
    }
  end
end
