defmodule BackendWeb.API.EnterpriseControllerTest do
  use BackendWeb.ConnCase, async: true

  alias Backend.Enterprise
  alias Backend.Repo

  setup %{conn: conn} do
    user_id = "enterprise_user_#{System.unique_integer([:positive])}"

    conn =
      conn
      |> init_test_session(%{
        current_user: %{
          "provider_uid" => user_id,
          "email" => "enterprise@example.com",
          "name" => "Enterprise User"
        }
      })

    {:ok, tenant_id: create_tenant(conn), conn: conn, user_id: user_id}
  end

  test "sso providers endpoints cover missing and configured flows", %{
    conn: conn,
    tenant_id: tenant_id
  } do
    bad = get(conn, "/api/v1/auth/sso/providers")
    assert bad.status == 400
    assert json_response(bad, 400)["code"] == "invalid_request"

    cb =
      post(conn, "/api/v1/auth/sso/callback", %{
        "tenant_id" => tenant_id,
        "provider" => "okta",
        "issuer" => "https://okta.example.com",
        "client_id" => "mobile-app"
      })

    assert cb.status == 201

    providers = get(conn, "/api/v1/auth/sso/providers?tenant_id=#{tenant_id}")
    assert providers.status == 200
    assert Enum.member?(json_response(providers, 200)["data"]["providers"], "okta")
  end

  test "scim users and groups create/list/patch", %{conn: conn, tenant_id: tenant_id} do
    user_create =
      post(conn, "/api/v1/scim/v2/Users", %{
        "tenant_id" => tenant_id,
        "external_id" => "ext-user-1",
        "user_name" => "enterprise.user",
        "email" => "enterprise.user@example.com"
      })

    assert user_create.status == 201
    user_id = json_response(user_create, 201)["data"]["id"]

    user_patch =
      patch(conn, "/api/v1/scim/v2/Users/#{user_id}", %{
        "tenant_id" => tenant_id,
        "email" => "updated.user@example.com"
      })

    assert user_patch.status == 200
    assert json_response(user_patch, 200)["data"]["email"] == "updated.user@example.com"

    user_list = get(conn, "/api/v1/scim/v2/Users?tenant_id=#{tenant_id}")
    assert user_list.status == 200
    assert json_response(user_list, 200)["data"] != []

    missing_user_patch =
      patch(conn, "/api/v1/scim/v2/Users/#{Ecto.UUID.generate()}", %{"tenant_id" => tenant_id})

    assert missing_user_patch.status == 404

    group_create =
      post(conn, "/api/v1/scim/v2/Groups", %{
        "tenant_id" => tenant_id,
        "external_id" => "ext-group-1",
        "display_name" => "Platform Admins"
      })

    assert group_create.status == 201
    group_id = json_response(group_create, 201)["data"]["id"]

    group_patch =
      patch(conn, "/api/v1/scim/v2/Groups/#{group_id}", %{
        "tenant_id" => tenant_id,
        "display_name" => "Platform Owners"
      })

    assert group_patch.status == 200
    assert json_response(group_patch, 200)["data"]["display_name"] == "Platform Owners"

    group_list = get(conn, "/api/v1/scim/v2/Groups?tenant_id=#{tenant_id}")
    assert group_list.status == 200
    assert json_response(group_list, 200)["data"] != []

    missing_group_patch =
      patch(conn, "/api/v1/scim/v2/Groups/#{Ecto.UUID.generate()}", %{"tenant_id" => tenant_id})

    assert missing_group_patch.status == 404
  end

  test "roles and policy evaluate flows", %{conn: conn, tenant_id: tenant_id, user_id: user_id} do
    role_create =
      post(conn, "/api/v1/roles", %{
        "tenant_id" => tenant_id,
        "name" => "manager",
        "permissions" => ["projects.read", "projects.write"],
        "user_id" => user_id
      })

    assert role_create.status == 201
    assert json_response(role_create, 201)["data"]["name"] == "manager"

    roles = get(conn, "/api/v1/roles?tenant_id=#{tenant_id}")
    assert roles.status == 200
    assert json_response(roles, 200)["data"] != []

    allow_eval =
      post(conn, "/api/v1/policy/evaluate", %{
        "tenant_id" => tenant_id,
        "permission" => "projects.read"
      })

    assert allow_eval.status == 200
    assert json_response(allow_eval, 200)["data"]["allowed"] == true

    deny_eval =
      post(conn, "/api/v1/policy/evaluate", %{
        "tenant_id" => tenant_id,
        "permission" => "billing.delete",
        "user_id" => "different_user"
      })

    assert deny_eval.status == 200
    assert json_response(deny_eval, 200)["data"]["allowed"] == false
  end

  test "audit index and show not-found branch", %{conn: conn, tenant_id: tenant_id} do
    {:ok, event} =
      Enterprise.log_audit_event(%{
        "tenant_id" => tenant_id,
        "actor_id" => "enterprise-actor",
        "action" => "resource.read",
        "resource_type" => "project",
        "resource_id" => Ecto.UUID.generate()
      })

    list = get(conn, "/api/v1/audit/events?tenant_id=#{tenant_id}&limit=5")
    assert list.status == 200
    assert json_response(list, 200)["data"] != []

    show = get(conn, "/api/v1/audit/events/#{event.id}?tenant_id=#{tenant_id}")
    assert show.status == 200
    assert json_response(show, 200)["data"]["id"] == event.id

    missing = get(conn, "/api/v1/audit/events/#{Ecto.UUID.generate()}?tenant_id=#{tenant_id}")
    assert missing.status == 404
  end

  test "webhooks create/list/replay and not-found replay", %{conn: conn, tenant_id: tenant_id} do
    endpoint_create =
      post(conn, "/api/v1/webhooks/endpoints", %{
        "tenant_id" => tenant_id,
        "url" => "https://hooks.example.com/events",
        "secret" => "top-secret",
        "events" => ["project.created"]
      })

    assert endpoint_create.status == 201
    endpoint_id = json_response(endpoint_create, 201)["data"]["id"]

    {:ok, delivery} =
      struct(Enterprise.WebhookDelivery)
      |> Enterprise.WebhookDelivery.changeset(%{
        "webhook_endpoint_id" => endpoint_id,
        "event_type" => "project.created",
        "payload" => %{"id" => "123"},
        "status" => "delivered",
        "attempts" => 1
      })
      |> Repo.insert()

    list = get(conn, "/api/v1/webhooks/deliveries?tenant_id=#{tenant_id}")
    assert list.status == 200
    assert Enum.any?(json_response(list, 200)["data"], &(&1["id"] == delivery.id))

    replay =
      post(conn, "/api/v1/webhooks/deliveries/#{delivery.id}/replay?tenant_id=#{tenant_id}", %{})

    assert replay.status == 200
    assert json_response(replay, 200)["data"]["status"] == "queued"

    missing =
      post(
        conn,
        "/api/v1/webhooks/deliveries/#{Ecto.UUID.generate()}/replay?tenant_id=#{tenant_id}",
        %{}
      )

    assert missing.status == 404
  end

  test "notifications and feature flags", %{conn: conn, tenant_id: tenant_id} do
    template =
      post(conn, "/api/v1/notifications/templates", %{
        "tenant_id" => tenant_id,
        "channel" => "email",
        "name" => "welcome",
        "subject" => "Welcome",
        "body" => "Hello from the platform"
      })

    assert template.status == 201

    send_msg =
      post(conn, "/api/v1/notifications/send", %{
        "tenant_id" => tenant_id,
        "channel" => "email",
        "to" => "recipient@example.com",
        "subject" => "Welcome",
        "body" => "Welcome aboard"
      })

    assert send_msg.status == 201
    assert json_response(send_msg, 201)["data"]["status"] == "queued"

    flag_create =
      post(conn, "/api/v1/features", %{
        "tenant_id" => tenant_id,
        "key" => "new-home",
        "description" => "New home rollout",
        "enabled" => true,
        "rollout" => 25
      })

    assert flag_create.status == 201

    flag_list = get(conn, "/api/v1/features?tenant_id=#{tenant_id}")
    assert flag_list.status == 200
    assert json_response(flag_list, 200)["data"] != []
  end

  test "tenant show, entitlements list, jobs and compliance", %{conn: conn, tenant_id: tenant_id} do
    show = get(conn, "/api/v1/tenants/#{tenant_id}")
    assert show.status == 200
    assert json_response(show, 200)["data"]["id"] == tenant_id

    missing_show = get(conn, "/api/v1/tenants/#{Ecto.UUID.generate()}")
    assert missing_show.status == 404

    {:ok, _entitlement} =
      struct(Enterprise.Entitlement)
      |> Enterprise.Entitlement.changeset(%{
        "tenant_id" => tenant_id,
        "key" => "api.enterprise",
        "enabled" => true,
        "limits" => %{"max_users" => 100}
      })
      |> Repo.insert()

    entitlements = get(conn, "/api/v1/entitlements?tenant_id=#{tenant_id}")
    assert entitlements.status == 200
    assert json_response(entitlements, 200)["data"] != []

    job_create =
      post(conn, "/api/v1/jobs", %{
        "tenant_id" => tenant_id,
        "kind" => "reindex",
        "payload" => %{"scope" => "projects"}
      })

    assert job_create.status == 201
    job_id = json_response(job_create, 201)["data"]["id"]

    job_show = get(conn, "/api/v1/jobs/#{job_id}?tenant_id=#{tenant_id}")
    assert job_show.status == 200

    missing_job = get(conn, "/api/v1/jobs/#{Ecto.UUID.generate()}?tenant_id=#{tenant_id}")
    assert missing_job.status == 404

    export_req =
      post(conn, "/api/v1/compliance/export", %{
        "tenant_id" => tenant_id,
        "payload" => %{"format" => "json"}
      })

    assert export_req.status == 202

    delete_req =
      post(conn, "/api/v1/compliance/delete", %{
        "tenant_id" => tenant_id,
        "payload" => %{"reason" => "gdpr"}
      })

    assert delete_req.status == 202
  end

  test "search endpoint returns results and validates required query parameter", %{
    conn: conn,
    tenant_id: tenant_id
  } do
    _project =
      post(conn, "/api/v1/projects", %{
        "name" => "Enterprise Platform",
        "description" => "Searchable project"
      })

    search = get(conn, "/api/v1/search?q=Enterprise&tenant_id=#{tenant_id}&limit=5")
    assert search.status == 200
    assert is_list(json_response(search, 200)["data"])

    invalid = get(conn, "/api/v1/search?tenant_id=#{tenant_id}")
    assert invalid.status == 400
    assert json_response(invalid, 400)["code"] == "invalid_request"
  end

  defp create_tenant(conn) do
    response =
      post(conn, "/api/v1/tenants", %{
        "name" => "Acme #{System.unique_integer([:positive])}",
        "slug" => "acme-#{System.unique_integer([:positive])}"
      })
      |> json_response(201)

    response["data"]["id"]
  end
end
