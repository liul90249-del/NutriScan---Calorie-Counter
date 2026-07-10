import base64
from collections import defaultdict, deque
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FutureTimeoutError
import hmac
import json
import os
import threading
import time
import urllib.error
import urllib.request
from typing import Any, Optional, Tuple

from fastapi import FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field
from openai import APITimeoutError, OpenAI


app = FastAPI(title="NutriScan Food Recognition Proxy")

provider = os.environ.get("AI_PROVIDER", "openai").strip().lower()
# Accept one or more comma-separated client tokens so the token can be rotated
# without breaking already-shipped app versions.
client_bearer_tokens = {
    token.strip()
    for token in os.environ["NUTRISCAN_CLIENT_TOKEN"].split(",")
    if token.strip()
}
if not client_bearer_tokens:
    raise RuntimeError("NUTRISCAN_CLIENT_TOKEN must contain at least one non-empty token.")
max_image_bytes = int(os.environ.get("MAX_IMAGE_BYTES", str(6 * 1024 * 1024)))
ai_request_timeout_seconds = float(os.environ.get("AI_REQUEST_TIMEOUT_SECONDS", "45"))

# Per-IP sliding-window rate limiting (in-memory; suitable for a single instance).
_rate_limit_lock = threading.Lock()
_rate_limit_hits: dict[str, deque] = defaultdict(deque)


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


class CoachUserProfile(BaseModel):
    gender: str = ""
    height: float = Field(ge=0)
    weight: float = Field(ge=0)
    goalWeight: float = Field(ge=0)
    activityLevel: str = ""
    weeklyLossRate: float = Field(ge=0)
    unit: str = "metric"
    isPremium: bool = False


class CoachMealEntry(BaseModel):
    mealType: str
    foodName: str
    calories: int = Field(ge=0)
    protein: float = Field(ge=0)
    carbs: float = Field(ge=0)
    fat: float = Field(ge=0)
    notes: str = ""
    createdAt: str = ""


class CoachRequest(BaseModel):
    locale: str
    profile: CoachUserProfile
    recentMeals: list[CoachMealEntry] = Field(default_factory=list, max_length=30)


class CoachSuggestionCard(BaseModel):
    title: str
    subtitle: str
    bullets: list[str] = Field(min_length=1, max_length=4)
    suggestedFoods: list[str] = Field(default_factory=list, max_length=6)
    targetFocus: str = ""
    priority: str = "medium"


class CoachResponse(BaseModel):
    summary: str
    nextGoal: str
    cards: list[CoachSuggestionCard] = Field(min_length=1, max_length=5)


class WaterReminderRequest(BaseModel):
    locale: str
    profile: CoachUserProfile


class WaterReminderItem(BaseModel):
    timeOfDay: str
    hour: int = Field(ge=0, le=23)
    title: str
    body: str


class WaterReminderResponse(BaseModel):
    reminders: list[WaterReminderItem] = Field(min_length=3, max_length=3)


def require_bearer_token(authorization: Optional[str]) -> None:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail={"error": "unauthorized", "message": "Missing bearer token."})

    token = authorization.removeprefix("Bearer ").strip()
    if not any(hmac.compare_digest(token, valid) for valid in client_bearer_tokens):
        raise HTTPException(status_code=401, detail={"error": "unauthorized", "message": "Invalid bearer token."})


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def enforce_rate_limit(request: Request, scope: str, max_requests: int, window_seconds: float) -> None:
    key = f"{scope}:{_client_ip(request)}"
    now = time.monotonic()
    cutoff = now - window_seconds
    with _rate_limit_lock:
        hits = _rate_limit_hits[key]
        while hits and hits[0] < cutoff:
            hits.popleft()
        if len(hits) >= max_requests:
            retry_after = max(int(hits[0] + window_seconds - now) + 1, 1)
            raise HTTPException(
                status_code=429,
                detail={"error": "rate_limited", "message": "Too many requests. Please slow down."},
                headers={"Retry-After": str(retry_after)},
            )
        hits.append(now)
        # Opportunistically drop idle IP buckets so the map cannot grow forever.
        if len(_rate_limit_hits) > 5000:
            for stale_key in [k for k, v in _rate_limit_hits.items() if not v or v[-1] < cutoff]:
                del _rate_limit_hits[stale_key]


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
    target_language = language_name_for_locale(locale)
    return f"""
You are a nutrition vision assistant.
Estimate the visible meal shown in the image and return strict JSON only.

Rules:
- Locale hint: {locale}
- Target language: {target_language}
- All user-visible text fields must be written in {target_language}.
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
- Write foodName, highlights, identifiedItems, and portionDescription in {target_language}.
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
        cleaned = cleaned.strip("`").strip()
        if cleaned.lower().startswith("json"):
            cleaned = cleaned[4:].strip()

    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        extracted = extract_json_object(cleaned)
        if extracted:
            try:
                return json.loads(extracted)
            except json.JSONDecodeError:
                pass

        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Model did not return valid JSON."},
        )


def extract_json_object(text: str) -> str:
    start = text.find("{")
    if start == -1:
        return ""

    depth = 0
    in_string = False
    escape = False

    for index in range(start, len(text)):
        char = text[index]

        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue

        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return text[start : index + 1]

    return ""


def build_coach_prompt(payload: CoachRequest) -> str:
    profile = payload.profile.model_dump()
    meals = [meal.model_dump() for meal in payload.recentMeals]
    target_language = language_name_for_locale(payload.locale)
    return f"""
