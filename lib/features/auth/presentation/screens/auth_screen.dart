import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        builder: (context, state) {
          if (state is AuthAgeGatePending) {
            return _buildParentConsentForm(context);
          } else if (state is AuthConsentPending) {
            return const Center(child: Text('Please check your parent\'s phone for OTP.'));
          } else if (state is AuthFullyAuthenticated) {
            return const Center(child: Text('Welcome! You are authenticated.'));
          }
          return _buildLoginForm(context);
        },
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    // Simplified for unit generation
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          ElevatedButton(
            onPressed: () {
              context.read<AuthBloc>().add(LoginRequested(emailController.text, passwordController.text));
            },
            child: const Text('Login'),
          ),
          ElevatedButton(
            onPressed: () {
              // Simulating signup with a DOB that triggers age gate
              context.read<AuthBloc>().add(SignupRequested(
                emailController.text, 
                passwordController.text, 
                DateTime.now().subtract(const Duration(days: 365 * 10)) // 10 years old
              ));
            },
            child: const Text('Sign Up (Simulate <14)'),
          )
        ],
      ),
    );
  }

  Widget _buildParentConsentForm(BuildContext context) {
    final phoneController = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Parental Consent Required'),
          TextField(controller: phoneController, decoration: const InputDecoration(labelText: 'Parent Phone Number')),
          ElevatedButton(
            onPressed: () {
              context.read<AuthBloc>().add(ParentNumberSubmitted(phoneController.text));
            },
            child: const Text('Send OTP'),
          ),
        ],
      ),
    );
  }
}
