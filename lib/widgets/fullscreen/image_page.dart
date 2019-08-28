import 'dart:io';
import 'dart:math';

import 'package:aves/model/image_collection.dart';
import 'package:aves/model/image_entry.dart';
import 'package:aves/utils/android_app_service.dart';
import 'package:aves/widgets/fullscreen/info/info_page.dart';
import 'package:aves/widgets/fullscreen/overlay_bottom.dart';
import 'package:aves/widgets/fullscreen/overlay_top.dart';
import 'package:aves/widgets/fullscreen/video.dart';
import 'package:flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:screen/screen.dart';

class FullscreenPage extends AnimatedWidget {
  final ImageCollection collection;
  final String initialUri;

  const FullscreenPage({
    Key key,
    this.collection,
    this.initialUri,
  }) : super(key: key, listenable: collection);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        Screen.keepOn(false);
        SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
        return Future.value(true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: FullscreenBody(
          collection: collection,
          initialUri: initialUri,
        ),
        resizeToAvoidBottomInset: false,
//        Hero(
//          tag: uri,
//          child: Stack(
//            children: [
//              Center(
//                child: widget.thumbnail == null
//                    ? CircularProgressIndicator()
//                    : Image.memory(
//                        widget.thumbnail,
//                        width: requestWidth,
//                        height: requestHeight,
//                        fit: BoxFit.contain,
//                      ),
//              ),
//              Center(
//                child: FadeInImage(
//                  placeholder: MemoryImage(kTransparentImage),
//                  image: FileImage(File(path)),
//                  fadeOutDuration: Duration(milliseconds: 1),
//                  fadeInDuration: Duration(milliseconds: 200),
//                  width: requestWidth,
//                  height: requestHeight,
//                  fit: BoxFit.contain,
//                ),
//              ),
//            ],
//          ),
//        ),
      ),
    );
  }
}

class FullscreenBody extends StatefulWidget {
  final ImageCollection collection;
  final String initialUri;

  const FullscreenBody({
    Key key,
    this.collection,
    this.initialUri,
  }) : super(key: key);

  @override
  FullscreenBodyState createState() => FullscreenBodyState();
}

class FullscreenBodyState extends State<FullscreenBody> with SingleTickerProviderStateMixin {
  bool _isInitialScale = true;
  int _currentHorizontalPage, _currentVerticalPage = 0;
  PageController _horizontalPager, _verticalPager;
  ValueNotifier<bool> _overlayVisible = ValueNotifier(true);
  AnimationController _overlayAnimationController;
  Animation<double> _topOverlayScale;
  Animation<Offset> _bottomOverlayOffset;
  EdgeInsets _frozenViewInsets, _frozenViewPadding;

  ImageCollection get collection => widget.collection;

  List<ImageEntry> get entries => widget.collection.sortedEntries;

  @override
  void initState() {
    super.initState();
    final index = entries.indexWhere((entry) => entry.uri == widget.initialUri);
    _currentHorizontalPage = max(0, index);
    _horizontalPager = PageController(initialPage: _currentHorizontalPage);
    _verticalPager = PageController(initialPage: _currentVerticalPage);
    _overlayAnimationController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
    _topOverlayScale = CurvedAnimation(
      parent: _overlayAnimationController,
      curve: Curves.easeOutQuart,
    );
    _bottomOverlayOffset = Tween(begin: Offset(0, 1), end: Offset(0, 0)).animate(CurvedAnimation(
      parent: _overlayAnimationController,
      curve: Curves.easeOutQuart,
    ));
    _overlayVisible.addListener(onOverlayVisibleChange);

    Screen.keepOn(true);
    initOverlay();
  }

  initOverlay() async {
    // wait for MaterialPageRoute.transitionDuration
    // to show overlay after hero animation is complete
    await Future.delayed(Duration(milliseconds: 300));
    onOverlayVisibleChange();
  }

