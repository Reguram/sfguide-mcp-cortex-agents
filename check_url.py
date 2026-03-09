import httpx, os
from dotenv import load_dotenv, find_dotenv
load_dotenv(find_dotenv())

PAT = os.getenv("SNOWFLAKE_PAT")
HEADERS = {
    "Authorization": f"Bearer {PAT}",
    "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
    "Content-Type": "application/json",
}
BODY = {"statement": "SELECT CURRENT_ACCOUNT(), CURRENT_USER()", "timeout": 10}

urls = [
    "https://htixmei-fwa17661.snowflakecomputing.com",
    "https://fwa17661.east-us-2.azure.snowflakecomputing.com",
    "https://htixmei-fwa17661.east-us-2.azure.snowflakecomputing.com",
]

for base in urls:
    try:
        r = httpx.post(f"{base}/api/v2/statements", json=BODY, headers=HEADERS, timeout=10)
        print(f"\n{base}  ->  HTTP {r.status_code}")
        if r.status_code == 200:
            print("  SUCCESS:", r.json())
        elif r.status_code != 404:
            print("  BODY:", r.text[:400])
        else:
            print("  404 Not Found")
    except Exception as e:
        print(f"\n{base}  ->  ERROR: {e}")
