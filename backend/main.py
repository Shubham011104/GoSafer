import os
import requests
from fastapi import FastAPI, Body, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import math
from dotenv import load_dotenv
import firebase_admin
from firebase_admin import credentials, firestore, messaging
from crime_engine import CrimeEngine
from safety_router import SafetyRouter

# Load environment variables
load_dotenv()

# Initialize Firebase Admin
try:
    cred_path = os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", "service-account-key.json")
    if os.path.exists(cred_path):
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("Firebase Admin initialized successfully.")
    else:
        db = None
        print(f"Warning: Firebase credentials not found at {cred_path}")
except Exception as e:
    db = None
    print(f"Error initializing Firebase: {e}")

app = FastAPI(title="GoSafer AI Backend")

# Enable CORS for Flutter Web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize engines
DATASET_PATH = os.path.join("..", "assets", "data", "pune_crime_dummy_dataset.csv")
crime_engine = CrimeEngine(DATASET_PATH)
safety_router = SafetyRouter(crime_engine)

@app.get("/health")
def health_check():
    return {"status": "ok", "engine_ready": crime_engine.crime_data is not None}

@app.get("/crime/centroids")
def get_centroids():
    return crime_engine.centroids

@app.get("/crime/heatmap")
def get_heatmap():
    return crime_engine.get_heatmap_data()

@app.post("/route/evaluate")
def evaluate_route(polyline: list = Body(...)):
    risk_score, is_night = safety_router.evaluate_route(polyline)
    return {
        "risk_score": risk_score,
        "is_night_mode": is_night
    }

# --- OpenStreetMap (Nominatim) Places API ---

def fetch_nominatim_suggestions(query: str):
    """Search using OpenStreetMap (Nominatim) — no API key needed."""
    url = f"https://nominatim.openstreetmap.org/search?q={query},Pune&format=json&addressdetails=1&limit=5"
    headers = {"User-Agent": "GoSafer-App-Demo"}
    try:
        response = requests.get(url, headers=headers)
        data = response.json()
        predictions = []
        for item in data:
            osm_id = f"osm_{item['lat']}_{item['lon']}"
            predictions.append({
                "place_id": osm_id,
                "description": item['display_name'],
                "structured_formatting": {
                    "main_text": item['display_name'].split(',')[0],
                    "secondary_text": ", ".join(item['display_name'].split(',')[1:3]).strip()
                }
            })
        return predictions
    except Exception as e:
        print(f"Nominatim Error: {e}")
        return []

@app.get("/places/autocomplete")
def autocomplete(input: str):
    """Uses Nominatim directly — no Google API key required."""
    predictions = fetch_nominatim_suggestions(input)
    return {"status": "OK", "predictions": predictions}

# --- OSRM Directions API (translated to Google JSON format) ---

def _format_distance(meters: float) -> str:
    if meters < 1000:
        return f"{int(meters)} m"
    return f"{meters / 1000:.1f} km"

def _format_duration(seconds: float) -> str:
    mins = int(seconds / 60)
    if mins < 60:
        return f"{mins} mins"
    hours = mins // 60
    rem = mins % 60
    return f"{hours} hour{'s' if hours > 1 else ''} {rem} mins"

def _osrm_to_google_format(osrm_data: dict) -> dict:
    """Convert OSRM response into Google Directions JSON structure."""
    if osrm_data.get("code") != "Ok":
        return {"status": "ZERO_RESULTS", "routes": []}

    google_routes = []
    for route in osrm_data.get("routes", []):
        distance_m = route["distance"]
        duration_s = route["duration"]
        encoded_poly = route["geometry"]  # OSRM returns encoded polyline

        google_routes.append({
            "overview_polyline": {"points": encoded_poly},
            "legs": [{
                "distance": {"value": int(distance_m), "text": _format_distance(distance_m)},
                "duration": {"value": int(duration_s), "text": _format_duration(duration_s)},
                "start_location": {},
                "end_location": {},
            }],
            "summary": route.get("legs", [{}])[0].get("summary", "") if route.get("legs") else "",
        })

    return {"status": "OK", "routes": google_routes}

