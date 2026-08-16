import 'package:flutter/material.dart';
import 'package:mpsc_combine_ai/models/teaching_slide_deck_item.dart';
import 'package:mpsc_combine_ai/services/link_launcher.dart';
import 'package:mpsc_combine_ai/theme/app_colors.dart';

/// Full-screen slide-by-slide viewer shared by the Admin Panel ("Preview
/// Slides") and the student Notes screen ("View Teaching Slides"). Images
/// render inline; PDFs open in an external viewer (no bundled PDF renderer
/// dependency needed).
Future<void> showTeachingSlideViewer(
  BuildContext context, {
  required String title,
  required List<TeachingSlide> slides,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => _TeachingSlideViewerScreen(title: title, slides: slides),
    ),
  );
}

class _TeachingSlideViewerScreen extends StatefulWidget {
  const _TeachingSlideViewerScreen({required this.title, required this.slides});

  final String title;
  final List<TeachingSlide> slides;

  @override
  State<_TeachingSlideViewerScreen> createState() => _TeachingSlideViewerScreenState();
}

class _TeachingSlideViewerScreenState extends State<_TeachingSlideViewerScreen> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final slides = widget.slides;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        title: Text('${widget.title} — ${_index + 1}/${slides.length}'),
      ),
      body: slides.isEmpty
          ? const Center(
              child: Text('No slides yet.', style: TextStyle(color: Colors.white70)),
            )
          : PageView.builder(
              controller: _controller,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final slide = slides[i];
                if (slide.type == 'pdf') {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded, color: Colors.white, size: 64),
                        const SizedBox(height: 16),
                        Text(
                          slide.caption.isEmpty ? 'PDF Slide' : slide.caption,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => openExternalLink(context, slide.url),
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: const Text('Open PDF'),
                        ),
                      ],
                    ),
                  );
                }
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(
                      slide.url,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 64,
                      ),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: slides.length < 2
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      color: Colors.white,
                      onPressed: _index == 0
                          ? null
                          : () => _controller.previousPage(
                              duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: (_index + 1) / slides.length,
                        color: AppColors.orange,
                      ),
                    ),
                    IconButton(
                      color: Colors.white,
                      onPressed: _index == slides.length - 1
                          ? null
                          : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
