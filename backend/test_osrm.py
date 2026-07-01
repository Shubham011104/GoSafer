import requests
import json

def decode_polyline(polyline_str, precision=5):
    """Decodes a polyline string with given precision."""
    index, lat, lng = 0, 0, 0
    coordinates = []
    factor = 10 ** precision
    while index < len(polyline_str):
        b, shift, result = 0, 0, 0
        while True:
            b = ord(polyline_str[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20: break
        lat += ~(result >> 1) if (result & 1) else (result >> 1)
        
        shift, result = 0, 0
        while True:
            b = ord(polyline_str[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20: break
        lng += ~(result >> 1) if (result & 1) else (result >> 1)
        coordinates.append((lat / factor, lng / factor))
    return coordinates

def test_osrm_alternatives():
    # Warje to Kothrud (Pune)
    olat, olng = 18.487348, 73.793274
    dlat, dlng = 18.507135, 73.805098
    
    for alt_val in ["true", "3"]:
        url = f"http://router.project-osrm.org/route/v1/driving/{olng},{olat};{dlng},{dlat}?overview=full&geometries=polyline&alternatives={alt_val}"
        print(f"\nTesting with alternatives={alt_val}...")
        try:
            response = requests.get(url, timeout=10)
            data = response.json()
            if data['code'] == 'Ok':
                routes = data.get('routes', [])
                print(f"Found {len(routes)} routes.")
                for i, r in enumerate(routes):
                    print(f"  Route {i}: dist={r['distance']}m, dur={r['duration']}s")
            else:
                print(f"OSRM Error: {data['code']}")
        except Exception as e:
            print(f"Request failed: {e}")

if __name__ == "__main__":
    test_osrm_alternatives()
