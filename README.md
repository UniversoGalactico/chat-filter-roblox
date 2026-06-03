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

1. Download all `.lua` files from this repository.
2. In Roblox Studio, place them inside `ServerScriptService`.
3. That's it. The system works automatically — no configuration needed.
4. (Optional) Customize words and sanctions by editing `ChatConfig.lua` and `ProfanityData.lua`.

## 📁 Files

| File | Type | Purpose |
|------|------|---------|
| `ChatConfig.lua` | ModuleScript | All configurable constants |
| `ProfanityData.lua` | ModuleScript | Banned words, phrases, emojis, white‑list |
| `ChatFilter.lua` | ModuleScript | Core filtering logic (normalization, Levenshtein) |
| `ModerationManager.lua` | ModuleScript | Strikes, silence, kicks, reports, audit log |
| `ChatConnector.lua` | ModuleScript | Facade that connects everything |
| `ChatServer.lua` | Script | Listens to `Player.Chatted` and routes messages |

## 📝 License

MIT — do whatever you want, just keep the copyright notice.

## 🌍 Languages

The filter supports **Spanish**, **English**, and **Portuguese** by default. You can easily add more by editing `ProfanityData.lua`.

---

*If this project helped you, consider starring ⭐ the repo. It means a lot.*
