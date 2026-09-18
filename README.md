# MindMate AI

On-device, privacy-first mental wellness companion for iOS (SwiftUI + SwiftData).

All profile data, journal entries, chat history, and crisis events are stored **locally** with SwiftData. Chat/sentiment stays on-device unless you opt in to the optional local Ollama backend below — even then, traffic never leaves your own network.

## Requirements

| Component | Requirement |
|---|---|
| Xcode | 26+ (for Apple Foundation Models) |
| iOS | 26+ on device/simulator |
| On-device LLM | iPhone 15 Pro or later with Apple Intelligence enabled |
| Local LLM (optional) | [Ollama](https://ollama.com) running `gemma4:e2b` on your Mac/network |
| Sentiment | Any device — `NaturalLanguage` (`NLTagger`) by default, or BERT/Gemma via Ollama when enabled |

Without Apple Intelligence or Ollama, the counselor falls back to **local template replies** (fully offline).

## Feature Status

| Feature | Status |
|---|---|
| Onboarding → SwiftData profile | ✅ |
| Daily check-in + mood slider | ✅ |
| Journal **description** sentiment (not just the slider) | ✅ BERT (Ollama) → Gemma (Ollama) → NLTagger |
| Chatbot backed by a local Ollama Gemma model (`gemma4:e2b`) | ✅ streaming, multi-turn |
| Home dashboard (mood gauge, gradient 7-day chart, week-over-week delta, insights) | ✅ |
| Trends (mood gauge, full timeline, week-by-week, weekday pattern, mood mix, insights) | ✅ |
| Counselor chat with crisis keyword screen | ✅ |
| On-device LLM (Apple Foundation Models) | ✅ |
| Persistent chat history + "New Chat" | ✅ |
| Daily check-in reminders (local notifications) | ✅ |
| Llama via MLX (optional add-on) | 📋 Stub ready — see below |
| Settings: delete all local data | ✅ |

## Architecture

```
Onboarding  →  UserProfile (SwiftData)
Daily check-in  →  SentimentService.deepScore(journalText)
                     ├─ BERT (Ollama) enabled & tag pulled → real BERT sentiment classifier
                     ├─ Ollama enabled & reachable       → LLM reads the description's meaning
                     └─ otherwise                         → NaturalLanguage (NLTagger)
                     →  DailyWellness (slider score + description score + blended combinedScore)
Trends / Home  →  TrendAnalyzer (slope, streaks, weekday & weekly averages)
                     → SwiftUI Charts (MoodGauge, MoodAreaChart, weekly/weekday/distribution)
Chat message  →  RiskDetector
                     ├─ crisis → CrisisEvent + safety reply
                     └─ safe   → SentimentService → CounselorService → ChatMessage
```

**Reply/sentiment priority:** Ollama (local Gemma, if enabled & reachable) → Apple Foundation Models → MLX Llama (if bundled) → Template fallback

**Journal sentiment priority:** BERT classifier (Ollama, if enabled & tag pulled) → Ollama LLM judge → NaturalLanguage (on-device)

## Run the App

1. Open `mateAI.xcodeproj` in Xcode 26+ on a Mac.
2. Select an **iPhone 15 Pro** (or later) simulator/device with Apple Intelligence.
3. Build & Run (`Cmd+R`).
4. Complete onboarding, do a daily check-in, then open **Chat**.

In **Settings → AI Engine**, verify the counselor backend:
- **Ollama (Gemma)** — local model active (if you've enabled it below)
- **Apple On-Device LLM** — Foundation Models active
- **Supportive Templates** — fallback (model downloading or device unsupported)

## Optional: Chat & journal sentiment via Ollama (Gemma e2b)

MindMate can talk to a locally-hosted [Ollama](https://ollama.com) server instead of (or as a
priority over) Apple's on-device model, using Google's compact **Gemma 3n "e2b"** checkpoint.
This also upgrades journal sentiment analysis from simple on-device NLTagger scoring to a
model that actually reads what you wrote.

1. **Install Ollama** on a Mac (or any machine on your network): https://ollama.com/download
2. **Pull the model:**
   ```
   ollama pull gemma4:e2b
   ```
3. **Start the server** (defaults to port 11434):
   ```
   ollama serve
   ```
4. In MindMate, go to **Settings → Ollama (Local Gemma Model)**:
   - Toggle **Use Ollama for chat & sentiment** on.
   - **Server URL** — `http://127.0.0.1:11434` works out of the box in the **iOS Simulator**
     (it shares the Mac's network). On a **physical device**, use your Mac's LAN IP instead,
     e.g. `http://192.168.1.23:11434`.
   - **Model** — defaults to `gemma4:e2b`; change it if you pulled a different tag.
   - Tap **Test Connection** to confirm the server is reachable and the model is pulled.
5. Send a chat message, or write a few sentences in a daily check-in's journal field — both
   now run through Gemma when Ollama is reachable, and silently fall back (Apple's on-device
   model for chat, NLTagger for sentiment) if it isn't. Chat replies stream in token-by-token
   and keep the recent conversation as context.

This requires an `NSAppTransportSecurity` local-networking exception and an
`NSLocalNetworkUsageDescription`, both already set in `mateAI/Info.plist` — iOS will prompt
once for local network permission the first time a request goes out.

## Optional: BERT sentiment analysis (real classifier, via Ollama)

MindMate can score journal sentiment with a **real fine-tuned BERT model** — `bert-base-uncased`
fine-tuned on the SST-2 sentiment benchmark — instead of asking a chat model to judge. A
classifier is faster and more consistent for this one narrow job, and it's a dedicated
single-purpose model (~110M params).

1. **Install Ollama** on a Mac (or any machine on your network): https://ollama.com/download
2. **Pull the BERT model:**
   ```
   ollama pull dugong/bert-base-uncased-finetuned-sst2
   ```
3. In MindMate → **Settings → AI Engine → Ollama**, keep **Prefer BERT for journal sentiment** on.
   The **BERT sentiment model** field defaults to the tag above; change it if you pulled another
   BERT/RoBERTa/DistilBERT SST-2-style tag.
4. Write a few sentences in a daily check-in's journal — the live "Detected mood" badge now reads
   `BERT (Ollama)` when the classifier answered.

If BERT is disabled, unreachable, or the tag isn't pulled yet, sentiment silently falls back to
the Gemma LLM judge, then to Apple's on-device NaturalLanguage model — the app never breaks.

## Optional: Add Llama (MLX)

To use a bundled Llama model instead of Apple's on-device model:

1. **Add package:** File → Add Package Dependencies  
   `https://github.com/ml-explore/mlx-swift-lm`
2. **Link products:** MLXLLM, MLXLMCommon
3. **Download model:** e.g. [Llama-3.2-1B-Instruct-4bit](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit) from Hugging Face
4. **Add to bundle:** Drag the model folder into the Xcode target → Copy Bundle Resources
5. **Enable capability:** Signing & Capabilities → Increased Memory Limit
6. **Implement** `MLXLlamaProvider.swift` using the [mlx-swift-lm quick start](https://github.com/ml-explore/mlx-swift-lm)

Set the bundled folder name in `Constants.llamaModelDirectoryName`.

## Safety

- MindMate is **not** a substitute for licensed mental health care.
- Crisis keyword detection runs **before** any LLM reply (including Ollama).
- LLM output — from Ollama or Apple's model — passes through `ResponseGuardrail` to block diagnostic/medication language.
- The Ollama sentiment prompt explicitly forbids diagnosis/advice and asks for a bare score only.
- In an emergency, call local emergency services.

## Project Structure

```
mateAI/
├── Info.plist        Local-network ATS exception + usage description for Ollama
├── Models/           SwiftData @Model entities (DailyWellness now tracks journalSentimentSource)
├── Views/
│   ├── Home/         Home dashboard (mood gauge + 7-day chart + insights)
│   ├── Trends/       Trends (timeline, weekly/weekday charts, mood mix, insights)
│   ├── Components/   Reusable charts & graphics (MoodGauge, MoodAreaChart, stat/insight cards)
│   └── Chat, CheckIn, Settings, Onboarding, Resources
├── ViewModels/       ChatViewModel
├── Services/
│   ├── SentimentService.swift   NaturalLanguage sentiment + deepScore() (BERT- & Ollama-aware)
│   ├── RiskDetector.swift       Crisis keyword screen
│   ├── CounselorService.swift   LLM orchestration (tracks lastUsedBackend)
│   └── LLM/
│       ├── OllamaProvider.swift   Local Ollama /api/chat client (reply + sentiment)
│       ├── BertSentimentProvider.swift  Real BERT SST-2 classifier via Ollama /api/generate
│       ├── OllamaSettings.swift   UserDefaults-backed server/toggles (incl. BERT tag)
│       ├── LLMService.swift       Apple Foundation Models
│       ├── TemplateLLMProvider.swift
│       └── MLXLlamaProvider.swift (stub)
└── Utilities/
    ├── Constants.swift
    └── TrendAnalyzer.swift    Mood math for trends (slope, streaks, weekday/weekly averages)
```
