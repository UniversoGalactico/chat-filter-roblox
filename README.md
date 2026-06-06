# 🛡️ ChatFilter Lite – Free Multilingual Chat Moderation for Roblox

A free, multilingual chat moderation system with **double‑layer filtering**, **Levenshtein evasion detection**, and **anti‑grooming tools**. Built for developers who want real control over their game's chat.

---

## ✨ Why this exists

In January 2026, I was scammed in a Roblox game. I lost 79 Robux. I submitted clear evidence to Roblox support and was ignored.  

I could have held a grudge. Instead, I built a chat filter that catches what Roblox misses – and gave it away for free.  

I'm 16 years old. This is what I know how to do.

---

## 🚀 Features (Lite version)

- ✅ **Multilingual insult detection** (Spanish, English, Portuguese)  
- ✅ **Levenshtein distance** – catches evasion attempts like `korer`, `hoder`, `m1erd4`  
- ✅ **Emoji translation** – blocks sexual emojis like 🍆, 💦, 🥵  
- ✅ **Rate limiting** – anti‑spam protection  
- ✅ **White‑list for innocent words** – avoids false positives  
- ✅ **~ detection** – blocks simulated moaning  

*(Need progressive strikes, auto‑silence, community reports and audit logs? Check out **ModerationManager Pro** below.)*

---

## 🆚 Lite vs Pro

| Feature | Lite (Free) | Pro |
|---------|-------------|-------------------|
| Insult detection | ✅ | ✅ |
| Emoji filtering | ✅ | ✅ |
| Rate limiting | ✅ | ✅ |
| White‑list | ✅ | ✅ |
| **Progressive strikes** | ❌ | ✅ |
| **Auto‑silence & kick** | ❌ | ✅ |
| **Community reports** (/report) | ❌ | ✅ |
| **Circular audit log** | ❌ | ✅ |
| **Priority support** | ❌ | ✅ |

---

## 📦 How to install (5 minutes)

### Server
1. Download all `.lua` files from the `server/` folder.  
2. In Roblox Studio, place them inside **ServerScriptService/ServerModules**.  
3. Place `ChatServer.lua` directly in **ServerScriptService**.

### Client
1. Download `ChatClient.lua` from the `client/` folder.  
2. Place it in **ReplicatedStorage/ClientModules**.  
3. Create a **ScreenGui** in StarterGui and add a LocalScript that calls `ChatClient.Iniciar(gui)`.

### Network
1. Create a **RemoteEvent** named `ChatMessage` inside **ReplicatedStorage**.  

That's it. The system works automatically – no configuration needed.  
*(Optional) Customize words and sensitivity by editing `ChatConfig.lua` and `ProfanityData.lua`.*

---

## 📁 Files (Lite version)

| File | Type | Location | Purpose |
|------|------|----------|---------|
| `ChatConfig.lua` | ModuleScript | ServerModules | All configurable constants |
| `ProfanityData.lua` | ModuleScript | ServerModules | Banned words, phrases, emojis, white‑list |
| `ChatFilter.lua` | ModuleScript | ServerModules | Core filtering logic (normalization, Levenshtein) |
| `ChatServer.lua` | Script | ServerScriptService | Receives messages, validates, broadcasts |
| `ChatClient.lua` | ModuleScript | ClientModules | Chat GUI, sends messages to server |

---

## 📝 License

MIT – do whatever you want, just keep the copyright notice.

---

## 🌍 Languages

The filter supports **Spanish, English, and Portuguese** by default. You can easily add more by editing `ProfanityData.lua`.

---

If this project helped you, consider starring ⭐ the repo. It means a lot.

---

## 💰 Want the full system?

Get **ModerationManager Pro** for 200k Robux:  
- Progressive strikes with auto‑silence and kick  
- Community reports (/report command)  
- Circular audit log  
- Priority support  

Contact me on Discord: `[tu discord]`
