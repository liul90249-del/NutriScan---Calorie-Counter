# NutriScan Cloud Food Recognition API

This document defines the backend contract expected by the iOS app in `CloudFoodRecognitionService`.

## Endpoint

- Method: `POST`
- Path example: `/food/analyze`
- Full URL example: `https://api.yourdomain.com/food/analyze`
- Content-Type: `application/json`
- Authorization: `Bearer <api_key>`

## Request Body

```json
{
  "imageBase64": "BASE64_ENCODED_IMAGE_BYTES",
  "locale": "zh_CN",
  "source": "NutriScan-iOS"
}
```

## Request Fields

- `imageBase64`: Required. Raw image data encoded as Base64.
- `locale`: Required. Current device locale from iOS, for example `zh_CN` or `en_US`.
- `source`: Required. Current client identifier. The app sends `NutriScan-iOS`.

## Success Response

Return HTTP `200` with this JSON shape:

```json
{
  "foodName": "Chicken Rice Bowl",
  "confidence": 0.91,
  "calories": 540,
  "protein": 28,
  "carbs": 62,
  "fat": 18,
  "highlights": [
    "Protein-rich meal",
    "Rice and grilled chicken detected",
    "Manual adjustment still recommended"
  ]
}
```

## Response Fields

- `foodName`: Required string.
- `confidence`: Required number in `0...1`.
- `calories`: Required integer.
- `protein`: Required number, grams.
- `carbs`: Required number, grams.
- `fat`: Required number, grams.
- `highlights`: Required string array, 1 to 3 short bullet points is enough.

## Error Behavior

The current iOS app treats any non-2xx status as a generic cloud failure.

Recommended server behavior:

- `400`: invalid image payload
- `401`: invalid or expired bearer token
- `413`: image too large
- `422`: image readable but meal could not be estimated
- `500`: temporary server or model failure

Recommended error body:

```json
{
  "error": "unable_to_analyze",
  "message": "Meal could not be recognized with enough confidence."
}
```

The current app does not parse this body yet, but you should still return it for debugging and future UI messaging.

## Backend Recommendations

- Do not call OpenAI directly from the iOS app.
- Put the OpenAI key only on your server.
- Validate image size before forwarding to model inference.
- Resize or compress large images server-side before model processing.
- Log request IDs, latency, and model outcome, but avoid storing raw user images long term unless the user explicitly agrees.
- Return normalized nutrition units in grams and kcal only.

## Suggested Server Pipeline

1. Validate bearer token.
2. Decode `imageBase64`.
3. Resize and normalize image if needed.
4. Run food recognition.
5. Map model output into a fixed nutrition schema.
6. Return the normalized JSON response above.

## OpenAI Mapping Suggestion

If your backend uses OpenAI or another multimodal model, keep the model output constrained to this schema:

```json
{
  "foodName": "string",
  "confidence": 0.0,
  "calories": 0,
  "protein": 0.0,
  "carbs": 0.0,
  "fat": 0.0,
  "highlights": ["string"]
}
```

The server should be responsible for:

- prompt design
- model retries
- schema validation
- fallback defaults
- provider switching

The iOS app should only consume the normalized result.

## Current Client Notes

The current app behavior is:

- `On-Device`: uses local stub recognition
- `Smart Hybrid`: tries the internally configured NutriScan backend first, then falls back to local estimation
- `Cloud Boost`: uses the internally configured NutriScan backend for the best available recognition quality

Users do not enter an AI endpoint or API key in the app. Configure the backend URL and client bearer token in the app build settings/source, and keep provider keys such as OpenAI, DeepSeek, or Grok only on your server.

If you change this contract, update:

- `NutriScan/Services/FoodRecognitionService.swift`
