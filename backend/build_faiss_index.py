import os
import json
import faiss
import numpy as np
from huggingface_api import get_embeddings

DATA_DIR = "data"
PROFILES_FILE = os.path.join(DATA_DIR, "profiles.json")
FAISS_DIR = "faiss_index"
INDEX_FILE = os.path.join(FAISS_DIR, "profiles.index")

os.makedirs(FAISS_DIR, exist_ok=True)

def build_index():
    """Builds FAISS index from profiles.json"""
    if not os.path.exists(PROFILES_FILE):
        raise FileNotFoundError(f"Profiles file not found: {PROFILES_FILE}")

    with open(PROFILES_FILE, "r", encoding="utf-8") as f:
        profiles = json.load(f)

    if not profiles:
        raise ValueError("No profiles found in profiles.json")

    vectors = []
    ids = []

    print(f"Building FAISS index for {len(profiles)} profiles...")

    for profile in profiles:
        try:
            text = f"{profile.get('name', '')} {profile.get('bio', '')} {profile.get('education', '')} {profile.get('religion', '')}"
            embedding = get_embeddings(text)
            vectors.append(embedding)
            ids.append(profile["id"])
        except Exception as e:
            print(f"⚠ Skipping profile {profile.get('id', 'UNKNOWN')} due to error: {e}")

    if not vectors:
        raise ValueError("No valid embeddings generated for FAISS index.")

    vectors = np.array(vectors).astype("float32")
    index = faiss.IndexFlatL2(vectors.shape[1])
    index.add(vectors)

    faiss.write_index(index, INDEX_FILE)

    print(f"✅ FAISS index saved at {INDEX_FILE} with {len(ids)} entries.")

if __name__ == "__main__":
    build_index()
