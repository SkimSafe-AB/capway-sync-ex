# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-   Personal number details to the synchronization process.

## [0.1.0] - 2025-10-06

### Added
-   Initial version of the `CapwaySync` application.
-   Core synchronization logic between Trinity and Capway.
-   Functionality to suspend and unsuspend accounts.
-   Generation of synchronization reports.
-   Creation of action items in DynamoDB.
-   Testing suite with ExUnit.
-   CI/CD pipeline with GitHub Actions.
-   Support for production and mock development environments.
-   Functionality to cancel contracts.
-   Concurrent execution of synchronization steps.
-   SOAP integration for communication with Capway.
-   Ecto integration for communication with Trinity.
-   Basic application supervision.