def _fetch_osrm_route(origin: str, destination: str, waypoint: str = None) -> dict:
    """Helper to fetch a single path from OSRM, optionally via a waypoint."""
    # Split "lat,lng"
    olat, olng = origin.split(",")
    dlat, dlng = destination.split(",")
    
    if waypoint:
        wlat, wlng = waypoint.split(",")
        coords = f"{olng},{olat};{wlng},{wlat};{dlng},{dlat}"
    else:
        coords = f"{olng},{olat};{dlng},{dlat}"
        
    osrm_url = f"http://router.project-osrm.org/route/v1/driving/{coords}?overview=full&geometries=polyline"
    
    try:
        response = requests.get(osrm_url, timeout=10)
        return response.json()
    except Exception as e:
        print(f"OSRM Error for {coords}: {e}")
        return {"code": "Error", "routes": []}

@app.get("/directions/json")
def get_directions(origin: str, destination: str, alternatives: bool = False):
    """
    Fetch routes from OSRM. 
    If OSRM provides only one, we manually generate alternatives via waypoints.
    """
    # 1. Get Primary (Fastest) Route
    primary_data = _fetch_osrm_route(origin, destination)
    
    if primary_data.get("code") != "Ok":
        return {"status": "ZERO_RESULTS", "routes": []}
    
    routes = primary_data.get("routes", [])
    
    # 2. If alternatives requested but OSRM was stingy, force extra paths
    if alternatives and len(routes) < 3:
        try:
            olat, olng = map(float, origin.split(","))
            dlat, dlng = map(float, destination.split(","))
            
            # Safe Waypoint Path
            safe_way = safety_router.get_safe_waypoint(olat, olng, dlat, dlng)
            safe_data = _fetch_osrm_route(origin, destination, waypoint=f"{safe_way[0]},{safe_way[1]}")
            if safe_data.get("code") == "Ok":
                routes.extend(safe_data.get("routes", []))
                
            # If still short, add a "Jittered" path (midpoint shifted 0.005 ~500m)
            if len(routes) < 3:
                mid_lat = (olat + dlat) / 2 + 0.005
                mid_lng = (olng + dlng) / 2 - 0.005
                jitter_data = _fetch_osrm_route(origin, destination, waypoint=f"{mid_lat},{mid_lng}")
                if jitter_data.get("code") == "Ok":
                    routes.extend(jitter_data.get("routes", []))
        except Exception as e:
            print(f"Waypoint calculation error: {e}")

    # Remove duplicates based on polyline
    unique_routes = []
    seen_polys = set()
    for r in routes:
        p = r.get("geometry")
        if p not in seen_polys:
            unique_routes.append(r)
            seen_polys.add(p)

    # Slice to 3 Max for Flutter
    final_osrm_data = {"code": "Ok", "routes": unique_routes[:3]}
    return _osrm_to_google_format(final_osrm_data)


@app.get("/places/details")
def place_details(place_id: str):
    """Resolve a place_id to lat/lng. Supports Nominatim osm_LAT_LNG ids."""
    if place_id.startswith("osm_"):
        try:
            parts = place_id.split('_')
            lat = float(parts[1])
            lon = float(parts[2])
            return {
                "status": "OK",
                "result": {
                    "geometry": {
                        "location": {"lat": lat, "lng": lon}
                    }
                }
            }
        except Exception:
            raise HTTPException(status_code=400, detail="Invalid osm place_id format")

    raise HTTPException(status_code=400, detail="Only Nominatim (osm_*) place IDs are supported")

