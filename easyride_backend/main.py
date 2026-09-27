from typing import Literal

import httpx
from fastapi import Depends, FastAPI, HTTPException
from geoalchemy2.elements import WKTElement
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.orm import Session

from database import Base, engine, get_db
from models import TelemetryData

app = FastAPI(title="EasyRide MVP API")

MIN_SPEED_KMH = 20.0
BASE_SPEED_KMH = 20.0
OSRM_BASE = "https://router.project-osrm.org"
OSRM_TIMEOUT = 5.0
CLUSTER_EPS_DEG = 0.0003


class TrajectoryPoint(BaseModel):
    lat: float
    lon: float
    timestamp: float


class TelemetryPayload(BaseModel):
    user_id: str
    latitude: float
    longitude: float
    speed_kmh: float
    bump_force: float
    defect_type: Literal["pothole", "rough_road"] = "pothole"
    infrastructure_type: Literal["road", "bridge", "tunnel"] = "road"
    trajectory: list[TrajectoryPoint] = Field(default_factory=list)


@app.on_event("startup")
def on_startup() -> None:
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
    Base.metadata.create_all(bind=engine)
    _ensure_schema()


def _ensure_schema() -> None:
    """Idempotent alters for DBs created before defect columns / GEOMETRY type."""
    stmts = [
        "ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS defect_type VARCHAR DEFAULT 'pothole'",
        "ALTER TABLE telemetry ADD COLUMN IF NOT EXISTS infrastructure_type VARCHAR DEFAULT 'road'",
        """
        DO $$
        BEGIN
          IF EXISTS (
            SELECT 1 FROM information_schema.columns
            WHERE table_name = 'telemetry' AND column_name = 'location'
          ) THEN
            ALTER TABLE telemetry
              ALTER COLUMN location TYPE geometry(Geometry, 4326)
              USING location::geometry(Geometry, 4326);
          END IF;
        END $$;
        """,
    ]
    try:
        with engine.begin() as conn:
            for stmt in stmts:
                conn.execute(text(stmt))
    except Exception:
        # Fresh create_all already has correct schema; ignore race/permission noise.
        pass


def calculate_normalized_force(bump_force: float, speed_kmh: float) -> float:
    safe_speed = max(speed_kmh, BASE_SPEED_KMH)
    return bump_force * (BASE_SPEED_KMH / safe_speed)


def _osrm_nearest(lat: float, lon: float) -> tuple[float, float]:
    url = f"{OSRM_BASE}/nearest/v1/driving/{lon},{lat}"
    try:
        with httpx.Client(timeout=OSRM_TIMEOUT) as client:
            resp = client.get(url)
            resp.raise_for_status()
            data = resp.json()
        waypoints = data.get("waypoints") or []
        if data.get("code") == "Ok" and waypoints:
            snapped_lon, snapped_lat = waypoints[0]["location"]
            return float(snapped_lat), float(snapped_lon)
    except Exception:
        pass
    return lat, lon


def _coords_to_linestring_wkt(coordinates: list) -> str | None:
    if len(coordinates) < 2:
        return None
    pts = ", ".join(f"{lon} {lat}" for lon, lat in coordinates)
    return f"LINESTRING({pts})"


def _osrm_match(trajectory: list[TrajectoryPoint]) -> tuple[str, str] | None:
    """
    OSRM /match → (wkt, geom_type) or None on failure/rate-limit.
    geom_type: 'Point' | 'LineString'
    """
    coords = ";".join(f"{p.lon},{p.lat}" for p in trajectory)
    timestamps = ";".join(str(int(p.timestamp)) for p in trajectory)
    url = f"{OSRM_BASE}/match/v1/driving/{coords}"
    params = {
        "geometries": "geojson",
        "overview": "full",
        "timestamps": timestamps,
    }
    try:
        with httpx.Client(timeout=OSRM_TIMEOUT) as client:
            resp = client.get(url, params=params)
            resp.raise_for_status()
            data = resp.json()
        matchings = data.get("matchings") or []
        if data.get("code") != "Ok" or not matchings:
            return None
        geometry = matchings[0].get("geometry") or {}
        gtype = geometry.get("type")
        coordinates = geometry.get("coordinates") or []
        if gtype == "LineString":
            wkt = _coords_to_linestring_wkt(coordinates)
            if wkt:
                return wkt, "LineString"
        if gtype == "Point" and len(coordinates) >= 2:
            lon, lat = coordinates[0], coordinates[1]
            return f"POINT({lon} {lat})", "Point"
    except Exception:
        return None
    return None


def get_snapped_coordinates(
    lat: float,
    lon: float,
    trajectory: list[TrajectoryPoint] | None = None,
) -> tuple[str, str]:
    """
    Map-match trajectory when possible; fallback to /nearest on first point.
    Returns (wkt, geom_type) where geom_type is 'Point' or 'LineString'.
    """
    if trajectory and len(trajectory) > 2:
        matched = _osrm_match(trajectory)
        if matched is not None:
            return matched

    snapped_lat, snapped_lon = _osrm_nearest(lat, lon)
    return f"POINT({snapped_lon} {snapped_lat})", "Point"


def _point_wkt_from_snap(wkt: str, geom_type: str, lat: float, lon: float) -> str:
    if geom_type == "Point":
        return wkt
    if geom_type == "LineString" and wkt.startswith("LINESTRING("):
        first = wkt.removeprefix("LINESTRING(").split(",")[0].strip()
        return f"POINT({first})"
    return f"POINT({lon} {lat})"


