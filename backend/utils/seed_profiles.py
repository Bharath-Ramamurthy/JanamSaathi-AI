# utils/seed_profiles.py
import json, os
from core.database import engine, SessionLocal, Base
from models import SignupRequest

BASE = os.path.dirname(os.path.dirname(__file__))
JSON_PATH = os.path.join(BASE, "data", "profiles.json")
print(JSON_PATH)

def seed():
    Base.metadata.create_all(bind=engine)  # safe no-ops if tables exist
    session = SessionLocal()
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        profiles = json.load(f)

    inserted = 0
    for p in profiles:
        try:

            validated = SignupRequest.model_validate(p)


        except Exception as e:
            print("Skipping invalid:", p.get("user_name"), e)
            continue
        exists = session.query(db_models.User).filter(db_models.User.user_name.ilike(validated.user_name)).first()
        if exists:
            print("Exists:", validated.user_name); continue
        user = db_models.User(
            user_name=validated.user_name,
            gender=validated.gender,
            dob=validated.dob,
            place_of_birth=validated.place_of_birth,
            education=validated.education,
            salary=validated.salary,
            religion=validated.religion,
            caste=validated.caste,
            color=validated.color or None,
            photo_url=validated.photo_url,
            preferences = validated.preferences.model_dump() if validated.preferences else {}
        )
        session.add(user)
        inserted += 1
    session.commit()
    session.close()
    print("Inserted:", inserted)

if __name__ == "__main__":
    seed()
