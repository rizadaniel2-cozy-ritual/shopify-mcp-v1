#!/usr/bin/env bash
set -e

REPO_URL="https://github.com/rizadaniel2-cozy-ritual/shopify-mcp-v1"
BRANCH="claude/shopify-ai-toolkit-plugin-1GKQU"
DIR="shopify-mcp-v1"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Shopify MCP — Local Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Clone ──────────────────────────────────
if [ -d "$DIR" ]; then
  echo "→ Directory '$DIR' already exists, pulling latest..."
  git -C "$DIR" fetch origin "$BRANCH"
  git -C "$DIR" checkout "$BRANCH"
  git -C "$DIR" pull origin "$BRANCH"
else
  echo "→ Cloning repo..."
  git clone --branch "$BRANCH" "$REPO_URL" "$DIR"
fi
cd "$DIR"

# ── 2. Python check ───────────────────────────
echo "→ Checking Python version..."
PYTHON=$(command -v python3 || command -v python)
if [ -z "$PYTHON" ]; then
  echo "✗ Python 3.11+ is required but not found. Install it from https://python.org and re-run this script."
  exit 1
fi
PY_VER=$($PYTHON -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "  Found Python $PY_VER"

# ── 3. Virtual environment ────────────────────
if [ ! -d ".venv" ]; then
  echo "→ Creating virtual environment..."
  $PYTHON -m venv .venv
fi
source .venv/bin/activate

# ── 4. Dependencies ───────────────────────────
echo "→ Installing dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# ── 5. Credentials ────────────────────────────
if [ -f ".env" ] && grep -q "^SHOPIFY_STORE=" .env && ! grep -q "your-store-name" .env; then
  echo "→ .env already configured, skipping credential prompts."
else
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Shopify Credentials"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Store name: the part before .myshopify.com"
  echo "  e.g. if your URL is my-store.myshopify.com → enter: my-store"
  echo ""
  read -r -p "  Store name: " STORE_NAME
  echo ""
  echo "  Access token: from Shopify Admin → Settings → Apps → Develop apps"
  echo "  (should start with shpat_ or atkn_)"
  echo ""
  read -r -p "  Access token: " ACCESS_TOKEN
  echo ""

  cat > .env <<EOF
# Shopify MCP Server credentials — never commit this file
SHOPIFY_STORE=$STORE_NAME
SHOPIFY_ACCESS_TOKEN=$ACCESS_TOKEN

# Optional — only needed for OAuth apps
SHOPIFY_CLIENT_ID=
SHOPIFY_CLIENT_SECRET=

# Optional — defaults shown
SHOPIFY_API_VERSION=2024-10
PORT=8000
EOF
  echo "→ Credentials saved to .env"
fi

# ── 6. Connection test ────────────────────────
echo "→ Testing Shopify connection..."
set -a && source .env && set +a

TEST_RESULT=$($PYTHON - <<'PYEOF'
import asyncio, httpx, os, sys

async def test():
    store = os.environ.get("SHOPIFY_STORE", "")
    token = os.environ.get("SHOPIFY_ACCESS_TOKEN", "")
    if not store or not token:
        print("ERROR: missing credentials in .env")
        sys.exit(1)
    url = f"https://{store}.myshopify.com/admin/api/2024-10/shop.json"
    async with httpx.AsyncClient() as c:
        r = await c.get(url, headers={"X-Shopify-Access-Token": token}, timeout=10)
        if r.status_code == 200:
            shop = r.json().get("shop", {})
            print(f"OK|{shop.get('name')}|{shop.get('domain')}|{shop.get('plan_name')}")
        else:
            print(f"ERROR|{r.status_code}|{r.text[:200]}")

asyncio.run(test())
PYEOF
)

if echo "$TEST_RESULT" | grep -q "^OK|"; then
  IFS='|' read -r _ NAME DOMAIN PLAN <<< "$TEST_RESULT"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✓ Connected to your Shopify store!"
  echo ""
  echo "    Store : $NAME"
  echo "    Domain: $DOMAIN"
  echo "    Plan  : $PLAN"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
  IFS='|' read -r _ CODE MSG <<< "$TEST_RESULT"
  echo ""
  echo "  ✗ Connection failed (HTTP $CODE): $MSG"
  echo "  Check your credentials in .env and re-run."
  echo ""
  exit 1
fi

# ── 7. Update .claude/settings.json with venv path ───
VENV_PYTHON="$(pwd)/.venv/bin/python3"
SCRIPT_PATH="$(pwd)/server.py"
ENV_PATH="$(pwd)/.env"

mkdir -p .claude
cat > .claude/settings.json <<EOF
{
  "mcpServers": {
    "shopify": {
      "command": "bash",
      "args": [
        "-c",
        "set -a && source $ENV_PATH && set +a && $VENV_PYTHON $SCRIPT_PATH"
      ],
      "env": {
        "MCP_TRANSPORT": "stdio"
      }
    }
  }
}
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Setup complete!"
echo ""
echo "  To connect Claude to your store:"
echo ""
echo "    cd $(pwd)"
echo "    claude"
echo ""
echo "  Claude will auto-connect to your Shopify"
echo "  store when you open this project."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