You are a practical nutrition coach for a calorie tracking app.
Return strict JSON only. Do not include markdown.

Locale hint: {payload.locale}
Target language: {target_language}

User profile JSON:
{json.dumps(profile, ensure_ascii=False)}

Recent meals JSON:
{json.dumps(meals, ensure_ascii=False)}

Rules:
- This feature is for premium users, but do not mention payment, premium, or subscriptions.
- Give safe, general nutrition coaching only. Do not diagnose disease, prescribe treatment, or make medical claims.
- Use {target_language} for every user-facing string, including summary, nextGoal, card titles, subtitles, bullets, and suggestedFoods.
- Do not mix languages or provide bilingual text. If the target language is Simplified Chinese, do not include English coaching phrases.
- Base advice on the supplied profile and recent meals.
- If recentMeals is empty, give starter goals and simple meal suggestions.
- nextGoal must be one concrete goal for the next 24 hours.
- cards must include 3 to 5 practical suggestion cards.
- Each card must have:
  - title: short action-oriented title
  - subtitle: one sentence explaining why it matters
  - bullets: 2 to 4 short actionable steps
  - suggestedFoods: 3 to 6 foods or meal ideas
  - targetFocus: one of "calories", "protein", "carbs", "fat", "fiber", "hydration", "consistency"
  - priority: one of "high", "medium", "low"
- Prefer concrete foods such as eggs, Greek yogurt, tofu, chicken breast, fish, beans, oats, rice bowls, vegetables, fruit, soup, potatoes, or salad bowls.
- Avoid extreme dieting advice. Keep calorie deficits moderate.
- Never tell the user exact medical requirements.

