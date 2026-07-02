import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 3-page walkthrough shown once on first launch. Matches the old app's
/// screenshots — one bright colored page per pillar (Students / Exams /
/// Fees) with a shared "SKIP · NEXT" chrome and a final "GET STARTED"
/// button. Sets `onboarding_completed=true` in prefs before routing on.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageCtrl = PageController();
  int _index = 0;

  static const _pages = <_OnboardingSlide>[
    _OnboardingSlide(
      background: Color(0xFF1F82BC),
      icon: Icons.school_rounded,
      title: 'Seamless Student Management',
      body:
          'Easily register admissions, track daily attendance, and keep '
          'dynamic student profiles at your fingertips.',
    ),
    _OnboardingSlide(
      background: Color(0xFF22B67F),
      icon: Icons.assignment_rounded,
      title: 'Academics & Exams',
      body:
          'Review academic standards, structure exam sessions, and share '
          'report cards with robust PDF exports.',
    ),
    _OnboardingSlide(
      background: Color(0xFF3F5566),
      icon: Icons.account_balance_wallet_rounded,
      title: 'Digital Fee Receipts & Payments',
      body:
          'Monitor collected vs pending fee KPIs, pay instantly with mock '
          'UPI/Cards, and generate professional receipts.',
    ),
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    context.go('/server_config');
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
      return;
    }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final slide = _pages[_index];
    return Scaffold(
      backgroundColor: slide.background,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageCtrl,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => _SlideView(slide: _pages[i]),
            ),
            // SKIP button (top-right)
            Positioned(
              top: 12,
              right: 20,
              child: TextButton(
                onPressed: _finish,
                child: const Text(
                  'SKIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            // Page indicator + NEXT / GET STARTED
            Positioned(
              left: 20,
              right: 20,
              bottom: 32,
              child: Row(
                children: [
                  for (int i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _index ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: i == _index ? 1 : 0.4,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  _CtaPill(
                    text: _index == _pages.length - 1 ? 'GET STARTED' : 'NEXT',
                    color: slide.background,
                    onTap: _next,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.background,
    required this.icon,
    required this.title,
    required this.body,
  });
  final Color background;
  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final _OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Spacer(),
          Icon(slide.icon, size: 120, color: Colors.white),
          const SizedBox(height: 40),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.94),
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _CtaPill extends StatelessWidget {
  const _CtaPill({
    required this.text,
    required this.color,
    required this.onTap,
  });
  final String text;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(32),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ),
    );
  }
}
