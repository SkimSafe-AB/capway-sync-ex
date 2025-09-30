# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CapwaySync is an Elixir application that integrates with SOAP web services for report generation. The application uses the Reactor pattern and includes SOAP client functionality to interact with external reporting services.

## Key Commands

### Development
- `mix deps.get` - Install dependencies
- `mix compile` - Compile the project
- `mix test` - Run all tests (always run after making changes)
- `iex -S mix` - Start interactive shell with application loaded

### Application Structure
- Main application: `CapwaySync.Application` - OTP application with supervisor
- SOAP module: `CapwaySync.Soap.GenerateReport` - Handles SOAP service interactions
- Configuration: `config/config.exs` - Contains SOAP WSDL URL and global settings

## Architecture

### Dependencies
- `reactor` (~> 0.16.0) - Pattern for composable, resumable, and introspectable workflows
- `soap` (~> 1.0) - SOAP client library for Elixir

### SOAP Integration
The application connects to a SOAP service for reporting:
- WSDL URL configured via `SOAP_REPORT_WSDL` environment variable
- Authentication via `SOAP_USERNAME` and `SOAP_PASSWORD` environment variables
- Uses HTTPoison with insecure SSL options for development
- SOAP operations available through `CapwaySync.Soap.GenerateReport.operations/0`

### Key Files
- `lib/capway_sync/soap/generate_report.ex` - SOAP client implementation
- `priv/` directory contains XML/WSDL files (1.xml through 5.xml)
- Configuration uses Elixir 1.18+ and OTP application pattern

## SOAP Configuration
- Global SOAP version set to "1.2" in config
- WSDL URL defaults to "https://api.capway.com/Service.svc?wsdl"
- Basic authentication configured for secure endpoints
- HTTPoison configured with hackney insecure option for development

## AWS/DynamoDB Integration
The application stores GeneralSyncReport data in AWS DynamoDB:
- Table name configured via `SYNC_REPORTS_TABLE` environment variable (default: "capway-sync-reports")
- AWS credentials via `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_REGION`
- LocalStack support for local development with `USE_LOCALSTACK=true`
- See `docs/AWS_CONFIGURATION.md` for comprehensive setup guide

### Required Environment Variables for Production
```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
export SYNC_REPORTS_TABLE="capway-sync-reports-prod"
```

## Testing
- Uses ExUnit framework
- Always run `mix test` after making changes per project requirements
- Ensure FLOP commands work correctly (crucial for the application)
- DynamoDB integration tests use LocalStack (configure with DYNAMODB_TEST_HOST/PORT)