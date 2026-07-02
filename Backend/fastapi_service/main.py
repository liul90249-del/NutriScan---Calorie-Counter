import base64
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
import json
import os
import urllib.error
import urllib.request
from typing import Any, Optional, Tuple

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from openai import APITimeoutError, OpenAI


app = FastAPI(title="NutriScan Food Recognition Proxy")

provider = os.environ.get("AI_PROVIDER", "openai").strip().lower()
client_bearer_token = os.environ["NUTRISCAN_CLIENT_TOKEN"]
max_image_bytes = int(os.environ.get("MAX_IMAGE_BYTES", str(6 * 1024 * 1024)))
ai_request_timeout_seconds = float(os.environ.get("AI_REQUEST_TIMEOUT_SECONDS", "18"))


def build_client() -> Tuple[Optional[OpenAI], str]:
    if provider in {"google", "gemini"}:
        return None, os.environ.get("GOOGLE_MODEL", "gemini-2.5-flash")

    if provider in {"anthropic", "claude"}:
        return None, os.environ.get("ANTHROPIC_MODEL", "claude-sonnet-4-5")

    if provider == "grok":
        api_key = os.environ["GROK_API_KEY"]
        model_name = os.environ.get("GROK_MODEL", "grok-2")
        base_url = os.environ.get("GROK_BASE_URL", "https://api.x.ai/v1")
        return OpenAI(api_key=api_key, base_url=base_url), model_name

    if provider == "deepseek":
        api_key = os.environ["DEEPSEEK_API_KEY"]
        model_name = os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash")
        base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
        return OpenAI(api_key=api_key, base_url=base_url), model_name

    api_key = os.environ["OPENAI_API_KEY"]
    model_name = os.environ.get("OPENAI_MODEL", "gpt-4.1-mini")
    base_url = os.environ.get("OPENAI_BASE_URL", "").strip()
    if base_url:
        return OpenAI(api_key=api_key, base_url=base_url), model_name
    return OpenAI(api_key=api_key), model_name


client, model_name = build_client()


class AnalyzeRequest(BaseModel):
    imageBase64: str
    locale: str
    source: str


class AnalyzeResponse(BaseModel):
    foodName: str
    confidence: float = Field(ge=0.0, le=1.0)
    calories: int = Field(ge=0)
    protein: float = Field(ge=0)
    carbs: float = Field(ge=0)
    fat: float = Field(ge=0)
    highlights: list[str]
    needsReview: bool = True
    identifiedItems: list[str] = Field(default_factory=list)
    portionDescription: str = ""


def require_bearer_token(authorization: Optional[str]) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail={"error": "unauthorized", "message": "Missing bearer token."})

    token = authorization.removeprefix("Bearer ").strip()
    if token != client_bearer_token:
        raise HTTPException(status_code=401, detail={"error": "unauthorized", "message": "Invalid bearer token."})


def decode_image(image_base64: str) -> bytes:
    try:
        image_bytes = base64.b64decode(image_base64, validate=True)
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_image", "message": "imageBase64 is not valid base64."},
        ) from exc

    if not image_bytes:
        raise HTTPException(
            status_code=400,
            detail={"error": "invalid_image", "message": "Decoded image is empty."},
        )

    if len(image_bytes) > max_image_bytes:
        raise HTTPException(
            status_code=413,
            detail={"error": "image_too_large", "message": "Image exceeds server size limit."},
        )

    return image_bytes