  @override
  void dispose() {
    _overlayVisible.removeListener(onOverlayVisibleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = entries[_currentHorizontalPage];
    return Stack(
      children: [
        PageView(
          scrollDirection: Axis.vertical,
          controller: _verticalPager,
          physics: _isInitialScale ? PageScrollPhysics() : NeverScrollableScrollPhysics(),
          onPageChanged: (page) => setState(() => _currentVerticalPage = page),
          children: [
            ImagePage(
              collection: collection,
              pageController: _horizontalPager,
              onTap: () => _overlayVisible.value = !_overlayVisible.value,
              onPageChanged: (page) => setState(() => _currentHorizontalPage = page),
              onScaleChanged: (state) => setState(() => _isInitialScale = state == PhotoViewScaleState.initial),
            ),
            NotificationListener(
              onNotification: (notification) {
                if (notification is BackUpNotification) goToVerticalPage(0);
                return false;
              },
              child: InfoPage(entry: entry),
            ),
          ],
        ),
        if (_currentHorizontalPage != null && _currentVerticalPage == 0) ...[
          FullscreenTopOverlay(
            entries: entries,
            index: _currentHorizontalPage,
            scale: _topOverlayScale,
            viewInsets: _frozenViewInsets,
            viewPadding: _frozenViewPadding,
            onActionSelected: (action) => onActionSelected(entry, action),
          ),
          Positioned(
            bottom: 0,
            child: SlideTransition(
              position: _bottomOverlayOffset,
              child: FullscreenBottomOverlay(
                entries: entries,
                index: _currentHorizontalPage,
                viewInsets: _frozenViewInsets,
                viewPadding: _frozenViewPadding,
              ),
            ),
          )
        ]
      ],
    );
  }

  goToVerticalPage(int page) {
    return _verticalPager.animateToPage(
      page,
      duration: Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  onOverlayVisibleChange() async {
    if (_overlayVisible.value) {
      SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);
      _overlayAnimationController.forward();
    } else {
      final mediaQuery = MediaQuery.of(context);
      _frozenViewInsets = mediaQuery.viewInsets;
      _frozenViewPadding = mediaQuery.viewPadding;
      SystemChrome.setEnabledSystemUIOverlays([]);
      await _overlayAnimationController.reverse();
      _frozenViewInsets = null;
      _frozenViewPadding = null;
    }
  }

  onActionSelected(ImageEntry entry, FullscreenAction action) {
    switch (action) {
      case FullscreenAction.delete:
        showDeleteDialog(entry);
        break;
      case FullscreenAction.edit:
        AndroidAppService.edit(entry.uri, entry.mimeType);
        break;
      case FullscreenAction.info:
        goToVerticalPage(1);
        break;
      case FullscreenAction.rename:
        showRenameDialog(entry);
        break;
      case FullscreenAction.open:
        AndroidAppService.open(entry.uri, entry.mimeType);
        break;
      case FullscreenAction.openMap:
        AndroidAppService.openMap(entry.geoUri);
        break;
      case FullscreenAction.rotateCCW:
        rotate(entry, clockwise: false);
        break;
      case FullscreenAction.rotateCW:
        rotate(entry, clockwise: true);
        break;
      case FullscreenAction.setAs:
        AndroidAppService.setAs(entry.uri, entry.mimeType);
        break;
      case FullscreenAction.share:
        AndroidAppService.share(entry.uri, entry.mimeType);
        break;
    }
  }

  showFeedback(String message) {
    Flushbar(
      message: message,
      margin: EdgeInsets.all(8),
      borderRadius: 8,
      borderColor: Colors.white30,
      borderWidth: 0.5,
      duration: Duration(seconds: 2),
      flushbarPosition: FlushbarPosition.TOP,
      animationDuration: Duration(milliseconds: 600),
    )..show(context);
  }

  rotate(ImageEntry entry, {@required bool clockwise}) async {
    final success = await entry.rotate(clockwise: clockwise);
    showFeedback(success ? 'Done!' : 'Failed');
  }

  showDeleteDialog(ImageEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Text('Are you sure?'),
          actions: [
            FlatButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL'),
            ),
            FlatButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('DELETE'),
            ),
          ],
        );
      },
    );
    if (confirmed == null || !confirmed) return;
    if (!await collection.delete(entry)) showFeedback('Failed');
  }

  showRenameDialog(ImageEntry entry) async {
    final currentName = entry.title;
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: TextField(
              controller: controller,
              autofocus: true,
            ),
            actions: [
              FlatButton(
                onPressed: () => Navigator.pop(context),
                child: Text('CANCEL'),
              ),
              FlatButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text('APPLY'),
              ),
            ],
          );
        });
    if (newName == null || newName.isEmpty) return;
    showFeedback(await entry.rename(newName) ? 'Done!' : 'Failed');
  }
}

enum FullscreenAction { delete, edit, info, open, openMap, rename, rotateCCW, rotateCW, setAs, share }

class ImagePage extends StatefulWidget {
  final ImageCollection collection;
  final PageController pageController;
  final VoidCallback onTap;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<PhotoViewScaleState> onScaleChanged;

  const ImagePage({
    this.collection,
    this.pageController,
    this.onTap,
    this.onPageChanged,
    this.onScaleChanged,
  });

  @override
  State<StatefulWidget> createState() => ImagePageState();
}

class ImagePageState extends State<ImagePage> with AutomaticKeepAliveClientMixin {
  List<ImageEntry> get entries => widget.collection.sortedEntries;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PhotoViewGallery.builder(
      itemCount: entries.length,
      builder: (galleryContext, index) {
        final entry = entries[index];
        if (entry.isVideo) {
          return PhotoViewGalleryPageOptions.customChild(
            child: AvesVideo(entry: entry),
            childSize: MediaQuery.of(galleryContext).size,
            // no heroTag because `Chewie` already internally builds one with the videoController
            minScale: PhotoViewComputedScale.contained,
            initialScale: PhotoViewComputedScale.contained,
            onTapUp: (tapContext, details, value) => widget.onTap?.call(),
          );
        }
        return PhotoViewGalleryPageOptions(
          imageProvider: FileImage(File(entry.path)),
          heroTag: entry.uri,
          minScale: PhotoViewComputedScale.contained,
          initialScale: PhotoViewComputedScale.contained,
          onTapUp: (tapContext, details, value) => widget.onTap?.call(),
        );
      },
      loadingChild: Center(
        child: CircularProgressIndicator(),
      ),
      pageController: widget.pageController,
      onPageChanged: widget.onPageChanged,
      scaleStateChangedCallback: widget.onScaleChanged,
      transitionOnUserGestures: true,
      scrollPhysics: BouncingScrollPhysics(),
    );
  }

  @override
  bool get wantKeepAlive => true;
}
