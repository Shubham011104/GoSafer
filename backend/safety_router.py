from datetime import datetime

class SafetyRouter:
    def __init__(self, crime_engine):
        self.crime_engine = crime_engine

    def is_night_time(self):
        hour = datetime.now().hour
        return hour >= 20 or hour < 6

    def evaluate_route(self, polyline):
        """
        Calculates a safety score for a given polyline (list of [lat, lng]).
        Returns risk score and whether night mode was applied.
        """
        if not polyline: return 1.0, self.is_night_time()
        
        total_risk = 0
        samples = 0
        
        # Sample every few points to avoid heavy computation
        for i in range(0, len(polyline), 3):
            lat, lng = polyline[i]
            total_risk += self.crime_engine.get_risk_at(lat, lng)
            samples += 1
            
        base_risk = total_risk / samples if samples > 0 else 2.0
        
        is_night = self.is_night_time()
        final_risk = base_risk * (1.6 if is_night else 1.0)
        
        return round(final_risk, 2), is_night

    def get_safe_waypoint(self, olat, olng, dlat, dlng):
        """
        Calculates a waypoint shifted away from the direct line 
        towards a safer zone if possible.
        """
        mid_lat = (olat + dlat) / 2
        mid_lng = (olng + dlng) / 2
        
        # Find all safe centroids (Risk 1-2)
        safe_centroids = [c for c in self.crime_engine.centroids if c['risk_score'] <= 2]
        
        if not safe_centroids:
            # If no safe zones available, add a generic jitter (0.01 degree ~1.1km)
            return mid_lat + 0.01, mid_lng + 0.01
        
        # Pick the safe centroid that is geographically closest to our trip's midpoint
        best_safe = min(safe_centroids, key=lambda c: (c['lat']-mid_lat)**2 + (c['lng']-mid_lng)**2)
        
        # We want to pull the route TOWARDS this safe centroid
        # But not go exactly TO it (may be too far). 
        # Aim for a point 50% between midpoint and safe centroid
        way_lat = (mid_lat + best_safe['lat']) / 2
        way_lng = (mid_lng + best_safe['lng']) / 2
        
        return round(way_lat, 6), round(way_lng, 6)

