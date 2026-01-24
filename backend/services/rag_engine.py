# services/rag_engine.py
import faiss
import numpy as np
from sentence_transformers import SentenceTransformer
from core.config import get_settings
from typing import List, Dict, Union, Optional

settings = get_settings()
embedding_dim = 384
_faiss_index: Optional[faiss.IndexFlatL2] = None
_profile_map: Dict[int, Dict] = {}
_model = SentenceTransformer("all-MiniLM-L6-v2", use_auth_token=settings.HUGGINGFACE_HUB_TOKEN)


def initialize_faiss() -> None:
    """
    Initialize a new FAISS index and clear the profile map.
    """
    global _faiss_index, _profile_map
    _faiss_index = faiss.IndexFlatL2(embedding_dim)
    _profile_map = {}


def create_embedding(text: str) -> np.ndarray:
    """
    Encode text into an embedding vector.
    """
    emb = _model.encode(text, convert_to_numpy=True)
    return np.asarray(emb, dtype=np.float32)


def rebuild_faiss(profiles: List[Union[dict, object]]) -> None:
    """
    Rebuild the FAISS index from scratch using the given list of profiles.
    """
    initialize_faiss()  # clear existing index and map

    for profile in profiles:
        profile_dict = profile.dict() if hasattr(profile, "dict") else profile
        prefs = profile_dict.get("preferences") or {}
        text = " | ".join(f"{k}: {v}" for k, v in prefs.items() if v)
        if not text:
            continue
        vec = create_embedding(text).reshape(1, -1)
        _faiss_index.add(vec)
        idx = _faiss_index.ntotal - 1
        _profile_map[idx] = profile_dict


def get_best_matches(profile: Union[dict, object], top_k: int = 3) -> List[dict]:
    """
    Query the FAISS index to get the top_k most similar profiles.
    """
    if not profile:
        return []

    profile_dict = profile.dict() if hasattr(profile, "dict") else profile
    prefs = profile_dict.get("preferences") or {}
    text = " | ".join(f"{k}: {v}" for k, v in prefs.items() if v)

    if not text or _faiss_index is None or _faiss_index.ntotal == 0:
        return []

    query_vec = create_embedding(text).reshape(1, -1)
    distances, indices = _faiss_index.search(query_vec, min(top_k, _faiss_index.ntotal))
    matches = [_profile_map[i] for i in indices[0] if i in _profile_map]

    return matches
