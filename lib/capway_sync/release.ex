defmodule CapwaySync.Release do
  @moduledoc """
  Release management module for CapwaySync application.

  This module provides functions for production release startup tasks.
  IMPORTANT: This application is READ-ONLY for Trinity data and should never run migrations.
  """

  @app :capway_sync

  require Logger

  @doc """
  Starts the application for production release.

  This function performs startup tasks but explicitly DOES NOT run migrations
  as this application is read-only for Trinity data.
  """
  def start() do
    Logger.info("🚀 Starting CapwaySync application...")

    # Load the application
    Application.load(@app)

    # Validate required environment variables
    validate_environment()

    # Ensure the repository is started (but do NOT run migrations)
    ensure_repo_started()

    Logger.info("✅ CapwaySync application started successfully (read-only mode)")
  end

  @doc """
  Validates that all required environment variables are set.
  """
  def validate_environment() do
    Logger.info("🔍 Validating environment variables...")

    required_envs = [
      "DATABASE_URL",
      "SYNC_REPORTS_TABLE",
      "ACTION_ITEMS_TABLE",
      "AWS_REGION"
    ]

    Enum.each(required_envs, fn env ->
      case System.get_env(env) do
        nil ->
          Logger.error("❌ Required environment variable #{env} is not set")
          raise "Required environment variable #{env} is not set"
        value ->
          Logger.info("✅ #{env} is configured")
          # Don't log sensitive values like DATABASE_URL
          if env in ["DATABASE_URL"], do: nil, else: Logger.debug("   Value: #{value}")
      end
    end)

    Logger.info("✅ All required environment variables are set")
  end

  @doc """
  Ensures the repository is started and connected.

  IMPORTANT: This function explicitly DOES NOT run migrations.
  The Trinity database is read-only for this application.
  """
  def ensure_repo_started() do
    Logger.info("🔌 Ensuring Trinity repository connection...")

    # Start the repository
    case CapwaySync.TrinityRepo.start_link() do
      {:ok, _pid} ->
        Logger.info("✅ Trinity repository started successfully")

        # Test the connection with a simple query
        test_database_connection()

      {:error, {:already_started, _pid}} ->
        Logger.info("✅ Trinity repository already started")
        test_database_connection()

      {:error, reason} ->
        Logger.error("❌ Failed to start Trinity repository: #{inspect(reason)}")
        raise "Failed to start Trinity repository: #{inspect(reason)}"
    end
  end

  @doc """
  Tests the database connection to ensure it's working.
  This is safe as it only performs a read operation.
  """
  def test_database_connection() do
    Logger.info("🔍 Testing Trinity database connection...")

    try do
      # Simple read-only query to test connection
      case CapwaySync.TrinityRepo.query("SELECT 1 as test", []) do
        {:ok, %{rows: [[1]]}} ->
          Logger.info("✅ Trinity database connection successful")

        {:error, reason} ->
          Logger.error("❌ Trinity database connection test failed: #{inspect(reason)}")
          raise "Trinity database connection test failed: #{inspect(reason)}"
      end
    rescue
      error ->
        Logger.error("❌ Trinity database connection error: #{inspect(error)}")
        raise "Trinity database connection error: #{inspect(error)}"
    end
  end

  @doc """
  Explicitly disabled migration function.

  This function exists to make it clear that migrations are intentionally disabled.
  The Trinity database is read-only for this application.
  """
  def migrate() do
    Logger.warn("⚠️  Migration attempt detected!")
    Logger.warn("⚠️  Migrations are DISABLED for CapwaySync application")
    Logger.warn("⚠️  Trinity database is READ-ONLY for this application")
    Logger.warn("⚠️  If you need to modify the Trinity schema, do it directly on the Trinity application")

    raise """
    Migrations are explicitly disabled for CapwaySync application.

    This application is READ-ONLY for Trinity data and should never modify the database schema.
    If you need to make schema changes, please do so in the Trinity application itself.
    """
  end

  @doc """
  Health check function for production monitoring.
  """
  def health_check() do
    Logger.info("🏥 Performing health check...")

    checks = [
      {"Environment variables", &validate_environment/0},
      {"Database connection", &test_database_connection/0}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        try do
          check_fn.()
          {name, :ok}
        rescue
          error ->
            Logger.error("❌ Health check failed for #{name}: #{inspect(error)}")
            {name, {:error, error}}
        end
      end)

    failed_checks = Enum.filter(results, fn {_name, result} -> result != :ok end)

    if Enum.empty?(failed_checks) do
      Logger.info("✅ All health checks passed")
      :ok
    else
      Logger.error("❌ Health check failures: #{inspect(failed_checks)}")
      {:error, failed_checks}
    end
  end
end