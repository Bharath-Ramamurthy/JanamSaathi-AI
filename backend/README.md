# 💍 MatrimAI – FastAPI Backend

MatrimAI is a matchmaking backend powered by FastAPI, Hugging Face, and FAISS + RAG. It supports chat and call compatibility analysis, horoscope matching, and preference-based partner recommendations.

---

## 🏗️ Features

- 🧑‍💼 User Signup with biodata and preferences
- 🔍 FAISS + RAG Matching (based on expected education, caste, religion, etc.)
- 🔮 Horoscope compatibility using DOB
- 💬 Chat-based compatibility scoring via Hugging Face Inference API
- 📞 Voice compatibility scoring post-call
- 🌐 RESTful APIs, fully modular

---

## 🛠️ Tech Stack

- 🐍 FastAPI
- 🤗 Hugging Face Inference API
- 🧠 FAISS for vector search
- 🧩 LangChain for Retrieval-Augmented Generation
- 🗃️ JSON data storage (no DB required initially)
- 🪄 Python 3.10+

---

## 📦 Setup Instructions

### 1. Clone Repo

```bash
git clone https://github.com/yourusername/matrimai-backend.git
cd matrimai-backend
