import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flow_sync/features/auth/presentation/bloc/auth_bloc.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          if (state is AuthAgeGatePending) {
            return _buildParentConsentForm(context);
          } else if (state is AuthConsentPending) {
            return const Center(
              child: Text('Please check your parent\'s phone for OTP.'),
            );
          } else if (state is AuthFullyAuthenticated) {
            return const Center(
              child: Text('Welcome! You are authenticated.'),
            );
          }
          return _buildLoginForm(context);
        },
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // App Title
          Text(
            'FlowSync',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'AI 스케줄 어시스턴트',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 48),

          // Email
          TextField(
            controller: _emailController,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),

          // Password
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline),
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),

          // Login Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                context.read<AuthBloc>().add(
                      LoginRequested(
                        _emailController.text,
                        _passwordController.text,
                      ),
                    );
              },
              child: const Text('로그인'),
            ),
          ),
          const SizedBox(height: 12),

          // Sign Up Button — opens age selection
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => _showSignupOptions(context),
              child: const Text('회원가입'),
            ),
          ),
        ],
      ),
    );
  }

  void _showSignupOptions(BuildContext context) {
    final email = _emailController.text;
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이메일과 비밀번호를 입력해주세요.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '회원 유형을 선택하세요',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '연령대에 따라 가입 절차가 다릅니다.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),

            // Adult (19+)
            _SignupOptionTile(
              icon: Icons.person,
              title: '성인 (19세 이상)',
              subtitle: '일반 회원가입',
              onTap: () {
                Navigator.pop(context);
                final dob = DateTime.now().subtract(
                  const Duration(days: 365 * 25),
                ); // 25세
                context.read<AuthBloc>().add(
                      SignupRequested(email, password, dob),
                    );
              },
            ),
            const SizedBox(height: 8),

            // Teenager (14-18)
            _SignupOptionTile(
              icon: Icons.school,
              title: '청소년 (14~18세)',
              subtitle: '보호자 동의 없이 가입',
              onTap: () {
                Navigator.pop(context);
                final dob = DateTime.now().subtract(
                  const Duration(days: 365 * 16),
                ); // 16세
                context.read<AuthBloc>().add(
                      SignupRequested(email, password, dob),
                    );
              },
            ),
            const SizedBox(height: 8),

            // Child (<14)
            _SignupOptionTile(
              icon: Icons.child_care,
              title: '어린이 (14세 미만)',
              subtitle: '보호자 동의 필요',
              onTap: () {
                Navigator.pop(context);
                final dob = DateTime.now().subtract(
                  const Duration(days: 365 * 10),
                ); // 10세
                context.read<AuthBloc>().add(
                      SignupRequested(email, password, dob),
                    );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildParentConsentForm(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.family_restroom, size: 64),
          const SizedBox(height: 16),
          const Text(
            '보호자 동의 필요',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text('14세 미만은 보호자의 전화번호 인증이 필요합니다.'),
          const SizedBox(height: 24),
          TextField(
            controller: _phoneController,
            decoration: const InputDecoration(
              labelText: '보호자 전화번호',
              prefixIcon: Icon(Icons.phone),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                context
                    .read<AuthBloc>()
                    .add(ParentNumberSubmitted(_phoneController.text));
              },
              child: const Text('OTP 전송'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignupOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SignupOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
