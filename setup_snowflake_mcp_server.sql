-- =============================================================================
-- Snowflake MCP Server Setup for Cortex Search Services
-- =============================================================================
-- This script creates:
--   1. Cortex Search services on your data
--   2. A Snowflake-native MCP server exposing those search services
--
-- Prerequisites:
--   - Run the table/data setup from mcp.txt first
--   - CORTEX_USER role or ACCOUNTADMIN
--   - Cross-region inference enabled:
--       ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'any_region';
-- =============================================================================

USE DATABASE DASH_MCP_DB;
USE SCHEMA DATA;
USE WAREHOUSE DASH_WH_S;

-- =============================================================================
-- STEP 1: Create Cortex Search Services
-- =============================================================================
-- These services enable vector + keyword hybrid search over your data.
-- Each service indexes a "search column" and exposes optional attribute columns.

-- -----------------------------------------------------------------------------
-- 1a. Support Tickets Search Service
--     Enables natural language search over support ticket subjects/descriptions
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.SUPPORT_TICKETS
  ON description
  ATTRIBUTES category, subcategory, priority, status, channel
  WAREHOUSE = DASH_WH_S
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      ticket_id,
      customer_id,
      description,
      subject,
      category,
      subcategory,
      priority,
      status,
      channel,
      created_date,
      satisfaction_score
    FROM DASH_MCP_DB.DATA.FACT_SUPPORT_TICKETS
  );

-- -----------------------------------------------------------------------------
-- 1b. Customer Search Service
--     Enables search over customer profile information
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.CUSTOMER_SEARCH
  ON address
  ATTRIBUTES city, state, region, customer_segment, risk_profile, status
  WAREHOUSE = DASH_WH_S
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      customer_id,
      first_name,
      last_name,
      email,
      address,
      city,
      state,
      zip_code,
      region,
      customer_segment,
      credit_score,
      annual_income,
      risk_profile,
      status,
      join_date
    FROM DASH_MCP_DB.DATA.DIM_CUSTOMERS
  );

-- -----------------------------------------------------------------------------
-- 1c. Transactions Search Service
--     Enables search over transaction descriptions and merchant info
-- -----------------------------------------------------------------------------
CREATE OR REPLACE CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.TRANSACTION_SEARCH
  ON description
  ATTRIBUTES merchant_category, transaction_type, channel
  WAREHOUSE = DASH_WH_S
  TARGET_LAG = '1 hour'
  AS (
    SELECT
      transaction_id,
      customer_id,
      account_id,
      transaction_date,
      transaction_type,
      amount,
      merchant_name,
      merchant_category,
      channel,
      location,
      description,
      is_flagged,
      fraud_score
    FROM DASH_MCP_DB.DATA.FACT_TRANSACTIONS
  );

-- =============================================================================
-- STEP 2: Verify Cortex Search Services are running
-- =============================================================================
SHOW CORTEX SEARCH SERVICES IN SCHEMA DASH_MCP_DB.DATA;

-- =============================================================================
-- STEP 3: Create the Snowflake MCP Server
-- =============================================================================
-- This MCP server exposes your Cortex Search services, Cortex Analyst
-- semantic model, SQL execution, and a custom email tool to any MCP client
-- (e.g., Claude Desktop, VS Code Copilot, custom agents).

CREATE OR REPLACE MCP SERVER DASH_MCP_DB.DATA.DASH_MCP_SERVER FROM SPECIFICATION
$$
tools:
  - name: "Support_Tickets_Search"
    identifier: "DASH_MCP_DB.DATA.SUPPORT_TICKETS"
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    description: >
      Search over customer support tickets using natural language.
      Performs hybrid keyword and vector search over ticket descriptions.
      Use this to find tickets by topic, issue type, or customer complaint details.
      Returns ticket details including category, priority, status, and satisfaction scores.
    title: "Support Tickets Search"

  - name: "Customer_Profile_Search"
    identifier: "DASH_MCP_DB.DATA.CUSTOMER_SEARCH"
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    description: >
      Search over customer profiles using natural language.
      Performs hybrid keyword and vector search over customer addresses and attributes.
      Use this to find customers by location, segment, risk profile, or other attributes.
    title: "Customer Profile Search"

  - name: "Transaction_Search"
    identifier: "DASH_MCP_DB.DATA.TRANSACTION_SEARCH"
    type: "CORTEX_SEARCH_SERVICE_QUERY"
    description: >
      Search over financial transactions using natural language.
      Performs hybrid keyword and vector search over transaction descriptions.
      Use this to find transactions by merchant, type, description, or flagged activity.
    title: "Transaction Search"

  - name: "Financial_Analytics_Semantic_Model"
    identifier: "DASH_MCP_DB.DATA.FINANCIAL_SERVICES_ANALYTICS"
    type: "CORTEX_ANALYST_MESSAGE"
    description: >
      Comprehensive semantic model for financial services analytics.
      Translates natural language questions into SQL using Cortex Analyst.
      Covers customer data, transactions, marketing campaigns, support 
      interactions, and risk assessments with full business context.
    title: "Financial Analytics"

  - name: "SQL_Execution"
    type: "SYSTEM_EXECUTE_SQL"
    description: >
      Execute SQL queries against the Snowflake database.
      Use this to run ad-hoc queries, aggregate data, or perform 
      follow-up analysis on results from other tools.
    title: "SQL Execution"

  - name: "Send_Email"
    identifier: "DASH_MCP_DB.DATA.SEND_EMAIL"
    type: "GENERIC"
    description: >
      Send an email to a verified email address. 
      Supports HTML content for rich formatting.
    title: "Send Email"
    config:
      type: "procedure"
      warehouse: "DASH_WH_S"
      input_schema:
        type: "object"
        properties:
          body:
            description: >
              Use HTML syntax for the email body. If the content is in markdown,
              translate it to HTML. If body is not provided, summarize the last 
              question and use that as content for the email.
            type: "string"
          recipient_email:
            description: >
              The recipient's email address. If not provided, send it to 
              the current user's email address.
            type: "string"
          subject:
            description: >
              The email subject line. If not provided, 
              use 'Snowflake Intelligence' as default.
            type: "string"
$$;

-- =============================================================================
-- STEP 4: Verify MCP Server
-- =============================================================================
SHOW MCP SERVERS IN SCHEMA DASH_MCP_DB.DATA;

-- =============================================================================
-- STEP 5: Grant access (adjust role names as needed)
-- =============================================================================
-- Grant usage on the MCP server to specific roles so they can connect.
-- Uncomment and modify these as needed:

-- GRANT USAGE ON MCP SERVER DASH_MCP_DB.DATA.DASH_MCP_SERVER TO ROLE <your_role>;
-- GRANT USAGE ON CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.SUPPORT_TICKETS TO ROLE <your_role>;
-- GRANT USAGE ON CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.CUSTOMER_SEARCH TO ROLE <your_role>;
-- GRANT USAGE ON CORTEX SEARCH SERVICE DASH_MCP_DB.DATA.TRANSACTION_SEARCH TO ROLE <your_role>;

SELECT 'MCP Server setup complete! Your search services are now exposed via the MCP protocol.' AS STATUS;
