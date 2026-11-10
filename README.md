# Second Self

A digital twin that builds a memory profile from your Gmail, Google Calendar, and public web presence, then acts on your behalf from a macOS notch app. Voice is powered end-to-end by **Gnani AI**.

**Solution pitch:** [PITCH.md](PITCH.md) — a one-page overview of the problem, product, and architecture.

## Voice agent

Second Self uses **only** Gnani for speech:

| Capability | Model | API |
|------------|-------|-----|
| Speech-to-text | **Gnani Prisma v2.5** | `POST https://api.vachana.ai/stt/v3` |
| Text-to-speech | **Gnani Timbre v2.5** | `POST https://api.vachana.ai/api/v1/tts/inference` |

- Hold the mic button to record. The clip is transcribed with Prisma v2.5 and sent to the Twin as a normal chat message.
- When spoken replies are enabled, the Twin's reply is synthesized with Timbre v2.5 and played back.
- Set one language per Prisma request. For English use `en-IN`; for Hindi use `hi-IN` and a Hindi voice such as `Nalini`.
- No other voice provider is included. Add your key as `GNANI_API_KEY` in `.env`.

## Architecture

```
Gmail OAuth ──> Fetch Emails ──> Clean ──> Analyze (parallel) ──> Build Profiles
                                             |
Google Auth ──> Calendar Fetch ──────────────┤
                                             |
              Tavily Search ─────────────────┘
```

The profile is a layered memory system written to `~/.secondself/`:

```
Layer 1    identity.md         Who you are — role, voice, interests, patterns
Layer 2    preferences.md      How you work — schedule, tools, communication style
Layer 2.5  relationships.json  Who you know — contact graph with closeness scores
Layer 4    episodic.md         What happened — timestamped life events
```

The Twin reads these files at runtime through the orchestrator's system prompt.

## Project structure

```
second-self/
├── main.py                     # Identity pipeline entry point
├── auth/                       # Google OAuth and token handling
├── fetch/                      # Gmail, Calendar, and Tavily fetchers
├── clean/                      # Email cleaning and thread reconstruction
├── analyze/                    # Voice, topic, behavior, relationship analyzers
├── utils/                      # Episodic memory writer
├── src/                        # FastAPI backend + Next.js app (TypeScript in src/app)
│   ├── server.py               # /health, /onboard, /chat
│   ├── agent/                  # Chat agent and tools
│   ├── connectors/             # Gmail, Calendar, Tavily clients
│   ├── db/                     # Firestore repositories
│   └── synthesis/              # Profile synthesis
├── orchestrator/               # Streaming chat + desktop tool loop (:8420)
├── agent-server/               # Desktop tools + MJPEG stream (:8421)
├── SecondSelf/                 # Native macOS notch app (SwiftUI)
│   ├── Services/GnaniVoiceAgent.swift
│   ├── Services/AudioRecorder.swift
│   └── ViewModels/ChatViewModel.swift
├── setup/                      # Provisioning and smoke tests
├── tests/                      # Python test suite
└── .env.example
```

For the full developer notes, see `CLAUDE.md` and `docs/DESIGN.md`.

## Requirements

- macOS 14+ for the native app
- Python 3.11+
- Node.js 20+ (Next.js 16)
- Xcode command line tools / Swift 5.9+
- API keys: Gnani, Anthropic, Tavily
- Optional: Firebase, Auth0, Google Cloud OAuth credentials

## Setup

### 1. Clone and install

```bash
git clone <your-repo-url> second-self
cd second-self

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

npm install
```

### 2. Configure environment

```bash
cp .env.example .env
```

Open `.env` and set at least:

```env
# Gnani Prisma v2.5 (speech-to-text) + Timbre v2.5 (text-to-speech)
GNANI_API_KEY=

# Twin chat and analysis
ANTHROPIC_API_KEY=

# Public profile search
TAVILY_API_KEY=
```

