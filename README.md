# 🛡️ Chat Filter for Roblox

A free, multilingual chat moderation system with progressive strikes, Levenshtein evasion detection, and anti‑grooming tools. Built for developers who want real control over their game's chat.

## ✨ Why this exists

In January 2026, I was scammed in a Roblox game. I lost 79 Robux. I submitted clear evidence to Roblox support and was ignored.  
I could have held a grudge. Instead, I built a chat filter that catches what Roblox misses — and gave it away for free.  
I'm 16 years old. This is what I know how to do.

## 🚀 Features

- **Multilingual insult detection** (Spanish, English, Portuguese)
- **Levenshtein distance** to catch evasion attempts like `korer`, `hoder`, `m1erd4`
- **Emoji translation** — blocks sexual emojis like 🍆, 💦, 🥵
- **Progressive sanctions** — strike 1 (10s silence), strike 2 (20s), strike 3 (kick)
- **Rate limiting** — anti‑spam protection
- **Community reports** — `/report` command with false‑report counterweight
- **Circular audit log** — full traceability
- **White‑list** for innocent words — avoids false positives
- **~ detection** — blocks simulated moaning

## 📦 How to install

### Server
1. Download all `.lua` files from the `server/` folder.
2. In Roblox Studio, place them inside `ServerScriptService/ServerModules`.
3. Place `ChatServer.lua` directly in `ServerScriptService`.

### Client
1. Download `ChatClient.lua` from the `client/` folder and place it in `ReplicatedStorage/ClientModules`.
2. Place `IniciarChat.lua` inside `StarterGui/ScreenGui`.
3. Create a `RemoteEvent` named `ChatMessage` inside `ReplicatedStorage`.

That's it. The system works automatically — no configuration needed.  
(Optional) Customize words and sanctions by editing `ChatConfig.lua` and `ProfanityData.lua`.

## 📁 Files

| File | Type | Location | Purpose |
|------|------|----------|---------|
| `ChatConfig.lua` | ModuleScript | ServerModules | All configurable constants |
| `ProfanityData.lua` | ModuleScript | ServerModules | Banned words, phrases, emojis, white‑list |
| `ChatFilter.lua` | ModuleScript | ServerModules | Core filtering logic (normalization, Levenshtein) |
| `ModerationManager.lua` | ModuleScript | ServerModules | Strikes, silence, kicks, reports, audit log |
| `ChatConnector.lua` | ModuleScript | ServerModules | Facade that connects everything |
| `ChatServer.lua` | Script | ServerScriptService | Receives messages, validates, broadcasts |
| `ChatClient.lua` | ModuleScript | ClientModules | Chat GUI, sends messages to server |
| `IniciarChat.lua` | LocalScript | StarterGui | Starts the ChatClient module |

## 📝 License

MIT — do whatever you want, just keep the copyright notice.

## 🌍 Languages

The filter supports **Spanish**, **English**, and **Portuguese** by default. You can easily add more by editing `ProfanityData.lua`.

---

*If this project helped you, consider starring ⭐ the repo. It means a lot.*
