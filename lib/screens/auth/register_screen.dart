import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../services/auth_service.dart';
import '../../models/user_model.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onToggle;
  const RegisterScreen({super.key, required this.onToggle});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  
  final List<TextEditingController> _contactNameControllers = [];
  final List<TextEditingController> _contactPhoneControllers = [];
  
  bool _isLoading = false;
  bool _agreeToTerms = false;

  @override
  void initState() {
    super.initState();
    _addContactField(); // Add one initial contact field
  }

  void _addContactField() {
    setState(() {
      _contactNameControllers.add(TextEditingController());
      _contactPhoneControllers.add(TextEditingController());
    });
  }

  void _removeContactField(int index) {
    if (_contactNameControllers.length > 1) {
      setState(() {
        _contactNameControllers[index].dispose();
        _contactPhoneControllers[index].dispose();
        _contactNameControllers.removeAt(index);
        _contactPhoneControllers.removeAt(index);
      });
    }
  }

  String _sanitizePhoneNumber(String raw) {
    // Remove all non-digit characters
    String digits = raw.replaceAll(RegExp(r'\D'), '');
    
    // If it's a 10-digit Indian number, prepend +91
    if (digits.length == 10) {
      return '+91$digits';
    }
    
    // If it's 12 digits and starts with 91, prepend +
    if (digits.length == 12 && digits.startsWith('91')) {
      return '+$digits';
    }
    
    // Fallback or if already prefixed (ensure it has +)
    if (digits.isNotEmpty && !raw.startsWith('+')) {
      return '+$digits';
    }
    
    return raw;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    for (var c in _contactNameControllers) {
      c.dispose();
    }
    for (var c in _contactPhoneControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Terms of Service')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      List<EmergencyContact> contacts = [];
      for (int i = 0; i < _contactNameControllers.length; i++) {
        if (_contactNameControllers[i].text.isNotEmpty) {
          contacts.add(EmergencyContact(
            name: _contactNameControllers[i].text,
            phone: _contactPhoneControllers[i].text,
          ));
        }
      }

      await _authService.register(
        fullName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
        phone: _sanitizePhoneNumber(_phoneController.text),
        emergencyContacts: contacts.map((c) => EmergencyContact(
          name: c.name,
          phone: _sanitizePhoneNumber(c.phone),
        )).toList(),
      );
      
      // Success! AuthWrapper will detect the change and show the Map screen 
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Registration Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? const Color(0xFF221610) : const Color(0xFFF8F6F6),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Create Account',
          style: GoogleFonts.publicSans(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Hero Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.shield, color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                'Join GoSafer',
                style: GoogleFonts.publicSans(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your details to stay protected',
                style: GoogleFonts.publicSans(color: Colors.grey[600], fontSize: 16),
              ),
              const SizedBox(height: 32),
              
              // Input Fields
              _buildLabel('Full Name'),
              _buildTextField(
                _nameController,
                'John Doe',
                Icons.person_outline,
                validator: (val) => val!.isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 20),
              
              _buildLabel('Email Address'),
              _buildTextField(
                _emailController,
                'name@example.com',
                Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                validator: (val) => !val!.contains('@') ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 20),
              
              _buildLabel('Phone Number'),
              _buildTextField(
                _phoneController,
                '98765 43210',
                Icons.call_outlined,
                keyboardType: TextInputType.phone,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Enter phone number';
                  final digits = val.replaceAll(RegExp(r'\D'), '');
                  if (digits.length != 10 && digits.length != 12) {
                    return 'Please enter a valid 10-digit number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              _buildLabel('Password'),
              _buildTextField(
                _passwordController,
                '••••••••',
                Icons.lock_outline,
                obscureText: true,
                validator: (val) => val!.length < 6 ? 'Password too short' : null,
              ),
              
              // Emergency Contacts Section
              const SizedBox(height: 32),
              Row(
                children: [
                  const Icon(Icons.emergency, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Emergency Contact',
                    style: GoogleFonts.publicSans(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 2, style: BorderStyle.solid),
                ),
                child: Column(
                  children: [
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _contactNameControllers.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return Column(
                          children: [
                            if (index > 0) 
                              Align(
                                alignment: Alignment.centerRight,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                                  onPressed: () => _removeContactField(index),
                                ),
                              ),
                            _buildTextField(_contactNameControllers[index], 'Contact Name', null, dense: true),
                            const SizedBox(height: 12),
                            _buildTextField(_contactPhoneControllers[index], 'Contact Phone', null, dense: true, keyboardType: TextInputType.phone, 
                              validator: (val) {
                                if (val == null || val.isEmpty) return 'Enter phone';
                                final digits = val.replaceAll(RegExp(r'\D'), '');
                                if (digits.length != 10 && digits.length != 12) {
                                  return 'Invalid number';
                                }
                                return null;
                              }),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _addContactField,
                      icon: const Icon(Icons.add_circle, size: 20),
                      label: const Text('Add another contact', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                    ),
                  ],
                ),
              ),
              
              // Terms Checkbox
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreeToTerms,
                    onChanged: (val) => setState(() => _agreeToTerms = val!),
                    activeColor: AppColors.primary,
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                        'I agree to the Terms of Service and Privacy Policy regarding emergency data usage.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Register Button
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading 
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        'Sign Up & Stay Safe',
                        style: GoogleFonts.publicSans(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                ),
              ),
              
              // Login Link
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account? '),
                  GestureDetector(
                    onTap: widget.onToggle,
                    child: const Text(
                      'Log in',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 48),
              
              // Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, color: Colors.grey[400]),
                  const SizedBox(width: 16),
                  Icon(Icons.location_on, color: Colors.grey[400]),
                  const SizedBox(width: 16),
                  Icon(Icons.notifications_active, color: Colors.grey[400]),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'POWERED BY GOSAFER SECURITY',
                style: GoogleFonts.publicSans(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.grey[500],
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          text,
          style: GoogleFonts.publicSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String hint,
    IconData? icon, {
    bool obscureText = false,
    bool dense = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400]),
        prefixIcon: icon != null ? Icon(icon, color: Colors.grey[400]) : null,
        filled: true,
        fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 12 : 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[200]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
