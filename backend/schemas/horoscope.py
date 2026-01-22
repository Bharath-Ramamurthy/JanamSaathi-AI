from pydantic import BaseModel


class HoroscopeRequest(BaseModel):

    partner_id: str

    model_config = {
        "from_attributes": True
    }
