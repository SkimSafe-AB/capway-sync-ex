# CapwaySync Elixir Application

## Project Overview

`CapwaySync` is an Elixir-based application designed to synchronize subscriber data between a primary system called "Trinity" and a secondary system, "Capway". The application's core responsibilities include:

-   **Data Synchronization:** Comparing subscriber data between Trinity and Capway to identify discrepancies.
-   **Account Status Management:** Determining which accounts should be suspended or unsuspended based on predefined business logic (e.g., number of collections, unpaid invoices).
-   **Reporting:** Generating detailed synchronization reports (`GeneralSyncReport`) that provide a comprehensive overview of the sync process.
-   **Action Item Generation:** Creating individual `ActionItem` records in DynamoDB for each necessary action (e.g., "suspend", "unsuspend", "sync_to_capway").

This application is built with a robust set of technologies, including:

-   **Backend:** Elixir
-   **Workflow Management:** `Reactor` library
-   **System Integration:**
    -   `SOAP` for communication with the Capway system.
    -   `Ecto` for database interactions with the Trinity system (likely PostgreSQL).
-   **Cloud Services:**
    -   `ExAws` for integration with AWS services, specifically DynamoDB for storing sync reports and action items, and AWS STS.
-   **Data Handling:**
    -   `Jason` for JSON processing.
    -   `Cloak` for data encryption.
-   **HTTP Communication:** `Req` for making HTTP requests.
-   **Time and Date Management:** `Timex`

The architecture is modular, with clear separation of concerns for interacting with different systems and services. It appears to be event-driven, using a workflow engine to orchestrate the synchronization process.

### Application Structure

-   **Main Application:** `CapwaySync.Application` - The OTP application with its supervisor.
-   **SOAP Module:** `CapwaySync.Soap.GenerateReport` - Handles interactions with the SOAP web service.
-   **Configuration:** `config/config.exs` - Contains global settings, including the SOAP WSDL URL.

### Architecture Details

#### Dependencies

-   `reactor` (~> 0.16.0): Provides a pattern for composable, resumable, and introspectable workflows.
-   `soap` (~> 1.0): The SOAP client library for Elixir.

#### SOAP Integration

The application connects to a SOAP service for reporting. Key aspects include:

-   **WSDL URL:** Configured via the `SOAP_REPORT_WSDL` environment variable.
-   **Authentication:** Uses `SOAP_USERNAME` and `SOAP_PASSWORD` environment variables for basic authentication.
-   **HTTP Client:** Utilizes HTTPoison, with options for insecure SSL during development.
-   **Operations:** SOAP operations are available through `CapwaySync.Soap.GenerateReport.operations/0`.
-   **Configuration:** Global SOAP version is set to "1.2" in the configuration.

#### AWS/DynamoDB Integration

The application stores `GeneralSyncReport` data in AWS DynamoDB and manages action items.

-   **Sync Reports Table:** Configured via the `SYNC_REPORTS_TABLE` environment variable (default: "capway-sync-reports").
-   **Action Items Table:** Configured via the `ACTION_ITEMS_TABLE` environment variable (default: "capway-sync-action-items").
-   **AWS Credentials:** Requires `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION` environment variables.
-   **Local Development:** Supports LocalStack for local DynamoDB development using `USE_LOCALSTACK=true`.
-   **Further Details:** A comprehensive setup guide is available in `docs/AWS_CONFIGURATION.md`.

**Required Environment Variables for Production:**

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
export SYNC_REPORTS_TABLE="capway-sync-reports-prod"
export SOAP_REPORT_WSDL="https://api.capway.com/Service.svc?wsdl"
export SOAP_USERNAME="your-soap-username"
export SOAP_PASSWORD="your-soap-password"
```

### Key Files

-   `lib/capway_sync/soap/generate_report.ex`: Contains the SOAP client implementation.
-   `priv/`: This directory holds various XML/WSDL files (e.g., `1.xml` through `5.xml`) and mock responses.

## Testing

-   **Framework:** The project uses the ExUnit testing framework.
-   **Execution:** Always run `mix test` after making changes to ensure code integrity and functionality.
-   **Coverage:** It is crucial that tests cover 100% of the application's functionality to prevent errors during execution.
-   **DynamoDB Integration Tests:** These tests utilize LocalStack for local DynamoDB emulation. Configuration for LocalStack can be managed via `DYNAMODB_TEST_HOST` and `DYNAMODB_TEST_PORT` environment variables.
-   **Validation:** Ensure all tests are valid and pass before considering changes complete.
