# routes/rag_faiss.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .deps import get_db, get_user_id
from utils.profile_utils import load_profiles, find_profile_by_id
from services.rag_engine import get_best_matches, rebuild_faiss
from models import User
from schemas import MatchResponse, UserOut  # adjust import if needed

router = APIRouter(tags=["Matchmaking"])


@router.get("/recommend", response_model=MatchResponse)
async def recommend_matches(
    db: Session = Depends(get_db),
    user_id: str = Depends(get_user_id),
):
    """
    Recommend top matching profiles for the authenticated user.
    Extracts user_id from JWT, finds the profile, and uses FAISS for similarity search.
    """

    # Step 1: Get profile of the logged-in user
    user_obj = find_profile_by_id(db, user_id)
    if not user_obj:
        raise HTTPException(status_code=404, detail="User profile not found")

    user_profile = UserOut.model_validate(user_obj)

    print("DEBUG: user exists?", user_profile, flush=True)
    if not user_profile:
        raise HTTPException(status_code=404, detail="User profile not found")

    # Step 2: Load all profiles from DB
    profiles = load_profiles(db)

    # Step 3: Filter eligible profiles (e.g., opposite gender)
    eligible_profiles = []
    for profile in profiles:
        if not profile.gender:
            print(f"Skipping profile without gender: {profile.user_name}")
            continue

        if user_profile.gender and profile.gender.lower() == user_profile.gender.lower():
            continue  # skip same-gender profiles

        eligible_profiles.append(profile)

    # Step 4: Rebuild FAISS index with eligible profiles
    rebuild_faiss(eligible_profiles)

    # Step 5: Get top matches from FAISS
    matched_profiles = get_best_matches(user_profile.model_dump(), top_k=5)

    # Step 6: Prepare recommended profiles for response
    recommended_profiles = matched_profiles if matched_profiles else []

    return MatchResponse(recommended_profiles=recommended_profiles)
