# NutriScan FastAPI Proxy

This service accepts the NutriScan app request format and forwards image analysis to Google Gemini, OpenAI, Anthropic/Claude, DeepSeek, or Grok-compatible APIs.

## 1. Create a virtual environment

```bash
cd Backend/fastapi_service
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2. Configure environment variables

```bash
cp .env.example .env
```

Set:

- `AI_PROVIDER`: `google`, `gemini`, `openai`, `anthropic`, `claude`, `deepseek`, or `grok`
- `GOOGLE_API_KEY`: your server-side Google AI Studio Gemini API key
- `GOOGLE_MODEL`: default is `gemini-2.0-flash`; use `gemini-2.5-flash` when available
- `GOOGLE_BASE_URL`: default is `https://generativelanguage.googleapis.com`
- `GOOGLE_MAX_OUTPUT_TOKENS`: default is `2000`
- `GOOGLE_THINKING_BUDGET`: default is `0` for concise JSON responses
- `OPENAI_API_KEY`: your server-side OpenAI API key
- `OPENAI_BASE_URL`: optional OpenAI-compatible proxy base URL, such as `https://dm-fox.rjj.cc/codex/v1`
- `NUTRISCAN_CLIENT_TOKEN`: the bearer token used by your iOS app
- `OPENAI_MODEL`: default is `gpt-4.1-mini`
- `ANTHROPIC_AUTH_TOKEN`: your server-side Anthropic or Claude-compatible proxy key
- `ANTHROPIC_BASE_URL`: default is `https://api.anthropic.com`; for the Ultra channel use `https://code.newcli.com/claude/ultra`
- `ANTHROPIC_MODEL`: default is `claude-sonnet-4-5`
- `DEEPSEEK_API_KEY`: your server-side DeepSeek API key
- `DEEPSEEK_MODEL`: default is `deepseek-v4-flash`
- `DEEPSEEK_BASE_URL`: default is `https://api.deepseek.com`
- `GROK_API_KEY`: your server-side xAI API key
- `GROK_MODEL`: default is `grok-2`
- `GROK_BASE_URL`: default is `https://api.x.ai/v1`
- `MAX_IMAGE_BYTES`: max allowed request image size
- `AI_REQUEST_TIMEOUT_SECONDS`: max time to wait for the model provider before returning `504`

## 3. Start the server

```bash
export $(grep -v '^#' .env | xargs)
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

## Production deployment

Deploy this backend as a public HTTPS web service. Do not use your local Mac IP for production.

Required production environment variables:

```bash
AI_PROVIDER=google
GOOGLE_API_KEY=your_google_ai_studio_key
GOOGLE_MODEL=gemini-2.5-flash
GOOGLE_BASE_URL=https://generativelanguage.googleapis.com
GOOGLE_MAX_OUTPUT_TOKENS=2000
GOOGLE_THINKING_BUDGET=0
DEEPSEEK_API_KEY=your_deepseek_key
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_COACH_MODEL=deepseek-v4-flash
NUTRISCAN_CLIENT_TOKEN=use_a_long_random_server_token
MAX_IMAGE_BYTES=6291456
AI_REQUEST_TIMEOUT_SECONDS=30
```

The included `Dockerfile` starts the service with:

```bash
uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}
```

For Render, use `render.yaml` from this folder and set the secret values for `GOOGLE_API_KEY` and `NUTRISCAN_CLIENT_TOKEN` in the Render dashboard.

After deployment, update the iOS app endpoint to:

```swift
static let foodAnalysisEndpoint = "https://your-backend-domain.example/food/analyze"
static let clientToken = "the_same_long_random_server_token"
```

## 4. iOS app configuration

The iOS app should not ask users to enter an endpoint or API key.

Configure your backend URL and client bearer token inside the app build configuration. The app sends meal photos only to your NutriScan backend, and the backend owns all provider API keys.

For local development, point the app's internal backend endpoint to:

```text
http://<your-ip>:8000/food/analyze
```

Set the app's internal client token to the same value as `NUTRISCAN_CLIENT_TOKEN`.

## 5. Test request

```bash
curl -X POST http://127.0.0.1:8000/food/analyze \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer nutriscan-local-token" \
  -d '{
    "imageBase64": "BASE64_IMAGE_HERE",
    "locale": "zh_CN",
    "source": "NutriScan-iOS"
  }'