def haversine(lat1, lon1, lat2, lon2):
    """Calculate the great-circle distance between two points in km."""
    R = 6371  # Earth radius in km
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (math.sin(d_lat / 2) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(d_lon / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return R * c

@app.post("/sos/trigger")
def trigger_sos(data: dict = Body(...)):
    """
    Handles SOS trigger:
    1. Finds users within 5km radius.
    2. Sends FCM notifications to them.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Firebase not initialized")

    caller_uid = data.get("uid")
    caller_name = data.get("fullName", "A user")
    lat = data.get("latitude")
    lng = data.get("longitude")

    if lat is None or lng is None:
        raise HTTPException(status_code=400, detail="Location required")

    try:
        # 1. Fetch all users with valid location and fcmToken
        users_ref = db.collection("users")
        docs = users_ref.stream()
        
        nearby_tokens = []
        user_count = 0
        match_count = 0

        for doc in docs:
            user_count += 1
            u_data = doc.to_dict()
            u_lat = u_data.get("latitude")
            u_lng = u_data.get("longitude")
            u_token = u_data.get("fcmToken")
            u_uid = doc.id

            if u_uid == caller_uid:
                continue
                
            if not u_token:
                print(f"User {u_uid} has no FCM token. Skipping.")
                continue
                
            if u_lat is None or u_lng is None:
                print(f"User {u_uid} has no location. Skipping.")
                continue

            distance = haversine(lat, lng, u_lat, u_lng)
            print(f"User {u_uid} is {distance:.2f} km away.")
            
            if distance <= 5.0: # 5km radius
                nearby_tokens.append(u_token)
                match_count += 1

        print(f"SOS Trigger: Found {user_count} total users, {match_count} within 5km.")

        # 2. Send Multicast Notification
        if nearby_tokens:
            print(f"Sending notifications to {len(nearby_tokens)} tokens...")
            message = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title="🚨 EMERGENCY NEARBY",
                    body=f"{caller_name} needs help within 5km of your location!",
                ),
                data={
                    "type": "SOS_ALERT",
                    "latitude": str(lat),
                    "longitude": str(lng),
                    "caller_name": caller_name,
                    "victim_uid": str(caller_uid)
                },
                tokens=nearby_tokens,
            )
            response = messaging.send_each_for_multicast(message)
            print(f"Successfully sent {response.success_count} messages. Failures: {response.failure_count}")
            
            if response.failure_count > 0:
                for idx, res in enumerate(response.responses):
                    if not res.success:
                        print(f"Token {idx} failed: {res.exception}")

            return {
                "status": "success",
                "notified_count": response.success_count,
                "total_nearby": len(nearby_tokens)
            }
        
        return {"status": "success", "notified_count": 0, "message": "No nearby users found"}

    except Exception as e:
        print(f"SOS Trigger Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/sos/respond")
def respond_sos(data: dict = Body(...)):
    """
    Handles SOS response:
    1. Notifies the victim that a specific user is on their way.
    """
    if db is None:
        raise HTTPException(status_code=500, detail="Firebase not initialized")

    victim_uid = data.get("victim_uid")
    responder_name = data.get("responder_name", "Someone")

    if not victim_uid:
        raise HTTPException(status_code=400, detail="Victim UID required")

    try:
        # 1. Fetch Victim data to get FCM token
        victim_doc = db.collection("users").document(victim_uid).get()
        if not victim_doc.exists:
            raise HTTPException(status_code=404, detail="Victim not found")

        victim_data = victim_doc.to_dict()
        victim_token = victim_data.get("fcmToken")

        if not victim_token:
            return {"status": "error", "message": "Victim has no FCM token"}

        # 2. Send Notification to Victim
        message = messaging.Message(
            notification=messaging.Notification(
                title="🙌 HELP IS COMING",
                body=f"{responder_name} is on their way to your location!",
            ),
            data={
                "type": "SOS_RESPONSE",
                "responder_name": responder_name,
            },
            token=victim_token,
        )
        
        response = messaging.send(message)
        print(f"SOS Response Sent: {response}")

        return {"status": "success", "message": "Notification sent to victim"}

    except Exception as e:
        print(f"SOS Response Error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