def resolve_location_wkt(payload: TelemetryPayload) -> str:
    wkt, geom_type = get_snapped_coordinates(
        payload.latitude,
        payload.longitude,
        payload.trajectory or None,
    )
    if payload.defect_type == "rough_road" and geom_type == "LineString":
        return wkt
    return _point_wkt_from_snap(
        wkt, geom_type, payload.latitude, payload.longitude
    )


@app.get("/health")
def health(db: Session = Depends(get_db)) -> dict:
    try:
        version = db.execute(text("SELECT PostGIS_Version()")).scalar()
        return {"status": "ok", "postgis": version}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"DB unavailable: {exc}") from exc


@app.post("/api/v1/telemetry")
def receive_telemetry(
    payload: TelemetryPayload,
    db: Session = Depends(get_db),
) -> dict:
    if payload.speed_kmh < MIN_SPEED_KMH:
        raise HTTPException(status_code=400, detail="Speed too low")

    location_wkt = resolve_location_wkt(payload)
    normalized_force = calculate_normalized_force(
        payload.bump_force, payload.speed_kmh
    )

    row = TelemetryData(
        user_id=payload.user_id,
        location=WKTElement(location_wkt, srid=4326),
        speed_kmh=payload.speed_kmh,
        bump_force=normalized_force,
        defect_type=payload.defect_type,
        infrastructure_type=payload.infrastructure_type,
    )
    try:
        db.add(row)
        db.commit()
        db.refresh(row)
    except Exception as exc:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    # Response keeps snapped_lat/lon for POINT; for LINESTRING use centroid.
    centroid = db.execute(
        text("SELECT ST_Y(ST_Centroid(location)), ST_X(ST_Centroid(location)) "
             "FROM telemetry WHERE id = :id"),
        {"id": row.id},
    ).one()
    snapped_lat, snapped_lon = float(centroid[0]), float(centroid[1])

    return {
        "status": "ok",
        "id": row.id,
        "snapped_lat": snapped_lat,
        "snapped_lon": snapped_lon,
        "bump_force": normalized_force,
        "defect_type": payload.defect_type,
        "infrastructure_type": payload.infrastructure_type,
        "geometry_type": "LineString"
        if location_wkt.startswith("LINESTRING")
        else "Point",
    }


@app.get("/api/v1/telemetry")
def get_telemetry(db: Session = Depends(get_db)) -> list[dict]:
    """
    Pothole POINTs → ClusterDBSCAN + centroid.
    rough_road (incl. LINESTRING) → each row as-is via ST_Centroid, no clustering.
    """
    pothole_sql = text(
        """
        WITH points AS (
          SELECT user_id, location, bump_force, infrastructure_type
          FROM telemetry
          WHERE defect_type = 'pothole'
        ),
        clustered AS (
          SELECT
            ST_ClusterDBSCAN(location, :eps, 1) OVER () AS cluster_id,
            user_id,
            location,
            bump_force,
            infrastructure_type
          FROM points
        )
        SELECT
          cluster_id,
          ST_Y(ST_Centroid(ST_Collect(location))) AS lat,
          ST_X(ST_Centroid(ST_Collect(location))) AS lon,
          MAX(bump_force) AS max_force,
          COUNT(DISTINCT user_id)::int AS unique_users,
          COUNT(*)::int AS total_hits,
          'pothole' AS defect_type,
          MAX(infrastructure_type) AS infrastructure_type
        FROM clustered
        WHERE cluster_id IS NOT NULL
        GROUP BY cluster_id
        """
    )
    rough_sql = text(
        """
        SELECT
          id AS cluster_id,
          ST_Y(ST_Centroid(location)) AS lat,
          ST_X(ST_Centroid(location)) AS lon,
          bump_force AS max_force,
          1 AS unique_users,
          1 AS total_hits,
          defect_type,
          infrastructure_type
        FROM telemetry
        WHERE defect_type = 'rough_road'
        """
    )

    results: list[dict] = []
    try:
        for row in db.execute(pothole_sql, {"eps": CLUSTER_EPS_DEG}):
            unique_users = int(row.unique_users)
            total_hits = int(row.total_hits)
            results.append(
                {
                    "cluster_id": int(row.cluster_id),
                    "lat": float(row.lat),
                    "lon": float(row.lon),
                    "max_force": float(row.max_force),
                    "unique_users": unique_users,
                    "total_hits": total_hits,
                    "is_confirmed": unique_users >= 2 or total_hits >= 3,
                    "defect_type": row.defect_type,
                    "infrastructure_type": row.infrastructure_type,
                }
            )

        # Offset rough_road ids so they never collide with DBSCAN cluster_id space.
        offset = 1_000_000
        for row in db.execute(rough_sql):
            results.append(
                {
                    "cluster_id": offset + int(row.cluster_id),
                    "lat": float(row.lat),
                    "lon": float(row.lon),
                    "max_force": float(row.max_force),
                    "unique_users": int(row.unique_users),
                    "total_hits": int(row.total_hits),
                    "is_confirmed": False,
                    "defect_type": row.defect_type,
                    "infrastructure_type": row.infrastructure_type,
                }
            )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    return results