def image_media_type(image_bytes: bytes) -> str:
    if image_bytes.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if image_bytes.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if image_bytes.startswith(b"GIF87a") or image_bytes.startswith(b"GIF89a"):
        return "image/gif"
    if len(image_bytes) >= 12 and image_bytes[4:8] == b"ftyp":
        brand = image_bytes[8:12]
        if brand in {b"avif", b"avis"}:
            return "image/avif"
        if brand in {b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1"}:
            return "image/heic"
    return "image/jpeg"


def build_prompt(locale: str) -> str:
    return f"""
You are a nutrition vision assistant.
Estimate the visible meal shown in the image and return strict JSON only.

Rules:
- Locale hint: {locale}
- Only identify food you can actually see with moderate confidence.
- Do not invent restaurant names, branded meal names, or hidden ingredients.
- If the dish is ambiguous, use a generic consumer-friendly name like "rice bowl", "noodle soup", or "mixed salad".
- Prefer useful generic food labels over "unknown" when any edible food is visible.
- Return nutrition totals only for the visible serving in the photo.
- You must return a usable nutrition estimate for normal food photos, even when portion size is uncertain.
- Do not return zero calories or zero macros unless there is clearly no food in the image.
- Protein, carbs, and fat are grams.
- Calories are integer kcal.
- Confidence is a number between 0 and 1.
- Set confidence conservatively:
  - 0.80 to 0.95 only when the dish and portion are visually clear
  - 0.55 to 0.79 when partly clear but ingredients or portion are uncertain
  - 0.20 to 0.54 when the result is a rough guess
- Set needsReview to true whenever ingredients, cooking method, or portion size are uncertain.
- identifiedItems must list 2 to 5 visible foods/components when food is visible; use generic names like "rice", "meat", "leafy greens", "sauce", or "noodles" when exact ingredients are uncertain.
- portionDescription must be a short phrase like "1 medium bowl", "1 plate", or "small side portion".
- portionDescription must not be empty when food is visible.
- highlights must contain 2 to 4 short strings focused on portion, notable macros, or what should be reviewed.
- Write foodName, highlights, identifiedItems, and portionDescription in the language implied by the locale hint.
- Never claim exactness. Never mention image recognition, AI, or model limitations.
- If the image is too unclear to judge but food is present, still provide the safest generic estimate, set a low confidence, and set needsReview to true.
- If there is no visible food, return foodName as "No visible food", calories 0, macros 0, low confidence, and needsReview true.
- Avoid "unknown", "unclear", or "not visible" unless there is truly no visible food in the image.

JSON schema:
{{
  "foodName": "string",
  "confidence": 0.0,
  "calories": 0,
  "protein": 0.0,
  "carbs": 0.0,
  "fat": 0.0,
  "highlights": ["string"],
  "needsReview": true,
  "identifiedItems": ["string"],
  "portionDescription": "string"
}}
""".strip()


def parse_model_json(raw_text: str) -> dict[str, Any]:
    cleaned = raw_text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        cleaned = cleaned.replace("json\n", "", 1).strip()

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Model did not return valid JSON."},
        ) from exc


def call_provider(image_bytes: bytes, locale: str) -> dict[str, Any]:
    if provider in {"google", "gemini"}:
        return call_google_provider(image_bytes, locale)

    if provider in {"anthropic", "claude"}:
        return call_anthropic_provider(image_bytes, locale)

    if client is None:
        raise HTTPException(
            status_code=500,
            detail={"error": "provider_not_configured", "message": "AI provider client is not configured."},
        )

    if provider == "deepseek":
        return call_deepseek_provider(image_bytes, locale)

    media_type = image_media_type(image_bytes)
    response = client.responses.create(
        model=model_name,
        input=[
            {
                "role": "user",
                "content": [
                    {"type": "input_text", "text": build_prompt(locale)},
                    {
                        "type": "input_image",
                        "image_url": f"data:{media_type};base64,{base64.b64encode(image_bytes).decode('utf-8')}",
                    },
                ],
            }
        ],
        timeout=ai_request_timeout_seconds,
    )

    return parse_model_json(response.output_text)


def google_generate_content_url() -> str:
    base_url = os.environ.get("GOOGLE_BASE_URL", "https://generativelanguage.googleapis.com").strip().rstrip("/")
    return f"{base_url}/v1beta/models/{model_name}:generateContent"


def call_google_provider(image_bytes: bytes, locale: str) -> dict[str, Any]:
    api_key = os.environ.get("GOOGLE_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail={"error": "provider_not_configured", "message": "GOOGLE_API_KEY is not configured."},
        )

    media_type = image_media_type(image_bytes)
    body = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": build_prompt(locale)},
                    {
                        "inline_data": {
                            "mime_type": media_type,
                            "data": base64.b64encode(image_bytes).decode("utf-8"),
                        }
                    },
                ],
            }
        ],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": int(os.environ.get("GOOGLE_MAX_OUTPUT_TOKENS", "2000")),
            "responseMimeType": "application/json",
            "thinkingConfig": {
                "thinkingBudget": int(os.environ.get("GOOGLE_THINKING_BUDGET", "0")),
            },
        },
    }

    request = urllib.request.Request(
        google_generate_content_url(),
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": api_key,
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=ai_request_timeout_seconds) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        message = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(
            status_code=502,
            detail={"error": "provider_error", "message": message[:1000]},
        ) from exc
    except TimeoutError as exc:
        raise HTTPException(
            status_code=504,
            detail={"error": "model_timeout", "message": "Google provider request timed out."},
        ) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=502,
            detail={"error": "provider_error", "message": str(exc.reason)[:1000]},
        ) from exc

    candidates = payload.get("candidates", [])
    parts = candidates[0].get("content", {}).get("parts", []) if candidates else []
    text_parts = [part.get("text", "") for part in parts if part.get("text")]
    if not text_parts:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Google response did not contain text content."},
        )
    return parse_model_json("\n".join(text_parts))


