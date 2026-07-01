import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/route_service.dart';

class RouteInfoCard extends StatelessWidget {
  final RouteEvaluation route;
  final VoidCallback onStart;
  final VoidCallback onShare;

  const RouteInfoCard({
    super.key,
    required this.route,
    required this.onStart,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate safety score (inverse of risk, mapped to 0-100)
    // Risk 1 (Very Safe) -> 98%
    // Risk 5 (High Crime) -> 40%
    int safetyPercentage = (110 - (route.riskScore * 15)).toInt().clamp(30, 99);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'RECOMMENDED SAFE ROUTE',
                      style: TextStyle(
                        fontSize: 10, 
                        fontWeight: FontWeight.bold, 
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${route.durationText} • ${route.distanceText}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user, color: AppColors.success, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '$safetyPercentage% Safe',
                          style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (route.isNightModeActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.nightlight_round, size: 12, color: Colors.indigo.shade400),
                          const SizedBox(width: 4),
                          Text(
                            'Night Mode Active',
                            style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation_outlined, color: Colors.white),
                  label: const Text('Start Navigation'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onShare,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
