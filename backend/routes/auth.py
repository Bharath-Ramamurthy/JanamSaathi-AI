# routes/auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from schemas import SignupRequest, LoginRequest
from utils.profile_utils import add_profile, find_profile_by_id, find_profile_by_email_id
from core.security import create_access_token, create_refresh_token, hash_password, verify_password
from .deps import get_db, get_user_id, get_user_id_from_refresh


router = APIRouter(tags=["Authentication"])



@router.post("/signup", status_code=201)
async def signup(req: SignupRequest, db: Session = Depends(get_db)):
    profile_data = req.dict()

    # check uniqueness by username or email
    if find_profile_by_email_id(db, profile_data["email_id"]):
        raise HTTPException(status_code=400, detail="Email already registered")

    if "password" not in profile_data or not profile_data["password"]:
        raise HTTPException(status_code=400, detail="Password required")

    profile_data["password"] = hash_password(profile_data.pop("password"))
    profile_data["photo_url"] = (
        f"/static/photos/{profile_data['user_name'].split()[0].lower()}.jpg"
    )

    added_user = add_profile(db, profile_data)  # pass db explicitly

    access = create_access_token(str(added_user["id"]))
    refresh = create_refresh_token(str(added_user["id"]))

    return {
        "status": "User profile created",
        "access_token": access,
        "refresh_token": refresh,
    }


@router.post("/login")
async def login(req: LoginRequest, db: Session = Depends(get_db)):
    profile = find_profile_by_email_id(db, req.email_id)

    if not profile:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not verify_password(req.password, profile.password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    access = create_access_token(str(profile.id))
    refresh = create_refresh_token(str(profile.id))

    return {
        "access_token": access,
        "refresh_token": refresh,
        "user": {
            "id": profile.id,
            "user_name": profile.user_name,
            "email_id": profile.email_id,
            "photo_url": profile.photo_url,
            "gender": profile.gender,
        }
    }


@router.post("/refresh")
async def refresh_token(user_id: str = Depends(get_user_id_from_refresh)):
    access = create_access_token(user_id)
    new_refresh = create_refresh_token(user_id)
    return {"access_token": access, "refresh_token": new_refresh}


@router.get("/me")
async def me(user_id: str = Depends(get_user_id)):
    return {"profile": {"id": user_id}}