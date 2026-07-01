import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../models/user_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  GoSaferUser? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _authService.getCurrentUserData();
      if (mounted) {
        setState(() {
          _userData = user;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLogout() async {
    await _authService.signOut();
    // AuthWrapper will handle navigation
  }

  Future<void> _showAddContactDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Mom')),
            const SizedBox(height: 8),
            TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              if (nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
                String formattedPhone = phoneController.text.trim();
                if (!formattedPhone.startsWith('+91')) {
                  if (formattedPhone.startsWith('91') && formattedPhone.length == 12) {
                    formattedPhone = '+$formattedPhone';
                  } else {
                    formattedPhone = '+91 $formattedPhone';
                  }
                }
                
                final newContact = EmergencyContact(name: nameController.text.trim(), phone: formattedPhone);
                try {
                  await _authService.addEmergencyContact(newContact);
                  if (!context.mounted) return;
                  setState(() {
                     _userData?.emergencyContacts.add(newContact);
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact Added'), backgroundColor: Colors.green));
                } catch(e) {
                   if (!context.mounted) return;
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showUpdateContactDialog(int index, EmergencyContact contact) async {
    final nameController = TextEditingController(text: contact.name);
    final phoneController = TextEditingController(text: contact.phone);
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Emergency Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController, 
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Mom'),
              enabled: false, // Keep name read-only for now as requested for phone number update
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController, 
              decoration: const InputDecoration(labelText: 'Phone'), 
              keyboardType: TextInputType.phone
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              if (phoneController.text.isNotEmpty) {
                String formattedPhone = phoneController.text.trim();
                if (!formattedPhone.startsWith('+91')) {
                  if (formattedPhone.startsWith('91') && formattedPhone.length == 12) {
                    formattedPhone = '+$formattedPhone';
                  } else {
                    formattedPhone = '+91 $formattedPhone';
                  }
                }
                
                final updatedContact = EmergencyContact(name: contact.name, phone: formattedPhone);
                try {
                  List<EmergencyContact> updatedList = List.from(_userData!.emergencyContacts);
                  updatedList[index] = updatedContact;
                  
                  await _authService.updateEmergencyContacts(updatedList);
                  
                  if (!context.mounted) return;
                  setState(() {
                     _userData?.emergencyContacts[index] = updatedContact;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact Updated'), backgroundColor: Colors.green));
                } catch(e) {
                   if (!context.mounted) return;
                   ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Update', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? AppColors.borderDark : const Color(0xFFFFF7ED), 
              shape: BoxShape.circle
            ),
            child: const Icon(Icons.arrow_back, color: AppColors.primary, size: 20),
          ),
          onPressed: () {},
        ),
        title: Text('Profile', style: TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => themeProvider.toggleTheme(),
            icon: Icon(
              themeProvider.isDarkMode ? Icons.dark_mode : Icons.wb_sunny_outlined,
              color: theme.colorScheme.onSurface,
            ),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: theme.colorScheme.onSurface), 
            onPressed: _handleLogout
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Center(
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.1), width: 4),
                        image: const DecorationImage(
                          image: NetworkImage('https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?q=80&w=120&h=120&auto=format&fit=crop'),
                          fit: BoxFit.cover,
                        ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.edit, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(_userData?.fullName ?? 'Anonymous User', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(_userData?.email ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                   Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Emergency Contacts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      TextButton.icon(
                        onPressed: _showAddContactDialog,
                        icon: const Icon(Icons.add_circle, size: 18),
                        label: const Text('Add New', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_userData?.emergencyContacts.isEmpty ?? true)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No emergency contacts added', style: TextStyle(color: Colors.grey)),
                    )
                  else
                    ..._userData!.emergencyContacts.asMap().entries.map((entry) {
                      int index = entry.key;
                      EmergencyContact contact = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildContactItem(index, contact),
                      );
                    }),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildContactItem(int index, EmergencyContact contact) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? AppColors.borderDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFF1F5F9),
            child: Icon(Icons.person, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(contact.phone, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _showUpdateContactDialog(index, contact),
            icon: const Icon(Icons.edit, color: AppColors.textHint, size: 20),
            tooltip: 'Edit Contact',
          ),
        ],
      ),
    );
  }
}
