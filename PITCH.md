# Second Self — Solution Pitch

**A digital twin that remembers your life and acts on it — by text or voice.**

## The problem

Every assistant starts from zero. You re-explain who you are, who matters, and what you promised. Generic chatbots answer questions; they do not carry context across days or take action in the tools where work actually happens. Voice is an afterthought, and Indian languages are usually second-class.

## What we built

Second Self learns a person from their Gmail, Google Calendar, and public web footprint, distills that into a layered memory, and becomes an always-available twin inside the macOS notch. It answers with real context, takes actions across email, calendar, and the desktop, and holds a spoken conversation in English or Hindi using Gnani.

## How it works

1. **Ingest** — OAuth-connected Gmail and Calendar, enriched by Tavily web search.
2. **Distill** — Email cleaning and thread reconstruction, then parallel analyzers for writing voice, topics, behavior, relationships, and life events.
3. **Remember** — Four memory layers in `~/.secondself/`: identity (who you are), preferences (how you work), relationships (who you know, with closeness scores), and episodic memory (what happened, timestamped).
4. **Act and speak** — The orchestrator streams Claude with a tool loop for email, calendar, Docs/Slides/Drive, web search, and desktop/browser control. In the native SwiftUI app, hold the mic to talk: **Gnani Prisma v2.5** transcribes the clip, the Twin responds, and **Gnani Timbre v2.5** speaks the reply.

## Why it is different

- **Continuity, not chat history.** The Twin's system prompt is built from persistent memory, so it knows your voice, your people, and your commitments.
- **Action, not just answers.** It drafts and sends email, manages events, creates documents, and operates the desktop through a supervised, approval-gated tool loop.
- **Ambient by design.** A notch app that stays present without demanding attention — it peeks, suggests, and gets out of the way.
- **Voice that fits India.** Prisma v2.5 handles Indian English and Hindi; Timbre v2.5 replies in a natural, matching voice. Language is one setting, not a separate product.
- **Local-first memory.** Profiles live on the machine and API keys stay in `.env`.

## In practice

"Reply to Priya, move our review to Thursday, and remind me what I promised her." Second Self finds the thread, drafts in your tone, updates the calendar, and answers aloud — hands-free while you keep working.

## Built with

SwiftUI · Python/FastAPI · Next.js · Claude · **Gnani Prisma v2.5 (STT)** · **Gnani Timbre v2.5 (TTS)** · Tavily · Firebase/Auth0

## Status

Working prototype: identity pipeline, web app, streaming orchestrator, and a native macOS twin with Gnani voice. Setup and demo steps are in the [README](README.md).