JSON schema:
{{
  "summary": "string",
  "nextGoal": "string",
  "cards": [
    {{
      "title": "string",
      "subtitle": "string",
      "bullets": ["string"],
      "suggestedFoods": ["string"],
      "targetFocus": "protein",
      "priority": "high"
    }}
  ]
}}
""".strip()


def language_name_for_locale(locale: str) -> str:
    normalized = locale.lower()
    if normalized.startswith("zh"):
        return "Simplified Chinese"
    if normalized.startswith("ja"):
        return "Japanese"
    if normalized.startswith("es"):
        return "Spanish"
    if normalized.startswith("it"):
        return "Italian"
    return "English"


def default_coach_result(locale: str) -> dict[str, Any]:
    if locale.lower().startswith("zh"):
        return {
            "summary": "这里是接下来可以优先执行的营养建议。",
            "nextGoal": "下一餐先记录一份包含蛋白质、蔬菜和主食的均衡餐。",
            "cards": [
                {
                    "title": "搭配一餐更均衡的正餐",
                    "subtitle": "从蛋白质、蔬菜和稳定主食开始，更容易控制饥饿感。",
                    "bullets": ["选择一种蛋白质来源。", "加入蔬菜或水果。", "主食和酱料保持适量。"],
                    "suggestedFoods": ["鸡蛋", "豆腐", "鸡胸肉", "米饭碗", "沙拉"],
                    "targetFocus": "consistency",
                    "priority": "medium",
                }
            ],
        }
    return {
        "summary": "Here are your next nutrition steps.",
        "nextGoal": "Log your next balanced meal.",
        "cards": [
            {
                "title": "Build a balanced next meal",
                "subtitle": "Start with a protein source, vegetables, and a steady carbohydrate.",
                "bullets": ["Choose one protein source.", "Add vegetables or fruit.", "Keep portions moderate."],
                "suggestedFoods": ["eggs", "tofu", "chicken", "rice bowl", "salad"],
                "targetFocus": "consistency",
                "priority": "medium",
            }
        ],
    }


def call_deepseek_coach_provider(payload: CoachRequest) -> dict[str, Any]:
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail={"error": "provider_not_configured", "message": "DEEPSEEK_API_KEY is not configured."},
        )

    base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip()
    model = os.environ.get("DEEPSEEK_COACH_MODEL", os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash"))
    deepseek_client = OpenAI(api_key=api_key, base_url=base_url)

    try:
        response = deepseek_client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "Return one valid JSON object only. Do not include markdown, code fences, comments, or explanatory text."},
                {"role": "user", "content": build_coach_prompt(payload)},
            ],
            response_format={"type": "json_object"},
            temperature=0.2,
            max_tokens=int(os.environ.get("DEEPSEEK_COACH_MAX_TOKENS", "1800")),
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


def normalize_coach_result(result: dict[str, Any], locale: str) -> dict[str, Any]:
    defaults = default_coach_result(locale)
    default_card = defaults["cards"][0]
    cards = result.get("cards")
    if not isinstance(cards, list):
        cards = []

    normalized_cards: list[dict[str, Any]] = []
    for card in cards[:5]:
        if not isinstance(card, dict):
            continue
        bullets = card.get("bullets")
        if not isinstance(bullets, list):
            bullets = []
        suggested_foods = card.get("suggestedFoods")
        if not isinstance(suggested_foods, list):
            suggested_foods = []
        normalized_cards.append(
            {
                "title": str(card.get("title", default_card["title"])).strip() or default_card["title"],
                "subtitle": str(card.get("subtitle", "")).strip(),
                "bullets": [str(item).strip() for item in bullets if str(item).strip()][:4] or default_card["bullets"],
                "suggestedFoods": [str(item).strip() for item in suggested_foods if str(item).strip()][:6],
                "targetFocus": str(card.get("targetFocus", "consistency")).strip() or "consistency",
                "priority": str(card.get("priority", "medium")).strip() or "medium",
            }
        )

    if not normalized_cards:
        normalized_cards = defaults["cards"]

    return {
        "summary": str(result.get("summary", defaults["summary"])).strip() or defaults["summary"],
        "nextGoal": str(result.get("nextGoal", defaults["nextGoal"])).strip() or defaults["nextGoal"],
        "cards": normalized_cards,
    }


def build_water_reminder_prompt(payload: WaterReminderRequest) -> str:
    return f"""
You write short push notification copy for a calorie tracking app.

User profile:
- locale: {payload.locale}
- gender: {payload.profile.gender}
- weight: {payload.profile.weight}
- goalWeight: {payload.profile.goalWeight}
- activityLevel: {payload.profile.activityLevel}
- weeklyLossRate: {payload.profile.weeklyLossRate}
- unit: {payload.profile.unit}

Return strict JSON only:
{{
  "reminders": [
    {{"timeOfDay": "morning", "hour": 9, "title": "string", "body": "string"}},
    {{"timeOfDay": "midday", "hour": 13, "title": "string", "body": "string"}},
    {{"timeOfDay": "evening", "hour": 19, "title": "string", "body": "string"}}
  ]
}}