def call_deepseek_provider(image_bytes: bytes, locale: str) -> dict[str, Any]:
    if client is None:
        raise HTTPException(
            status_code=500,
            detail={"error": "provider_not_configured", "message": "DeepSeek client is not configured."},
        )

    media_type = image_media_type(image_bytes)
    try:
        response = client.chat.completions.create(
            model=model_name,
            messages=[
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": build_prompt(locale)},
                        {
                            "type": "image_url",
                            "image_url": {
                                "url": f"data:{media_type};base64,{base64.b64encode(image_bytes).decode('utf-8')}"
                            },
                        },
                    ],
                }
            ],
            response_format={"type": "json_object"},
            timeout=ai_request_timeout_seconds,
        )
    except APITimeoutError:
        raise
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail={"error": "provider_error", "message": str(exc)[:1000]},
        ) from exc

    content = response.choices[0].message.content if response.choices else ""
    return parse_model_json(content or "")


def anthropic_messages_url() -> str:
    base_url = os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com").strip().rstrip("/")
    if base_url.endswith("/v1"):
        return f"{base_url}/messages"
    return f"{base_url}/v1/messages"


def call_anthropic_provider(image_bytes: bytes, locale: str) -> dict[str, Any]:
    token = os.environ.get("ANTHROPIC_AUTH_TOKEN", "").strip()
    if not token:
        raise HTTPException(
            status_code=500,
            detail={"error": "provider_not_configured", "message": "ANTHROPIC_AUTH_TOKEN is not configured."},
        )

    media_type = image_media_type(image_bytes)
    body = {
        "model": model_name,
        "max_tokens": 700,
        "temperature": 0.1,
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": media_type,
                            "data": base64.b64encode(image_bytes).decode("utf-8"),
                        },
                    },
                    {"type": "text", "text": build_prompt(locale)},
                ],
            }
        ],
    }

    request = urllib.request.Request(
        anthropic_messages_url(),
        data=json.dumps(body).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "x-api-key": token,
            "Authorization": f"Bearer {token}",
            "anthropic-version": "2023-06-01",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=ai_request_timeout_seconds) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        message = exc.read().decode("utf-8", errors="replace")
        raise HTTPException(
            status_code=502,
            detail={"error": "provider_error", "message": message[:1000]},
        ) from exc
    except TimeoutError as exc:
        raise HTTPException(
            status_code=504,
            detail={"error": "model_timeout", "message": "Anthropic provider request timed out."},
        ) from exc
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=502,
            detail={"error": "provider_error", "message": str(exc.reason)[:1000]},
        ) from exc

    text_parts = [
        item.get("text", "")
        for item in payload.get("content", [])
        if item.get("type") == "text"
    ]
    if not text_parts:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Provider response did not contain text content."},
        )
    return parse_model_json("\n".join(text_parts))


def normalize_result(result: dict[str, Any]) -> dict[str, Any]:
    identified_items = result.get("identifiedItems")
    if not isinstance(identified_items, list):
        identified_items = []

    highlights = result.get("highlights")
    if not isinstance(highlights, list) or not highlights:
        highlights = ["Review portion size before saving.", "Nutrition values are estimated from the visible meal."]

    confidence = result.get("confidence", 0.0)
    try:
        confidence = float(confidence)
    except Exception:
        confidence = 0.0
    confidence = max(0.0, min(confidence, 1.0))

    normalized = {
        "foodName": str(result.get("foodName", "Estimated meal")).strip() or "Estimated meal",
        "confidence": confidence,
        "calories": int(max(float(result.get("calories", 0)), 0)),
        "protein": max(float(result.get("protein", 0)), 0.0),
        "carbs": max(float(result.get("carbs", 0)), 0.0),
        "fat": max(float(result.get("fat", 0)), 0.0),
        "highlights": [str(item).strip() for item in highlights if str(item).strip()][:4],
        "needsReview": bool(result.get("needsReview", confidence < 0.8)),
        "identifiedItems": [str(item).strip() for item in identified_items if str(item).strip()][:5],
        "portionDescription": str(result.get("portionDescription", "")).strip(),
    }

    if not normalized["highlights"]:
        normalized["highlights"] = [
            "Review portion size before saving.",
            "Nutrition values are estimated from the visible meal.",
        ]

    return normalized


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "provider": provider, "model": model_name}


@app.post("/food/analyze", response_model=AnalyzeResponse)
def analyze_food(
    payload: AnalyzeRequest,
    authorization: Optional[str] = Header(default=None),
) -> AnalyzeResponse:
    require_bearer_token(authorization)
    image_bytes = decode_image(payload.imageBase64)
    executor = ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(call_provider, image_bytes, payload.locale)
        result = normalize_result(future.result(timeout=ai_request_timeout_seconds))
    except (APITimeoutError, FutureTimeoutError) as exc:
        raise HTTPException(
            status_code=504,
            detail={"error": "model_timeout", "message": "Food analysis model timed out."},
        ) from exc
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    try:
        return AnalyzeResponse(**result)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Model response shape did not match schema."},
        ) from exc
