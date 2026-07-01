import pandas as pd
import numpy as np
from sklearn.cluster import KMeans
import os

class CrimeEngine:
    def __init__(self, csv_path):
        self.csv_path = csv_path
        self.crime_data = None
        self.centroids = []
        self._load_data()

    def _load_data(self):
        if not os.path.exists(self.csv_path):
            print(f"Dataset not found at {self.csv_path}")
            return
        
        # Load dataset
        df = pd.read_csv(self.csv_path)
        
        # We need Latitude, Longitude, and Total Crime
        # Based on previous inspection, indices were around 9, 10, 11
        # In Pandas we'll use column names or indices
        # Let's assume the columns are: 'LocationName', ..., 'TotalCrime', 'Longitude', 'Latitude'
        # Adjust indices based on the actual CSV structure found earlier
        
        # Mocking the column extraction since we know the structure from Dart implementation:
        # row[9] = totalCrime, row[10] = lng, row[11] = lat
        
        self.crime_data = df.iloc[:, [11, 10, 9]] # Lat, Lng, Total
        self.crime_data.columns = ['lat', 'lng', 'total_crime']
        
        self._perform_clustering()

    def _perform_clustering(self):
        if self.crime_data is None: return
        
        # K-Means Clustering on Lat/Lng
        coords = self.crime_data[['lat', 'lng']]
        kmeans = KMeans(n_clusters=5, random_state=42, n_init=10).fit(coords)
        
        self.crime_data['cluster'] = kmeans.labels_
        
        # Calculate risk score (1-5) for each cluster based on avg crime volume
        cluster_stats = self.crime_data.groupby('cluster')['total_crime'].mean().sort_values()
        risk_map = {cluster: rank + 1 for rank, cluster in enumerate(cluster_stats.index)}
        
        self.centroids = []
        for i, center in enumerate(kmeans.cluster_centers_):
            self.centroids.append({
                'lat': center[0],
                'lng': center[1],
                'risk_score': risk_map[i],
                'safety_level': self._get_safety_label(risk_map[i])
            })

    def _get_safety_label(self, score):
        labels = {1: 'Very Safe', 2: 'Safe', 3: 'Moderate', 4: 'Unsafe', 5: 'High Crime'}
        return labels.get(score, 'Safe')

    def get_risk_at(self, lat, lng):
        if not self.centroids: return 2
        
        # Nearest centroid risk
        distances = [((lat - c['lat'])**2 + (lng - c['lng'])**2) for c in self.centroids]
        closest_idx = np.argmin(distances)
        return self.centroids[closest_idx]['risk_score']

    def get_heatmap_data(self):
        return self.crime_data[['lat', 'lng', 'total_crime']].to_dict('records')
