import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'controllers/audio_recognition_controller.dart';
import 'music_theory.dart';
import 'services/settings_service.dart';
import 'theme/apple_violin_theme.dart';
import 'ui/song_practice_screen.dart';
import 'ui/synth_test_panel.dart';
import 'ui/trainer_screen.dart';
import 'ui/tuner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EasyViolinApp());
}

class EasyViolinApp extends StatelessWidget {
  const EasyViolinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'easy violin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppleViolinTheme.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: AppleViolinTheme.appleBlue,
          secondary: AppleViolinTheme.appleGreen,
          surface: AppleViolinTheme.cardDark,
        ),
        fontFamily: '-apple-system',
      ),
      home: const MainViolinScreen(),
    );
  }
}

class MainViolinScreen extends StatefulWidget {
  const MainViolinScreen({super.key});

  @override
  State<MainViolinScreen> createState() => _MainViolinScreenState();
}

class _MainViolinScreenState extends State<MainViolinScreen> {
  late final AudioRecognitionController _audioController;
  SettingsService? _settings;

  int _selectedTabIndex = 2; // Direct to SongPracticeScreen
  final bool _isMobileFrame = false;
  final bool _showDebugSynth = false;

  @override
  void initState() {
    super.initState();
    _audioController = AudioRecognitionController();
    _audioController.addListener(_onAudioControllerChanged);
    _initApp();
  }

  Future<void> _initApp() async {
    final s = await SettingsService.init();
    if (mounted) {
      setState(() {
        _settings = s;
        _selectedTabIndex = 2; // Direct to SongPracticeScreen for instant test
      });
      _audioController.setConcertA4Hz(s.concertA4Hz);
    }
    await _audioController.initialize();
  }

  void _onAudioControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _audioController.removeListener(_onAudioControllerChanged);
    _audioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = mediaQuery.size.width >= 560;

    Widget coreApp = Scaffold(
      backgroundColor: AppleViolinTheme.darkBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Main Body by Tab (3 Tabs: Тюнер, Гаммы, Пьесы)
            Expanded(
              child: IndexedStack(
                index: _selectedTabIndex,
                children: [
                  TunerScreen(
                    audioEngine: _audioController.audioEngine,
                    currentNote: _audioController.currentNote,
                    selectedString: _audioController.selectedTunerString,
                    concertA4Hz: _audioController.concertA4Hz,
                    isMobileMode: true,
                    onConcertPitchChanged: (pitch) {
                      _audioController.setConcertA4Hz(pitch);
                    },
                    onStringSelected: (str) {
                      _audioController.setSelectedTunerString(str);
                    },
                  ),
                  TrainerScreen(
                    audioEngine: _audioController.audioEngine,
                    currentNote: _audioController.currentNote,
                    noteNotifier: _audioController.noteNotifier,
                  ),
                  SongPracticeScreen(
                    audioEngine: _audioController.audioEngine,
                    currentNote: _audioController.currentNote,
                    noteNotifier: _audioController.noteNotifier,
                    isMobileMode: true,
                  ),
                ],
              ),
            ),

            // Collapsible Debug Synth Panel (if toggled)
            if (_showDebugSynth)
              SynthTestPanel(
                audioEngine: _audioController.audioEngine,
                isMicActive: _audioController.isMicActive,
                isMobileMode: true,
                onMicToggle: (enable) => _audioController.toggleMic(enable),
              ),

            // Apple HIG Bottom Navigation Bar & Home Bar Indicator
            _buildAppleTabBar(),
          ],
        ),
      ),
    );

    if (isDesktop && !_isMobileFrame) {
      // Center in a realistic iPhone chassis frame on desktop screens
      return Scaffold(
        backgroundColor: const Color(0xFF0C0C0E),
        body: Center(
          child: Container(
            width: 420,
            height: math.min(mediaQuery.size.height, 880.0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppleViolinTheme.darkBg,
              borderRadius: BorderRadius.circular(48),
              border: Border.all(color: const Color(0xFF2C2C2E), width: 3),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black87,
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: coreApp,
          ),
        ),
      );
    }

    return coreApp;
  }

  Widget _buildAppleTabBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xE6161618),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildTabItem(0, Icons.adjust_rounded, 'Тюнер'),
                _buildTabItem(1, Icons.queue_music_rounded, 'Гаммы'),
                _buildTabItem(2, Icons.music_note_rounded, 'Пьесы'),
              ],
            ),
          ),
          // iOS Home Bar Indicator
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Container(
              width: 134,
              height: 4.5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
        _selectedTabIndex = index;
        _settings?.setLastTab(index);
      },
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppleViolinTheme.appleBlue : AppleViolinTheme.subtext,
            ),
          ),
        ],
      ),
    );
  }
}