Rules:
- Match the locale language.
- Make the three reminders different by time of day.
- Keep title under 18 characters and body under 70 characters.
- Be supportive, not medical. Do not mention disease or treatment.
- Do not use emoji.
""".strip()


def default_water_reminders(locale: str) -> list[dict[str, Any]]:
    if locale.startswith("zh"):
        return [
            {"timeOfDay": "morning", "hour": 9, "title": "早晨补水", "body": "起床后补一杯水，帮今天的记录有个稳定开始。"},
            {"timeOfDay": "midday", "hour": 13, "title": "午间喝水", "body": "午餐前后喝点水，别把口渴误当成饥饿。"},
            {"timeOfDay": "evening", "hour": 19, "title": "晚间补水", "body": "晚饭后少量补水，给今天的状态做个温和收尾。"},
        ]
    return [
        {"timeOfDay": "morning", "hour": 9, "title": "Morning water", "body": "Start steady with a glass of water before the day gets busy."},
        {"timeOfDay": "midday", "hour": 13, "title": "Midday sip", "body": "Take a water break before thirst starts looking like hunger."},
        {"timeOfDay": "evening", "hour": 19, "title": "Evening reset", "body": "A small glass now helps you close the day with a steadier routine."},
    ]


def call_deepseek_water_reminder_provider(payload: WaterReminderRequest) -> dict[str, Any]:
    api_key = os.environ.get("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        return {"reminders": default_water_reminders(payload.locale)}

    base_url = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip()
    model = os.environ.get("DEEPSEEK_COACH_MODEL", os.environ.get("DEEPSEEK_MODEL", "deepseek-v4-flash"))
    deepseek_client = OpenAI(api_key=api_key, base_url=base_url)

    try:
        response = deepseek_client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": "You return strict JSON for notification copy."},
                {"role": "user", "content": build_water_reminder_prompt(payload)},
            ],
            response_format={"type": "json_object"},
            temperature=0.4,
            timeout=ai_request_timeout_seconds,
        )
    except APITimeoutError:
        raise
    except Exception:
        return {"reminders": default_water_reminders(payload.locale)}

    content = response.choices[0].message.content if response.choices else ""
    return parse_model_json(content or "")


def normalize_water_reminders(result: dict[str, Any], locale: str) -> dict[str, Any]:
    defaults = default_water_reminders(locale)
    reminders = result.get("reminders")
    if not isinstance(reminders, list):
        reminders = []

    normalized: list[dict[str, Any]] = []
    fallback_by_time = {item["timeOfDay"]: item for item in defaults}
    for index, time_of_day in enumerate(["morning", "midday", "evening"]):
        source = next((item for item in reminders if isinstance(item, dict) and item.get("timeOfDay") == time_of_day), None)
        fallback = fallback_by_time[time_of_day]
        if source is None:
            source = fallback
        title = str(source.get("title", fallback["title"])).strip() or fallback["title"]
        body = str(source.get("body", fallback["body"])).strip() or fallback["body"]
        hour = source.get("hour", fallback["hour"])
        if not isinstance(hour, int) or hour < 0 or hour > 23:
            hour = fallback["hour"]
        normalized.append(
            {
                "timeOfDay": time_of_day,
                "hour": hour,
                "title": title[:32],
                "body": body[:120],
            }
        )

    return {"reminders": normalized[:3]}


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
            "maxOutputTokens": int(os.environ.get("GOOGLE_MAX_OUTPUT_TOKENS", "900")),
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
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> AnalyzeResponse:
    require_bearer_token(authorization)
    enforce_rate_limit(request, "food", max_requests=20, window_seconds=60)
    image_bytes = decode_image(payload.imageBase64)
    started_at = time.perf_counter()
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

    elapsed_ms = int((time.perf_counter() - started_at) * 1000)
    print(
        f"food_analyze provider={provider} model={model_name} image_kb={len(image_bytes) // 1024} elapsed_ms={elapsed_ms}",
        flush=True,
    )

    try:
        return AnalyzeResponse(**result)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Model response shape did not match schema."},
        ) from exc


@app.post("/coach/suggestions", response_model=CoachResponse)
def coach_suggestions(
    payload: CoachRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> CoachResponse:
    require_bearer_token(authorization)
    enforce_rate_limit(request, "coach", max_requests=15, window_seconds=60)
    if not payload.profile.isPremium:
        raise HTTPException(
            status_code=403,
            detail={"error": "premium_required", "message": "Nutrition coaching suggestions require an active subscription."},
        )

    executor = ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(call_deepseek_coach_provider, payload)
        result = normalize_coach_result(future.result(timeout=ai_request_timeout_seconds), payload.locale)
    except (APITimeoutError, FutureTimeoutError) as exc:
        raise HTTPException(
            status_code=504,
            detail={"error": "model_timeout", "message": "Nutrition coaching model timed out."},
        ) from exc
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    try:
        return CoachResponse(**result)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"error": "bad_model_response", "message": "Coach response shape did not match schema."},
        ) from exc


@app.post("/notifications/water-reminders", response_model=WaterReminderResponse)
def water_reminders(
    payload: WaterReminderRequest,
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> WaterReminderResponse:
    require_bearer_token(authorization)
    enforce_rate_limit(request, "water", max_requests=15, window_seconds=60)
    executor = ThreadPoolExecutor(max_workers=1)
    try:
        future = executor.submit(call_deepseek_water_reminder_provider, payload)
        result = normalize_water_reminders(future.result(timeout=ai_request_timeout_seconds), payload.locale)
    except (APITimeoutError, FutureTimeoutError):
        result = {"reminders": default_water_reminders(payload.locale)}
    finally:
        executor.shutdown(wait=False, cancel_futures=True)

    return WaterReminderResponse(**result)
