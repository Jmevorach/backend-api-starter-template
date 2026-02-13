# API Integrations Guide

This guide covers the pre-built API client modules included in the backend accelerator.
These modules provide ready-to-use integrations with popular third-party services.

## Table of Contents

- [Overview](#overview)
- [Stripe Integration](#stripe-integration)
- [Checkr Integration](#checkr-integration)
- [Google Maps Integration](#google-maps-integration)
- [Adding Your Own Integrations](#adding-your-own-integrations)
- [Testing API Integrations](#testing-api-integrations)
- [Error Handling](#error-handling)
- [Security Best Practices](#security-best-practices)

## Overview

All API client modules follow a consistent pattern:

- **Optional Configuration**: Modules only activate when their API key is set
- **Error Handling**: All functions return `{:ok, result}` or `{:error, reason}`
- **Logging**: Errors are logged automatically for debugging
- **Security**: Webhook signatures are verified using constant-time comparison

### Quick Start

1. Set your API key as an environment variable:
   ```bash
   export STRIPE_API_KEY="sk_live_..."
   ```

2. Use the module in your code:
   ```elixir
   {:ok, customer} = Backend.Stripe.create_customer(%{email: "user@example.com"})
   ```

3. For production, store API keys in AWS Secrets Manager and configure the Terraform
   variables to inject them into ECS.

## Stripe Integration

The `Backend.Stripe` module provides payment processing capabilities.

### Configuration

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `STRIPE_API_KEY` | Stripe secret key (sk_live_... or sk_test_...) | Yes |

For production, set the `stripe_api_key_secret_arn` Terraform variable to inject the key
from Secrets Manager.

### Customer Management

```elixir
# Create a customer
{:ok, customer} = Backend.Stripe.create_customer(%{
  email: "user@example.com",
  name: "John Doe",
  metadata: %{internal_id: "user_123"}
})

# Get a customer
{:ok, customer} = Backend.Stripe.get_customer("cus_xxx")

# Update a customer
{:ok, customer} = Backend.Stripe.update_customer("cus_xxx", %{
  name: "Jane Doe"
})

# List customers with pagination
{:ok, %{"data" => customers, "has_more" => has_more}} = 
  Backend.Stripe.list_customers(%{limit: 10, starting_after: "cus_xxx"})

# Delete a customer
{:ok, _} = Backend.Stripe.delete_customer("cus_xxx")
```

### Payment Processing

#### Payment Intents (Recommended)

```elixir
# Create a payment intent
{:ok, intent} = Backend.Stripe.create_payment_intent(%{
  amount: 2000,           # $20.00 in cents
  currency: "usd",
  customer: "cus_xxx",    # Optional
  metadata: %{order_id: "order_123"}
})

# The client_secret is used by your frontend
client_secret = intent["client_secret"]

# Confirm a payment intent (server-side)
{:ok, confirmed} = Backend.Stripe.confirm_payment_intent("pi_xxx", %{
  payment_method: "pm_xxx"
})

# Get payment intent status
{:ok, intent} = Backend.Stripe.get_payment_intent("pi_xxx")
```

#### Legacy Charges

```elixir
# Create a charge (legacy - prefer Payment Intents)
{:ok, charge} = Backend.Stripe.create_charge(%{
  amount: 2000,
  currency: "usd",
  customer: "cus_xxx"
})

# Get a charge
{:ok, charge} = Backend.Stripe.get_charge("ch_xxx")
```

### Subscription Management

```elixir
# Create a subscription
{:ok, subscription} = Backend.Stripe.create_subscription(%{
  customer: "cus_xxx",
  items: [%{price: "price_xxx"}],
  trial_period_days: 14  # Optional
})

# Get subscription
{:ok, subscription} = Backend.Stripe.get_subscription("sub_xxx")

# Update subscription (e.g., change plan)
{:ok, subscription} = Backend.Stripe.update_subscription("sub_xxx", %{
  items: [%{id: "si_xxx", price: "price_new"}]
})

# Cancel at period end
{:ok, subscription} = Backend.Stripe.cancel_subscription("sub_xxx", %{
  cancel_at_period_end: true
})

# Cancel immediately
{:ok, subscription} = Backend.Stripe.cancel_subscription("sub_xxx")

# List subscriptions
{:ok, %{"data" => subs}} = Backend.Stripe.list_subscriptions(%{
  customer: "cus_xxx",
  status: "active"
})
```

### Products and Prices

```elixir
# List products
{:ok, %{"data" => products}} = Backend.Stripe.list_products(%{active: true})

# List prices
{:ok, %{"data" => prices}} = Backend.Stripe.list_prices(%{product: "prod_xxx"})
```

### Webhook Handling

```elixir
# In your controller
def webhook(conn, _params) do
  payload = conn.assigns.raw_body  # Ensure you capture raw body
  signature = get_req_header(conn, "stripe-signature") |> List.first()
  webhook_secret = System.get_env("STRIPE_WEBHOOK_SECRET")

  case Backend.Stripe.verify_webhook_signature(payload, signature, webhook_secret) do
    {:ok, event} ->
      handle_event(event)
      json(conn, %{received: true})

    {:error, :invalid_signature} ->
      conn |> put_status(400) |> json(%{error: "Invalid signature"})

    {:error, :invalid_payload} ->
      conn |> put_status(400) |> json(%{error: "Invalid payload"})
  end
end

defp handle_event(%{"type" => "customer.subscription.created"} = event) do
  subscription = event["data"]["object"]
  # Handle new subscription
end

defp handle_event(%{"type" => "invoice.paid"} = event) do
  invoice = event["data"]["object"]
  # Handle successful payment
end

defp handle_event(_event), do: :ok
```

## Checkr Integration

The `Backend.Checkr` module provides background check capabilities.

### Configuration

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `CHECKR_API_KEY` | Checkr API key | Yes |
| `CHECKR_ENVIRONMENT` | `sandbox` or `production` | No (defaults to sandbox) |

### Background Check Workflow

The typical workflow is:

1. Create a candidate
2. Create an invitation (sends email to candidate)
3. Candidate completes authorization
4. Poll for report status or use webhooks

```elixir
# Step 1: Create a candidate
{:ok, candidate} = Backend.Checkr.create_candidate(%{
  first_name: "John",
  last_name: "Doe",
  email: "john@example.com",
  dob: "1990-01-15",
  zipcode: "94107"
})

# Step 2: Create an invitation (triggers email to candidate)
{:ok, invitation} = Backend.Checkr.create_invitation(%{
  candidate_id: candidate["id"],
  package: "tasker_standard"
})

# Step 3: After candidate completes authorization, get the report
{:ok, report} = Backend.Checkr.get_report(invitation["report_id"])

# Check report status
case report["status"] do
  "pending" -> # Still processing
  "clear" -> # No adverse findings
  "consider" -> # Review recommended
  "suspended" -> # Needs more information
  "dispute" -> # Candidate disputed
end
```

### Available Packages

Use `list_packages/0` to see packages available for your account:

```elixir
{:ok, %{"data" => packages}} = Backend.Checkr.list_packages()

# Common packages:
# - tasker_standard: Standard background check
# - driver_standard: Driver check with MVR
# - basic_criminal: Criminal check only
# - pro: Professional background check
```

### Candidate Management

```elixir
# Get candidate
{:ok, candidate} = Backend.Checkr.get_candidate("candidate_id")

# List candidates
{:ok, %{"data" => candidates}} = Backend.Checkr.list_candidates(%{
  per_page: 25,
  page: 1
})
```

### Invitation Management

```elixir
# Get invitation status
{:ok, invitation} = Backend.Checkr.get_invitation("invitation_id")

# List invitations
{:ok, %{"data" => invitations}} = Backend.Checkr.list_invitations()

# Cancel a pending invitation
{:ok, _} = Backend.Checkr.cancel_invitation("invitation_id")
```

### Report Management

```elixir
# Create report directly (requires prior consent)
{:ok, report} = Backend.Checkr.create_report(%{
  candidate_id: "candidate_id",
  package: "tasker_standard"
})

# List reports
{:ok, %{"data" => reports}} = Backend.Checkr.list_reports(%{
  candidate_id: "candidate_id",
  status: "clear"
})

# Get specific screening within a report
{:ok, screening} = Backend.Checkr.get_screening("screening_id")
```

### Webhook Handling

```elixir
def webhook(conn, _params) do
  payload = conn.assigns.raw_body
  signature = get_req_header(conn, "x-checkr-signature") |> List.first()
  webhook_secret = System.get_env("CHECKR_WEBHOOK_SECRET")

  case Backend.Checkr.verify_webhook_signature(payload, signature, webhook_secret) do
    {:ok, event} ->
      handle_checkr_event(event)
      json(conn, %{received: true})

    {:error, _} ->
      conn |> put_status(400) |> json(%{error: "Invalid signature"})
  end
end

defp handle_checkr_event(%{"type" => "report.completed", "data" => %{"object" => report}}) do
  # Background check completed
  case report["status"] do
    "clear" -> # Approve candidate
    "consider" -> # Manual review needed
  end
end
```

## Google Maps Integration

The `Backend.GoogleMaps` module provides geocoding and places functionality.

### Configuration

| Environment Variable | Description | Required |
|---------------------|-------------|----------|
| `GOOGLE_MAPS_API_KEY` | Google Maps Platform API key | Yes |

Enable these APIs in Google Cloud Console:
- Geocoding API
- Places API
- Distance Matrix API (if using distance calculations)

### Geocoding

```elixir
# Convert address to coordinates
{:ok, result} = Backend.GoogleMaps.geocode("1600 Amphitheatre Parkway, Mountain View, CA")

lat = result["geometry"]["location"]["lat"]  # 37.4224764
lng = result["geometry"]["location"]["lng"]  # -122.0842499
formatted_address = result["formatted_address"]
place_id = result["place_id"]

# With region biasing
{:ok, result} = Backend.GoogleMaps.geocode("Sydney", region: "au")

# Get all results (not just the first)
{:ok, results} = Backend.GoogleMaps.geocode_all("Main Street")
```

### Reverse Geocoding

```elixir
# Convert coordinates to address
{:ok, result} = Backend.GoogleMaps.reverse_geocode(37.4224764, -122.0842499)

address = result["formatted_address"]
# "1600 Amphitheatre Pkwy, Mountain View, CA 94043, USA"

# Filter by result type
{:ok, result} = Backend.GoogleMaps.reverse_geocode(37.4224764, -122.0842499,
  result_type: "street_address"
)

# Get all results
{:ok, results} = Backend.GoogleMaps.reverse_geocode_all(37.4224764, -122.0842499)
```

### Places Autocomplete

```elixir
# Basic autocomplete
{:ok, predictions} = Backend.GoogleMaps.autocomplete("coffee shops near")

Enum.each(predictions, fn p ->
  IO.puts("#{p["description"]} (#{p["place_id"]})")
end)

# With location biasing (prioritize results near a point)
{:ok, predictions} = Backend.GoogleMaps.autocomplete("coffee",
  location: {37.7749, -122.4194},
  radius: 5000
)

# Filter by type
{:ok, predictions} = Backend.GoogleMaps.autocomplete("starbucks",
  types: "establishment"
)

# Restrict to country
{:ok, predictions} = Backend.GoogleMaps.autocomplete("123 main",
  components: "country:us"
)
```

### Place Details

```elixir
# Get full place details
{:ok, place} = Backend.GoogleMaps.place_details("ChIJ2eUgeAK6j4ARbn5u_wAGqWA")

name = place["name"]
address = place["formatted_address"]
phone = place["formatted_phone_number"]
rating = place["rating"]
website = place["website"]
hours = place["opening_hours"]

# Request specific fields only (reduces API cost)
{:ok, place} = Backend.GoogleMaps.place_details(place_id,
  fields: "name,formatted_address,geometry,rating"
)
```

### Nearby Search

```elixir
# Search for nearby restaurants
{:ok, places} = Backend.GoogleMaps.nearby_search(37.7749, -122.4194,
  radius: 1000,
  type: "restaurant"
)

# Search by keyword
{:ok, places} = Backend.GoogleMaps.nearby_search(37.7749, -122.4194,
  radius: 500,
  keyword: "vegetarian"
)

# Rank by distance
{:ok, places} = Backend.GoogleMaps.nearby_search(37.7749, -122.4194,
  rankby: "distance",
  type: "cafe"
)
```

### Text Search

```elixir
# Search with natural language query
{:ok, places} = Backend.GoogleMaps.text_search("pizza in New York")

# With location biasing
{:ok, places} = Backend.GoogleMaps.text_search("museum",
  location: {48.8566, 2.3522},
  radius: 5000
)
```

### Distance Matrix

```elixir
# Calculate distance and travel time
{:ok, result} = Backend.GoogleMaps.distance_matrix(
  ["Seattle, WA"],
  ["San Francisco, CA", "Los Angeles, CA"]
)

# Access results
rows = result["rows"]
first_origin = hd(rows)["elements"]
to_sf = hd(first_origin)
distance = to_sf["distance"]["text"]  # "808 mi"
duration = to_sf["duration"]["text"]  # "12 hours 5 mins"

# With travel mode
{:ok, result} = Backend.GoogleMaps.distance_matrix(
  ["New York, NY"],
  ["Boston, MA"],
  mode: "transit"
)

# Using coordinates
{:ok, result} = Backend.GoogleMaps.distance_matrix(
  [{47.6062, -122.3321}],
  [{37.7749, -122.4194}],
  units: "imperial"
)
```

## Adding Your Own Integrations

See [CONTRIBUTING.md](../CONTRIBUTING.md#adding-api-client-modules) for detailed
instructions on adding new API integrations.

### Quick Template

```elixir
defmodule Backend.YourApi do
  @moduledoc """
  Client for YourApi.
  
  Set `YOUR_API_KEY` environment variable to enable.
  """

  require Logger

  @base_url "https://api.yourservice.com/v1"

  def do_something(params) do
    case get_api_key() do
      nil -> {:error, :api_key_not_configured}
      _key -> request(:post, "/endpoint", params)
    end
  end

  defp request(method, path, params) do
    url = @base_url <> path
    opts = [
      headers: [{"Authorization", "Bearer #{get_api_key()}"}],
      json: params
    ]

    case apply(Req, method, [url, opts]) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}
      {:ok, %{body: %{"error" => error}}} ->
        {:error, error}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_api_key do
    Application.get_env(:backend, :your_api)[:api_key]
  end
end
```

## Testing API Integrations

### Unit Testing Your Code

Test the code that uses these modules by checking error handling:

```elixir
defmodule MyApp.PaymentServiceTest do
  use ExUnit.Case

  describe "when Stripe is not configured" do
    setup do
      # Ensure Stripe is not configured for this test
      original = Application.get_env(:backend, :stripe)
      Application.delete_env(:backend, :stripe)
      on_exit(fn -> 
        if original, do: Application.put_env(:backend, :stripe, original)
      end)
      :ok
    end

    test "handles missing configuration gracefully" do
      result = MyApp.PaymentService.create_payment("user_123", 1000)
      assert {:error, :payment_not_configured} = result
    end
  end
end
```

### Integration Testing

For integration tests with real APIs, use test/sandbox environments:

```elixir
# config/test.exs
config :backend, :stripe, api_key: System.get_env("STRIPE_TEST_KEY")
config :backend, :checkr, 
  api_key: System.get_env("CHECKR_TEST_KEY"),
  environment: "sandbox"
```

Run integration tests separately:

```bash
STRIPE_TEST_KEY=sk_test_xxx mix test test/integration/ --include integration
```

### Webhook Testing

Use tools like [Stripe CLI](https://stripe.com/docs/stripe-cli) for local webhook testing:

```bash
stripe listen --forward-to localhost:4000/webhooks/stripe
```

## Error Handling

All modules return consistent error tuples:

```elixir
case Backend.Stripe.create_customer(params) do
  {:ok, customer} ->
    # Success
    customer["id"]

  {:error, :api_key_not_configured} ->
    # API key not set
    Logger.error("Stripe not configured")

  {:error, %{"type" => "card_error", "message" => message}} ->
    # Stripe API error
    Logger.warning("Card error: #{message}")

  {:error, %Req.TransportError{reason: reason}} ->
    # Network error
    Logger.error("Network error: #{inspect(reason)}")

  {:error, {:unexpected_status, status, body}} ->
    # Unexpected HTTP status
    Logger.error("Unexpected response: #{status}")
end
```

### Common Error Types

| Error | Description |
|-------|-------------|
| `:api_key_not_configured` | API key environment variable not set |
| `%{"type" => "...", "message" => "..."}` | API-specific error (Stripe, Checkr) |
| `{:api_error, status}` | Google Maps API error status |
| `%Req.TransportError{}` | Network/connection error |
| `{:unexpected_status, status, body}` | Unexpected HTTP response |

## Security Best Practices

### API Key Storage

**Development:**
```bash
# .env file (add to .gitignore)
export STRIPE_API_KEY="sk_test_..."
export CHECKR_API_KEY="..."
export GOOGLE_MAPS_API_KEY="..."
```

**Production:**
Store in AWS Secrets Manager and reference via Terraform:
```hcl
stripe_api_key_secret_arn = "arn:aws:secretsmanager:..."
```

### Webhook Security

Always verify webhook signatures:

```elixir
# DON'T do this - vulnerable to spoofing
def webhook(conn, params) do
  handle_event(params)  # WRONG!
end

# DO this - verify signature first
def webhook(conn, _params) do
  payload = conn.assigns.raw_body
  signature = get_req_header(conn, "stripe-signature") |> List.first()
  
  case Backend.Stripe.verify_webhook_signature(payload, signature, secret) do
    {:ok, event} -> handle_event(event)  # CORRECT!
    {:error, _} -> send_resp(conn, 400, "Invalid")
  end
end
```

### Rate Limiting

Implement rate limiting for API calls:

```elixir
# Consider using a library like Hammer for rate limiting
def create_payment(user_id, amount) do
  case Hammer.check_rate("stripe:#{user_id}", 60_000, 10) do
    {:allow, _count} ->
      Backend.Stripe.create_payment_intent(%{amount: amount, currency: "usd"})
    {:deny, _limit} ->
      {:error, :rate_limited}
  end
end
```

### Logging

The modules log errors automatically, but avoid logging sensitive data:

```elixir
# DON'T log full API responses (may contain PII)
Logger.info("Customer created: #{inspect(customer)}")

# DO log only necessary identifiers
Logger.info("Customer created: #{customer["id"]}")
```