```

## Notes

- Do not put `OPENAI_API_KEY` into the iOS app.
- Do not put `OPENAI_BASE_URL` into the iOS app.
- Do not put `GOOGLE_API_KEY` into the iOS app.
- Do not put `ANTHROPIC_AUTH_TOKEN` into the iOS app.
- Do not put `ANTHROPIC_BASE_URL` into the iOS app.
- Do not put `DEEPSEEK_API_KEY` into the iOS app.
- Do not put `GROK_API_KEY` into the iOS app.
- This sample uses synchronous request handling for simplicity.
- If the provider returns non-JSON text, the server returns HTTP `500`.
- Use a model/provider endpoint that supports image input. A text-only model may pass `/health` and simple text tests but time out on `/food/analyze`.
- For production, add rate limiting, structured logging, and image compression.

## Use Google Gemini

For NutriScan food photo analysis, Gemini is the preferred image-capable option.

In `.env`:

```bash
AI_PROVIDER=google
GOOGLE_API_KEY=your_google_ai_studio_key
GOOGLE_MODEL=gemini-2.5-flash
GOOGLE_BASE_URL=https://generativelanguage.googleapis.com
GOOGLE_MAX_OUTPUT_TOKENS=2000
GOOGLE_THINKING_BUDGET=0
NUTRISCAN_CLIENT_TOKEN=nutriscan-local-token
AI_REQUEST_TIMEOUT_SECONDS=30
```

Then restart the service. The iOS app does not need any code change; it still sends photos only to your NutriScan backend.

## Premium nutrition coaching with DeepSeek

The food photo endpoint can use Gemini while the premium coaching endpoint uses DeepSeek text reasoning.

Endpoint:

```text
POST /coach/suggestions
Authorization: Bearer <NUTRISCAN_CLIENT_TOKEN>
```

Request body:

```json
{
  "locale": "zh-Hans",
  "profile": {
    "gender": "Female",
    "height": 165,
    "weight": 62,
    "goalWeight": 56,
    "activityLevel": "Lightly active",
    "weeklyLossRate": 0.5,
    "unit": "metric",
    "isPremium": true
  },
  "recentMeals": [
    {
      "mealType": "Lunch",
      "foodName": "Chicken rice bowl",
      "calories": 620,
      "protein": 32,
      "carbs": 72,
      "fat": 18,
      "notes": "",
      "createdAt": "2026-07-02T12:30:00Z"
    }
  ]
}
```

Response body:

```json
{
  "summary": "string",
  "nextGoal": "string",
  "cards": [
    {
      "title": "string",
      "subtitle": "string",
      "bullets": ["string"],
      "suggestedFoods": ["string"],
      "targetFocus": "protein",
      "priority": "high"
    }
  ]
}
```

Non-premium requests return `403 premium_required`.

## Switch to DeepSeek

For NutriScan food photo analysis, use DeepSeek's Anthropic-compatible endpoint so image messages are accepted.

In `.env`:

```bash
AI_PROVIDER=anthropic
ANTHROPIC_AUTH_TOKEN=your_deepseek_key
ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
ANTHROPIC_MODEL=deepseek-v4-flash
NUTRISCAN_CLIENT_TOKEN=nutriscan-local-token
```

Then restart the service. The iOS app does not need any code change.

DeepSeek's OpenAI-compatible `chat/completions` endpoint works for text, but rejects the `image_url` message format used by the food photo flow.

## Use fox OpenAI-compatible proxy

In `.env`:

```bash
AI_PROVIDER=openai
OPENAI_API_KEY=your_fox_api_key_here
OPENAI_BASE_URL=https://dm-fox.rjj.cc/codex/v1
OPENAI_MODEL=gpt-5.5
NUTRISCAN_CLIENT_TOKEN=nutriscan-local-token
```

Then restart the service. In the iOS app build configuration, keep the internal endpoint pointed at your own backend, for example `http://<your-ip>:8000/food/analyze`, and set the internal client token to the same value as `NUTRISCAN_CLIENT_TOKEN`.

## Use Claude/Ultra Anthropic-compatible proxy

In `.env`:

```bash
AI_PROVIDER=anthropic
ANTHROPIC_AUTH_TOKEN=your_proxy_key
ANTHROPIC_BASE_URL=https://code.newcli.com/claude/ultra
ANTHROPIC_MODEL=claude-sonnet-4-5
NUTRISCAN_CLIENT_TOKEN=nutriscan-local-token
```

Then restart the service. The iOS app still talks only to your NutriScan backend; end users do not install Claude CLI and do not enter provider keys.

## Switch to Grok

In `.env`:

```bash
AI_PROVIDER=grok
GROK_API_KEY=your_xai_key
GROK_MODEL=grok-2
GROK_BASE_URL=https://api.x.ai/v1
```

Then restart the service. The iOS app does not need any code change.