Add Firebase, Auth0, and Google OAuth values if you are using the web app and the Google data pipeline. See [Environment variables](#environment-variables).

Voice defaults live in the same file:

```env
GNANI_STT_MODEL=prisma-v2.5
GNANI_STT_LANGUAGE=en-IN
GNANI_TTS_MODEL=timbre-v2.5
GNANI_TTS_VOICE=Kaveri
GNANI_TTS_LANGUAGE=auto
```

### 3. Build the identity profile

```bash
python main.py
```

This fetches Gmail + Calendar, runs the analyzers, and writes the memory files to `~/.secondself/`.

Useful flags:

| Flag | Description |
|------|-------------|
| `--dry-run` | Run without writing to `~/.secondself/` |
| `--no-cache` | Bypass caches and re-fetch from APIs |
| `--tavily-only` | Skip Gmail and build from web search only |
| `--memory-only` | Refresh Layers 2 + 4 only |
| `--verbose` | Enable DEBUG logging |

### 4. Run the backend

```bash
python -m uvicorn src.server:app --host 0.0.0.0 --port 8000 --reload
```

### 5. Run the web app

```bash
npm run dev
```

Open <http://localhost:3000>.

### 6. Run the macOS app

```bash
cd SecondSelf
swift build
swift run
```

Or build a distributable app bundle:

```bash
./build-app.sh
```

The app reads `.env` from the repository root. It starts the auth server and orchestrator automatically.

First-time macOS setup (provisions the background `secondself` user and services):

```bash
./setup/provision.sh
# sign in to the secondself user and grant Screen Recording to python3
./setup/restart-agent.sh
./setup/smoke-test.sh
```

## Environment variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `GNANI_API_KEY` | Voice | Gnani Prisma v2.5 + Timbre v2.5 |
| `GNANI_STT_MODEL` | No | Defaults to `prisma-v2.5` |
| `GNANI_STT_LANGUAGE` | No | One Prisma language code, default `en-IN` |
| `GNANI_TTS_MODEL` | No | Defaults to `timbre-v2.5` |
| `GNANI_TTS_VOICE` | No | Timbre v2.5 voice, default `Kaveri` |
| `GNANI_TTS_LANGUAGE` | No | Defaults to `auto` |
| `ANTHROPIC_API_KEY` | Yes | Twin chat and profile analysis |
| `CLAUDE_MODEL` | No | Defaults to `claude-sonnet-4-20250514` |
| `TAVILY_API_KEY` | Yes | Web search enrichment |
| `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` | Pipeline | Gmail + Calendar OAuth |
| `GOOGLE_REDIRECT_URI` | No | Defaults to `http://localhost:8080` |
| `AUTH0_*` | Web/macOS | Auth0 login |
| `FIREBASE_*` / `NEXT_PUBLIC_FIREBASE_*` | Web | Firebase auth + Firestore |
| `NEXT_PUBLIC_BACKEND_URL` | No | Backend origin, default `http://localhost:8000` |
| `DEMO_MODE` | No | Return a demo profile without data sources |
| `ALLOWED_ORIGINS` | No | CORS origins, default `http://localhost:3000` |
| `HOST` / `PORT` | No | Backend bind address, defaults `0.0.0.0:8000` |
| `USER_NAME` / `USER_EMAIL` | No | Override identity pipeline user details |

## Voice troubleshooting

| Symptom | Fix |
|---------|-----|
| Mic button is hidden | `GNANI_API_KEY` is missing or empty in `.env` |
| "Invalid Gnani API key" | Check the key in the Gnani dashboard and restart the app |
| "Insufficient credit" | Add credit to your Gnani account |
| "Rate limited" | Your account allows one active request at a time; retry |
| "Nothing heard" | Record a little longer; Prisma clips must be 1–30 seconds |
| Wrong language transcript | Set `GNANI_STT_LANGUAGE` to the language being spoken |
| No spoken replies | Turn on the speaker button in the chat input bar |
| Robotic / mismatched voice | Match `GNANI_TTS_LANGUAGE` to the voice's language (e.g. `Nalini` + `hi-IN`) |

## Ports

| Port | Service | Session |
|------|---------|---------|
| 8000 | FastAPI backend | Current user |
| 8420 | Orchestrator (Claude bridge) | Primary (launched by app) |
| 8421 | Agent server (desktop tools + MJPEG) | `secondself` |
| 5901 | Vine Server VNC (optional) | `secondself` |
| 9222 | Chrome DevTools Protocol | `secondself` |

## Tests

```bash
python -m pytest tests/ -v
```

## License

Private.
