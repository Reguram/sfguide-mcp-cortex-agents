"""
Quick test script to verify Cortex Search connectivity.
Run: python test_cortex_search.py
"""
import asyncio
import json
import httpx
from dotenv import load_dotenv, find_dotenv
import os

load_dotenv(find_dotenv())

SNOWFLAKE_ACCOUNT_URL = os.getenv("SNOWFLAKE_ACCOUNT_URL")
SNOWFLAKE_PAT = os.getenv("SNOWFLAKE_PAT")
CORTEX_SEARCH_SERVICE = os.getenv("CORTEX_SEARCH_SERVICE")  # ceo_demo_db.css_schema.css_pdf_search

API_HEADERS = {
    "Authorization": f"Bearer {SNOWFLAKE_PAT}",
    "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
    "Content-Type": "application/json",
}

# --------------------------------------------------------------------------
# The REST API endpoint for Cortex Search uses this URL pattern:
# /api/v2/databases/<db>/schemas/<schema>/cortex-search-services/<service>:query
# --------------------------------------------------------------------------
def build_search_url(service: str) -> str:
    """Convert 'db.schema.service' into the REST API path."""
    parts = service.split(".")
    if len(parts) != 3:
        raise ValueError(f"CORTEX_SEARCH_SERVICE must be in 'db.schema.service' format, got: {service}")
    db, schema, svc = parts
    return f"{SNOWFLAKE_ACCOUNT_URL}/api/v2/databases/{db}/schemas/{schema}/cortex-search-services/{svc}:query"


async def query_cortex_search(
    query: str,
    columns: list[str],
    limit: int = 5,
    filter_expr: dict | None = None,
) -> dict:
    """
    Query the Cortex Search service and return results.

    Args:
        query:       Natural language search query
        columns:     Column names to include in results
        limit:       Max number of results to return
        filter_expr: Optional filter, e.g. {"@eq": {"category": "support"}}
    """
    url = build_search_url(CORTEX_SEARCH_SERVICE)
    payload: dict = {"query": query, "columns": columns, "limit": limit}
    if filter_expr:
        payload["filter"] = filter_expr

    print(f"\nCalling: POST {url}")
    print(f"Payload: {json.dumps(payload, indent=2)}\n")

    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(url, json=payload, headers=API_HEADERS)

    print(f"HTTP Status: {resp.status_code}")

    if resp.status_code != 200:
        print(f"Error response:\n{resp.text}")
        resp.raise_for_status()

    return resp.json()


async def main():
    # -----------------------------------------------------------------------
    # STEP 1: Basic query
    # Service: CEO_DEMO_DB.CSS_SCHEMA.CSS_PDF_SEARCH
    # Columns: CONTENT (search column), FILE_NAME (attribute)
    # -----------------------------------------------------------------------
    results = await query_cortex_search(
        query="Who performed the inspection?",
        columns=["CONTENT", "FILE_NAME"],
        limit=3,
    )

    print("\n=== Results ===")
    for i, r in enumerate(results.get("results", []), 1):
        print(f"\n[{i}]")
        for k, v in r.items():
            # Truncate long text for readability
            val = str(v)[:300] + "..." if len(str(v)) > 300 else str(v)
            print(f"  {k}: {val}")

    print(f"\nTotal results: {len(results.get('results', []))}")
    print(f"Request ID: {results.get('request_id')}")

    # -----------------------------------------------------------------------
    # STEP 2: Query with a filter on FILE_NAME (uncomment to use)
    # -----------------------------------------------------------------------
    # results_filtered = await query_cortex_search(
    #     query="annual revenue",
    #     columns=["CONTENT", "FILE_NAME"],
    #     limit=3,
    #     filter_expr={"@eq": {"FILE_NAME": "annual_report_2024.pdf"}},
    # )
    # print("\n=== Filtered Results ===")
    # for r in results_filtered.get("results", []):
    #     print(r)


if __name__ == "__main__":
    asyncio.run(main())
