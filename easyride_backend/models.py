from geoalchemy2 import Geometry
from sqlalchemy import Column, DateTime, Float, Integer, String, func

from database import Base


class TelemetryData(Base):
    __tablename__ = "telemetry"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(String, nullable=False, index=True)
    # GEOMETRY: POINT (pothole) or LINESTRING (rough_road segment)
    location = Column(Geometry("GEOMETRY", srid=4326), nullable=False)
    speed_kmh = Column(Float, nullable=False)
    bump_force = Column(Float, nullable=False)
    defect_type = Column(String, nullable=False, default="pothole", server_default="pothole")
    infrastructure_type = Column(
        String, nullable=False, default="road", server_default="road"
    )
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
